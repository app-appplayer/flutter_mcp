package com.example.flutter_mcp.background

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.example.flutter_mcp.R
import com.example.flutter_mcp.utils.Constants
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import io.flutter.view.FlutterMain

class BackgroundService : Service() {
    private var backgroundEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    
    companion object {
        const val ACTION_START = "com.example.flutter_mcp.START_SERVICE"
        const val ACTION_STOP = "com.example.flutter_mcp.STOP_SERVICE"
        const val ACTION_EXECUTE_TASK = "com.example.flutter_mcp.EXECUTE_TASK"
        const val EXTRA_TASK_ID = "task_id"
        const val EXTRA_TASK_DATA = "task_data"
        const val NOTIFICATION_ID = 1001
        
        var isRunning = false
            private set
    }
    
    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        initializeFlutterEngine()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> handleStart(intent)
            ACTION_STOP -> handleStop()
            ACTION_EXECUTE_TASK -> handleExecuteTask(intent)
        }
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        backgroundEngine?.destroy()
        backgroundEngine = null
    }
    
    private fun initializeFlutterEngine() {
        backgroundEngine = FlutterEngine(this)
        
        val callbackHandle = getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
            .getLong(Constants.CALLBACK_HANDLE_KEY, 0)
        
        if (callbackHandle == 0L) {
            return
        }
        
        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(callbackHandle)
        val dartBundlePath = FlutterMain.findAppBundlePath()
        
        backgroundEngine?.dartExecutor?.executeDartCallback(
            DartExecutor.DartCallback(
                assets,
                dartBundlePath,
                callbackInfo
            )
        )
        
        // Set up method channel for communication
        methodChannel = MethodChannel(
            backgroundEngine!!.dartExecutor.binaryMessenger,
            Constants.BACKGROUND_CHANNEL
        )
    }
    
    private fun handleStart(intent: Intent) {
        // Extract configuration from intent if needed
        val config = intent.getStringExtra("config")
        
        // Notify Flutter side that service has started
        methodChannel?.invokeMethod("onServiceStarted", mapOf(
            "timestamp" to System.currentTimeMillis(),
            "config" to config
        ))
    }
    
    private fun handleStop() {
        // Notify Flutter side that service is stopping
        methodChannel?.invokeMethod("onServiceStopping", null)
        stopSelf()
    }
    
    private fun handleExecuteTask(intent: Intent) {
        val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return
        val taskData = intent.getStringExtra(EXTRA_TASK_DATA)
        
        // Execute task in Flutter
        methodChannel?.invokeMethod("executeTask", mapOf(
            "taskId" to taskId,
            "data" to taskData,
            "timestamp" to System.currentTimeMillis()
        ))
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                Constants.NOTIFICATION_CHANNEL_ID,
                Constants.NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = Constants.NOTIFICATION_CHANNEL_DESC
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, Constants.NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Flutter MCP")
            .setContentText("Background service is running")
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }
}