# Android Integration Example

This example demonstrates Android-specific Flutter MCP features, including background services, notifications, and native API integration.

## Overview

This example shows how to:
- Implement Android background services
- Handle push notifications
- Integrate with Android APIs
- Work with Android permissions

## Background Service Implementation

### Kotlin Service Implementation

```kotlin
// android/app/src/main/kotlin/com/example/flutter_mcp/BackgroundService.kt
package com.example.flutter_mcp

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class BackgroundService : Service() {
    private var flutterEngine: FlutterEngine? = null
    private val CHANNEL_ID = "flutter_mcp_background"
    private val NOTIFICATION_ID = 1001
    
    companion object {
        const val ACTION_START = "com.example.flutter_mcp.START_BACKGROUND"
        const val ACTION_STOP = "com.example.flutter_mcp.STOP_BACKGROUND"
    }
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        initializeFlutterEngine()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startBackgroundTask()
            ACTION_STOP -> stopSelf()
        }
        return START_STICKY
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Flutter MCP Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background service for Flutter MCP"
            }
            
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Flutter MCP")
            .setContentText("Background service is running")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .build()
    }
    
    private fun initializeFlutterEngine() {
        flutterEngine = FlutterEngine(this)
        
        // Start executing Dart code
        flutterEngine!!.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        
        // Initialize method channels
        MethodChannel(
            flutterEngine!!.dartExecutor.binaryMessenger,
            "flutter_mcp/background"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBackgroundData" -> {
                    val data = getBackgroundData()
                    result.success(data)
                }
                "updateNotification" -> {
                    val message = call.argument<String>("message")
                    updateNotification(message ?: "")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun startBackgroundTask() {
        // Call Dart code to start background task
        flutterEngine?.let { engine ->
            MethodChannel(
                engine.dartExecutor.binaryMessenger,
                "flutter_mcp/background_task"
            ).invokeMethod("startTask", null)
        }
    }
    
    private fun getBackgroundData(): Map<String, Any> {
        return mapOf(
            "timestamp" to System.currentTimeMillis(),
            "deviceInfo" to getDeviceInfo(),
            "batteryLevel" to getBatteryLevel()
        )
    }
    
    private fun getDeviceInfo(): Map<String, String> {
        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "androidVersion" to Build.VERSION.RELEASE
        )
    }
    
    private fun getBatteryLevel(): Int {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
        return batteryManager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }
    
    private fun updateNotification(message: String) {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Flutter MCP")
            .setContentText(message)
            .setSmallIcon(R.drawable.ic_notification)
            .build()
        
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        flutterEngine?.destroy()
        super.onDestroy()
    }
}
```

### Service Manager

```kotlin
// android/app/src/main/kotlin/com/example/flutter_mcp/ServiceManager.kt
package com.example.flutter_mcp

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.*
import java.util.concurrent.TimeUnit

class ServiceManager(private val context: Context) {
    
    fun startBackgroundService() {
        val intent = Intent(context, BackgroundService::class.java)
        intent.action = BackgroundService.ACTION_START
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }
    
    fun stopBackgroundService() {
        val intent = Intent(context, BackgroundService::class.java)
        intent.action = BackgroundService.ACTION_STOP
        context.startService(intent)
    }
    
    fun schedulePeriodicWork(tag: String, intervalMinutes: Long) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()
        
        val workRequest = PeriodicWorkRequestBuilder<MCPWorker>(
            intervalMinutes, TimeUnit.MINUTES
        )
            .setConstraints(constraints)
            .addTag(tag)
            .build()
        
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            tag,
            ExistingPeriodicWorkPolicy.REPLACE,
            workRequest
        )
    }
    
    fun cancelWork(tag: String) {
        WorkManager.getInstance(context).cancelAllWorkByTag(tag)
    }
}
```

### Work Manager Implementation

