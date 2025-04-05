네, 누락된 몇 가지 중요한 파일들을 추가로 작성해 드리겠습니다.

### 1. lib/src/platform/background/ios_background.dart

```dart
import 'dart:async';
import '../../config/background_config.dart';
import '../../utils/logger.dart';
import 'background_service.dart';

/// iOS 백그라운드 서비스 구현
class IOSBackgroundService implements BackgroundService {
  bool _isRunning = false;
  Timer? _backgroundTimer;
  final MCPLogger _logger = MCPLogger('mcp.ios_background');
  
  @override
  bool get isRunning => _isRunning;
  
  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.debug('iOS 백그라운드 서비스 초기화');
    // iOS는 제한된 백그라운드 실행 기능만 제공합니다
    // Background Fetch 또는 Background Processing 등록
    
    // 필요한 초기화 작업 수행
  }
  
  @override
  Future<bool> start() async {
    _logger.debug('iOS 백그라운드 서비스 시작');
    
    // iOS에서는 실제 백그라운드 작업을 위한 다양한 방법이 있습니다
    // 1. Background Fetch
    // 2. Background Processing
    // 3. Background Notification
    // 여기서는 타이머를 이용한 단순한 구현을 예시로 제공합니다
    
    // 주기적 작업을 위한 타이머 설정 (iOS 앱이 포그라운드에 있을 때만 작동)
    _backgroundTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      _performBackgroundTask();
    });
    
    _isRunning = true;
    return true;
  }
  
  @override
  Future<bool> stop() async {
    _logger.debug('iOS 백그라운드 서비스 중지');
    
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    
    _isRunning = false;
    return true;
  }
  
  /// 백그라운드 작업 수행
  void _performBackgroundTask() {
    _logger.debug('iOS 백그라운드 작업 수행');
    
    // 실제 백그라운드 작업 구현
    // - 상태 동기화
    // - 알림 업데이트
    // - 필수 서비스 유지 등
  }
}
```

### 2. lib/src/platform/background/desktop_background.dart

```dart
import 'dart:async';
import '../../config/background_config.dart';
import '../../utils/logger.dart';
import 'background_service.dart';

/// 데스크탑(macOS, Windows, Linux) 백그라운드 서비스 구현
class DesktopBackgroundService implements BackgroundService {
  bool _isRunning = false;
  Timer? _backgroundTimer;
  final MCPLogger _logger = MCPLogger('mcp.desktop_background');
  
  @override
  bool get isRunning => _isRunning;
  
  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.debug('데스크탑 백그라운드 서비스 초기화');
    
    // 데스크탑 플랫폼별 초기화 로직
  }
  
  @override
  Future<bool> start() async {
    _logger.debug('데스크탑 백그라운드 서비스 시작');
    
    // 주기적 작업을 위한 타이머 설정
    _backgroundTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      _performBackgroundTask();
    });
    
    _isRunning = true;
    return true;
  }
  
  @override
  Future<bool> stop() async {
    _logger.debug('데스크탑 백그라운드 서비스 중지');
    
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    
    _isRunning = false;
    return true;
  }
  
  /// 백그라운드 작업 수행
  void _performBackgroundTask() {
    _logger.debug('데스크탑 백그라운드 작업 수행');
    
    // 실제 백그라운드 작업 구현
    // - 상태 유지
    // - 정기적인 작업 수행
    // - 시스템 정보 업데이트 등
  }
}
```

### 3. lib/src/platform/notification/android_notification.dart

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import 'notification_manager.dart';

/// 안드로이드 알림 관리자 구현
class AndroidNotificationManager implements NotificationManager {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final MCPLogger _logger = MCPLogger('mcp.android_notification');
  
  String _channelId = 'flutter_mcp_channel';
  String _channelName = 'MCP Notifications';
  String _channelDescription = 'Notifications from MCP';
  
  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('안드로이드 알림 관리자 초기화');
    
    if (config != null) {
      _channelId = config.channelId ?? _channelId;
      _channelName = config.channelName ?? _channelName;
      _channelDescription = config.channelDescription ?? _channelDescription;
    }
    
