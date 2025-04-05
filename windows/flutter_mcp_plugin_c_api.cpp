#include "include/flutter_mcp/flutter_mcp_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_mcp_plugin.h"

void FlutterMcpPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_mcp::FlutterMcpPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
