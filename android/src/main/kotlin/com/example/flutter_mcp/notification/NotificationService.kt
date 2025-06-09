package com.example.flutter_mcp.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.flutter_mcp.R
import com.example.flutter_mcp.utils.Constants

class NotificationService(private val context: Context) {
    private val notificationManager: NotificationManagerCompat = NotificationManagerCompat.from(context)
    private var channelId = Constants.NOTIFICATION_CHANNEL_ID
    private var channelName = Constants.NOTIFICATION_CHANNEL_NAME
    private var channelDescription = Constants.NOTIFICATION_CHANNEL_DESC
    
    init {
        createNotificationChannel()
    }
    
    fun configure(config: Map<String, Any>) {
        config["channelId"]?.let { channelId = it as String }
        config["channelName"]?.let { channelName = it as String }
        config["channelDescription"]?.let { channelDescription = it as String }
        
        createNotificationChannel()
    }
    
    fun showNotification(title: String, body: String, icon: String?, id: String) {
        val notificationId = id.hashCode()
        
        val builder = NotificationCompat.Builder(context, channelId)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(getNotificationIcon(icon))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
        
        notificationManager.notify(notificationId, builder.build())
    }
    
    fun cancelNotification(id: String) {
        val notificationId = id.hashCode()
        notificationManager.cancel(notificationId)
    }
    
    fun cancelAllNotifications() {
        notificationManager.cancelAll()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = channelDescription
            }
            
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun getNotificationIcon(icon: String?): Int {
        if (icon == null) {
            return R.drawable.ic_notification
        }
        
        // Try to find the icon resource by name
        val resourceId = context.resources.getIdentifier(icon, "drawable", context.packageName)
        return if (resourceId != 0) resourceId else R.drawable.ic_notification
    }
}