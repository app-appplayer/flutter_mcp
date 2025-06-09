package com.example.flutter_mcp.utils

object Constants {
    const val PREFS_NAME = "flutter_mcp_prefs"
    const val CALLBACK_HANDLE_KEY = "callback_handle"
    const val BACKGROUND_CHANNEL = "flutter_mcp/background"
    const val NOTIFICATION_CHANNEL_ID = "flutter_mcp_background"
    const val NOTIFICATION_CHANNEL_NAME = "Flutter MCP Background Service"
    const val NOTIFICATION_CHANNEL_DESC = "Notification channel for Flutter MCP background service"
    
    // Permission codes
    const val NOTIFICATION_PERMISSION_CODE = 1001
    const val BACKGROUND_PERMISSION_CODE = 1002
    
    // Keys for secure storage
    const val SECURE_STORAGE_ALIAS = "flutter_mcp_secure_storage"
}