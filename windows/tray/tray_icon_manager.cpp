#include "tray_icon_manager.h"
#include <strsafe.h>

namespace flutter_mcp {

TrayIconManager* TrayIconManager::instance_ = nullptr;

TrayIconManager::TrayIconManager(flutter::FlutterView* view)
    : flutter_view_(view), window_handle_(nullptr), context_menu_(nullptr), is_visible_(false) {
  instance_ = this;
  CreateTrayWindow();
}

TrayIconManager::~TrayIconManager() {
  HideTrayIcon();
  DestroyTrayWindow();
  instance_ = nullptr;
}

void TrayIconManager::CreateTrayWindow() {
  // Register window class
  WNDCLASSEX wc = {0};
  wc.cbSize = sizeof(WNDCLASSEX);
  wc.lpfnWndProc = WindowProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = L"FlutterMCPTrayWindow";
  
  if (!RegisterClassEx(&wc)) {
    return;
  }

  // Create message-only window
  window_handle_ = CreateWindowEx(
      0,
      L"FlutterMCPTrayWindow",
      L"Flutter MCP Tray",
      0,
      0, 0, 0, 0,
      HWND_MESSAGE,
      nullptr,
      GetModuleHandle(nullptr),
      nullptr
  );
}

void TrayIconManager::DestroyTrayWindow() {
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  UnregisterClass(L"FlutterMCPTrayWindow", GetModuleHandle(nullptr));
}

void TrayIconManager::ShowTrayIcon(const std::wstring& icon_path, const std::wstring& tooltip) {
  if (!window_handle_) return;

  ZeroMemory(&nid_, sizeof(NOTIFYICONDATA));
  nid_.cbSize = sizeof(NOTIFYICONDATA);
  nid_.hWnd = window_handle_;
  nid_.uID = TRAY_ICON_ID;
  nid_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid_.uCallbackMessage = WM_TRAYICON;

  // Load icon
  if (!icon_path.empty()) {
    nid_.hIcon = (HICON)LoadImage(nullptr, icon_path.c_str(), IMAGE_ICON, 16, 16, LR_LOADFROMFILE);
  }
  if (!nid_.hIcon) {
    // Use default application icon
    nid_.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  }

  // Set tooltip
  if (!tooltip.empty()) {
    StringCchCopy(nid_.szTip, ARRAYSIZE(nid_.szTip), tooltip.c_str());
  } else {
    StringCchCopy(nid_.szTip, ARRAYSIZE(nid_.szTip), L"Flutter MCP");
  }

  // Add or modify tray icon
  if (!is_visible_) {
    Shell_NotifyIcon(NIM_ADD, &nid_);
    is_visible_ = true;
  } else {
    Shell_NotifyIcon(NIM_MODIFY, &nid_);
  }
}

void TrayIconManager::HideTrayIcon() {
  if (is_visible_ && window_handle_) {
    Shell_NotifyIcon(NIM_DELETE, &nid_);
    is_visible_ = false;
  }
  
  if (nid_.hIcon && nid_.hIcon != LoadIcon(nullptr, IDI_APPLICATION)) {
    DestroyIcon(nid_.hIcon);
    nid_.hIcon = nullptr;
  }
}

void TrayIconManager::UpdateTooltip(const std::wstring& tooltip) {
  if (!is_visible_ || !window_handle_) return;

  nid_.uFlags = NIF_TIP;
  StringCchCopy(nid_.szTip, ARRAYSIZE(nid_.szTip), tooltip.c_str());
  Shell_NotifyIcon(NIM_MODIFY, &nid_);
}

void TrayIconManager::SetMenuItems(const std::vector<TrayMenuItem>& items,
                                   std::function<void(const std::string&)> callback) {
  menu_items_ = items;
  menu_callback_ = callback;

  // Destroy old menu
  if (context_menu_) {
    DestroyMenu(context_menu_);
  }

  // Create new menu
  context_menu_ = CreatePopupMenu();
  int menu_id = MENU_ITEM_BASE_ID;

  for (const auto& item : menu_items_) {
    if (item.is_separator) {
      AppendMenu(context_menu_, MF_SEPARATOR, 0, nullptr);
    } else {
      UINT flags = MF_STRING;
      if (item.disabled) {
        flags |= MF_GRAYED;
      }
      
      std::wstring wide_label(item.label.begin(), item.label.end());
      AppendMenu(context_menu_, flags, menu_id++, wide_label.c_str());
    }
  }
}

void TrayIconManager::ShowContextMenu() {
  if (!context_menu_ || !window_handle_) return;

  POINT pt;
  GetCursorPos(&pt);

  // Required to make menu disappear when clicking outside
  SetForegroundWindow(window_handle_);

  TrackPopupMenu(
      context_menu_,
      TPM_RIGHTALIGN | TPM_BOTTOMALIGN | TPM_LEFTBUTTON,
      pt.x, pt.y,
      0,
      window_handle_,
      nullptr
  );

  // Required to make menu disappear when clicking outside
  PostMessage(window_handle_, WM_NULL, 0, 0);
}

LRESULT CALLBACK TrayIconManager::WindowProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  if (!instance_) return DefWindowProc(hwnd, msg, wparam, lparam);

  switch (msg) {
    case WM_TRAYICON:
      if (LOWORD(lparam) == WM_RBUTTONUP) {
        instance_->ShowContextMenu();
      } else if (LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        if (instance_->menu_callback_) {
          instance_->menu_callback_("trayIconClicked");
        }
      }
      return 0;

    case WM_COMMAND:
      if (wparam >= MENU_ITEM_BASE_ID && 
          wparam < MENU_ITEM_BASE_ID + instance_->menu_items_.size()) {
        int index = wparam - MENU_ITEM_BASE_ID;
        if (instance_->menu_callback_ && !instance_->menu_items_[index].is_separator) {
          instance_->menu_callback_(instance_->menu_items_[index].id);
        }
      }
      return 0;

    default:
      return DefWindowProc(hwnd, msg, wparam, lparam);
  }
}

}  // namespace flutter_mcp