#ifndef NOTIFICATION_MANAGER_H_
#define NOTIFICATION_MANAGER_H_

#include <windows.h>
#include <string>
#include <map>
#include <memory>

namespace flutter_mcp {

class NotificationManager {
 public:
  NotificationManager();
  ~NotificationManager();

  void ShowNotification(const std::string& title, const std::string& body, const std::string& id);
  void CancelNotification(const std::string& id);
  void CancelAllNotifications();
  void Configure(const std::map<std::string, std::string>& config);

 private:
  struct NotificationData {
    std::string title;
    std::string body;
    std::string id;
    HWND hwnd;
  };

  void ShowBalloonNotification(const NotificationData& data);
  static LRESULT CALLBACK NotificationWindowProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);
  
  std::map<std::string, std::unique_ptr<NotificationData>> active_notifications_;
  static NotificationManager* instance_;
  static constexpr UINT WM_TRAYNOTIFY = WM_APP + 100;
  static constexpr UINT NOTIFICATION_ID_BASE = 3000;
};

}  // namespace flutter_mcp

#endif  // NOTIFICATION_MANAGER_H_