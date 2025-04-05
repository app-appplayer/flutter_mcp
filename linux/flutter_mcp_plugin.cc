#include "include/flutter_mcp/flutter_mcp_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>

#include "flutter_mcp_plugin_private.h"

#define FLUTTER_MCP_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_mcp_plugin_get_type(), \
                              FlutterMcpPlugin))

struct _FlutterMcpPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(FlutterMcpPlugin, flutter_mcp_plugin, g_object_get_type())


static void flutter_mcp_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(flutter_mcp_plugin_parent_class)->dispose(object);
}

static void flutter_mcp_plugin_class_init(FlutterMcpPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_mcp_plugin_dispose;
}

static void flutter_mcp_plugin_init(FlutterMcpPlugin* self) {}


void flutter_mcp_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterMcpPlugin* plugin = FLUTTER_MCP_PLUGIN(
      g_object_new(flutter_mcp_plugin_get_type(), nullptr));

  g_object_unref(plugin);
}