    // 안드로이드 알림 설정
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
        
    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }
  
  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    _logger.debug('안드로이드 알림 표시: $title');
    
    // 안드로이드 알림 채널 설정
    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    
    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await _notificationsPlugin.show(
      0, // Notification ID
      title,
      body,
      platformChannelSpecifics,
      payload: id,
    );
  }
  
  @override
  Future<void> hideNotification(String id) async {
    _logger.debug('안드로이드 알림 숨김: $id');
    
    await _notificationsPlugin.cancel(0); // ID에 따라 여러 알림 관리 가능
  }
  
  /// 알림 탭 핸들러
  void _onNotificationTap(NotificationResponse response) {
    _logger.debug('알림 탭됨: ${response.payload}');
    
    // 알림 탭 이벤트 처리
    // 예: 앱을 포그라운드로 가져오기, 특정 화면으로 이동 등
  }
}
```

### 4. lib/src/platform/notification/ios_notification.dart

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import 'notification_manager.dart';

/// iOS 알림 관리자 구현
class IOSNotificationManager implements NotificationManager {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final MCPLogger _logger = MCPLogger('mcp.ios_notification');
  
  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('iOS 알림 관리자 초기화');
    
    // iOS 알림 설정
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    
    final InitializationSettings initializationSettings = InitializationSettings(
      iOS: initializationSettingsIOS,
    );
    
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    
    // iOS 권한 요청
    await _requestPermissions();
  }
  
  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    _logger.debug('iOS 알림 표시: $title');
    
    // iOS 알림 설정
    DarwinNotificationDetails iOSPlatformChannelSpecifics =
        const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    NotificationDetails platformChannelSpecifics =
        NotificationDetails(iOS: iOSPlatformChannelSpecifics);
    
    await _notificationsPlugin.show(
      0, // Notification ID
      title,
      body,
      platformChannelSpecifics,
      payload: id,
    );
  }
  
  @override
  Future<void> hideNotification(String id) async {
    _logger.debug('iOS 알림 숨김: $id');
    
    await _notificationsPlugin.cancel(0);
  }
  
  /// 알림 권한 요청
  Future<void> _requestPermissions() async {
    _logger.debug('iOS 알림 권한 요청');
    
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }
  
  /// 알림 탭 핸들러
  void _onNotificationTap(NotificationResponse response) {
    _logger.debug('알림 탭됨: ${response.payload}');
    
    // 알림 탭 이벤트 처리
  }
}
```

### 5. lib/src/platform/notification/notification_manager.dart

```dart
import '../../config/notification_config.dart';

/// 알림 관리자 인터페이스
abstract class NotificationManager {
  /// 알림 관리자 초기화
  Future<void> initialize(NotificationConfig? config);
  
  /// 알림 표시
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  });
  
  /// 알림 숨김
  Future<void> hideNotification(String id);
}

/// 기능 없는 알림 관리자 (지원하지 않는 플랫폼용)
class NoOpNotificationManager implements NotificationManager {
  @override
  Future<void> initialize(NotificationConfig? config) async {}
  
  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {}
  
  @override
  Future<void> hideNotification(String id) async {}
}
```

### 6. lib/src/platform/tray/tray_manager.dart

```dart
import '../../config/tray_config.dart';

/// 트레이 메뉴 항목
class TrayMenuItem {
  /// 메뉴 항목 라벨
  final String? label;
  
  /// 메뉴 항목 클릭 핸들러
  final Function()? onTap;
  
  /// 메뉴 항목 비활성화 여부
  final bool disabled;
  
  /// 구분선 여부
  final bool isSeparator;
  
  /// 메뉴 항목 생성
  TrayMenuItem({
    this.label,
    this.onTap,
    this.disabled = false,
  }) : isSeparator = false;
  
  /// 구분선 생성
  TrayMenuItem.separator()
    : label = null,
      onTap = null,
      disabled = false,
      isSeparator = true;
}

/// 트레이 관리자 인터페이스
abstract class TrayManager {
  /// 트레이 관리자 초기화
  Future<void> initialize(TrayConfig? config);
  
  /// 아이콘 설정
  Future<void> setIcon(String path);
  
  /// 툴팁 설정
  Future<void> setTooltip(String tooltip);
  
  /// 컨텍스트 메뉴 설정
  Future<void> setContextMenu(List<TrayMenuItem> items);
  
  /// 리소스 해제
  Future<void> dispose();
}

/// 기능 없는 트레이 관리자 (지원하지 않는 플랫폼용)
class NoOpTrayManager implements TrayManager {
  @override
  Future<void> initialize(TrayConfig? config) async {}
  
  @override
  Future<void> setIcon(String path) async {}
  
  @override
  Future<void> setTooltip(String tooltip) async {}
  
  @override
  Future<void> setContextMenu(List<TrayMenuItem> items) async {}
  
  @override
  Future<void> dispose() async {}
}
```

