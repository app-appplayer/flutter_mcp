#ifndef FLUTTER_PLUGIN_FLUTTER_MCP_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_MCP_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_mcp {

class FlutterMcpPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterMcpPlugin();

  virtual ~FlutterMcpPlugin();

  // Disallow copy and assign.
  FlutterMcpPlugin(const FlutterMcpPlugin&) = delete;
  FlutterMcpPlugin& operator=(const FlutterMcpPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_mcp

#endif  // FLUTTER_PLUGIN_FLUTTER_MCP_PLUGIN_H_
