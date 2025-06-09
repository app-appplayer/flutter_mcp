#include "flutter_mcp_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <wincrypt.h>
#include <shellapi.h>
#include <shlobj.h>

// For getPlatformVersion
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>

#include <memory>
#include <sstream>
#include <map>
#include <thread>
#include <chrono>
#include <mutex>

#include "tray/tray_icon_manager.h"
#include "notification/notification_manager.h"
#include "storage/secure_storage_service.h"
#include "background/background_service.h"

namespace flutter_mcp {

// static
void FlutterMcpPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_mcp",
          &flutter::StandardMethodCodec::GetInstance());

  auto event_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_mcp/events",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterMcpPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  auto event_handler = std::make_unique<flutter::StreamHandlerFunctions<>>(
      [plugin_pointer = plugin.get()](
          const flutter::EncodableValue* arguments,
          std::unique_ptr<flutter::EventSink<>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        plugin_pointer->OnListen(arguments, std::move(events));
        return nullptr;
      },
      [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        plugin_pointer->OnCancel(arguments);
        return nullptr;
      });

  event_channel->SetStreamHandler(std::move(event_handler));

  registrar->AddPlugin(std::move(plugin));
}

FlutterMcpPlugin::FlutterMcpPlugin(flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar),
      tray_manager_(std::make_unique<TrayIconManager>(registrar->GetView())),
      notification_manager_(std::make_unique<NotificationManager>()),
      secure_storage_(std::make_unique<SecureStorageService>()),
      background_service_(std::make_unique<BackgroundService>()) {}

FlutterMcpPlugin::~FlutterMcpPlugin() {
  // Clean up resources
  background_service_->Stop();
  tray_manager_->HideTrayIcon();
}

void FlutterMcpPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method_name = method_call.method_name();

  if (method_name.compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  } else if (method_name.compare("initialize") == 0) {
    Initialize(method_call, std::move(result));
  } else if (method_name.compare("startBackgroundService") == 0) {
    StartBackgroundService(std::move(result));
  } else if (method_name.compare("stopBackgroundService") == 0) {
    StopBackgroundService(std::move(result));
  } else if (method_name.compare("configureBackgroundService") == 0) {
    ConfigureBackgroundService(method_call, std::move(result));
  } else if (method_name.compare("scheduleBackgroundTask") == 0) {
    ScheduleBackgroundTask(method_call, std::move(result));
  } else if (method_name.compare("cancelBackgroundTask") == 0) {
    CancelBackgroundTask(method_call, std::move(result));
  } else if (method_name.compare("showNotification") == 0) {
    ShowNotification(method_call, std::move(result));
  } else if (method_name.compare("requestNotificationPermission") == 0) {
    // Windows doesn't require notification permission
    result->Success(flutter::EncodableValue(true));
  } else if (method_name.compare("configureNotifications") == 0) {
    ConfigureNotifications(method_call, std::move(result));
  } else if (method_name.compare("cancelNotification") == 0) {
    CancelNotification(method_call, std::move(result));
  } else if (method_name.compare("cancelAllNotifications") == 0) {
    CancelAllNotifications(std::move(result));
  } else if (method_name.compare("secureStore") == 0) {
    SecureStore(method_call, std::move(result));
  } else if (method_name.compare("secureRead") == 0) {
    SecureRead(method_call, std::move(result));
  } else if (method_name.compare("secureDelete") == 0) {
    SecureDelete(method_call, std::move(result));
  } else if (method_name.compare("secureContainsKey") == 0) {
    SecureContainsKey(method_call, std::move(result));
  } else if (method_name.compare("secureDeleteAll") == 0) {
    SecureDeleteAll(std::move(result));
  } else if (method_name.compare("showTrayIcon") == 0) {
    ShowTrayIcon(method_call, std::move(result));
  } else if (method_name.compare("hideTrayIcon") == 0) {
    HideTrayIcon(std::move(result));
  } else if (method_name.compare("setTrayMenu") == 0) {
    SetTrayMenu(method_call, std::move(result));
  } else if (method_name.compare("updateTrayTooltip") == 0) {
    UpdateTrayTooltip(method_call, std::move(result));
  } else if (method_name.compare("configureTray") == 0) {
    ConfigureTray(method_call, std::move(result));
  } else if (method_name.compare("checkPermission") == 0) {
    // Windows doesn't require most permissions
    result->Success(flutter::EncodableValue(true));
  } else if (method_name.compare("requestPermission") == 0) {
    // Windows doesn't require most permissions
    result->Success(flutter::EncodableValue(true));
  } else if (method_name.compare("shutdown") == 0) {
    Shutdown(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void FlutterMcpPlugin::Initialize(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Initialize components based on config
  result->Success();
}

void FlutterMcpPlugin::StartBackgroundService(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  background_service_->Start([this](const std::string& event_type, 
                                   const std::map<std::string, flutter::EncodableValue>& data) {
    SendEvent(event_type, data);
  });
  result->Success(flutter::EncodableValue(true));
}

void FlutterMcpPlugin::StopBackgroundService(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  background_service_->Stop();
  result->Success(flutter::EncodableValue(true));
}

void FlutterMcpPlugin::ConfigureBackgroundService(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (arguments) {
    auto interval_it = arguments->find(flutter::EncodableValue("intervalMs"));
    if (interval_it != arguments->end()) {
      if (const auto* interval = std::get_if<int32_t>(&interval_it->second)) {
        background_service_->SetInterval(*interval);
      }
    }
  }
  result->Success();
}

void FlutterMcpPlugin::ScheduleBackgroundTask(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto task_id_it = arguments->find(flutter::EncodableValue("taskId"));
  auto delay_it = arguments->find(flutter::EncodableValue("delayMillis"));

  if (task_id_it == arguments->end() || delay_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing required arguments");
    return;
  }

  const auto* task_id = std::get_if<std::string>(&task_id_it->second);
  const auto* delay_millis = std::get_if<int64_t>(&delay_it->second);

  if (!task_id || !delay_millis) {
    result->Error("INVALID_ARGS", "Invalid argument types");
    return;
  }

  background_service_->ScheduleTask(*task_id, *delay_millis, [this, task_id = *task_id]() {
    std::map<std::string, flutter::EncodableValue> data;
    data["taskId"] = flutter::EncodableValue(task_id);
    data["timestamp"] = flutter::EncodableValue(static_cast<int64_t>(
        std::chrono::system_clock::now().time_since_epoch().count()));
    SendEvent("backgroundTaskResult", data);
  });

  result->Success();
}

void FlutterMcpPlugin::CancelBackgroundTask(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto task_id_it = arguments->find(flutter::EncodableValue("taskId"));
  if (task_id_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing task ID");
    return;
  }

  const auto* task_id = std::get_if<std::string>(&task_id_it->second);
  if (!task_id) {
    result->Error("INVALID_ARGS", "Invalid task ID type");
    return;
  }

  background_service_->CancelTask(*task_id);
  result->Success();
}

void FlutterMcpPlugin::ShowNotification(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto title_it = arguments->find(flutter::EncodableValue("title"));
  auto body_it = arguments->find(flutter::EncodableValue("body"));
  auto id_it = arguments->find(flutter::EncodableValue("id"));

  if (title_it == arguments->end() || body_it == arguments->end() || 
      id_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing required arguments");
    return;
  }

  const auto* title = std::get_if<std::string>(&title_it->second);
  const auto* body = std::get_if<std::string>(&body_it->second);
  const auto* id = std::get_if<std::string>(&id_it->second);

  if (!title || !body || !id) {
    result->Error("INVALID_ARGS", "Invalid argument types");
    return;
  }

  notification_manager_->ShowNotification(*title, *body, *id);
  result->Success();
}

void FlutterMcpPlugin::ConfigureNotifications(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Configuration can be extended as needed
  result->Success();
}

void FlutterMcpPlugin::CancelNotification(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto id_it = arguments->find(flutter::EncodableValue("id"));
  if (id_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing notification ID");
    return;
  }

  const auto* id = std::get_if<std::string>(&id_it->second);
  if (!id) {
    result->Error("INVALID_ARGS", "Invalid ID type");
    return;
  }

  notification_manager_->CancelNotification(*id);
  result->Success();
}

void FlutterMcpPlugin::CancelAllNotifications(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  notification_manager_->CancelAllNotifications();
  result->Success();
}

void FlutterMcpPlugin::SecureStore(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto key_it = arguments->find(flutter::EncodableValue("key"));
  auto value_it = arguments->find(flutter::EncodableValue("value"));

  if (key_it == arguments->end() || value_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing required arguments");
    return;
  }

  const auto* key = std::get_if<std::string>(&key_it->second);
  const auto* value = std::get_if<std::string>(&value_it->second);

  if (!key || !value) {
    result->Error("INVALID_ARGS", "Invalid argument types");
    return;
  }

  if (secure_storage_->Store(*key, *value)) {
    result->Success();
  } else {
    result->Error("STORAGE_ERROR", "Failed to store value");
  }
}

void FlutterMcpPlugin::SecureRead(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto key_it = arguments->find(flutter::EncodableValue("key"));
  if (key_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing key");
    return;
  }

  const auto* key = std::get_if<std::string>(&key_it->second);
  if (!key) {
    result->Error("INVALID_ARGS", "Invalid key type");
    return;
  }

  std::string value;
  if (secure_storage_->Read(*key, value)) {
    result->Success(flutter::EncodableValue(value));
  } else {
    result->Error("KEY_NOT_FOUND", "Key not found");
  }
}

void FlutterMcpPlugin::SecureDelete(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto key_it = arguments->find(flutter::EncodableValue("key"));
  if (key_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing key");
    return;
  }

  const auto* key = std::get_if<std::string>(&key_it->second);
  if (!key) {
    result->Error("INVALID_ARGS", "Invalid key type");
    return;
  }

  secure_storage_->Delete(*key);
  result->Success();
}

void FlutterMcpPlugin::SecureContainsKey(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto key_it = arguments->find(flutter::EncodableValue("key"));
  if (key_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing key");
    return;
  }

  const auto* key = std::get_if<std::string>(&key_it->second);
  if (!key) {
    result->Error("INVALID_ARGS", "Invalid key type");
    return;
  }

  result->Success(flutter::EncodableValue(secure_storage_->ContainsKey(*key)));
}

void FlutterMcpPlugin::SecureDeleteAll(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  secure_storage_->DeleteAll();
  result->Success();
}

void FlutterMcpPlugin::ShowTrayIcon(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  
  std::wstring icon_path;
  std::wstring tooltip;
  
  if (arguments) {
    auto icon_it = arguments->find(flutter::EncodableValue("iconPath"));
    if (icon_it != arguments->end()) {
      if (const auto* path = std::get_if<std::string>(&icon_it->second)) {
        icon_path = std::wstring(path->begin(), path->end());
      }
    }
    
    auto tooltip_it = arguments->find(flutter::EncodableValue("tooltip"));
    if (tooltip_it != arguments->end()) {
      if (const auto* tip = std::get_if<std::string>(&tooltip_it->second)) {
        tooltip = std::wstring(tip->begin(), tip->end());
      }
    }
  }
  
  tray_manager_->ShowTrayIcon(icon_path, tooltip);
  result->Success();
}

void FlutterMcpPlugin::HideTrayIcon(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  tray_manager_->HideTrayIcon();
  result->Success();
}

void FlutterMcpPlugin::SetTrayMenu(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto items_it = arguments->find(flutter::EncodableValue("items"));
  if (items_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing menu items");
    return;
  }

  const auto* items = std::get_if<flutter::EncodableList>(&items_it->second);
  if (!items) {
    result->Error("INVALID_ARGS", "Invalid items type");
    return;
  }

  std::vector<TrayMenuItem> menu_items;
  for (const auto& item : *items) {
    const auto* item_map = std::get_if<flutter::EncodableMap>(&item);
    if (!item_map) continue;

    TrayMenuItem menu_item;
    
    auto label_it = item_map->find(flutter::EncodableValue("label"));
    if (label_it != item_map->end()) {
      if (const auto* label = std::get_if<std::string>(&label_it->second)) {
        menu_item.label = *label;
      }
    }

    auto id_it = item_map->find(flutter::EncodableValue("id"));
    if (id_it != item_map->end()) {
      if (const auto* id = std::get_if<std::string>(&id_it->second)) {
        menu_item.id = *id;
      }
    }

    auto separator_it = item_map->find(flutter::EncodableValue("isSeparator"));
    if (separator_it != item_map->end()) {
      if (const auto* is_separator = std::get_if<bool>(&separator_it->second)) {
        menu_item.is_separator = *is_separator;
      }
    }

    auto disabled_it = item_map->find(flutter::EncodableValue("disabled"));
    if (disabled_it != item_map->end()) {
      if (const auto* disabled = std::get_if<bool>(&disabled_it->second)) {
        menu_item.disabled = *disabled;
      }
    }

    menu_items.push_back(menu_item);
  }

  tray_manager_->SetMenuItems(menu_items, [this](const std::string& item_id) {
    std::map<std::string, flutter::EncodableValue> data;
    data["action"] = flutter::EncodableValue("menuItemClicked");
    data["itemId"] = flutter::EncodableValue(item_id);
    SendEvent("trayEvent", data);
  });

  result->Success();
}

void FlutterMcpPlugin::UpdateTrayTooltip(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGS", "Missing arguments");
    return;
  }

  auto tooltip_it = arguments->find(flutter::EncodableValue("tooltip"));
  if (tooltip_it == arguments->end()) {
    result->Error("INVALID_ARGS", "Missing tooltip");
    return;
  }

  const auto* tooltip = std::get_if<std::string>(&tooltip_it->second);
  if (!tooltip) {
    result->Error("INVALID_ARGS", "Invalid tooltip type");
    return;
  }

  tray_manager_->UpdateTooltip(std::wstring(tooltip->begin(), tooltip->end()));
  result->Success();
}

void FlutterMcpPlugin::ConfigureTray(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Handle tray configuration
  result->Success();
}

void FlutterMcpPlugin::Shutdown(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Stop background service
  background_service_->Stop();
  
  // Hide tray icon
  tray_manager_->HideTrayIcon();
  
  // Cancel all notifications
  notification_manager_->CancelAllNotifications();
  
  result->Success();
}

void FlutterMcpPlugin::OnListen(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
  std::lock_guard<std::mutex> lock(event_sink_mutex_);
  event_sink_ = std::move(events);
}

void FlutterMcpPlugin::OnCancel(const flutter::EncodableValue* arguments) {
  std::lock_guard<std::mutex> lock(event_sink_mutex_);
  event_sink_ = nullptr;
}

void FlutterMcpPlugin::SendEvent(const std::string& event_type,
                                const std::map<std::string, flutter::EncodableValue>& data) {
  std::lock_guard<std::mutex> lock(event_sink_mutex_);
  if (event_sink_) {
    flutter::EncodableMap event;
    event[flutter::EncodableValue("type")] = flutter::EncodableValue(event_type);
    event[flutter::EncodableValue("data")] = flutter::EncodableValue(data);
    event_sink_->Success(flutter::EncodableValue(event));
  }
}

}  // namespace flutter_mcp