```kotlin
// android/app/src/main/kotlin/com/example/flutter_mcp/MCPWorker.kt
package com.example.flutter_mcp

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.runBlocking

class MCPWorker(context: Context, workerParams: WorkerParameters) : Worker(context, workerParams) {
    
    override fun doWork(): Result {
        return runBlocking {
            try {
                // Create Flutter engine for background work
                val flutterEngine = FlutterEngine(applicationContext)
                
                // Start Dart code
                flutterEngine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault()
                )
                
                // Execute background task
                val channel = MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    "flutter_mcp/worker"
                )
                
                val taskResult = channel.invokeMethod(
                    "executeBackgroundTask",
                    mapOf(
                        "taskId" to id.toString(),
                        "inputData" to inputData.keyValueMap
                    )
                )
                
                // Clean up
                flutterEngine.destroy()
                
                Result.success()
            } catch (e: Exception) {
                Result.failure()
            }
        }
    }
}
```

## Push Notifications

### Firebase Messaging Service

```kotlin
// android/app/src/main/kotlin/com/example/flutter_mcp/FCMService.kt
package com.example.flutter_mcp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.MethodChannel

class FCMService : FirebaseMessagingService() {
    
    companion object {
        const val CHANNEL_ID = "flutter_mcp_notifications"
        const val CHANNEL_NAME = "Flutter MCP Notifications"
        var methodChannel: MethodChannel? = null
    }
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }
    
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        
        // Handle data payload
        if (remoteMessage.data.isNotEmpty()) {
            handleDataMessage(remoteMessage.data)
        }
        
        // Handle notification payload
        remoteMessage.notification?.let {
            showNotification(it)
        }
    }
    
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        
        // Send token to Flutter
        methodChannel?.invokeMethod("onTokenRefresh", token)
        
        // Send token to server
        sendTokenToServer(token)
    }
    
    private fun handleDataMessage(data: Map<String, String>) {
        when (data["type"]) {
            "sync" -> triggerDataSync()
            "update" -> handleUpdate(data)
            "command" -> executeCommand(data)
            else -> handleCustomMessage(data)
        }
    }
    
    private fun showNotification(notification: RemoteMessage.Notification) {
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(notification.title)
            .setContentText(notification.body)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
        
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(System.currentTimeMillis().toInt(), notificationBuilder.build())
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for Flutter MCP"
                enableLights(true)
                enableVibration(true)
            }
            
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun triggerDataSync() {
        val intent = Intent(this, BackgroundService::class.java)
        intent.action = "SYNC_DATA"
        startService(intent)
    }
    
    private fun handleUpdate(data: Map<String, String>) {
        methodChannel?.invokeMethod("handleUpdate", data)
    }
    
    private fun executeCommand(data: Map<String, String>) {
        val command = data["command"] ?: return
        val params = data.filterKeys { it != "command" && it != "type" }
        
        methodChannel?.invokeMethod("executeCommand", mapOf(
            "command" to command,
            "params" to params
        ))
    }
    
    private fun handleCustomMessage(data: Map<String, String>) {
        methodChannel?.invokeMethod("handleCustomMessage", data)
    }
    
    private fun sendTokenToServer(token: String) {
        // Implementation to send token to your server
    }
}
```

### Notification Manager

