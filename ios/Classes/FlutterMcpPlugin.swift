import Flutter
import UIKit
import BackgroundTasks
import UserNotifications

public class FlutterMcpPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var channel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    
    // Services
    private let keychainService = KeychainService()
    private let notificationManager = NotificationManager()
    private let backgroundTaskManager = BackgroundTaskManager.shared
    private let permissionManager = PermissionManager()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlutterMcpPlugin()
        
        // Method channel
        let channel = FlutterMethodChannel(
            name: "flutter_mcp",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.channel = channel
        
        // Event channel
        let eventChannel = FlutterEventChannel(
            name: "flutter_mcp/events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
        instance.eventChannel = eventChannel
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        // Platform info
        case "getPlatformVersion":
            let device = UIDevice.current
            result("iOS \(device.systemVersion)")
            
        // Initialization
        case "initialize":
            initialize(call: call, result: result)
            
        // Background service
        case "startBackgroundService":
            startBackgroundService(result: result)
        case "stopBackgroundService":
            stopBackgroundService(result: result)
        case "configureBackgroundService":
            configureBackgroundService(call: call, result: result)
        case "scheduleBackgroundTask":
            scheduleBackgroundTask(call: call, result: result)
        case "cancelBackgroundTask":
            cancelBackgroundTask(call: call, result: result)
            
        // Notifications
        case "showNotification":
            showNotification(call: call, result: result)
        case "requestNotificationPermission":
            requestNotificationPermission(result: result)
        case "configureNotifications":
            configureNotifications(call: call, result: result)
        case "cancelNotification":
            cancelNotification(call: call, result: result)
        case "cancelAllNotifications":
            cancelAllNotifications(result: result)
            
        // Secure storage
        case "secureStore":
            secureStore(call: call, result: result)
        case "secureRead":
            secureRead(call: call, result: result)
        case "secureDelete":
            secureDelete(call: call, result: result)
        case "secureContainsKey":
            secureContainsKey(call: call, result: result)
        case "secureDeleteAll":
            secureDeleteAll(result: result)
            
        // Permissions
        case "checkPermission":
            checkPermission(call: call, result: result)
        case "requestPermission":
            requestPermission(call: call, result: result)
        case "requestPermissions":
            requestPermissions(call: call, result: result)
            
        // Lifecycle
        case "shutdown":
            shutdown(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Implementation Methods
    
    private func initialize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Initialize components based on config
        if let config = call.arguments as? [String: Any] {
            // Apply configuration
        }
        
        // Register background tasks
        backgroundTaskManager.registerBackgroundTasks()
        
        result(nil)
    }
    
    private func startBackgroundService(result: @escaping FlutterResult) {
        // iOS doesn't have a traditional background service
        // We'll use background tasks instead
        backgroundTaskManager.isRunning = true
        UserDefaults.standard.set(true, forKey: "background_service_enabled")
        result(true)
    }
    
    private func stopBackgroundService(result: @escaping FlutterResult) {
        backgroundTaskManager.isRunning = false
        UserDefaults.standard.set(false, forKey: "background_service_enabled")
        result(true)
    }
    
    private func configureBackgroundService(call: FlutterMethodCall, result: @escaping FlutterResult) {
        if let config = call.arguments as? [String: Any] {
            // Store configuration
        }
        result(nil)
    }
    
    private func scheduleBackgroundTask(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? String,
              let delayMillis = args["delayMillis"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }
        
        let delay = TimeInterval(delayMillis) / 1000.0
        backgroundTaskManager.scheduleTask(identifier: taskId, delay: delay)
        result(nil)
    }
    
    private func cancelBackgroundTask(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing task ID", details: nil))
            return
        }
        
        backgroundTaskManager.cancelTask(identifier: taskId)
        result(nil)
    }
    
    private func showNotification(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let body = args["body"] as? String,
              let id = args["id"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }
        
        notificationManager.showNotification(
            title: title,
            body: body,
            identifier: id
        ) { error in
            if let error = error {
                result(FlutterError(code: "NOTIFICATION_ERROR", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }
    
    private func requestNotificationPermission(result: @escaping FlutterResult) {
        notificationManager.requestPermission { granted in
            result(granted)
        }
    }
    
    private func configureNotifications(call: FlutterMethodCall, result: @escaping FlutterResult) {
        if let config = call.arguments as? [String: Any] {
            notificationManager.configure(config: config)
        }
        result(nil)
    }
    
    private func cancelNotification(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing notification ID", details: nil))
            return
        }
        
        notificationManager.cancelNotification(identifier: id)
        result(nil)
    }
    
    private func cancelAllNotifications(result: @escaping FlutterResult) {
        notificationManager.cancelAllNotifications()
        result(nil)
    }
    
    private func secureStore(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String,
              let value = args["value"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }
        
        do {
            try keychainService.store(key: key, value: value)
            result(nil)
        } catch {
            result(FlutterError(code: "STORAGE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func secureRead(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing key", details: nil))
            return
        }
        
        do {
            let value = try keychainService.read(key: key)
            if let value = value {
                result(value)
            } else {
                result(FlutterError(code: "KEY_NOT_FOUND", message: "Key not found", details: nil))
            }
        } catch {
            result(FlutterError(code: "STORAGE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func secureDelete(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing key", details: nil))
            return
        }
        
        do {
            try keychainService.delete(key: key)
            result(nil)
        } catch {
            result(FlutterError(code: "STORAGE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func secureContainsKey(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing key", details: nil))
            return
        }
        
        do {
            let contains = try keychainService.containsKey(key: key)
            result(contains)
        } catch {
            result(FlutterError(code: "STORAGE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func secureDeleteAll(result: @escaping FlutterResult) {
        do {
            try keychainService.deleteAll()
            result(nil)
        } catch {
            result(FlutterError(code: "STORAGE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func checkPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let permission = args["permission"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing permission", details: nil))
            return
        }
        
        permissionManager.checkPermission(permission: permission) { granted in
            result(granted)
        }
    }
    
    private func requestPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let permission = args["permission"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing permission", details: nil))
            return
        }
        
        permissionManager.requestPermission(permission: permission) { granted in
            result(granted)
        }
    }
    
    private func requestPermissions(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let permissions = args["permissions"] as? [String] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing permissions", details: nil))
            return
        }
        
        var results: [String: Bool] = [:]
        let group = DispatchGroup()
        
        for permission in permissions {
            group.enter()
            permissionManager.requestPermission(permission: permission) { granted in
                results[permission] = granted
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            result(results)
        }
    }
    
    private func shutdown(result: @escaping FlutterResult) {
        // Stop background tasks
        backgroundTaskManager.isRunning = false
        
        // Cancel all notifications
        notificationManager.cancelAllNotifications()
        
        result(nil)
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}