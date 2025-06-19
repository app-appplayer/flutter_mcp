import UserNotifications
import Foundation

@available(macOS 10.14, *)
class NotificationManager: NSObject {
    private let notificationCenter = UNUserNotificationCenter.current()
    
    override init() {
        super.init()
        setupDelegate()
    }
    
    func setupDelegate() {
        notificationCenter.delegate = self
    }
    
    func configure(config: [String: Any]) {
        // Configuration can be extended as needed
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error)")
            }
            completion(granted)
        }
    }
    
    func showNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }
    
    func cancelNotification(identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate
@available(macOS 10.14, *)
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                              willPresent notification: UNNotification, 
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                              didReceive response: UNNotificationResponse, 
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification click
        NotificationCenter.default.post(
            name: Notification.Name("flutter_mcp_notification_received"),
            object: nil,
            userInfo: [
                "identifier": response.notification.request.identifier,
                "action": response.actionIdentifier == UNNotificationDefaultActionIdentifier ? "clicked" : response.actionIdentifier
            ]
        )
        completionHandler()
    }
}

// Legacy NotificationManager for macOS < 10.14
class LegacyNotificationManager: NSObject {
    private let notificationCenter = NSUserNotificationCenter.default
    
    override init() {
        super.init()
        notificationCenter.delegate = self
    }
    
    func configure(config: [String: Any]) {
        // Configuration can be extended as needed
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        // NSUserNotification doesn't require permission
        completion(true)
    }
    
    func showNotification(title: String, body: String, identifier: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.identifier = identifier
        notification.soundName = NSUserNotificationDefaultSoundName
        
        notificationCenter.deliver(notification)
    }
    
    func cancelNotification(identifier: String) {
        for notification in notificationCenter.deliveredNotifications {
            if notification.identifier == identifier {
                notificationCenter.removeDeliveredNotification(notification)
            }
        }
        
        for notification in notificationCenter.scheduledNotifications {
            if notification.identifier == identifier {
                notificationCenter.removeScheduledNotification(notification)
            }
        }
    }
    
    func cancelAllNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
        for notification in notificationCenter.scheduledNotifications {
            notificationCenter.removeScheduledNotification(notification)
        }
    }
}

// MARK: - NSUserNotificationCenterDelegate
extension LegacyNotificationManager: NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        NotificationCenter.default.post(
            name: Notification.Name("flutter_mcp_notification_received"),
            object: nil,
            userInfo: [
                "identifier": notification.identifier ?? "",
                "action": "clicked"
            ]
        )
    }
}

// Factory to create appropriate notification manager based on OS version
class NotificationManagerFactory {
    static func create() -> Any {
        if #available(macOS 10.14, *) {
            return NotificationManager()
        } else {
            return LegacyNotificationManager()
        }
    }
}