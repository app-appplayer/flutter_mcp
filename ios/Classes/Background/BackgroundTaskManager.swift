import BackgroundTasks
import Foundation
import Flutter

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    private let taskIdentifier = "com.example.flutter_mcp.background"
    var isRunning = false
    
    // Flutter engine for background execution
    private var backgroundEngine: FlutterEngine?
    private var backgroundChannel: FlutterMethodChannel?
    
    private init() {}
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task: task as! BGProcessingTask)
        }
    }
    
    func setupFlutterEngine(callbackHandle: Int64) {
        if backgroundEngine == nil {
            backgroundEngine = FlutterEngine(name: "BackgroundEngine", project: nil, allowHeadlessExecution: true)
            
            let registrar = backgroundEngine!.registrar(forPlugin: "flutter_mcp")
            backgroundChannel = FlutterMethodChannel(
                name: "flutter_mcp/background",
                binaryMessenger: registrar!.messenger()
            )
            
            // Start the isolate with the callback
            let callbackInfo = FlutterCallbackCache.lookupCallbackInformation(callbackHandle)
            if let callbackInfo = callbackInfo {
                let entrypoint = callbackInfo.callbackName
                let uri = callbackInfo.callbackLibraryPath
                backgroundEngine!.run(withEntrypoint: entrypoint, libraryURI: uri)
            }
        }
    }
    
    func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        // Set earliest begin date to at least 15 minutes from now (iOS requirement)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
    
    func scheduleTask(identifier: String, delay: TimeInterval, data: [String: Any]?) {
        // Store task info for later execution
        var scheduledTasks = UserDefaults.standard.dictionary(forKey: "scheduled_tasks") ?? [:]
        scheduledTasks[identifier] = [
            "scheduledTime": Date().addingTimeInterval(delay).timeIntervalSince1970,
            "identifier": identifier,
            "data": data ?? [:]
        ]
        UserDefaults.standard.set(scheduledTasks, forKey: "scheduled_tasks")
        
        // Schedule background task if not already scheduled
        scheduleBackgroundTask()
    }
    
    func cancelTask(identifier: String) {
        var scheduledTasks = UserDefaults.standard.dictionary(forKey: "scheduled_tasks") ?? [:]
        scheduledTasks.removeValue(forKey: identifier)
        UserDefaults.standard.set(scheduledTasks, forKey: "scheduled_tasks")
    }
    
    private func handleBackgroundTask(task: BGProcessingTask) {
        task.expirationHandler = {
            // Clean up and complete
            self.backgroundEngine?.destroyContext()
            task.setTaskCompleted(success: false)
        }
        
        // Check for scheduled tasks
        let scheduledTasks = UserDefaults.standard.dictionary(forKey: "scheduled_tasks") ?? [:]
        let currentTime = Date().timeIntervalSince1970
        
        var tasksToExecute: [(String, [String: Any])] = []
        var remainingTasks: [String: Any] = [:]
        
        for (taskId, taskInfo) in scheduledTasks {
            if let info = taskInfo as? [String: Any],
               let scheduledTime = info["scheduledTime"] as? TimeInterval {
                if scheduledTime <= currentTime {
                    let data = info["data"] as? [String: Any] ?? [:]
                    tasksToExecute.append((taskId, data))
                } else {
                    remainingTasks[taskId] = taskInfo
                }
            }
        }
        
        // Update remaining tasks
        UserDefaults.standard.set(remainingTasks, forKey: "scheduled_tasks")
        
        // Execute tasks using Flutter engine
        if let channel = backgroundChannel {
            let group = DispatchGroup()
            
            for (taskId, data) in tasksToExecute {
                group.enter()
                
                channel.invokeMethod("executeTask", arguments: [
                    "taskId": taskId,
                    "data": data,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ]) { result in
                    group.leave()
                }
            }
            
            // Wait for all tasks to complete (with timeout)
            let result = group.wait(timeout: .now() + 25) // iOS gives us ~30 seconds
            
            // Reschedule if needed
            if isRunning && !remainingTasks.isEmpty {
                scheduleBackgroundTask()
            }
            
            task.setTaskCompleted(success: result == .success)
        } else {
            // No Flutter engine, just notify via notification center
            for (taskId, _) in tasksToExecute {
                NotificationCenter.default.post(
                    name: Notification.Name("flutter_mcp_background_task"),
                    object: nil,
                    userInfo: ["taskId": taskId]
                )
            }
            
            task.setTaskCompleted(success: true)
        }
    }
    
    // Call this when stopping background service
    func stopBackgroundService() {
        isRunning = false
        backgroundEngine?.destroyContext()
        backgroundEngine = nil
        backgroundChannel = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }
}

// Extension to support background task registration
extension AppDelegate {
    override func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register background tasks
        BackgroundTaskManager.shared.registerBackgroundTasks()
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}