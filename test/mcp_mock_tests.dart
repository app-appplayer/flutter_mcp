import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/platform/background/background_service.dart';
import 'package:flutter_mcp/src/platform/notification/notification_manager.dart';
import 'package:flutter_mcp/src/platform/tray/tray_manager.dart';
import 'package:flutter_mcp/src/platform/platform_services.dart';
import 'package:flutter_mcp/src/platform/storage/secure_storage.dart';

import 'mcp_mock_tests.mocks.dart';

// Generate mocks for platform-specific implementations
@GenerateMocks([
  BackgroundService,
  NotificationManager,
  TrayManager,
  SecureStorageManager,
])
void main() {
  late MockBackgroundService mockBackgroundService;
  late MockNotificationManager mockNotificationManager;
  late MockTrayManager mockTrayManager;
  late MockSecureStorageManager mockSecureStorage;
  late TestPlatformServices platformServices;

  setUp(() {
    // Set up logging for tests
    MCPLogger.setDefaultLevel(LogLevel.debug);

    // Initialize mocks
    mockBackgroundService = MockBackgroundService();
    mockNotificationManager = MockNotificationManager();
    mockTrayManager = MockTrayManager();
    mockSecureStorage = MockSecureStorageManager();

    // Configure mock behaviors
    when(mockBackgroundService.initialize(any)).thenAnswer((_) async {});
    when(mockBackgroundService.isRunning).thenReturn(false);
    when(mockBackgroundService.start()).thenAnswer((_) async => true);
    when(mockBackgroundService.stop()).thenAnswer((_) async => true);

    when(mockNotificationManager.initialize(any)).thenAnswer((_) async {});
    when(mockNotificationManager.showNotification(
      title: anyNamed('title'),
      body: anyNamed('body'),
      icon: anyNamed('icon'),
      id: anyNamed('id'),
    )).thenAnswer((_) async {});
    when(mockNotificationManager.hideNotification(any)).thenAnswer((_) async {});

    when(mockTrayManager.initialize(any)).thenAnswer((_) async {});
    when(mockTrayManager.setIcon(any)).thenAnswer((_) async {});
    when(mockTrayManager.setTooltip(any)).thenAnswer((_) async {});
    when(mockTrayManager.setContextMenu(any)).thenAnswer((_) async {});
    when(mockTrayManager.dispose()).thenAnswer((_) async {});

    when(mockSecureStorage.initialize()).thenAnswer((_) async {});
    when(mockSecureStorage.saveString(any, any)).thenAnswer((_) async {});
    when(mockSecureStorage.readString(any)).thenAnswer((_) async => 'mock-value');
    when(mockSecureStorage.delete(any)).thenAnswer((_) async => true);
    when(mockSecureStorage.containsKey(any)).thenAnswer((_) async => true);

    // Create test platform services with mocks
    platformServices = TestPlatformServices(
      mockBackgroundService,
      mockNotificationManager,
      mockTrayManager,
      mockSecureStorage,
    );
  });

  group('PlatformServices Tests', () {
    test('Initialize platform services', () async {
      // Create configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        useBackgroundService: true,
        useNotification: true,
        useTray: true,
      );

      // Initialize platform services
      await platformServices.initialize(config);

      // Verify initialization of each component
      verify(mockBackgroundService.initialize(config.background)).called(1);
      verify(mockNotificationManager.initialize(config.notification)).called(1);
      verify(mockTrayManager.initialize(config.tray)).called(1);
      verify(mockSecureStorage.initialize()).called(1);
    });

    test('Start background service', () async {
      // Create configuration and initialize
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      await platformServices.initialize(config);

      // Start background service
      final result = await platformServices.startBackgroundService();

      // Verify service was started
      expect(result, true);
      verify(mockBackgroundService.start()).called(1);
    });

    test('Stop background service', () async {
      // Create configuration and initialize
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      await platformServices.initialize(config);

      // Stop background service
      final result = await platformServices.stopBackgroundService();

      // Verify service was stopped
      expect(result, true);
      verify(mockBackgroundService.stop()).called(1);
    });

    test('Show notification', () async {
      // Create configuration and initialize
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      await platformServices.initialize(config);

      // Show a notification
      await platformServices.showNotification(
        title: 'Test Title',
        body: 'Test Body',
        icon: 'test_icon',
        id: 'test_notification',
      );

      // Verify notification was shown
      verify(mockNotificationManager.showNotification(
        title: 'Test Title',
        body: 'Test Body',
        icon: 'test_icon',
        id: 'test_notification',
      )).called(1);
    });

    test('Hide notification', () async {
      // Create configuration and initialize
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      await platformServices.initialize(config);

      // Hide a notification
      await platformServices.hideNotification('test_notification');

      // Verify notification was hidden
      verify(mockNotificationManager.hideNotification('test_notification')).called(1);
    });

    test('Set tray menu', () async {
      // Create configuration and initialize
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      await platformServices.initialize(config);

      // Create menu items
      final menuItems = [
        TrayMenuItem(label: 'Item 1'),
        TrayMenuItem.separator(),
        TrayMenuItem(label: 'Item 2'),
      ];

      // Set tray menu
      await platformServices.setTrayMenu(menuItems);

      // Verify tray menu was set
      verify(mockTrayManager.setContextMenu(menuItems)).called(1);
    });

    test('Set tray icon', () async {
      // Create configuration and initialize
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      await platformServices.initialize(config);

      // Set tray icon
      await platformServices.setTrayIcon('test_icon.png');

      // Verify icon was set
      verify(mockTrayManager.setIcon('test_icon.png')).called(1);
    });

    test('Set tray tooltip', () async {
      // Create configuration and initialize
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      await platformServices.initialize(config);

      // Set tray tooltip
      await platformServices.setTrayTooltip('Test Tooltip');

      // Verify tooltip was set
      verify(mockTrayManager.setTooltip('Test Tooltip')).called(1);
    });

    test('Secure storage operations', () async {
      // Create configuration and initialize
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      await platformServices.initialize(config);

      // Test secure storage operations
      await platformServices.secureStore('test_key', 'test_value');
      final value = await platformServices.secureRead('test_key');
      final exists = await platformServices.secureContains('test_key');
      await platformServices.secureDelete('test_key');

      // Verify operations
      verify(mockSecureStorage.saveString('test_key', 'test_value')).called(1);
      verify(mockSecureStorage.readString('test_key')).called(1);
      verify(mockSecureStorage.containsKey('test_key')).called(1);
      verify(mockSecureStorage.delete('test_key')).called(1);

      expect(value, 'mock-value');
      expect(exists, true);
    });

    test('Shutdown platform services', () async {
      // Create configuration and initialize
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      await platformServices.initialize(config);

      // Start background service to verify it stops on shutdown
      when(mockBackgroundService.isRunning).thenReturn(true);

      // Shutdown
      await platformServices.shutdown();

      // Verify background service was stopped
      verify(mockBackgroundService.stop()).called(1);

      // Verify tray manager was disposed
      verify(mockTrayManager.dispose()).called(1);
    });

    test('Not initialized throws exception', () async {
      // Do not initialize

      // Calling methods should throw exception
      expect(
            () => platformServices.startBackgroundService(),
        throwsA(isInstanceOf<MCPException>()),
      );

      expect(
            () => platformServices.showNotification(
          title: 'Test',
          body: 'Test',
        ),
        throwsA(isInstanceOf<MCPException>()),
      );

      expect(
            () => platformServices.secureStore('key', 'value'),
        throwsA(isInstanceOf<MCPException>()),
      );
    });
  });
}

