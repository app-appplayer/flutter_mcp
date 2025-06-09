package com.example.flutter_mcp.background

import android.content.Context
import android.content.Intent
import androidx.work.Worker
import androidx.work.WorkerParameters

class BackgroundTaskWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {
    
    override fun doWork(): Result {
        val taskId = inputData.getString("taskId") ?: return Result.failure()
        
        // Convert input data to map
        val data = mutableMapOf<String, Any>()
        inputData.keyValueMap.forEach { (key, value) ->
            if (key != "taskId" && value != null) {
                data[key] = value
            }
        }
        
        // Execute task through background service
        val intent = Intent(applicationContext, BackgroundService::class.java).apply {
            action = BackgroundService.ACTION_EXECUTE_TASK
            putExtra(BackgroundService.EXTRA_TASK_ID, taskId)
            putExtra(BackgroundService.EXTRA_TASK_DATA, data.toString())
        }
        
        applicationContext.startService(intent)
        
        return Result.success()
    }
}