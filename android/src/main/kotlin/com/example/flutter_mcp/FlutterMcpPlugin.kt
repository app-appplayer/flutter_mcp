package com.example.flutter_mcp

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import com.example.flutter_mcp.background.BackgroundService
import com.example.flutter_mcp.background.BackgroundTaskScheduler
import com.example.flutter_mcp.notification.NotificationService
import com.example.flutter_mcp.storage.SecureStorageService
import com.example.flutter_mcp.utils.PermissionManager

/** FlutterMcpPlugin */
class FlutterMcpPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, 
    EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {
  
  private lateinit var context: Context
  private lateinit var channel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private var activity: Activity? = null
  private var eventSink: EventChannel.EventSink? = null
  
  // Services
  private lateinit var secureStorage: SecureStorageService
  private lateinit var notificationService: NotificationService
  private lateinit var backgroundScheduler: BackgroundTaskScheduler
  private lateinit var permissionManager: PermissionManager

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    
    // Initialize services
    secureStorage = SecureStorageService(context)
    notificationService = NotificationService(context)
    backgroundScheduler = BackgroundTaskScheduler(context)
    permissionManager = PermissionManager()
    
    // Set up method channel
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_mcp")
    channel.setMethodCallHandler(this)
    
    // Set up event channel
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_mcp/events")
    eventChannel.setStreamHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      // Platform info
      "getPlatformVersion" -> {
        result.success("Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})")
      }
      
      // Initialization
      "initialize" -> {
        val config = call.arguments as? Map<String, Any>
        initialize(config, result)
      }
      
      // Background service
      "startBackgroundService" -> {
        startBackgroundService(result)
      }
      "stopBackgroundService" -> {
        stopBackgroundService(result)
      }
      "configureBackgroundService" -> {
        val config = call.arguments as? Map<String, Any>
        configureBackgroundService(config, result)
      }
      "scheduleBackgroundTask" -> {
        val taskId = call.argument<String>("taskId")
        val delayMillis = call.argument<Long>("delayMillis")
        val data = call.argument<Map<String, Any>>("data")
        scheduleBackgroundTask(taskId, delayMillis, data, result)
      }
      "cancelBackgroundTask" -> {
        val taskId = call.argument<String>("taskId")
        cancelBackgroundTask(taskId, result)
      }
      
      // Notifications
      "showNotification" -> {
        val title = call.argument<String>("title") ?: ""
        val body = call.argument<String>("body") ?: ""
        val icon = call.argument<String>("icon")
        val id = call.argument<String>("id") ?: "default"
        showNotification(title, body, icon, id, result)
      }
      "requestNotificationPermission" -> {
        requestNotificationPermission(result)
      }
      "configureNotifications" -> {
        val config = call.arguments as? Map<String, Any>
        configureNotifications(config, result)
      }
      "cancelNotification" -> {
        val id = call.argument<String>("id") ?: ""
        cancelNotification(id, result)
      }
      "cancelAllNotifications" -> {
        cancelAllNotifications(result)
      }
      
      // Secure storage
      "secureStore" -> {
        val key = call.argument<String>("key") ?: ""
        val value = call.argument<String>("value") ?: ""
        secureStore(key, value, result)
      }
      "secureRead" -> {
        val key = call.argument<String>("key") ?: ""
        secureRead(key, result)
      }
      "secureDelete" -> {
        val key = call.argument<String>("key") ?: ""
        secureDelete(key, result)
      }
      "secureContainsKey" -> {
        val key = call.argument<String>("key") ?: ""
        secureContainsKey(key, result)
      }
      "secureDeleteAll" -> {
        secureDeleteAll(result)
      }
      
      // Permissions
      "checkPermission" -> {
        val permission = call.argument<String>("permission") ?: ""
        checkPermission(permission, result)
      }
      "requestPermission" -> {
        val permission = call.argument<String>("permission") ?: ""
        requestPermission(permission, result)
      }
      "requestPermissions" -> {
        val permissions = call.argument<List<String>>("permissions") ?: emptyList()
        requestPermissions(permissions, result)
      }
      
      // Lifecycle
      "shutdown" -> {
        shutdown(result)
      }
      
      else -> {
        result.notImplemented()
      }
    }
  }
  
  // Implementation methods
  
  private fun initialize(config: Map<String, Any>?, result: Result) {
    try {
      // Initialize components based on config
      if (config != null) {
        // Apply configuration
      }
      result.success(null)
    } catch (e: Exception) {
      result.error("INIT_ERROR", "Failed to initialize: ${e.message}", null)
    }
  }
  
  private fun startBackgroundService(result: Result) {
    try {
      val intent = Intent(context, BackgroundService::class.java).apply {
        action = BackgroundService.ACTION_START
      }
      context.startService(intent)
      result.success(true)
    } catch (e: Exception) {
      result.error("BACKGROUND_ERROR", "Failed to start background service: ${e.message}", null)
    }
  }
  
  private fun stopBackgroundService(result: Result) {
    try {
      val intent = Intent(context, BackgroundService::class.java).apply {
        action = BackgroundService.ACTION_STOP
      }
      context.startService(intent)
      result.success(true)
    } catch (e: Exception) {
      result.error("BACKGROUND_ERROR", "Failed to stop background service: ${e.message}", null)
    }
  }
  
  private fun configureBackgroundService(config: Map<String, Any>?, result: Result) {
    try {
      // Store configuration for background service
      result.success(null)
    } catch (e: Exception) {
      result.error("BACKGROUND_ERROR", "Failed to configure background service: ${e.message}", null)
    }
  }
  
  private fun scheduleBackgroundTask(taskId: String?, delayMillis: Long?, data: Map<String, Any>?, result: Result) {
    if (taskId == null || delayMillis == null) {
      result.error("INVALID_ARGS", "Missing required arguments", null)
      return
    }
    
    try {
      backgroundScheduler.scheduleTask(taskId, delayMillis, data)
      result.success(null)
    } catch (e: Exception) {
      result.error("BACKGROUND_ERROR", "Failed to schedule task: ${e.message}", null)
    }
  }
  
  private fun cancelBackgroundTask(taskId: String?, result: Result) {
    if (taskId == null) {
      result.error("INVALID_ARGS", "Missing task ID", null)
      return
    }
    
    try {
      backgroundScheduler.cancelTask(taskId)
      result.success(null)
    } catch (e: Exception) {
      result.error("BACKGROUND_ERROR", "Failed to cancel task: ${e.message}", null)
    }
  }
  
  private fun showNotification(title: String, body: String, icon: String?, id: String, result: Result) {
    try {
      notificationService.showNotification(title, body, icon, id)
      result.success(null)
    } catch (e: Exception) {
      result.error("NOTIFICATION_ERROR", "Failed to show notification: ${e.message}", null)
    }
  }
  
  private fun requestNotificationPermission(result: Result) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      activity?.let {
        permissionManager.requestNotificationPermission(it) { granted ->
          result.success(granted)
        }
      } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    } else {
      // Permission not required for older versions
      result.success(true)
    }
  }
  
  private fun configureNotifications(config: Map<String, Any>?, result: Result) {
    try {
      if (config != null) {
        notificationService.configure(config)
      }
      result.success(null)
    } catch (e: Exception) {
      result.error("NOTIFICATION_ERROR", "Failed to configure notifications: ${e.message}", null)
    }
  }
  
  private fun cancelNotification(id: String, result: Result) {
    try {
      notificationService.cancelNotification(id)
      result.success(null)
    } catch (e: Exception) {
      result.error("NOTIFICATION_ERROR", "Failed to cancel notification: ${e.message}", null)
    }
  }
  
  private fun cancelAllNotifications(result: Result) {
    try {
      notificationService.cancelAllNotifications()
      result.success(null)
    } catch (e: Exception) {
      result.error("NOTIFICATION_ERROR", "Failed to cancel all notifications: ${e.message}", null)
    }
  }
  
  private fun secureStore(key: String, value: String, result: Result) {
    try {
      val success = secureStorage.store(key, value)
      if (success) {
        result.success(null)
      } else {
        result.error("STORAGE_ERROR", "Failed to store value", null)
      }
    } catch (e: Exception) {
      result.error("STORAGE_ERROR", "Failed to store secure value: ${e.message}", null)
    }
  }
  
  private fun secureRead(key: String, result: Result) {
    try {
      val value = secureStorage.read(key)
      if (value != null) {
        result.success(value)
      } else {
        result.error("KEY_NOT_FOUND", "Key not found", null)
      }
    } catch (e: Exception) {
      result.error("STORAGE_ERROR", "Failed to read secure value: ${e.message}", null)
    }
  }
  
  private fun secureDelete(key: String, result: Result) {
    try {
      val success = secureStorage.delete(key)
      result.success(null)
    } catch (e: Exception) {
      result.error("STORAGE_ERROR", "Failed to delete secure value: ${e.message}", null)
    }
  }
  
  private fun secureContainsKey(key: String, result: Result) {
    try {
      val contains = secureStorage.containsKey(key)
      result.success(contains)
    } catch (e: Exception) {
      result.error("STORAGE_ERROR", "Failed to check secure key: ${e.message}", null)
    }
  }
  
  private fun secureDeleteAll(result: Result) {
    try {
      val success = secureStorage.deleteAll()
      result.success(null)
    } catch (e: Exception) {
      result.error("STORAGE_ERROR", "Failed to delete all secure values: ${e.message}", null)
    }
  }
  
  private fun checkPermission(permission: String, result: Result) {
    try {
      val hasPermission = permissionManager.checkPermission(context, permission)
      result.success(hasPermission)
    } catch (e: Exception) {
      result.error("PERMISSION_ERROR", "Failed to check permission: ${e.message}", null)
    }
  }
  
  private fun requestPermission(permission: String, result: Result) {
    activity?.let {
      permissionManager.requestPermission(it, permission) { granted ->
        result.success(granted)
      }
    } ?: result.error("NO_ACTIVITY", "Activity not available", null)
  }
  
  private fun requestPermissions(permissions: List<String>, result: Result) {
    activity?.let { activity ->
      val results = mutableMapOf<String, Boolean>()
      var remaining = permissions.size
      
      if (permissions.isEmpty()) {
        result.success(results)
        return
      }
      
      permissions.forEach { permission ->
        permissionManager.requestPermission(activity, permission) { granted ->
          results[permission] = granted
          remaining--
          if (remaining == 0) {
            result.success(results)
          }
        }
      }
    } ?: result.error("NO_ACTIVITY", "Activity not available", null)
  }
  
  private fun shutdown(result: Result) {
    try {
      // Stop background service if running
      if (BackgroundService.isRunning) {
        val intent = Intent(context, BackgroundService::class.java).apply {
          action = BackgroundService.ACTION_STOP
        }
        context.startService(intent)
      }
      
      // Cancel all notifications
      notificationService.cancelAllNotifications()
      
      result.success(null)
    } catch (e: Exception) {
      result.error("SHUTDOWN_ERROR", "Failed to shutdown: ${e.message}", null)
    }
  }
  
  // Activity aware
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }
  
  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }
  
  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }
  
  override fun onDetachedFromActivity() {
    activity = null
  }
  
  // Event channel
  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }
  
  override fun onCancel(arguments: Any?) {
    eventSink = null
  }
  
  // Permission result
  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    return permissionManager.handlePermissionResult(requestCode, permissions, grantResults)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
  }
}