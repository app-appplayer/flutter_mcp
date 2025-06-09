package com.example.flutter_mcp.background

import android.content.Context
import androidx.work.*
import java.util.concurrent.TimeUnit

class BackgroundTaskScheduler(private val context: Context) {
    
    fun scheduleTask(taskId: String, delayMillis: Long, data: Map<String, Any>?) {
        val inputData = Data.Builder().apply {
            putString("taskId", taskId)
            data?.forEach { (key, value) ->
                when (value) {
                    is String -> putString(key, value)
                    is Int -> putInt(key, value)
                    is Long -> putLong(key, value)
                    is Double -> putDouble(key, value)
                    is Boolean -> putBoolean(key, value)
                }
            }
        }.build()
        
        val workRequest = OneTimeWorkRequestBuilder<BackgroundTaskWorker>()
            .setInputData(inputData)
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .addTag(taskId)
            .build()
        
        WorkManager.getInstance(context).enqueueUniqueWork(
            taskId,
            ExistingWorkPolicy.REPLACE,
            workRequest
        )
    }
    
    fun cancelTask(taskId: String) {
        WorkManager.getInstance(context).cancelAllWorkByTag(taskId)
    }
}