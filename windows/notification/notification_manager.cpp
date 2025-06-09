#include "notification_manager.h"
#include <shellapi.h>
#include <strsafe.h>

namespace flutter_mcp {

NotificationManager* NotificationManager::instance_ = nullptr;

NotificationManager::NotificationManager() {
  instance_ = this;
}

NotificationManager::~NotificationManager() {
  CancelAllNotifications();
  instance_ = nullptr;
}

void NotificationManager::ShowNotification(const std::string& title, const std::string& body, const std::string& id) {
  // Cancel existing notification with same ID
  CancelNotification(id);

  // Create notification data
  auto data = std::make_unique<NotificationData>();
  data->title = title;
  data->body = body;
  data->id = id;

  // Register window class for this notification
  WNDCLASSEX wc = {0};
  wc.cbSize = sizeof(WNDCLASSEX);
  wc.lpfnWndProc = NotificationWindowProc;
  wc.hInstance = GetModuleHandle(nullptr);
  
  std::wstring class_name = L"FlutterMCPNotification_" + std::wstring(id.begin(), id.end());
  wc.lpszClassName = class_name.c_str();
  
  RegisterClassEx(&wc);

  // Create message-only window for this notification
  data->hwnd = CreateWindowEx(
      0,
      class_name.c_str(),
      L"Notification Window",
      0,
      0, 0, 0, 0,
      HWND_MESSAGE,
      nullptr,
      GetModuleHandle(nullptr),
      nullptr
  );

  if (data->hwnd) {
    // Store pointer to notification data in window
    SetWindowLongPtr(data->hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(data.get()));
    
    ShowBalloonNotification(*data);
    active_notifications_[id] = std::move(data);
  }
}

void NotificationManager::ShowBalloonNotification(const NotificationData& data) {
  NOTIFYICONDATA nid = {0};
  nid.cbSize = sizeof(NOTIFYICONDATA);
  nid.hWnd = data.hwnd;
  nid.uID = NOTIFICATION_ID_BASE + std::hash<std::string>{}(data.id);
  nid.uFlags = NIF_INFO | NIF_MESSAGE;
  nid.uCallbackMessage = WM_TRAYNOTIFY;
  
  // Set notification text
  std::wstring wide_title(data.title.begin(), data.title.end());
  std::wstring wide_body(data.body.begin(), data.body.end());
  
  StringCchCopy(nid.szInfoTitle, ARRAYSIZE(nid.szInfoTitle), wide_title.c_str());
  StringCchCopy(nid.szInfo, ARRAYSIZE(nid.szInfo), wide_body.c_str());
  
  nid.dwInfoFlags = NIIF_INFO;
  nid.uTimeout = 10000; // 10 seconds
  
  // Add icon to show notification
  nid.uFlags |= NIF_ICON;
  nid.hIcon = LoadIcon(nullptr, IDI_INFORMATION);
  
  Shell_NotifyIcon(NIM_ADD, &nid);
  
  // Schedule removal after timeout
  SetTimer(data.hwnd, 1, 10000, nullptr);
}

void NotificationManager::CancelNotification(const std::string& id) {
  auto it = active_notifications_.find(id);
  if (it != active_notifications_.end()) {
    NOTIFYICONDATA nid = {0};
    nid.cbSize = sizeof(NOTIFYICONDATA);
    nid.hWnd = it->second->hwnd;
    nid.uID = NOTIFICATION_ID_BASE + std::hash<std::string>{}(id);
    
    Shell_NotifyIcon(NIM_DELETE, &nid);
    
    if (it->second->hwnd) {
      DestroyWindow(it->second->hwnd);
    }
    
    std::wstring class_name = L"FlutterMCPNotification_" + std::wstring(id.begin(), id.end());
    UnregisterClass(class_name.c_str(), GetModuleHandle(nullptr));
    
    active_notifications_.erase(it);
  }
}

void NotificationManager::CancelAllNotifications() {
  std::vector<std::string> ids;
  for (const auto& pair : active_notifications_) {
    ids.push_back(pair.first);
  }
  
  for (const auto& id : ids) {
    CancelNotification(id);
  }
}

void NotificationManager::Configure(const std::map<std::string, std::string>& config) {
  // Configuration can be extended as needed
}

LRESULT CALLBACK NotificationManager::NotificationWindowProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  NotificationData* data = reinterpret_cast<NotificationData*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  
  switch (msg) {
    case WM_TRAYNOTIFY:
      if (LOWORD(lparam) == NIN_BALLOONUSERCLICK) {
        // User clicked the notification
        // Could send event to Flutter here
      } else if (LOWORD(lparam) == NIN_BALLOONTIMEOUT || LOWORD(lparam) == NIN_BALLOONHIDE) {
        // Notification closed
        if (data && instance_) {
          instance_->CancelNotification(data->id);
        }
      }
      return 0;
      
    case WM_TIMER:
      if (wparam == 1 && data && instance_) {
        instance_->CancelNotification(data->id);
      }
      return 0;
      
    default:
      return DefWindowProc(hwnd, msg, wparam, lparam);
  }
}

}  // namespace flutter_mcp