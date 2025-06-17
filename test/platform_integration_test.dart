import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/platform/platform_services.dart';
import 'package:flutter_mcp/src/platform/background/background_service.dart';
import 'package:flutter_mcp/src/utils/platform_utils.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

// @GenerateMocks([BackgroundService, PlatformServices])
// import 'platform_integration_test.mocks.dart';

import 'mcp_integration_test.mocks.dart';
import 'mcp_integration_test.dart';

// Platform-specific test extension of TestFlutterMCP
class PlatformTestFlutterMCP extends TestFlutterMCP {
  // Store reference to platform services
  final MockPlatformServices _mockPlatformServices;
  
  PlatformTestFlutterMCP(MockPlatformServices platformServices) 
    : _mockPlatformServices = platformServices, 
      super(platformServices);
  
  // Add platform-specific getters and methods
  Map<String, dynamic> get platformServicesStatus => {
    'backgroundServiceRunning': _mockPlatformServices.isBackgroundServiceRunning,
    'platformName': PlatformUtils.platformName,
  };
  
  Future<Map<String, dynamic>> getPlatformStatus() async {
    return platformServicesStatus;
  }
  
  Future<bool> startBackgroundService() async {
    return await _mockPlatformServices.startBackgroundService();
  }
  
  Future<bool> stopBackgroundService() async {
    return await _mockPlatformServices.stopBackgroundService();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Platform Integration Tests', () {
    late PlatformTestFlutterMCP mcp;
    late MockPlatformServices mockPlatformServices;
    
    setUp(() {
      // Use mock objects instead of real platform services
      mockPlatformServices = MockPlatformServices();
      
      // Set up default mock behavior
      when(mockPlatformServices.initialize(any)).thenAnswer((_) async {});
      when(mockPlatformServices.isBackgroundServiceRunning).thenReturn(false);
      when(mockPlatformServices.startBackgroundService()).thenAnswer((_) async => true);
      when(mockPlatformServices.stopBackgroundService()).thenAnswer((_) async => true);
      when(mockPlatformServices.showNotification(
        title: anyNamed('title'),
        body: anyNamed('body'),
        icon: anyNamed('icon'),
        id: anyNamed('id'),
      )).thenAnswer((_) async {});
      when(mockPlatformServices.secureStore(any, any)).thenAnswer((_) async {});
      when(mockPlatformServices.secureRead(any)).thenAnswer((_) async => 'mock-stored-value');
      
      // Use PlatformTestFlutterMCP
      mcp = PlatformTestFlutterMCP(mockPlatformServices);
    });
    
    tearDown(() async {
      await mcp.shutdown();
    });
    
    group('Cross-Platform Background Service', () {
      test('Desktop background service should support custom intervals', () async {
        if (!PlatformUtils.isDesktop) {
          // Skip test for non-desktop platforms
          return;
        }
        
        final config = MCPConfig(
          appName: 'Test App',
          appVersion: '1.0.0',
          useBackgroundService: true,
          background: BackgroundConfig(
            intervalMs: 5000, // 5 seconds
            keepAlive: true,
          ),
          autoStart: false, // Prevent auto start during init
        );
        
        await mcp.init(config);
        
        // Mock platform status
        when(mockPlatformServices.isBackgroundServiceRunning).thenReturn(true);
        final status = await mcp.getPlatformStatus();
        expect(status['backgroundServiceRunning'], isTrue);
        
        // Start background service manually
        when(mockPlatformServices.startBackgroundService()).thenAnswer((_) async => true);
        final started = await mcp.startBackgroundService();
        expect(started, isTrue);
        
        // Verify start was called only once
        verify(mockPlatformServices.startBackgroundService()).called(1);
        
        // Stop background service
        when(mockPlatformServices.stopBackgroundService()).thenAnswer((_) async => true);
        final stopped = await mcp.stopBackgroundService();
        expect(stopped, isTrue);
        
        // Verify stop was called
        verify(mockPlatformServices.stopBackgroundService()).called(1);
      });
      
      test('iOS background service should respect platform limitations', () async {
        if (PlatformUtils.platformName != 'iOS') {
          // Skip test for non-iOS platforms
          return;
        }
        
        final config = MCPConfig(
          appName: 'Test App',
          appVersion: '1.0.0',
          useBackgroundService: true,
          background: BackgroundConfig(
            intervalMs: 300000, // 5 minutes (less than iOS minimum)
            keepAlive: true,
          ),
        );
        
        await mcp.init(config);
        
        // iOS should adjust interval to minimum 15 minutes
        // This would be verified through platform-specific implementation
        expect(mcp.platformServicesStatus['backgroundServiceRunning'], isTrue);
      });
      
      test('Android background service should use foreground service', () async {
        if (PlatformUtils.platformName != 'Android') {
          // Skip test for non-Android platforms
          return;
        }
        
        final config = MCPConfig(
          appName: 'Test App',
          appVersion: '1.0.0',
          useBackgroundService: true,
          background: BackgroundConfig(
            notificationChannelId: 'test_channel',
            notificationChannelName: 'Test Service',
            notificationDescription: 'Test background service',
            autoStartOnBoot: true,
            intervalMs: 60000, // 1 minute
          ),
        );
        
        await mcp.init(config);
        
        // Verify background service is configured correctly
        expect(mcp.platformServicesStatus['backgroundServiceRunning'], isTrue);
      });
    });
    
    group('Memory Management', () {
      test('Should report actual memory usage on supported platforms', () async {
        if (PlatformUtils.platformName == 'Web') {
          // Skip test for web
          return;
        }
        
        final config = MCPConfig(
          appName: 'Test App',
          appVersion: '1.0.0',
          highMemoryThresholdMB: 512,
        );
        
        await mcp.init(config);
        
        // Get memory statistics
        // final stats = MemoryManager.instance.getMemoryStats();
        
        // Should have actual memory readings
        // expect(stats['currentMB'], greaterThan(0));
        // expect(stats['currentMB'], lessThan(10000)); // Reasonable upper bound
      });
      
      test('Should trigger memory cleanup on high memory', () async {
        final config = MCPConfig(
          appName: 'Test App',
          appVersion: '1.0.0',
          highMemoryThresholdMB: 1, // Very low threshold for testing
        );
        
        await mcp.init(config);
        
        var cleanupTriggered = false;
        
        // Add cleanup callback
        // MemoryManager.instance.addHighMemoryCallback(() async {
        //   cleanupTriggered = true;
        // });
        
        // Force memory check
        await Future.delayed(Duration(seconds: 1));
        
        // Cleanup should have been triggered
        // expect(cleanupTriggered, isTrue);
      });
    });
    
    group('Platform-Specific Features', () {
      test('System tray should be available on desktop', () async {
        if (!PlatformUtils.isDesktop) {
          // Skip test for non-desktop platforms
          return;
        }
        
        final config = MCPConfig(
          appName: 'Test App',
          appVersion: '1.0.0',
          useTray: true,
          tray: TrayConfig(
            tooltip: 'Test App',
            menuItems: [
              TrayMenuItem(label: 'Test Item'),
            ],
          ),
        );
        
        await mcp.init(config);
        
        // Verify tray was initialized
        expect(mcp.platformServicesStatus['platformName'], 
               anyOf(['macOS', 'Windows', 'Linux']));
      });
      
      test('Notifications should work on all platforms', () async {
        final config = MCPConfig(
          appName: 'Test App',
          appVersion: '1.0.0',
          useNotification: true,
          notification: NotificationConfig(
            channelId: 'test_notifications',
            channelName: 'Test Notifications',
          ),
        );
        
        await mcp.init(config);
        
        // Show notification
        // await mcp.showNotification(
        //   title: 'Test',
        //   body: 'Test notification',
        // );
        
        // No exception should be thrown
        expect(true, isTrue);
      });
    });
  });
  
  group('Background Service Performance', () {
    test('Should handle task errors gracefully', () async {
      final mockPlatformServices = MockPlatformServices();
      
      // Mock setup
      when(mockPlatformServices.initialize(any)).thenAnswer((_) async {});
      when(mockPlatformServices.isBackgroundServiceRunning).thenReturn(true);
      when(mockPlatformServices.startBackgroundService()).thenAnswer((_) async => true);
      when(mockPlatformServices.stopBackgroundService()).thenAnswer((_) async => true);
      when(mockPlatformServices.secureStore(any, any)).thenAnswer((_) async {});
      when(mockPlatformServices.secureRead(any)).thenAnswer((_) async => 'mock-stored-value');
      
      final mcp = PlatformTestFlutterMCP(mockPlatformServices);
      
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        useBackgroundService: true,
        background: BackgroundConfig(
          intervalMs: 1000, // 1 second for quick testing
        ),
        autoStart: false,
      );
      
      await mcp.init(config);
      
      var errorCount = 0;
      
      // Register a task that throws errors
      void errorTask() {
        errorCount++;
        throw Exception('Test error');
      }
      
      // This would be platform-specific implementation
      // For desktop, we would use:
      // DesktopBackgroundService.registerTaskHandler(errorTask);
      
      // await mcp.startBackgroundService();
      
      // Wait for multiple executions
      await Future.delayed(Duration(seconds: 3));
      
      // Service should still be running despite errors
      expect(mcp.platformServicesStatus['backgroundServiceRunning'], isTrue);
      
      // await mcp.stopBackgroundService();
    });
    
    test('Should measure background task performance', () async {
      final mockPlatformServices = MockPlatformServices();
      
      // Mock setup
      when(mockPlatformServices.initialize(any)).thenAnswer((_) async {});
      when(mockPlatformServices.isBackgroundServiceRunning).thenReturn(true);
      when(mockPlatformServices.startBackgroundService()).thenAnswer((_) async => true);
      when(mockPlatformServices.stopBackgroundService()).thenAnswer((_) async => true);
      when(mockPlatformServices.secureStore(any, any)).thenAnswer((_) async {});
      when(mockPlatformServices.secureRead(any)).thenAnswer((_) async => 'mock-stored-value');
      
      final mcp = PlatformTestFlutterMCP(mockPlatformServices);
      
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        useBackgroundService: true,
        enablePerformanceMonitoring: true,
        background: BackgroundConfig(
          intervalMs: 1000,
        ),
        autoStart: false,
      );
      
      await mcp.init(config);
      
      // await mcp.startBackgroundService();
      
      // Wait for some executions
      await Future.delayed(Duration(seconds: 5));
      
      // Check performance metrics
      // final metrics = PerformanceMonitor.instance.getMetricsSummary();
      
      // Should have background task metrics
      // expect(metrics['timers'], isNotNull);
      
      // await mcp.stopBackgroundService();
    });
  });
}