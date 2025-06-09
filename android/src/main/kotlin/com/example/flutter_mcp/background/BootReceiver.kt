package com.example.flutter_mcp.background

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.example.flutter_mcp.utils.Constants

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            
            // Check if background service should be restarted on boot
            val prefs = context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
            val shouldRestart = prefs.getBoolean("restart_on_boot", false)
            
            if (shouldRestart) {
                val serviceIntent = Intent(context, BackgroundService::class.java).apply {
                    action = BackgroundService.ACTION_START
                }
                context.startService(serviceIntent)
            }
        }
    }
}