#ifndef TRAY_ICON_MANAGER_H_
#define TRAY_ICON_MANAGER_H_

#include <windows.h>
#include <shellapi.h>
#include <flutter/plugin_registrar_windows.h>
#include <functional>
#include <string>
#include <vector>
#include <memory>

namespace flutter_mcp {

struct TrayMenuItem {
  std::string id;
  std::string label;
  bool is_separator = false;
  bool disabled = false;
};

class TrayIconManager {
 public:
  explicit TrayIconManager(flutter::FlutterView* view);
  ~TrayIconManager();

  void ShowTrayIcon(const std::wstring& icon_path, const std::wstring& tooltip);
  void HideTrayIcon();
  void UpdateTooltip(const std::wstring& tooltip);
  void SetMenuItems(const std::vector<TrayMenuItem>& items,
                    std::function<void(const std::string&)> callback);

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);
  void CreateTrayWindow();
  void DestroyTrayWindow();
  void ShowContextMenu();
  
  static constexpr UINT WM_TRAYICON = WM_APP + 1;
  static constexpr UINT TRAY_ICON_ID = 1001;
  static constexpr UINT MENU_ITEM_BASE_ID = 2000;

  HWND window_handle_;
  NOTIFYICONDATA nid_;
  HMENU context_menu_;
  flutter::FlutterView* flutter_view_;
  bool is_visible_;
  std::vector<TrayMenuItem> menu_items_;
  std::function<void(const std::string&)> menu_callback_;
  static TrayIconManager* instance_;
};

}  // namespace flutter_mcp

#endif  // TRAY_ICON_MANAGER_H_