```kotlin
// android/app/src/main/kotlin/com/example/flutter_mcp/NotificationManager.kt
package com.example.flutter_mcp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class MCPNotificationManager(private val context: Context) {
    
    companion object {
        const val CHANNEL_ID_DEFAULT = "flutter_mcp_default"
        const val CHANNEL_ID_HIGH = "flutter_mcp_high_priority"
        const val CHANNEL_ID_ONGOING = "flutter_mcp_ongoing"
    }
    
    init {
        createNotificationChannels()
    }
    
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channels = listOf(
                NotificationChannel(
                    CHANNEL_ID_DEFAULT,
                    "Default Notifications",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "General notifications"
                },
                NotificationChannel(
                    CHANNEL_ID_HIGH,
                    "Important Notifications",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "High priority notifications"
                    enableLights(true)
                    enableVibration(true)
                },
                NotificationChannel(
                    CHANNEL_ID_ONGOING,
                    "Ongoing Notifications",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Persistent notifications"
                    setShowBadge(false)
                }
            )
            
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            channels.forEach { notificationManager.createNotificationChannel(it) }
        }
    }
    
    fun showNotification(
        id: Int,
        title: String,
        content: String,
        priority: NotificationPriority = NotificationPriority.DEFAULT,
        actions: List<NotificationAction> = emptyList(),
        ongoing: Boolean = false
    ) {
        val channelId = when (priority) {
            NotificationPriority.HIGH -> CHANNEL_ID_HIGH
            NotificationPriority.DEFAULT -> CHANNEL_ID_DEFAULT
            NotificationPriority.LOW -> CHANNEL_ID_ONGOING
        }
        
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(content)
            .setPriority(priority.androidPriority)
            .setAutoCancel(!ongoing)
            .setOngoing(ongoing)
        
        // Add actions
        actions.forEach { action ->
            val intent = Intent(context, NotificationActionReceiver::class.java).apply {
                this.action = action.actionId
                putExtra("notification_id", id)
                putExtra("action_data", action.data)
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                action.requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            builder.addAction(
                action.icon,
                action.label,
                pendingIntent
            )
        }
        
        // Set content intent
        val contentIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("notification_id", id)
        }
        
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            id,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        builder.setContentIntent(contentPendingIntent)
        
        // Show notification
        with(NotificationManagerCompat.from(context)) {
            notify(id, builder.build())
        }
    }
    
    fun updateNotificationProgress(
        id: Int,
        title: String,
        progress: Int,
        max: Int = 100
    ) {
        val builder = NotificationCompat.Builder(context, CHANNEL_ID_ONGOING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setProgress(max, progress, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        
        with(NotificationManagerCompat.from(context)) {
            notify(id, builder.build())
        }
    }
    
    fun cancelNotification(id: Int) {
        with(NotificationManagerCompat.from(context)) {
            cancel(id)
        }
    }
    
    fun cancelAllNotifications() {
        with(NotificationManagerCompat.from(context)) {
            cancelAll()
        }
    }
}

enum class NotificationPriority(val androidPriority: Int) {
    HIGH(NotificationCompat.PRIORITY_HIGH),
    DEFAULT(NotificationCompat.PRIORITY_DEFAULT),
    LOW(NotificationCompat.PRIORITY_LOW)
}

data class NotificationAction(
    val actionId: String,
    val label: String,
    val icon: Int = 0,
    val requestCode: Int = System.currentTimeMillis().toInt(),
    val data: Map<String, String> = emptyMap()
)
```

## Native API Integration

### Platform Channel Handler

```kotlin
// android/app/src/main/kotlin/com/example/flutter_mcp/PlatformChannelHandler.kt
package com.example.flutter_mcp

import android.content.Context
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import io.flutter.plugin.common.MethodChannel

class PlatformChannelHandler(private val context: Context) {
    
    fun setupMethodChannel(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> result.success(getDeviceInfo())
                "getBatteryLevel" -> result.success(getBatteryLevel())
                "getNetworkInfo" -> result.success(getNetworkInfo())
                "getLocationStatus" -> result.success(getLocationStatus())
                "requestPermissions" -> {
                    val permissions = call.argument<List<String>>("permissions")
                    requestPermissions(permissions ?: emptyList(), result)
                }
                "checkPermissions" -> {
                    val permissions = call.argument<List<String>>("permissions")
                    result.success(checkPermissions(permissions ?: emptyList()))
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "device" to Build.DEVICE,
            "product" to Build.PRODUCT,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "hardware" to Build.HARDWARE,
            "isPhysicalDevice" to !isEmulator(),
            "supportedAbis" to Build.SUPPORTED_ABIS.toList()
        )
    }
    
    private fun isEmulator(): Boolean {
        return (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic"))
            || Build.FINGERPRINT.startsWith("generic")
            || Build.FINGERPRINT.startsWith("unknown")
            || Build.HARDWARE.contains("goldfish")
            || Build.HARDWARE.contains("ranchu")
            || Build.MODEL.contains("google_sdk")
            || Build.MODEL.contains("Emulator")
            || Build.MODEL.contains("Android SDK built for x86")
            || Build.MANUFACTURER.contains("Genymotion")
            || Build.PRODUCT.contains("sdk")
            || Build.PRODUCT.contains("google_sdk")
            || Build.PRODUCT.contains("sdk_google")
            || Build.PRODUCT.contains("sdk_x86")
            || Build.PRODUCT.contains("vbox86p")
            || Build.PRODUCT.contains("emulator")
            || Build.PRODUCT.contains("simulator")
    }
    
    private fun getBatteryLevel(): Map<String, Any> {
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        
        return mapOf(
            "level" to batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
            "isCharging" to batteryManager.isCharging,
            "temperature" to batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_TEMPERATURE) / 10.0,
            "voltage" to batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_VOLTAGE) / 1000.0
        )
    }
    
    private fun getNetworkInfo(): Map<String, Any> {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = connectivityManager.activeNetwork
            val capabilities = connectivityManager.getNetworkCapabilities(network)
            
            mapOf(
                "isConnected" to (capabilities != null),
                "isWifi" to (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true),
                "isCellular" to (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true),
                "isEthernet" to (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true),
                "isVpn" to (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true),
                "isMetered" to (connectivityManager.isActiveNetworkMetered)
            )
        } else {
            val networkInfo = connectivityManager.activeNetworkInfo
            mapOf(
                "isConnected" to (networkInfo?.isConnected == true),
                "type" to (networkInfo?.typeName ?: "none")
            )
        }
    }
    
    private fun getLocationStatus(): Map<String, Any> {
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        
        return mapOf(
            "isGpsEnabled" to locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER),
            "isNetworkEnabled" to locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        )
    }
    
    private fun requestPermissions(permissions: List<String>, result: MethodChannel.Result) {
        // This should be handled by the activity
        result.error("ACTIVITY_REQUIRED", "Permission request must be handled by activity", null)
    }
    
    private fun checkPermissions(permissions: List<String>): Map<String, Boolean> {
        return permissions.associateWith { permission ->
            context.checkSelfPermission(permission) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }
    }
}
```

