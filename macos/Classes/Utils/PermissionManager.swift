import Foundation

class PermissionManager {
    func checkPermission(permission: String) -> Bool {
        // macOS doesn't require explicit permissions for most features
        return true
    }
    
    func requestPermission(permission: String) -> Bool {
        // macOS doesn't require explicit permissions for most features
        return true
    }
}