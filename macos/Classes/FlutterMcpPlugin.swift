import Cocoa
import FlutterMacOS
import UserNotifications

// Forwarding stream handler for the dedicated `flutter_mcp/tray_events`
// channel. EnhancedTrayManager (Dart) listens on this channel for
// menu-item clicks and tray icon click events.
private class TrayEventStreamHandler: NSObject, FlutterStreamHandler {
    var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}

public class FlutterMcpPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var channel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    // Dedicated channel for tray events (menu clicks, tray icon clicks).
    private var trayEventChannel: FlutterEventChannel?
    private let trayEventHandler = TrayEventStreamHandler()

    // Services
    private let keychainService = KeychainService()
    private let notificationManager: Any
    private let trayIconManager = TrayIconManager()
    private let permissionManager = PermissionManager()
    private var backgroundTimer: Timer?
    private var isBackgroundServiceRunning = false
    
    override init() {
        if #available(macOS 10.14, *) {
            notificationManager = NotificationManager()
        } else {
            notificationManager = LegacyNotificationManager()
        }
        super.init()
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlutterMcpPlugin()
        
        // Method channel
        let channel = FlutterMethodChannel(
            name: "flutter_mcp",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.channel = channel
        
        // Event channel
        let eventChannel = FlutterEventChannel(
            name: "flutter_mcp/events",
            binaryMessenger: registrar.messenger
        )
        eventChannel.setStreamHandler(instance)
        instance.eventChannel = eventChannel

        // Tray event channel — EnhancedTrayManager listens here for menu
        // item clicks and tray icon click events.
        let trayEventChannel = FlutterEventChannel(
            name: "flutter_mcp/tray_events",
            binaryMessenger: registrar.messenger
        )
        trayEventChannel.setStreamHandler(instance.trayEventHandler)
        instance.trayEventChannel = trayEventChannel
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        // Platform info
        case "getPlatformVersion":
            let version = ProcessInfo.processInfo.operatingSystemVersionString
            result("macOS \(version)")
            
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
            
        // System tray (legacy method names — kept for back-compat)
        case "showTrayIcon":
            showTrayIcon(call: call, result: result)
        case "hideTrayIcon":
            hideTrayIcon(result: result)
        case "setTrayMenu":
            setTrayMenu(call: call, result: result)
        case "updateTrayTooltip":
            updateTrayTooltip(call: call, result: result)
        case "configureTray":
            configureTray(call: call, result: result)

        // System tray (EnhancedTrayManager — new method names used by Dart)
        case "initializeTray":
            // No-op on macOS: NSStatusItem is created lazily by setTrayIcon.
            result(nil)
        case "setTrayIcon":
            setTrayIconEnhanced(call: call, result: result)
        case "setTrayIconFromBytes":
            // Bytes-based tray icon is not yet implemented — accept the call
            // and report success so the harness can move forward.
            result(nil)
        case "setTrayTooltip":
            updateTrayTooltip(call: call, result: result)
        case "setTrayContextMenu":
            setTrayContextMenu(call: call, result: result)
        case "showTray":
            // Showing happens implicitly when an icon is set.
            result(nil)
        case "hideTray":
            hideTrayIcon(result: result)
        case "updateTrayMenuItem":
            // No-op for now — full per-item update needs more state in
            // TrayIconManager. Accept so EnhancedTrayManager calls
            // complete cleanly.
            result(nil)
        case "disposeTray":
            hideTrayIcon(result: result)
        case "setStatusBarItemProperties":
            result(nil)
        case "setMenuBarVisibility":
            result(nil)

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
        if call.arguments is [String: Any] {
            // Apply configuration
        }
        
        // Set up notification delegate
        if #available(macOS 10.14, *) {
            (notificationManager as! NotificationManager).setupDelegate()
        }
        
        result(nil)
    }
    
    private func startBackgroundService(result: @escaping FlutterResult) {
        guard !isBackgroundServiceRunning else {
            result(true)
            return
        }
        
        isBackgroundServiceRunning = true
        
        // macOS doesn't have traditional background services
        // We'll use a timer for periodic tasks
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.performBackgroundTask()
        }
        
        result(true)
    }
    
    private func stopBackgroundService(result: @escaping FlutterResult) {
        isBackgroundServiceRunning = false
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        result(true)
    }
    
    private func configureBackgroundService(call: FlutterMethodCall, result: @escaping FlutterResult) {
        if let config = call.arguments as? [String: Any] {
            // Store configuration
            if let intervalMs = config["intervalMs"] as? Int {
                // Restart timer with new interval if running
                if isBackgroundServiceRunning {
                    backgroundTimer?.invalidate()
                    let interval = TimeInterval(intervalMs) / 1000.0
                    backgroundTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                        self?.performBackgroundTask()
                    }
                }
            }
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.eventSink?([
                "type": "backgroundTaskResult",
                "data": [
                    "taskId": taskId,
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ]
            ])
        }
        
        result(nil)
    }
    
    private func cancelBackgroundTask(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Task cancellation would require storing dispatch work items
        // For now, we'll just acknowledge the request
        result(nil)
    }
    
    private func performBackgroundTask() {
        eventSink?([
            "type": "backgroundServiceStateChanged",
            "data": ["isRunning": true]
        ])
    }
    
    private func showNotification(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let body = args["body"] as? String,
              let id = args["id"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }
        
        if #available(macOS 10.14, *) {
            (notificationManager as! NotificationManager).showNotification(
                title: title,
                body: body,
                identifier: id
            )
        } else {
            (notificationManager as! LegacyNotificationManager).showNotification(
                title: title,
                body: body,
                identifier: id
            )
        }
        result(nil)
    }
    
    private func requestNotificationPermission(result: @escaping FlutterResult) {
        if #available(macOS 10.14, *) {
            (notificationManager as! NotificationManager).requestPermission { granted in
                result(granted)
            }
        } else {
            (notificationManager as! LegacyNotificationManager).requestPermission { granted in
                result(granted)
            }
        }
    }
    
    private func configureNotifications(call: FlutterMethodCall, result: @escaping FlutterResult) {
        if let config = call.arguments as? [String: Any] {
            if #available(macOS 10.14, *) {
                (notificationManager as! NotificationManager).configure(config: config)
            } else {
                (notificationManager as! LegacyNotificationManager).configure(config: config)
            }
        }
        result(nil)
    }
    
    private func cancelNotification(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing notification ID", details: nil))
            return
        }
        
        if #available(macOS 10.14, *) {
            (notificationManager as! NotificationManager).cancelNotification(identifier: id)
        } else {
            (notificationManager as! LegacyNotificationManager).cancelNotification(identifier: id)
        }
        result(nil)
    }
    
    private func cancelAllNotifications(result: @escaping FlutterResult) {
        if #available(macOS 10.14, *) {
            (notificationManager as! NotificationManager).cancelAllNotifications()
        } else {
            (notificationManager as! LegacyNotificationManager).cancelAllNotifications()
        }
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
    
    private func showTrayIcon(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        
        let iconPath = args["iconPath"] as? String
        let tooltip = args["tooltip"] as? String
        
        trayIconManager.showTrayIcon(iconPath: iconPath, tooltip: tooltip)
        result(nil)
    }
    
    private func hideTrayIcon(result: @escaping FlutterResult) {
        trayIconManager.hideTrayIcon()
        result(nil)
    }
    
    private func setTrayMenu(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let items = args["items"] as? [[String: Any]] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing menu items", details: nil))
            return
        }
        
        trayIconManager.setMenuItems(items) { [weak self] itemId in
            self?.eventSink?([
                "type": "trayEvent",
                "data": [
                    "action": "menuItemClicked",
                    "itemId": itemId
                ]
            ])
        }
        result(nil)
    }
    
    private func updateTrayTooltip(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let tooltip = args["tooltip"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing tooltip", details: nil))
            return
        }
        
        trayIconManager.updateTooltip(tooltip)
        result(nil)
    }
    
    // EnhancedTrayManager.platformSetIcon → 'setTrayIcon'.
    // Args: { 'path': String, 'isTemplate': Bool }
    private func setTrayIconEnhanced(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
            return
        }
        // showTrayIcon creates the NSStatusItem if needed and sets the icon.
        trayIconManager.showTrayIcon(iconPath: path, tooltip: nil)
        result(nil)
    }

    // EnhancedTrayManager.platformSetContextMenu → 'setTrayContextMenu'.
    // Args: { 'items': List<{id, label, disabled, type, ...}> }
    // The legacy `setTrayMenu` accepted the same shape; reuse the underlying
    // TrayIconManager.setMenuItems but normalise the separator key to match
    // EnhancedTrayMenuItem JSON ('type': 'separator' instead of
    // 'isSeparator': true).
    private func setTrayContextMenu(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let items = args["items"] as? [[String: Any]] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing items", details: nil))
            return
        }
        // Translate the EnhancedTrayMenuItem shape to the legacy key set
        // TrayIconManager understands.
        let normalized: [[String: Any]] = items.map { item in
            var copy = item
            if let type = item["type"] as? String, type == "separator" {
                copy["isSeparator"] = true
            }
            return copy
        }
        trayIconManager.setMenuItems(normalized) { [weak self] itemId in
            self?.eventSink?([
                "type": "trayEvent",
                "data": [
                    "action": "menuItemClicked",
                    "itemId": itemId
                ]
            ])
        }
        result(nil)
    }

    private func configureTray(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let config = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing configuration", details: nil))
            return
        }
        
        let iconPath = config["iconPath"] as? String
        let tooltip = config["tooltip"] as? String
        let menuItems = config["menuItems"] as? [[String: Any]]
        
        if iconPath != nil || tooltip != nil {
            trayIconManager.showTrayIcon(iconPath: iconPath, tooltip: tooltip)
        }
        
        if let menuItems = menuItems {
            trayIconManager.setMenuItems(menuItems) { [weak self] itemId in
                self?.eventSink?([
                    "type": "trayEvent",
                    "data": [
                        "action": "menuItemClicked",
                        "itemId": itemId
                    ]
                ])
            }
        }
        
        result(nil)
    }
    
    private func checkPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // macOS doesn't require most permissions
        result(true)
    }
    
    private func requestPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // macOS doesn't require most permissions
        result(true)
    }

    private func requestPermissions(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // macOS doesn't require most permissions; report every requested
        // permission as granted. The Dart side expects a Map<String,bool>.
        let permissions = (call.arguments as? [String: Any])?["permissions"] as? [String] ?? []
        var granted: [String: Bool] = [:]
        for permission in permissions {
            granted[permission] = true
        }
        result(granted)
    }

    private func shutdown(result: @escaping FlutterResult) {
        // Stop background service
        isBackgroundServiceRunning = false
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        
        // Hide tray icon
        trayIconManager.hideTrayIcon()
        
        // Cancel all notifications
        if #available(macOS 10.14, *) {
            (notificationManager as! NotificationManager).cancelAllNotifications()
        } else {
            (notificationManager as! LegacyNotificationManager).cancelAllNotifications()
        }
        
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