## Flutter Integration

### Android Service Manager

```dart
// lib/services/android_service_manager.dart
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class AndroidServiceManager {
  static const _channel = MethodChannel('flutter_mcp/android_service');
  static const _backgroundChannel = MethodChannel('flutter_mcp/background');
  
  static bool _isServiceRunning = false;
  
  static Future<void> startBackgroundService() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _channel.invokeMethod('startBackgroundService');
      _isServiceRunning = true;
    } catch (e) {
      print('Failed to start background service: $e');
    }
  }
  
  static Future<void> stopBackgroundService() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _channel.invokeMethod('stopBackgroundService');
      _isServiceRunning = false;
    } catch (e) {
      print('Failed to stop background service: $e');
    }
  }
  
  static bool get isServiceRunning => _isServiceRunning;
  
  static void setupBackgroundHandler() {
    _backgroundChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'executeBackgroundTask':
          final taskId = call.arguments['taskId'] as String;
          final inputData = call.arguments['inputData'] as Map<String, dynamic>;
          return await _executeBackgroundTask(taskId, inputData);
          
        case 'handleDataSync':
          return await _handleDataSync(call.arguments);
          
        default:
          return null;
      }
    });
  }
  
  static Future<Map<String, dynamic>> _executeBackgroundTask(
    String taskId,
    Map<String, dynamic> inputData,
  ) async {
    try {
      // Execute MCP operations in background
      final server = await FlutterMCP.connect('background-server');
      
      final result = await server.execute('processBackgroundTask', {
        'taskId': taskId,
        'data': inputData,
      });
      
      return {
        'success': true,
        'result': result,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  static Future<bool> _handleDataSync(Map<String, dynamic> data) async {
    try {
      final syncData = await LocalStorage.getUnsyncedData();
      
      if (syncData.isNotEmpty) {
        final server = await FlutterMCP.connect('sync-server');
        await server.execute('syncData', {'data': syncData});
        await LocalStorage.markDataAsSynced();
      }
      
      return true;
    } catch (e) {
      print('Data sync failed: $e');
      return false;
    }
  }
}
```

### Android Notification Manager

