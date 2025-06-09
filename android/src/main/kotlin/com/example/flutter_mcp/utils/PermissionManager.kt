package com.example.flutter_mcp.utils

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class PermissionManager {
    private val permissionCallbacks = mutableMapOf<Int, (Boolean) -> Unit>()
    private var requestCode = Constants.NOTIFICATION_PERMISSION_CODE
    
    fun checkPermission(context: Context, permission: String): Boolean {
        val androidPermission = mapToAndroidPermission(permission) ?: return false
        return ContextCompat.checkSelfPermission(context, androidPermission) == PackageManager.PERMISSION_GRANTED
    }
    
    fun requestPermission(activity: Activity, permission: String, callback: (Boolean) -> Unit) {
        val androidPermission = mapToAndroidPermission(permission) ?: run {
            callback(false)
            return
        }
        
        if (checkPermission(activity, permission)) {
            callback(true)
            return
        }
        
        val code = requestCode++
        permissionCallbacks[code] = callback
        
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(androidPermission),
            code
        )
    }
    
    fun requestNotificationPermission(activity: Activity, callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermission(activity, "notification", callback)
        } else {
            callback(true)
        }
    }
    
    fun handlePermissionResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        val callback = permissionCallbacks.remove(requestCode) ?: return false
        
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        callback(granted)
        
        return true
    }
    
    private fun mapToAndroidPermission(permission: String): String? {
        return when (permission) {
            "notification" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Manifest.permission.POST_NOTIFICATIONS
            } else null
            "storage" -> Manifest.permission.WRITE_EXTERNAL_STORAGE
            "backgroundExecution" -> null // No specific permission needed
            "systemAlertWindow" -> Manifest.permission.SYSTEM_ALERT_WINDOW
            "scheduleExactAlarm" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Manifest.permission.SCHEDULE_EXACT_ALARM
            } else null
            "location" -> Manifest.permission.ACCESS_FINE_LOCATION
            "locationBackground" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Manifest.permission.ACCESS_BACKGROUND_LOCATION
            } else null
            "camera" -> Manifest.permission.CAMERA
            "microphone" -> Manifest.permission.RECORD_AUDIO
            "wakeLock" -> Manifest.permission.WAKE_LOCK
            "bootCompleted" -> Manifest.permission.RECEIVE_BOOT_COMPLETED
            else -> null
        }
    }
}