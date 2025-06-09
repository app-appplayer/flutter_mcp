import BackgroundTasks
import Foundation

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    private let taskIdentifier = "com.example.flutter_mcp.background"
    var isRunning = false
    
    private init() {}
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task: task as! BGProcessingTask)
        }
    }
    
    func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
    
    func scheduleTask(identifier: String, delay: TimeInterval) {
        // iOS doesn't support scheduling tasks with specific delays
        // We'll use the general background task system
        scheduleBackgroundTask()
        
        // Store the task info for later execution
        var scheduledTasks = UserDefaults.standard.dictionary(forKey: "scheduled_tasks") ?? [:]
        scheduledTasks[identifier] = [
            "scheduledTime": Date().addingTimeInterval(delay).timeIntervalSince1970,
            "identifier": identifier
        ]
        UserDefaults.standard.set(scheduledTasks, forKey: "scheduled_tasks")
    }
    
    func cancelTask(identifier: String) {
        var scheduledTasks = UserDefaults.standard.dictionary(forKey: "scheduled_tasks") ?? [:]
        scheduledTasks.removeValue(forKey: identifier)
        UserDefaults.standard.set(scheduledTasks, forKey: "scheduled_tasks")
    }
    
    private func handleBackgroundTask(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Check for scheduled tasks
        let scheduledTasks = UserDefaults.standard.dictionary(forKey: "scheduled_tasks") ?? [:]
        let currentTime = Date().timeIntervalSince1970
        
        var tasksToExecute: [String] = []
        var remainingTasks: [String: Any] = [:]
        
        for (taskId, taskInfo) in scheduledTasks {
            if let info = taskInfo as? [String: Any],
               let scheduledTime = info["scheduledTime"] as? TimeInterval {
                if scheduledTime <= currentTime {
                    tasksToExecute.append(taskId)
                } else {
                    remainingTasks[taskId] = taskInfo
                }
            }
        }
        
        // Update remaining tasks
        UserDefaults.standard.set(remainingTasks, forKey: "scheduled_tasks")
        
        // Execute due tasks
        for taskId in tasksToExecute {
            // Notify Flutter about task execution
            NotificationCenter.default.post(
                name: Notification.Name("flutter_mcp_background_task"),
                object: nil,
                userInfo: ["taskId": taskId]
            )
        }
        
        // Reschedule if needed
        if isRunning {
            scheduleBackgroundTask()
        }
        
        task.setTaskCompleted(success: true)
    }
}