```dart
// lib/services/android_notification_manager.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class AndroidNotificationManager {
  static final FlutterLocalNotificationsPlugin _plugin = 
      FlutterLocalNotificationsPlugin();
  
  static const _androidChannel = AndroidNotificationChannel(
    'flutter_mcp_default',
    'Flutter MCP Notifications',
    description: 'Default notification channel',
    importance: Importance.high,
    playSound: true,
  );
  
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );
    
    // Create notification channels
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    await androidPlugin?.createNotificationChannel(_androidChannel);
  }
  
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    AndroidNotificationDetails? androidDetails,
  }) async {
    final details = NotificationDetails(
      android: androidDetails ?? AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        ticker: title,
      ),
    );
    
    await _plugin.show(id, title, body, details, payload: payload);
  }
  
  static Future<void> showProgressNotification({
    required int id,
    required String title,
    required int progress,
    int maxProgress = 100,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
    );
    
    await showNotification(
      id: id,
      title: title,
      body: '$progress%',
      androidDetails: androidDetails,
    );
  }
  
  static Future<void> showGroupedNotifications({
    required String groupKey,
    required List<NotificationData> notifications,
  }) async {
    // Show individual notifications
    for (final notification in notifications) {
      final androidDetails = AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        groupKey: groupKey,
      );
      
      await showNotification(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        androidDetails: androidDetails,
        payload: notification.payload,
      );
    }
    
    // Show group summary
    final summaryDetails = AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      groupKey: groupKey,
      setAsGroupSummary: true,
    );
    
    await showNotification(
      id: groupKey.hashCode,
      title: 'Flutter MCP',
      body: '${notifications.length} new notifications',
      androidDetails: summaryDetails,
    );
  }
  
  static void _handleNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      // Handle notification tap
      FlutterMCP.handleNotificationPayload(response.payload!);
    }
  }
  
  static Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }
  
  static Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }
}

class NotificationData {
  final int id;
  final String title;
  final String body;
  final String? payload;
  
  NotificationData({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });
}
```

## Android-Specific Features

### Permission Manager

```dart
// lib/services/android_permission_manager.dart
import 'package:permission_handler/permission_handler.dart';

class AndroidPermissionManager {
  static Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();
    return status == PermissionStatus.granted;
  }
  
  static Future<bool> requestBackgroundLocation() async {
    if (await Permission.locationAlways.isGranted) {
      return true;
    }
    
    // Show explanation dialog
    final shouldShowRationale = await Permission.locationAlways.shouldShowRequestRationale;
    
    if (shouldShowRationale) {
      // Show custom dialog explaining why background location is needed
      await _showBackgroundLocationRationale();
    }
    
    final status = await Permission.locationAlways.request();
    return status == PermissionStatus.granted;
  }
  
  static Future<bool> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      
      if (androidInfo.version.sdkInt >= 33) {
        final status = await Permission.notification.request();
        return status == PermissionStatus.granted;
      }
    }
    
    return true; // Notifications don't need permission on older Android versions
  }
  
  static Future<Map<Permission, PermissionStatus>> checkPermissions() async {
    return await [
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
      Permission.storage,
      Permission.camera,
      Permission.microphone,
    ].request();
  }
  
  static Future<void> openAppSettings() async {
    await openAppSettings();
  }
  
  static Future<void> _showBackgroundLocationRationale() async {
    // Show dialog implementation
  }
}
```

### Battery Optimization

```dart
// lib/services/android_battery_optimization.dart
import 'package:flutter/services.dart';

class AndroidBatteryOptimization {
  static const _channel = MethodChannel('flutter_mcp/battery_optimization');
  
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    
    try {
      return await _channel.invokeMethod('isIgnoringBatteryOptimizations');
    } catch (e) {
      return false;
    }
  }
  
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      print('Failed to request battery optimization exemption: $e');
    }
  }
  
  static Future<BatteryInfo> getBatteryInfo() async {
    if (!Platform.isAndroid) {
      return BatteryInfo(
        level: 100,
        isCharging: false,
        temperature: 0,
        voltage: 0,
      );
    }
    
    try {
      final result = await _channel.invokeMethod('getBatteryInfo');
      return BatteryInfo.fromMap(result);
    } catch (e) {
      throw Exception('Failed to get battery info: $e');
    }
  }
}

class BatteryInfo {
  final int level;
  final bool isCharging;
  final double temperature;
  final double voltage;
  
  BatteryInfo({
    required this.level,
    required this.isCharging,
    required this.temperature,
    required this.voltage,
  });
  
  factory BatteryInfo.fromMap(Map<String, dynamic> map) {
    return BatteryInfo(
      level: map['level'] as int,
      isCharging: map['isCharging'] as bool,
      temperature: map['temperature'] as double,
      voltage: map['voltage'] as double,
    );
  }
}
```

## Android Example App

### Main Activity

