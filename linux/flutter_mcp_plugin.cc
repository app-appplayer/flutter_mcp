#include "include/flutter_mcp/flutter_mcp_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>
#include <libnotify/notify.h>
#include <libsecret/secret.h>
#include <appindicator3-0.1/libappindicator/app-indicator.h>

#include <cstring>
#include <memory>
#include <map>
#include <string>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <chrono>

#include "flutter_mcp_plugin_private.h"

#define FLUTTER_MCP_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_mcp_plugin_get_type(), \
                              FlutterMcpPlugin))

// Secret schema for secure storage
static const SecretSchema flutter_mcp_schema = {
    "com.example.flutter_mcp",
    SECRET_SCHEMA_NONE,
    {
        { "key", SECRET_SCHEMA_ATTRIBUTE_STRING },
        { "NULL", 0 },
    }
};

struct _FlutterMcpPlugin {
  GObject parent_instance;
  
  FlMethodChannel* channel;
  FlEventChannel* event_channel;
  FlEventSink* event_sink;
  
  // Tray icon
  AppIndicator* app_indicator;
  GtkWidget* tray_menu;
  std::map<std::string, std::string> menu_item_map;
  
  // Background service
  std::unique_ptr<std::thread> background_thread;
  std::atomic<bool> background_running;
  std::atomic<int> background_interval_ms;
  std::mutex background_mutex;
  std::condition_variable background_cv;
  
  // Scheduled tasks
  std::map<std::string, std::pair<std::chrono::steady_clock::time_point, std::function<void()>>> scheduled_tasks;
  std::mutex tasks_mutex;
};

G_DEFINE_TYPE(FlutterMcpPlugin, flutter_mcp_plugin, g_object_get_type())

// Forward declarations
static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data);
static void event_listen_cb(FlEventChannel* channel,
                            FlValue* args,
                            gpointer user_data);
static void event_cancel_cb(FlEventChannel* channel,
                            FlValue* args,
                            gpointer user_data);
static void send_event(FlutterMcpPlugin* self, const gchar* event_type,
                       FlValue* data);

// Background service worker
static void background_worker(FlutterMcpPlugin* self) {
  while (self->background_running) {
    {
      std::unique_lock<std::mutex> lock(self->background_mutex);
      self->background_cv.wait_for(lock, 
          std::chrono::milliseconds(self->background_interval_ms),
          [self] { return !self->background_running; });
    }
    
    if (self->background_running) {
      // Send periodic event
      g_autoptr(FlValue) data = fl_value_new_map();
      fl_value_set_string_take(data, "type", fl_value_new_string("periodic"));
      fl_value_set_string_take(data, "timestamp", 
          fl_value_new_int(std::chrono::system_clock::now().time_since_epoch().count()));
      
      send_event(self, "backgroundEvent", data);
    }
    
    // Check scheduled tasks
    {
      std::lock_guard<std::mutex> lock(self->tasks_mutex);
      auto now = std::chrono::steady_clock::now();
      
      for (auto it = self->scheduled_tasks.begin(); it != self->scheduled_tasks.end(); ) {
        if (it->second.first <= now) {
          // Execute task
          if (it->second.second) {
            it->second.second();
          }
          it = self->scheduled_tasks.erase(it);
        } else {
          ++it;
        }
      }
    }
  }
}

// Tray menu item callback
static void tray_menu_item_cb(GtkMenuItem* item, gpointer user_data) {
  FlutterMcpPlugin* self = FLUTTER_MCP_PLUGIN(user_data);
  
  const gchar* item_id = (const gchar*)g_object_get_data(G_OBJECT(item), "item_id");
  if (item_id) {
    g_autoptr(FlValue) data = fl_value_new_map();
    fl_value_set_string_take(data, "action", fl_value_new_string("menuItemClicked"));
    fl_value_set_string_take(data, "itemId", fl_value_new_string(item_id));
    
    send_event(self, "trayEvent", data);
  }
}

static void flutter_mcp_plugin_dispose(GObject* object) {
  FlutterMcpPlugin* self = FLUTTER_MCP_PLUGIN(object);
  
  // Stop background service
  if (self->background_thread) {
    self->background_running = false;
    self->background_cv.notify_all();
    self->background_thread->join();
  }
  
  // Clean up tray icon
  if (self->app_indicator) {
    g_object_unref(self->app_indicator);
  }
  if (self->tray_menu) {
    gtk_widget_destroy(self->tray_menu);
  }
  
  g_clear_object(&self->channel);
  g_clear_object(&self->event_channel);
  
  G_OBJECT_CLASS(flutter_mcp_plugin_parent_class)->dispose(object);
}

