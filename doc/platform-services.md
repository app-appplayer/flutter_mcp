# Platform Services

`PlatformServices` is the layer that integrates Flutter MCP with the
host operating system: background execution, notifications, system
tray, secure storage, lifecycle, and runtime permissions. Reach it via:

```dart
final platform = FlutterMCP.instance.platformServices;
```

This page lists what's available, the constraints per platform, and
the auto-wiring that happens when you set the corresponding
`MCPConfig` flags.

---

## Auto-wiring through `MCPConfig`

Setting a feature flag in `MCPConfig` provisions the matching native
manager during `init`:

| Flag | Wires |
|---|---|
| `useBackgroundService: true` | Platform-specific background service (Android foreground service, iOS BGTaskScheduler, desktop standalone, web Worker fallback) |
| `useNotification: true` | Native notification system + permission request |
| `useTray: true` | Platform tray manager (macOS / Windows / Linux only) |
| `secure: true` (default) | `SecureStorageManager` backed by Keychain / Credential Manager / `EncryptedSharedPreferences` |
| `lifecycleManaged: true` (default) | `LifecycleManager` listening to platform foreground/background transitions |
| `autoStart: true` (default) | Calls `startServices()` at the tail of `init` |

Disable per feature with `false`. Mismatched flags throw
`MCPPlatformNotSupportedException` with a `resolution:` hint
(e.g. `useTray: true` on Android).

---

## Background service

```dart
final platform = FlutterMCP.instance.platformServices;
await platform.startBackgroundService();   // bool — true if started
await platform.stopBackgroundService();
final running = platform.isBackgroundServiceRunning;
```

Per-platform behaviour:

| Platform | Implementation |
|---|---|
| Android | Foreground service. Configure types via `pubspec.yaml` (`flutter_mcp.android.foreground_service_types`); default is `dataSync`. Boot-restart available via `BackgroundConfig.autoStartOnBoot`. |
| iOS | `BGTaskScheduler` background fetch + processing tasks. iOS enforces a **15-minute minimum** interval — Flutter MCP raises any `intervalMs < 900000` to 15 minutes silently. |
| macOS / Windows / Linux | Pure-Dart timer + native channel for OS notifications. No special permissions. |
| Web | Web Worker if available, else a Dart `Timer.periodic`. Heavily restricted by the browser when the tab is hidden. |

Configure interval and notification appearance via
`MCPConfig.background`:

```dart
MCPConfig(
  useBackgroundService: true,
  background: BackgroundConfig(
    notificationChannelId: 'mcp_bg',
    notificationChannelName: 'MCP Background',
    notificationDescription: 'Keeps MCP services alive',
    notificationIcon: 'ic_notification',     // Android resource name
    autoStartOnBoot: false,
    intervalMs: 60000,
    keepAlive: true,
  ),
);
```

---

## Notifications

```dart
await platform.showNotification(
  title: 'Hello',
  body:  'World',
  icon:  'ic_notification',
  id:    'msg-1',
);
await platform.hideNotification('msg-1');
```

Permission is requested automatically when `useNotification: true`
unless you call `requestPermission` yourself first. iOS and Android 13+
require runtime consent.

Configure default channel / priority via `MCPConfig.notification`:

```dart
MCPConfig(
  useNotification: true,
  notification: NotificationConfig(
    channelId: 'mcp_notifications',
    channelName: 'MCP Notifications',
    channelDescription: 'App-level notifications',
    icon: 'ic_notification',
    enableSound: true,
    enableVibration: true,
    priority: NotificationPriority.high,    // min, low, normal, high, max
  ),
);
```

The richer surface (actions, progress, image, ongoing) is on the
underlying `NotificationManager` returned by `PlatformFactory`; reach
it through `platform` only when you want the simple title/body case.

---

## System tray (desktop only)

```dart
await platform.setTrayIcon('assets/tray.png');
await platform.setTrayTooltip('My MCP App');
await platform.setTrayMenu([
  TrayMenuItem(label: 'Show', onTap: showWindow),
  TrayMenuItem.separator(),
  TrayMenuItem(label: 'Quit', onTap: exit),
]);
```

Or pre-declare via `MCPConfig.tray`:

