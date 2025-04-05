#include "flutter_mcp_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

namespace flutter_mcp {

// static
void FlutterMcpPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {

  auto plugin = std::make_unique<FlutterMcpPlugin>();

  registrar->AddPlugin(std::move(plugin));
}

FlutterMcpPlugin::FlutterMcpPlugin() {}

FlutterMcpPlugin::~FlutterMcpPlugin() {}

}  // namespace flutter_mcp
