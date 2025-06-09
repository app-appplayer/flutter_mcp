#include "background_service.h"
#include <algorithm>

namespace flutter_mcp {

BackgroundService::BackgroundService() 
    : is_running_(false), 
      interval_ms_(60000), // Default 1 minute
      scheduler_running_(false) {
}

BackgroundService::~BackgroundService() {
  Stop();
}

void BackgroundService::Start(EventCallback callback) {
  if (is_running_) return;
  
  event_callback_ = callback;
  is_running_ = true;
  scheduler_running_ = true;
  
  // Start background worker thread
  worker_thread_ = std::thread(&BackgroundService::BackgroundWorker, this);
  
  // Start task scheduler thread
  scheduler_thread_ = std::thread(&BackgroundService::TaskScheduler, this);
}

void BackgroundService::Stop() {
  if (!is_running_) return;
  
  is_running_ = false;
  scheduler_running_ = false;
  
  // Wake up scheduler thread
  tasks_cv_.notify_all();
  
  // Wait for threads to finish
  if (worker_thread_.joinable()) {
    worker_thread_.join();
  }
  
  if (scheduler_thread_.joinable()) {
    scheduler_thread_.join();
  }
  
  // Clear scheduled tasks
  {
    std::lock_guard<std::mutex> lock(tasks_mutex_);
    scheduled_tasks_.clear();
  }
}

void BackgroundService::SetInterval(int interval_ms) {
  interval_ms_ = interval_ms;
}

void BackgroundService::ScheduleTask(const std::string& task_id, int64_t delay_millis, std::function<void()> task) {
  std::lock_guard<std::mutex> lock(tasks_mutex_);
  
  ScheduledTask scheduled_task;
  scheduled_task.id = task_id;
  scheduled_task.execute_time = std::chrono::steady_clock::now() + std::chrono::milliseconds(delay_millis);
  scheduled_task.task = task;
  
  scheduled_tasks_[task_id] = scheduled_task;
  tasks_cv_.notify_one();
}

void BackgroundService::CancelTask(const std::string& task_id) {
  std::lock_guard<std::mutex> lock(tasks_mutex_);
  scheduled_tasks_.erase(task_id);
}

void BackgroundService::BackgroundWorker() {
  while (is_running_) {
    // Perform periodic background work
    if (event_callback_) {
      std::map<std::string, flutter::EncodableValue> data;
      data["timestamp"] = flutter::EncodableValue(static_cast<int64_t>(
          std::chrono::system_clock::now().time_since_epoch().count()));
      data["type"] = flutter::EncodableValue("periodic");
      
      event_callback_("backgroundEvent", data);
    }
    
    // Sleep for the configured interval
    std::this_thread::sleep_for(std::chrono::milliseconds(interval_ms_.load()));
  }
}

void BackgroundService::TaskScheduler() {
  while (scheduler_running_) {
    std::unique_lock<std::mutex> lock(tasks_mutex_);
    
    if (scheduled_tasks_.empty()) {
      // Wait for new tasks or stop signal
      tasks_cv_.wait(lock, [this] { 
        return !scheduled_tasks_.empty() || !scheduler_running_; 
      });
      continue;
    }
    
    // Find the task with the earliest execution time
    auto earliest = std::min_element(
        scheduled_tasks_.begin(), 
        scheduled_tasks_.end(),
        [](const auto& a, const auto& b) {
          return a.second.execute_time < b.second.execute_time;
        });
    
    if (earliest != scheduled_tasks_.end()) {
      auto now = std::chrono::steady_clock::now();
      
      if (earliest->second.execute_time <= now) {
        // Execute the task
        auto task = earliest->second.task;
        scheduled_tasks_.erase(earliest);
        
        lock.unlock();
        if (task) {
          task();
        }
      } else {
        // Wait until the next task is ready
        tasks_cv_.wait_until(lock, earliest->second.execute_time, [this] {
          return !scheduler_running_;
        });
      }
    }
  }
}

}  // namespace flutter_mcp