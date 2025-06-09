import Foundation
import UserNotifications

class PermissionManager {
    func checkPermission(permission: String, completion: @escaping (Bool) -> Void) {
        switch permission {
        case "notification":
            checkNotificationPermission(completion: completion)
        default:
            // iOS doesn't require explicit permissions for most features
            completion(true)
        }
    }
    
    func requestPermission(permission: String, completion: @escaping (Bool) -> Void) {
        switch permission {
        case "notification":
            requestNotificationPermission(completion: completion)
        default:
            // iOS doesn't require explicit permissions for most features
            completion(true)
        }
    }
    
    private func checkNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }
    
    private func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}