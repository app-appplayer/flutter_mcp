#ifndef BACKGROUND_SERVICE_H_
#define BACKGROUND_SERVICE_H_

#include <windows.h>
#include <functional>
#include <string>
#include <map>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <chrono>
#include <flutter/encodable_value.h>

namespace flutter_mcp {

class BackgroundService {
 public:
  using EventCallback = std::function<void(const std::string&, const std::map<std::string, flutter::EncodableValue>&)>;

  BackgroundService();
  ~BackgroundService();

  void Start(EventCallback callback);
  void Stop();
  void SetInterval(int interval_ms);
  void ScheduleTask(const std::string& task_id, int64_t delay_millis, std::function<void()> task);
  void CancelTask(const std::string& task_id);
  bool IsRunning() const { return is_running_; }

 private:
  void BackgroundWorker();
  void TaskScheduler();

  std::thread worker_thread_;
  std::thread scheduler_thread_;
  std::atomic<bool> is_running_;
  std::atomic<int> interval_ms_;
  EventCallback event_callback_;
  
  struct ScheduledTask {
    std::string id;
    std::chrono::steady_clock::time_point execute_time;
    std::function<void()> task;
  };
  
  std::map<std::string, ScheduledTask> scheduled_tasks_;
  std::mutex tasks_mutex_;
  std::condition_variable tasks_cv_;
  std::atomic<bool> scheduler_running_;
};

}  // namespace flutter_mcp

#endif  // BACKGROUND_SERVICE_H_