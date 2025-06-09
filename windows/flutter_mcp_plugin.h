#ifndef FLUTTER_PLUGIN_FLUTTER_MCP_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_MCP_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/event_sink.h>
#include <flutter/event_channel.h>

#include <memory>
#include <map>
#include <string>
#include <mutex>

namespace flutter_mcp {

// Forward declarations
class TrayIconManager;
class NotificationManager;
class SecureStorageService;
class BackgroundService;

struct TrayMenuItem {
  std::string id;
  std::string label;
  bool is_separator = false;
  bool disabled = false;
};

class FlutterMcpPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit FlutterMcpPlugin(flutter::PluginRegistrarWindows *registrar);

  virtual ~FlutterMcpPlugin();

  // Disallow copy and assign.
  FlutterMcpPlugin(const FlutterMcpPlugin&) = delete;
  FlutterMcpPlugin& operator=(const FlutterMcpPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Event channel handlers
  void OnListen(const flutter::EncodableValue* arguments,
                std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events);
  void OnCancel(const flutter::EncodableValue* arguments);

 private:
  // Method handlers
  void Initialize(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StartBackgroundService(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StopBackgroundService(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ConfigureBackgroundService(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ScheduleBackgroundTask(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CancelBackgroundTask(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ShowNotification(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ConfigureNotifications(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CancelNotification(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CancelAllNotifications(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SecureStore(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SecureRead(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SecureDelete(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SecureContainsKey(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SecureDeleteAll(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ShowTrayIcon(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HideTrayIcon(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetTrayMenu(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void UpdateTrayTooltip(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ConfigureTray(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                     std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Shutdown(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Event sending
  void SendEvent(const std::string& event_type,
                 const std::map<std::string, flutter::EncodableValue>& data);

  // Member variables
  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<TrayIconManager> tray_manager_;
  std::unique_ptr<NotificationManager> notification_manager_;
  std::unique_ptr<SecureStorageService> secure_storage_;
  std::unique_ptr<BackgroundService> background_service_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::mutex event_sink_mutex_;
};

}  // namespace flutter_mcp

#endif  // FLUTTER_PLUGIN_FLUTTER_MCP_PLUGIN_H_