### 7. lib/src/platform/tray/macos_tray.dart

```dart
import 'package:tray_manager/tray_manager.dart' as native_tray;
import '../../config/tray_config.dart';
import '../../utils/logger.dart';
import 'tray_manager.dart';

/// macOS 트레이 관리자 구현
class MacOSTrayManager implements TrayManager {
  final MCPLogger _logger = MCPLogger('mcp.macos_tray');
  
  @override
  Future<void> initialize(TrayConfig? config) async {
    _logger.debug('macOS 트레이 관리자 초기화');
    
    // 초기 설정
    if (config != null) {
      if (config.iconPath != null) {
        await setIcon(config.iconPath!);
      }
      
      if (config.tooltip != null) {
        await setTooltip(config.tooltip!);
      }
      
      if (config.menuItems != null) {
        await setContextMenu(config.menuItems!);
      }
    }
  }
  
  @override
  Future<void> setIcon(String path) async {
    _logger.debug('macOS 트레이 아이콘 설정: $path');
    
    try {
      await native_tray.TrayManager.instance.setIcon(path);
    } catch (e) {
      _logger.error('macOS 트레이 아이콘 설정 오류', e);
    }
  }
  
  @override
  Future<void> setTooltip(String tooltip) async {
    _logger.debug('macOS 트레이 툴팁 설정: $tooltip');
    
    try {
      await native_tray.TrayManager.instance.setToolTip(tooltip);
    } catch (e) {
      _logger.error('macOS 트레이 툴팁 설정 오류', e);
    }
  }
  
  @override
  Future<void> setContextMenu(List<TrayMenuItem> items) async {
    _logger.debug('macOS 트레이 컨텍스트 메뉴 설정');
    
    try {
      // 네이티브 메뉴 항목 변환
      final nativeItems = _convertToNativeMenuItems(items);
      
      // 메뉴 초기화
      final menu = native_tray.Menu();
      await menu.buildFrom(nativeItems);
      
      // 트레이 메뉴 설정
      await native_tray.TrayManager.instance.setContextMenu(menu);
    } catch (e) {
      _logger.error('macOS 트레이 컨텍스트 메뉴 설정 오류', e);
    }
  }
  
  @override
  Future<void> dispose() async {
    _logger.debug('macOS 트레이 관리자 종료');
    
    try {
      await native_tray.TrayManager.instance.destroy();
    } catch (e) {
      _logger.error('macOS 트레이 관리자 종료 오류', e);
    }
  }
  
  /// 메뉴 항목 변환
  List<native_tray.MenuItem> _convertToNativeMenuItems(List<TrayMenuItem> items) {
    final nativeItems = <native_tray.MenuItem>[];
    
    for (final item in items) {
      if (item.isSeparator) {
        nativeItems.add(native_tray.MenuItem.separator());
      } else {
        nativeItems.add(
          native_tray.MenuItem(
            label: item.label ?? '',
            disabled: item.disabled,
            onClick: item.onTap != null ? (_) => item.onTap!() : null,
          ),
        );
      }
    }
    
    return nativeItems;
  }
}
```

### 8. lib/src/platform/tray/windows_tray.dart