```kotlin
// android/app/src/main/kotlin/com/example/flutter_mcp/MainActivity.kt
package com.example.flutter_mcp

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private lateinit var serviceManager: ServiceManager
    private lateinit var notificationManager: MCPNotificationManager
    private lateinit var channelHandler: PlatformChannelHandler
    
    companion object {
        private const val CHANNEL = "flutter_mcp/android_service"
        private const val PERMISSION_REQUEST_CODE = 1001
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        serviceManager = ServiceManager(this)
        notificationManager = MCPNotificationManager(this)
        channelHandler = PlatformChannelHandler(this)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Setup method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundService" -> {
                    serviceManager.startBackgroundService()
                    result.success(null)
                }
                "stopBackgroundService" -> {
                    serviceManager.stopBackgroundService()
                    result.success(null)
                }
                "scheduleWork" -> {
                    val tag = call.argument<String>("tag") ?: "default"
                    val intervalMinutes = call.argument<Long>("intervalMinutes") ?: 15
                    serviceManager.schedulePeriodicWork(tag, intervalMinutes)
                    result.success(null)
                }
                "cancelWork" -> {
                    val tag = call.argument<String>("tag") ?: "default"
                    serviceManager.cancelWork(tag)
                    result.success(null)
                }
                "requestPermissions" -> {
                    val permissions = call.argument<List<String>>("permissions")
                    requestPermissions(permissions ?: emptyList())
                    result.success(null)
                }
                else -> channelHandler.setupMethodChannel(
                    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                )
            }
        }
        
        // Setup FCM channel
        FCMService.methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "flutter_mcp/fcm"
        )
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        
        // Handle notification tap
        if (intent.hasExtra("notification_id")) {
            val notificationId = intent.getIntExtra("notification_id", -1)
            handleNotificationTap(notificationId)
        }
    }
    
    private fun requestPermissions(permissions: List<String>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(
                permissions.toTypedArray(),
                PERMISSION_REQUEST_CODE
            )
        }
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val results = mutableMapOf<String, Boolean>()
            
            permissions.forEachIndexed { index, permission ->
                results[permission] = grantResults[index] == android.content.pm.PackageManager.PERMISSION_GRANTED
            }
            
            // Send results back to Flutter
            MethodChannel(
                flutterEngine?.dartExecutor?.binaryMessenger ?: return,
                CHANNEL
            ).invokeMethod("onPermissionsResult", results)
        }
    }
    
    private fun handleNotificationTap(notificationId: Int) {
        // Send to Flutter
        MethodChannel(
            flutterEngine?.dartExecutor?.binaryMessenger ?: return,
            "flutter_mcp/notifications"
        ).invokeMethod("onNotificationTap", notificationId)
    }
}
```

## Testing Android Features

```dart
// test/android_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('Android Services', () {
    test('starts background service', () async {
      final mockChannel = MockMethodChannel();
      
      await AndroidServiceManager.startBackgroundService();
      
      verify(mockChannel.invokeMethod('startBackgroundService')).called(1);
    });
    
    test('shows notification', () async {
      await AndroidNotificationManager.showNotification(
        id: 1,
        title: 'Test Notification',
        body: 'This is a test',
      );
      
      // Verify notification was shown
    });
    
    test('handles permissions', () async {
      final permissions = await AndroidPermissionManager.checkPermissions();
      
      expect(permissions, isNotEmpty);
    });
  });
}
```

## Best Practices

### Power Management

```dart
// Respect battery optimization
if (!await AndroidBatteryOptimization.isIgnoringBatteryOptimizations()) {
  // Reduce background activity
  reduceBackgroundWork();
}
```

### Doze Mode Handling

```dart
// Adapt to Doze mode
if (androidInfo.version.sdkInt >= 23) {
  // Use JobScheduler or WorkManager for background work
  scheduleJobWithConstraints();
}
```

### App Standby

```dart
// Handle app standby buckets
if (androidInfo.version.sdkInt >= 28) {
  // Adjust sync frequency based on standby bucket
  adjustSyncFrequency();
}
```

## Next Steps

- Explore [iOS Integration](./ios-integration.md)
- Learn about [Desktop Applications](./desktop-applications.md)
- Try [Web Applications](./web-applications.md)