```dart
MCPConfig(
  useTray: true,
  tray: TrayConfig(
    iconPath: 'assets/tray.png',
    tooltip: 'My MCP App',
    menuItems: [
      TrayMenuItem(label: 'Show', onTap: showWindow),
      TrayMenuItem.separator(),
      TrayMenuItem(label: 'Quit', onTap: exit),
    ],
  ),
);
```

Per-platform notes:
- **macOS** — `MacOSEnhancedTrayManager`: NSStatusItem, supports
  template icons (`*Template.png`), submenus, keyboard shortcuts via
  `EnhancedTrayMenuItem(shortcut: 'Cmd+Q')`.
- **Windows** — Win32 `Shell_NotifyIcon`. Balloon notifications via
  `platformShowBalloon`.
- **Linux** — `AppIndicator` / `StatusNotifierItem`; depends on a
  compatible session bus.
- **Android / iOS / Web** — no system tray; `useTray: true` raises
  `MCPPlatformNotSupportedException`.

---

## Secure storage

```dart
await platform.secureStore('api_key', 'sk-...');
final key = await platform.secureRead('api_key');
final removed = await platform.secureDelete('api_key');     // bool
final present = await platform.secureContains('api_key');   // bool
```

Backing implementations:

| Platform | Backend |
|---|---|
| Android | `EncryptedSharedPreferences` (AES-256, master key in Android Keystore) |
| iOS / macOS | Keychain Services |
| Windows | Credential Manager |
| Linux | libsecret / GNOME Keyring (where available) |
| Web | `WebStorageManager` over `localStorage` / `sessionStorage` with AES-encrypted values; weaker than native Keychain but better than plaintext |

Native platforms route through the method channel, so values never
materialise in JS. On the web only the encrypted ciphertext is on
disk; the IV and key derivation parameters are stored alongside.

---

## Lifecycle

`LifecycleManager` (when `lifecycleManaged: true`) wires the
`WidgetsBindingObserver` lifecycle to the manager runtime so that
background entry / foreground resume can pause/resume schedulers and
notify clients. Listen to changes:

```dart
platform.setLifecycleChangeListener((state) {
  // state: AppLifecycleState (resumed / inactive / paused / detached)
});
```

The default observer flushes the response cache when the app goes to
background and re-warms it on resume.

---

## Permissions

```dart
await platform.checkPermission('notification');     // bool
await platform.requestPermission('notification');   // bool
await platform.requestPermissions(['notification', 'location']);
                                                    // Map<String, bool>
```

Or rely on the auto-request flow — calling
`FlutterMCP.instance.requestRequiredPermissions()` after `init` walks
the active `MCPConfig` and asks for everything implied by the enabled
flags (currently: notification, plus POST_NOTIFICATIONS on Android 13+
when background service is on).

---

## Inspecting platform state

`getSystemStatus()` returns `platformName` and `platformFeatures`
(a `{feature: supported}` map). For a richer per-component view use
`getSystemHealth()` (see `doc/observability.md`). For preflight checks:

```dart
import 'package:flutter_mcp/flutter_mcp.dart';

if (PlatformUtils.supportsTray) { /* OK to set tray */ }
if (PlatformUtils.supportsBackgroundService) { /* OK */ }
if (await PlatformUtils.isAndroidAtLeast(33)) { /* needs runtime perms */ }
if (await PlatformUtils.isIOSAtLeast('15.0')) { /* iOS 15+ feature */ }
```

`PlatformUtils.getPlatformVersionInfo()` returns a populated map:
`{platform, isWeb, operatingSystemVersion, [androidSdkVersion],
[iosVersion]}`.

---

## Web caveats

- No native tray, no native foreground service. Setting either with
  `useTray: true` / `useBackgroundService: true` returns `false`
  cleanly on web (the implementation is best-effort).
- Notification permission must be triggered by a user gesture in most
  browsers — calling `showNotification` without prior user activation
  will be blocked.
- `WebMemoryMonitor` (exposed via `WebMemoryMonitor.instance`) gives
  approximate JS heap stats from `performance.memory` /
  `PerformanceObserver` / `NavigatorUAData`. See the worked example in
  `README.md`.