```dart
import 'package:tray_manager/tray_manager.dart' as native_tray;
import '../../config/tray_config.dart';
import '../../utils/logger.dart';
import 'tray_manager.dart';

/// Windows 트레이 관리자 구현
class WindowsTrayManager implements TrayManager {
  final MCPLogger _logger = MCPLogger('mcp.windows_tray');
  
  @override
  Future<void> initialize(TrayConfig? config) async {
    _logger.debug('Windows 트레이 관리자 초기화');
    
    // 초기 설정
    if (config != null) {
      if (config.iconPath != null) {
        await setIcon(config.iconPath!);
      }
      
      if (config.tooltip != null) {
        await setTooltip(config.tooltip!);
      }
      
      if (config.menuItems != null) {
        await setContextMenu(config.menuItems!);
      }
    }
  }
  
  @override
  Future<void> setIcon(String path) async {
    _logger.debug('Windows 트레이 아이콘 설정: $path');
    
    try {
      await native_tray.TrayManager.instance.setIcon(path);
    } catch (e) {
      _logger.error('Windows 트레이 아이콘 설정 오류', e);
    }
  }
  
  @override
  Future<void> setTooltip(String tooltip) async {
    _logger.debug('Windows 트레이 툴팁 설정: $tooltip');
    
    try {
      await native_tray.TrayManager.instance.setToolTip(tooltip);
    } catch (e) {
      _logger.error('Windows 트레이 툴팁 설정 오류', e);
    }
  }
  
  @override
  Future<void> setContextMenu(List<TrayMenuItem> items) async {
    _logger.debug('Windows 트레이 컨텍스트 메뉴 설정');
    
    try {
      // 네이티브 메뉴 항목 변환
      final nativeItems = _convertToNativeMenuItems(items);
      
      // 메뉴 초기화
      final menu = native_tray.Menu();
      await menu.buildFrom(nativeItems);
      
      // 트레이 메뉴 설정
      await native_tray.TrayManager.instance.setContextMenu(menu);
    } catch (e) {
      _logger.error('Windows 트레이 컨텍스트 메뉴 설정 오류', e);
    }
  }
  
  @override
  Future<void> dispose() async {
    _logger.debug('Windows 트레이 관리자 종료');
    
    try {
      await native_tray.TrayManager.instance.destroy();
    } catch (e) {
      _logger.error('Windows 트레이 관리자 종료 오류', e);
    }
  }
  
  /// 메뉴 항목 변환
  List<native_tray.MenuItem> _convertToNativeMenuItems(List<TrayMenuItem> items) {
    final nativeItems = <native_tray.MenuItem>[];
    
    for (final item in items) {
      if (item.isSeparator) {
        nativeItems.add(native_tray.MenuItem.separator());
      } else {
        nativeItems.add(
          native_tray.MenuItem(
            label: item.label ?? '',
            disabled: item.disabled,
            onClick: item.onTap != null ? (_) => item.onTap!() : null,
          ),
        );
      }
    }
    
    return nativeItems;
  }
}
```

### 9. lib/src/platform/lifecycle_manager.dart

```dart
import 'package:flutter/widgets.dart';
import '../utils/logger.dart';

/// 라이프사이클 관리자
class LifecycleManager with WidgetsBindingObserver {
  final MCPLogger _logger = MCPLogger('mcp.lifecycle_manager');
  
  // 라이프사이클 변경 콜백
  Function(AppLifecycleState)? _onLifecycleStateChange;
  
  /// 초기화
  void initialize() {
    _logger.debug('라이프사이클 관리자 초기화');
    WidgetsBinding.instance.addObserver(this);
  }
  
  /// 라이프사이클 변경 리스너 등록
  void setLifecycleChangeListener(Function(AppLifecycleState) listener) {
    _onLifecycleStateChange = listener;
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.debug('앱 라이프사이클 상태 변경: $state');
    
    // 라이프사이클 변경 처리
    switch (state) {
      case AppLifecycleState.resumed:
        _logger.debug('앱이 포그라운드로 복귀');
        break;
      case AppLifecycleState.inactive:
        _logger.debug('앱이 비활성화됨');
        break;
      case AppLifecycleState.paused:
        _logger.debug('앱이 백그라운드로 이동');
        break;
      case AppLifecycleState.detached:
        _logger.debug('앱이 분리됨');
        break;
      default:
        _logger.debug('알 수 없는 라이프사이클 상태: $state');
    }
    
    // 콜백 호출
    if (_onLifecycleStateChange != null) {
      _onLifecycleStateChange!(state);
    }
  }
  
  /// 리소스 해제
  void dispose() {
    _logger.debug('라이프사이클 관리자 종료');
    WidgetsBinding.instance.removeObserver(this);
    _onLifecycleStateChange = null;
  }
}
```

### 10. lib/src/config/background_config.dart