/// Test implementation of PlatformServices for testing
class TestPlatformServices extends PlatformServices {
  final BackgroundService _backgroundService;
  final NotificationManager _notificationManager;
  final TrayManager _trayManager;
  final SecureStorageManager _secureStorage;
  bool _initialized = false;

  TestPlatformServices(
      this._backgroundService,
      this._notificationManager,
      this._trayManager,
      this._secureStorage,
      );

  @override
  Future<void> initialize(MCPConfig config) async {
    if (_initialized) {
      return;
    }

    // Initialize each service
    if (config.useBackgroundService) {
      await _backgroundService.initialize(config.background);
    }

    if (config.useNotification) {
      await _notificationManager.initialize(config.notification);
    }

    if (config.useTray) {
      await _trayManager.initialize(config.tray);
    }

    // Always initialize secure storage
    await _secureStorage.initialize();

    _initialized = true;
  }

  @override
  bool get isBackgroundServiceRunning {
    return _backgroundService.isRunning;
  }

  @override
  Future<bool> startBackgroundService() async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    return await _backgroundService.start();
  }

  @override
  Future<bool> stopBackgroundService() async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    return await _backgroundService.stop();
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    await _notificationManager.showNotification(
      title: title,
      body: body,
      icon: icon,
      id: id,
    );
  }

  @override
  Future<void> hideNotification(String id) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    await _notificationManager.hideNotification(id);
  }

  @override
  Future<void> setTrayMenu(List<TrayMenuItem> items) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    await _trayManager.setContextMenu(items);
  }

  @override
  Future<void> setTrayIcon(String path) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    await _trayManager.setIcon(path);
  }

  @override
  Future<void> setTrayTooltip(String tooltip) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    await _trayManager.setTooltip(tooltip);
  }

  @override
  Future<void> secureStore(String key, String value) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    await _secureStorage.saveString(key, value);
  }

  @override
  Future<String?> secureRead(String key) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    return await _secureStorage.readString(key);
  }

  @override
  Future<bool> secureDelete(String key) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    return await _secureStorage.delete(key);
  }

  @override
  Future<bool> secureContains(String key) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    return await _secureStorage.containsKey(key);
  }

  @override
  Future<void> shutdown() async {
    if (!_initialized) {
      return;
    }

    // Stop background service if running
    if (_backgroundService.isRunning) {
      await _backgroundService.stop();
    }

    // Dispose tray manager
    await _trayManager.dispose();

    _initialized = false;
  }

  @override
  String get platformName => 'Test';
}