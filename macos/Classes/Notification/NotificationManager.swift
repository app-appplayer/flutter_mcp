import UserNotifications
import Foundation

class NotificationManager: NSObject {
    private let notificationCenter = NSUserNotificationCenter.default
    
    override init() {
        super.init()
    }
    
    func setupDelegate() {
        notificationCenter.delegate = self
    }
    
    func configure(config: [String: Any]) {
        // Configuration can be extended as needed
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
extension NotificationManager: NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        // Show notification even when app is in foreground
        return true
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        // Handle notification click
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