```dart
/// 백그라운드 서비스 설정
class BackgroundConfig {
  /// 알림 채널 ID (Android)
  final String? notificationChannelId;
  
  /// 알림 채널 이름 (Android)
  final String? notificationChannelName;
  
  /// 알림 채널 설명 (Android)
  final String? notificationDescription;
  
  /// 알림 아이콘 (Android)
  final String? notificationIcon;
  
  /// 부팅 시 자동 시작 여부
  final bool autoStartOnBoot;
  
  /// 백그라운드 작업 간격 (밀리초)
  final int intervalMs;
  
  /// 연결 유지
  final bool keepAlive;
  
  BackgroundConfig({
    this.notificationChannelId,
    this.notificationChannelName,
    this.notificationDescription,
    this.notificationIcon,
    this.autoStartOnBoot = false,
    this.intervalMs = 5000,
    this.keepAlive = true,
  });
  
  /// 기본 설정 생성
  factory BackgroundConfig.defaultConfig() {
    return BackgroundConfig(
      notificationChannelId: 'flutter_mcp_channel',
      notificationChannelName: 'MCP Service',
      notificationDescription: 'MCP Background Service',
      autoStartOnBoot: false,
      intervalMs: 5000,
      keepAlive: true,
    );
  }
}
```

### 11. lib/src/config/notification_config.dart

```dart
/// 알림 설정
class NotificationConfig {
  /// 알림 채널 ID (Android)
  final String? channelId;
  
  /// 알림 채널 이름 (Android)
  final String? channelName;
  
  /// 알림 채널 설명 (Android)
  final String? channelDescription;
  
  /// 알림 아이콘
  final String? icon;
  
  /// 알림음 사용 여부
  final bool enableSound;
  
  /// 알림 진동 사용 여부
  final bool enableVibration;
  
  /// 알림 중요도
  final NotificationPriority priority;
  
  NotificationConfig({
    this.channelId,
    this.channelName,
    this.channelDescription,
    this.icon,
    this.enableSound = true,
    this.enableVibration = true,
    this.priority = NotificationPriority.normal,
  });
}

/// 알림 중요도
enum NotificationPriority {
  min,
  low,
  normal,
  high,
  max,
}
```

### 12. lib/src/config/tray_config.dart

```dart
import '../platform/tray/tray_manager.dart';

/// 트레이 설정
class TrayConfig {
  /// 트레이 아이콘 경로
  final String? iconPath;
  
  /// 트레이 툴팁
  final String? tooltip;
  
  /// 트레이 메뉴 항목
  final List<TrayMenuItem>? menuItems;
  
  TrayConfig({
    this.iconPath,
    this.tooltip,
    this.menuItems,
  });
}
```

### 13. CHANGELOG.md

```markdown
# Changelog

## 0.1.0

* Initial release
* Support for MCP client, server, and LLM integration
* Platform features: background service, notifications, system tray
* Secure storage integration
* Lifecycle management
* Scheduled tasks
```

### 14. README.md

```markdown
# Flutter MCP

A Flutter plugin for integrating Large Language Models (LLMs) with [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). This plugin provides comprehensive integration between MCP components and platform-specific features like background execution, notifications, system tray, and lifecycle management.

## Features

- **MCP Integration**:
  - Seamless integration with `mcp_client`, `mcp_server`, and `mcp_llm`
  - Support for multiple simultaneous MCP clients and servers
  - LLM integration with MCP components

- **Platform Features**:
  - Background service execution
  - Local notifications
  - System tray support (on desktop platforms)
  - Application lifecycle management
  - Secure storage for credentials and configuration

- **Advanced Capabilities**:
  - Task scheduling
  - Configurable logging
  - Cross-platform support: Android, iOS, macOS, Windows, Linux

## Getting Started

### Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_mcp: ^0.1.0
```

Or install via command line:

```bash
flutter pub add flutter_mcp
```

### Basic Usage

```dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Flutter MCP
  await FlutterMCP.instance.init(
    MCPConfig(
      appName: 'My MCP App',
      appVersion: '1.0.0',
      useBackgroundService: true,
      useNotification: true,
      useTray: true,
      autoStart: true,
      // Auto-start server configuration
      autoStartServer: [
        MCPServerConfig(
          name: 'MCP Server',
          version: '1.0.0',
          capabilities: ServerCapabilities(
            tools: true,
            resources: true,
            prompts: true,
          ),
          integrateLlm: MCPLlmIntegration(
            providerName: 'your-provider',
            config: LlmConfiguration(
              apiKey: 'your-api-key',
              model: 'your-model',
            ),
          ),
        ),
      ],
      // Auto-start client configuration
      autoStartClient: [
        MCPClientConfig(
          name: 'MCP Client',
          version: '1.0.0',
          capabilities: ClientCapabilities(
            sampling: true,
            roots: true,
          ),
          integrateLlm: MCPLlmIntegration(
            existingLlmId: 'llm_1',
          ),
        ),
      ],
      // Scheduled tasks
      schedule: [
        MCPJob.every(
          Duration(minutes: 15),
          task: () {
            print('This runs every 15 minutes');
          },
        ),
      ],
    ),
  );
  
  runApp(MyApp());
}
```

