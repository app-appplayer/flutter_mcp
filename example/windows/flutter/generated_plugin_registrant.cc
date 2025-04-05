//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_mcp/flutter_mcp_plugin_c_api.h>
#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>
#include <tray_manager/tray_manager_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterMcpPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterMcpPluginCApi"));
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterSecureStorageWindowsPlugin"));
  TrayManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("TrayManagerPlugin"));
}