static void flutter_mcp_plugin_class_init(FlutterMcpPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_mcp_plugin_dispose;
}

static void flutter_mcp_plugin_init(FlutterMcpPlugin* self) {
  self->app_indicator = nullptr;
  self->tray_menu = nullptr;
  self->event_sink = nullptr;
  self->background_running = false;
  self->background_interval_ms = 60000; // Default 1 minute
}

// Method implementations
static FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar* version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* initialize(FlValue* args) {
  // Initialize components based on config
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* start_background_service(FlutterMcpPlugin* self) {
  if (!self->background_running) {
    self->background_running = true;
    self->background_thread = std::make_unique<std::thread>(background_worker, self);
  }
  
  g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* stop_background_service(FlutterMcpPlugin* self) {
  if (self->background_thread) {
    self->background_running = false;
    self->background_cv.notify_all();
    self->background_thread->join();
    self->background_thread.reset();
  }
  
  g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* configure_background_service(FlutterMcpPlugin* self, FlValue* args) {
  if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* interval_value = fl_value_lookup_string(args, "intervalMs");
    if (interval_value && fl_value_get_type(interval_value) == FL_VALUE_TYPE_INT) {
      self->background_interval_ms = fl_value_get_int(interval_value);
    }
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* schedule_background_task(FlutterMcpPlugin* self, FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* task_id_value = fl_value_lookup_string(args, "taskId");
  FlValue* delay_value = fl_value_lookup_string(args, "delayMillis");
  
  if (!task_id_value || !delay_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing required arguments", nullptr));
  }
  
  const gchar* task_id = fl_value_get_string(task_id_value);
  int64_t delay_millis = fl_value_get_int(delay_value);
  
  std::lock_guard<std::mutex> lock(self->tasks_mutex);
  
  auto execute_time = std::chrono::steady_clock::now() + std::chrono::milliseconds(delay_millis);
  self->scheduled_tasks[task_id] = std::make_pair(execute_time, [self, task_id = std::string(task_id)]() {
    g_autoptr(FlValue) data = fl_value_new_map();
    fl_value_set_string_take(data, "taskId", fl_value_new_string(task_id.c_str()));
    fl_value_set_string_take(data, "timestamp", 
        fl_value_new_int(std::chrono::system_clock::now().time_since_epoch().count()));
    
    send_event(self, "backgroundTaskResult", data);
  });
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* cancel_background_task(FlutterMcpPlugin* self, FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* task_id_value = fl_value_lookup_string(args, "taskId");
  if (!task_id_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing task ID", nullptr));
  }
  
  const gchar* task_id = fl_value_get_string(task_id_value);
  
  std::lock_guard<std::mutex> lock(self->tasks_mutex);
  self->scheduled_tasks.erase(task_id);
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* show_notification(FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* title_value = fl_value_lookup_string(args, "title");
  FlValue* body_value = fl_value_lookup_string(args, "body");
  FlValue* id_value = fl_value_lookup_string(args, "id");
  
  if (!title_value || !body_value || !id_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing required arguments", nullptr));
  }
  
  const gchar* title = fl_value_get_string(title_value);
  const gchar* body = fl_value_get_string(body_value);
  
  NotifyNotification* notification = notify_notification_new(title, body, nullptr);
  notify_notification_show(notification, nullptr);
  g_object_unref(G_OBJECT(notification));
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* cancel_notification(FlValue* args) {
  // Linux doesn't provide a way to cancel specific notifications
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* cancel_all_notifications() {
  // Linux doesn't provide a way to cancel all notifications
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* configure_notifications(FlValue* args) {
  // Configuration can be extended as needed
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* secure_store(FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* key_value = fl_value_lookup_string(args, "key");
  FlValue* value_value = fl_value_lookup_string(args, "value");
  
  if (!key_value || !value_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing required arguments", nullptr));
  }
  
  const gchar* key = fl_value_get_string(key_value);
  const gchar* value = fl_value_get_string(value_value);
  
  GError* error = nullptr;
  gboolean result = secret_password_store_sync(&flutter_mcp_schema,
                                               SECRET_COLLECTION_DEFAULT,
                                               key,
                                               value,
                                               nullptr,
                                               &error,
                                               "key", key,
                                               nullptr);
  
  if (error) {
    g_autofree gchar* error_msg = g_strdup(error->message);
    g_error_free(error);
    return FL_METHOD_RESPONSE(fl_method_error_response_new("STORAGE_ERROR", error_msg, nullptr));
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* secure_read(FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* key_value = fl_value_lookup_string(args, "key");
  if (!key_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing key", nullptr));
  }
  
  const gchar* key = fl_value_get_string(key_value);
  
  GError* error = nullptr;
  gchar* password = secret_password_lookup_sync(&flutter_mcp_schema,
                                                nullptr,
                                                &error,
                                                "key", key,
                                                nullptr);
  
  if (error) {
    g_autofree gchar* error_msg = g_strdup(error->message);
    g_error_free(error);
    return FL_METHOD_RESPONSE(fl_method_error_response_new("STORAGE_ERROR", error_msg, nullptr));
  }
  
  if (!password) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("KEY_NOT_FOUND", "Key not found", nullptr));
  }
  
  g_autoptr(FlValue) result = fl_value_new_string(password);
  secret_password_free(password);
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* secure_delete(FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* key_value = fl_value_lookup_string(args, "key");
  if (!key_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing key", nullptr));
  }
  
  const gchar* key = fl_value_get_string(key_value);
  
  GError* error = nullptr;
  secret_password_clear_sync(&flutter_mcp_schema,
                             nullptr,
                             &error,
                             "key", key,
                             nullptr);
  
  if (error) {
    g_autofree gchar* error_msg = g_strdup(error->message);
    g_error_free(error);
    return FL_METHOD_RESPONSE(fl_method_error_response_new("STORAGE_ERROR", error_msg, nullptr));
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* secure_contains_key(FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* key_value = fl_value_lookup_string(args, "key");
  if (!key_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing key", nullptr));
  }
  
  const gchar* key = fl_value_get_string(key_value);
  
  GError* error = nullptr;
  gchar* password = secret_password_lookup_sync(&flutter_mcp_schema,
                                                nullptr,
                                                &error,
                                                "key", key,
                                                nullptr);
  
  if (error) {
    g_error_free(error);
    g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }
  
  gboolean exists = (password != nullptr);
  if (password) {
    secret_password_free(password);
  }
  
  g_autoptr(FlValue) result = fl_value_new_bool(exists);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* secure_delete_all() {
  GError* error = nullptr;
  secret_password_clear_sync(&flutter_mcp_schema,
                             nullptr,
                             &error,
                             nullptr);
  
  if (error) {
    g_error_free(error);
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* show_tray_icon(FlutterMcpPlugin* self, FlValue* args) {
  if (!self->app_indicator) {
    self->app_indicator = app_indicator_new("flutter-mcp",
                                            "application-default-icon",
                                            APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  }
  
  if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* icon_path_value = fl_value_lookup_string(args, "iconPath");
    if (icon_path_value && fl_value_get_type(icon_path_value) == FL_VALUE_TYPE_STRING) {
      const gchar* icon_path = fl_value_get_string(icon_path_value);
      app_indicator_set_icon(self->app_indicator, icon_path);
    }
    
    FlValue* tooltip_value = fl_value_lookup_string(args, "tooltip");
    if (tooltip_value && fl_value_get_type(tooltip_value) == FL_VALUE_TYPE_STRING) {
      const gchar* tooltip = fl_value_get_string(tooltip_value);
      app_indicator_set_title(self->app_indicator, tooltip);
    }
  }
  
  app_indicator_set_status(self->app_indicator, APP_INDICATOR_STATUS_ACTIVE);
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* hide_tray_icon(FlutterMcpPlugin* self) {
  if (self->app_indicator) {
    app_indicator_set_status(self->app_indicator, APP_INDICATOR_STATUS_PASSIVE);
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* set_tray_menu(FlutterMcpPlugin* self, FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* items_value = fl_value_lookup_string(args, "items");
  if (!items_value || fl_value_get_type(items_value) != FL_VALUE_TYPE_LIST) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing menu items", nullptr));
  }
  
  // Clear old menu
  if (self->tray_menu) {
    gtk_widget_destroy(self->tray_menu);
  }
  self->menu_item_map.clear();
  
  // Create new menu
  self->tray_menu = gtk_menu_new();
  
  size_t item_count = fl_value_get_length(items_value);
  for (size_t i = 0; i < item_count; i++) {
    FlValue* item = fl_value_get_list_value(items_value, i);
    if (fl_value_get_type(item) != FL_VALUE_TYPE_MAP) continue;
    
    FlValue* separator_value = fl_value_lookup_string(item, "isSeparator");
    gboolean is_separator = separator_value && fl_value_get_bool(separator_value);
    
    GtkWidget* menu_item;
    if (is_separator) {
      menu_item = gtk_separator_menu_item_new();
    } else {
      FlValue* label_value = fl_value_lookup_string(item, "label");
      FlValue* id_value = fl_value_lookup_string(item, "id");
      
      if (!label_value || !id_value) continue;
      
      const gchar* label = fl_value_get_string(label_value);
      const gchar* item_id = fl_value_get_string(id_value);
      
      menu_item = gtk_menu_item_new_with_label(label);
      
      // Store item ID
      g_object_set_data_full(G_OBJECT(menu_item), "item_id", 
                             g_strdup(item_id), g_free);
      
      // Connect click handler
      g_signal_connect(menu_item, "activate",
                       G_CALLBACK(tray_menu_item_cb), self);
      
      FlValue* disabled_value = fl_value_lookup_string(item, "disabled");
      if (disabled_value && fl_value_get_bool(disabled_value)) {
        gtk_widget_set_sensitive(menu_item, FALSE);
      }
    }
    
    gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), menu_item);
  }
  
  gtk_widget_show_all(self->tray_menu);
  
  if (self->app_indicator) {
    app_indicator_set_menu(self->app_indicator, GTK_MENU(self->tray_menu));
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* update_tray_tooltip(FlutterMcpPlugin* self, FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* tooltip_value = fl_value_lookup_string(args, "tooltip");
  if (!tooltip_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing tooltip", nullptr));
  }
  
  const gchar* tooltip = fl_value_get_string(tooltip_value);
  
  if (self->app_indicator) {
    app_indicator_set_title(self->app_indicator, tooltip);
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* configure_tray(FlValue* args) {
  // Handle tray configuration
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* check_permission(FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* permission_value = fl_value_lookup_string(args, "permission");
  if (!permission_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing permission", nullptr));
  }
  
  const gchar* permission = fl_value_get_string(permission_value);
  gboolean granted = FALSE;
  
  // Handle Linux-specific permissions
  if (g_strcmp0(permission, "notification") == 0) {
    // Check if notification daemon is available
    GList* capabilities = notify_get_server_caps();
    granted = (capabilities != NULL);
    g_list_free_full(capabilities, g_free);
  } else if (g_strcmp0(permission, "background") == 0) {
    // Linux allows background execution
    granted = TRUE;
  } else if (g_strcmp0(permission, "storage") == 0) {
    // Check if secret service is available
    GError* error = nullptr;
    SecretService* service = secret_service_get_sync(SECRET_SERVICE_NONE, nullptr, &error);
    if (service) {
      granted = TRUE;
      g_object_unref(service);
    }
    if (error) {
      g_error_free(error);
    }
  } else if (g_strcmp0(permission, "systemTray") == 0) {
    // Check if system tray is available (AppIndicator)
    granted = TRUE; // Assume available
  } else {
    // Unknown permission, assume not granted
    granted = FALSE;
  }
  
  g_autoptr(FlValue) result = fl_value_new_bool(granted);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* request_permission(FlValue* args) {
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing arguments", nullptr));
  }
  
  FlValue* permission_value = fl_value_lookup_string(args, "permission");
  if (!permission_value) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Missing permission", nullptr));
  }
  
  const gchar* permission = fl_value_get_string(permission_value);
  gboolean granted = FALSE;
  
  // Handle Linux-specific permissions
  if (g_strcmp0(permission, "notification") == 0) {
    // Initialize notification system if not already done
    if (!notify_is_initted()) {
      GError* error = nullptr;
      if (notify_init("Flutter MCP")) {
        granted = TRUE;
      } else {
        granted = FALSE;
      }
    } else {
      granted = TRUE;
    }
  } else if (g_strcmp0(permission, "background") == 0) {
    // Linux allows background execution
    granted = TRUE;
  } else if (g_strcmp0(permission, "storage") == 0) {
    // Secret service should be available
    granted = TRUE;
  } else if (g_strcmp0(permission, "systemTray") == 0) {
    // System tray is generally available
    granted = TRUE;
  } else {
    // Unknown permission
    granted = FALSE;
  }
  
  g_autoptr(FlValue) result = fl_value_new_bool(granted);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* shutdown(FlutterMcpPlugin* self) {
  // Stop background service
  if (self->background_thread) {
    self->background_running = false;
    self->background_cv.notify_all();
    self->background_thread->join();
    self->background_thread.reset();
  }
  
  // Hide tray icon
  if (self->app_indicator) {
    app_indicator_set_status(self->app_indicator, APP_INDICATOR_STATUS_PASSIVE);
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

// Method channel handler
static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  FlutterMcpPlugin* self = FLUTTER_MCP_PLUGIN(user_data);
  
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  
  g_autoptr(FlMethodResponse) response = nullptr;
  
  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else if (strcmp(method, "initialize") == 0) {
    response = initialize(args);
  } else if (strcmp(method, "startBackgroundService") == 0) {
    response = start_background_service(self);
  } else if (strcmp(method, "stopBackgroundService") == 0) {
    response = stop_background_service(self);
  } else if (strcmp(method, "configureBackgroundService") == 0) {
    response = configure_background_service(self, args);
  } else if (strcmp(method, "scheduleBackgroundTask") == 0) {
    response = schedule_background_task(self, args);
  } else if (strcmp(method, "cancelBackgroundTask") == 0) {
    response = cancel_background_task(self, args);
  } else if (strcmp(method, "showNotification") == 0) {
    response = show_notification(args);
  } else if (strcmp(method, "requestNotificationPermission") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "configureNotifications") == 0) {
    response = configure_notifications(args);
  } else if (strcmp(method, "cancelNotification") == 0) {
    response = cancel_notification(args);
  } else if (strcmp(method, "cancelAllNotifications") == 0) {
    response = cancel_all_notifications();
  } else if (strcmp(method, "secureStore") == 0) {
    response = secure_store(args);
  } else if (strcmp(method, "secureRead") == 0) {
    response = secure_read(args);
  } else if (strcmp(method, "secureDelete") == 0) {
    response = secure_delete(args);
  } else if (strcmp(method, "secureContainsKey") == 0) {
    response = secure_contains_key(args);
  } else if (strcmp(method, "secureDeleteAll") == 0) {
    response = secure_delete_all();
  } else if (strcmp(method, "showTrayIcon") == 0) {
    response = show_tray_icon(self, args);
  } else if (strcmp(method, "hideTrayIcon") == 0) {
    response = hide_tray_icon(self);
  } else if (strcmp(method, "setTrayMenu") == 0) {
    response = set_tray_menu(self, args);
  } else if (strcmp(method, "updateTrayTooltip") == 0) {
    response = update_tray_tooltip(self, args);
  } else if (strcmp(method, "configureTray") == 0) {
    response = configure_tray(args);
  } else if (strcmp(method, "checkPermission") == 0) {
    response = check_permission(args);
  } else if (strcmp(method, "requestPermission") == 0) {
    response = request_permission(args);
  } else if (strcmp(method, "shutdown") == 0) {
    response = shutdown(self);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  
  fl_method_call_respond(method_call, response, nullptr);
}

// Event channel handlers
static void event_listen_cb(FlEventChannel* channel,
                            FlValue* args,
                            gpointer user_data) {
  FlutterMcpPlugin* self = FLUTTER_MCP_PLUGIN(user_data);
  self->event_sink = fl_event_channel_get_event_sink(channel);
}

static void event_cancel_cb(FlEventChannel* channel,
                            FlValue* args,
                            gpointer user_data) {
  FlutterMcpPlugin* self = FLUTTER_MCP_PLUGIN(user_data);
  self->event_sink = nullptr;
}

// Send event to Flutter
static void send_event(FlutterMcpPlugin* self, const gchar* event_type,
                       FlValue* data) {
  if (self->event_sink) {
    g_autoptr(FlValue) event = fl_value_new_map();
    fl_value_set_string_take(event, "type", fl_value_new_string(event_type));
    fl_value_set_string_take(event, "data", fl_value_ref(data));
    
    fl_event_sink_add(self->event_sink, event);
  }
}

void flutter_mcp_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  // Initialize libraries
  notify_init("flutter_mcp");
  
  FlutterMcpPlugin* plugin = FLUTTER_MCP_PLUGIN(
      g_object_new(flutter_mcp_plugin_get_type(), nullptr));
  
  // Set up method channel
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                                           "flutter_mcp",
                                           FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(plugin->channel,
                                            method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);
  
  // Set up event channel
  plugin->event_channel = fl_event_channel_new(fl_plugin_registrar_get_messenger(registrar),
                                                "flutter_mcp/events",
                                                FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->event_channel,
                                       event_listen_cb,
                                       event_cancel_cb,
                                       g_object_ref(plugin),
                                       g_object_unref);
  
  fl_plugin_registrar_set_destroy_notify(registrar, G_OBJECT(plugin), g_object_unref);
}