### Manual Component Creation

You can also manually create and manage MCP components:

```dart
// Create a server
final serverId = await FlutterMCP.instance.createServer(
  name: 'MCP Server',
  version: '1.0.0',
  capabilities: ServerCapabilities(
    tools: true,
    resources: true,
    prompts: true,
  ),
);

// Create a client
final clientId = await FlutterMCP.instance.createClient(
  name: 'MCP Client',
  version: '1.0.0',
  transportCommand: 'server',
  transportArgs: ['--port', '8080'],
);

// Create an LLM
final llmId = await FlutterMCP.instance.createLlm(
  providerName: 'openai',
  config: LlmConfiguration(
    apiKey: 'your-api-key',
    model: 'gpt-4',
  ),
);

// Connect components
await FlutterMCP.instance.integrateServerWithLlm(
  serverId: serverId,
  llmId: llmId,
);

await FlutterMCP.instance.integrateClientWithLlm(
  clientId: clientId,
  llmId: llmId,
);

// Start components
FlutterMCP.instance.connectServer(serverId);
await FlutterMCP.instance.connectClient(clientId);

// Use components
final response = await FlutterMCP.instance.chat(
  llmId,
  'Hello, how are you today?',
);
print('AI: ${response.text}');

// Clean up when done
await FlutterMCP.instance.shutdown();
```

## Platform Support

| Platform | Background Service | Notifications | System Tray |
|----------|-------------------|---------------|------------|
| Android  | ✅                | ✅             | ❌          |
| iOS      | ⚠️ (Limited)      | ✅             | ❌          |
| macOS    | ✅                | ✅             | ✅          |
| Windows  | ✅                | ✅             | ✅          |
| Linux    | ✅                | ✅             | ✅          |

## Configuration Options

### Background Service Configuration

```dart
BackgroundConfig(
  notificationChannelId: 'my_channel',
  notificationChannelName: 'My Channel',
  notificationDescription: 'Background service notification',
  notificationIcon: 'app_icon',
  autoStartOnBoot: true,
  intervalMs: 5000,
  keepAlive: true,
)
```

### Notification Configuration

```dart
NotificationConfig(
  channelId: 'notifications_channel',
  channelName: 'Notifications',
  channelDescription: 'App notifications',
  icon: 'notification_icon',
  enableSound: true,
  enableVibration: true,
  priority: NotificationPriority.high,
)
```

### System Tray Configuration

```dart
TrayConfig(
  iconPath: 'assets/tray_icon.png',
  tooltip: 'My MCP App',
  menuItems: [
    TrayMenuItem(label: 'Show', onTap: showApp),
    TrayMenuItem.separator(),
    TrayMenuItem(label: 'Exit', onTap: exitApp),
  ],
)
```

## Advanced Usage

### Secure Storage

```dart
// Store values securely
await FlutterMCP.instance.secureStore('api_key', 'your-secret-api-key');

// Retrieve values
final apiKey = await FlutterMCP.instance.secureRead('api_key');
```

### Task Scheduling

```dart
// Add scheduled tasks
final jobId = FlutterMCP.instance.addScheduledJob(
  MCPJob.every(
    Duration(hours: 1),
    task: () {
      // Perform regular task
    },
  ),
);

// Remove scheduled tasks
FlutterMCP.instance.removeScheduledJob(jobId);
```

### System Status

```dart
// Get system status
final status = FlutterMCP.instance.getSystemStatus();
print('Clients: ${status['clients']}');
print('Servers: ${status['servers']}');
print('LLMs: ${status['llms']}');
```

## Examples

Check out the [example](https://github.com/app-appplayer/flutter_mcp/tree/main/example) directory for a complete sample application.

## Issues and Feedback

Please file any issues, bugs, or feature requests in our [issue tracker](https://github.com/app-appplayer/flutter_mcp/issues).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
```


