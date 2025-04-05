package com.example.flutter_mcp

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** FlutterMcpPlugin */
class FlutterMcpPlugin: FlutterPlugin, MethodCallHandler {

  private lateinit var channel : MethodChannel

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
  }
}
