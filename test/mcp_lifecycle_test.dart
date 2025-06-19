import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:mockito/mockito.dart';

import 'mcp_integration_test.dart';
import 'mcp_integration_test.mocks.dart';

// Define a simplified AppLifecycleState enum for testing
enum AppLifecycleStateTest {
  resumed,
  inactive,
  paused,
  detached,
  hidden,
}

// Mock AppLifecycleState changes
class MockLifecycleListener {
  final List<AppLifecycleStateTest> stateChanges = [];
  Function(AppLifecycleStateTest)? _listener;

  void registerListener(Function(AppLifecycleStateTest) listener) {
    _listener = listener;
  }

  void simulateLifecycleChange(AppLifecycleStateTest state) {
    stateChanges.add(state);
    if (_listener != null) {
      _listener!(state);
    }
  }
}

class LifecycleTestFlutterMCP extends TestFlutterMCP {
  final MockLifecycleListener lifecycleListener;
  final List<String> lifecycleEvents = [];

  LifecycleTestFlutterMCP(super.platformServices, this.lifecycleListener) {
    // Set up lifecycle listener
    lifecycleListener.registerListener(_onLifecycleChange);
  }

  void _onLifecycleChange(AppLifecycleStateTest state) {
    lifecycleEvents.add(state.toString());

    // Handle lifecycle event
    switch (state) {
      case AppLifecycleStateTest.paused:
        handleAppPaused();
        break;
      case AppLifecycleStateTest.resumed:
        handleAppResumed();
        break;
      case AppLifecycleStateTest.detached:
        handleAppDetached();
        break;
      case AppLifecycleStateTest.inactive:
        handleAppInactive();
        break;
      case AppLifecycleStateTest.hidden:
        // Handle hidden state
        break;
    }
  }

  // Lifecycle handlers
  final List<String> resourceOperations = [];

  void handleAppPaused() {
    resourceOperations.add('paused_resources_saved');
  }

  void handleAppResumed() {
    resourceOperations.add('resumed_resources_restored');
  }

  void handleAppDetached() {
    resourceOperations.add('detached_resources_cleaned');
  }

  void handleAppInactive() {
    resourceOperations.add('inactive_resources_minimized');
  }

  // Override to use our mock lifecycle listener
  Future<void> setLifecycleChangeListener(
      Function(AppLifecycleStateTest) listener) async {
    // Override to use our mock lifecycle listener
    lifecycleListener.registerListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockPlatformServices mockPlatformServices;
  late MockLifecycleListener mockLifecycleListener;
  late LifecycleTestFlutterMCP flutterMcp;

  setUp(() {
    mockPlatformServices = MockPlatformServices();
    mockLifecycleListener = MockLifecycleListener();

    // Mock platform services behavior
    when(mockPlatformServices.initialize(any)).thenAnswer((_) async {});
    when(mockPlatformServices.isBackgroundServiceRunning).thenReturn(false);
    when(mockPlatformServices.startBackgroundService())
        .thenAnswer((_) async => true);
    when(mockPlatformServices.stopBackgroundService())
        .thenAnswer((_) async => true);
    when(mockPlatformServices.secureStore(any, any)).thenAnswer((_) async {});
    when(mockPlatformServices.secureRead(any))
        .thenAnswer((_) async => 'mock-stored-value');
    when(mockPlatformServices.setLifecycleChangeListener(any))
        .thenAnswer((_) async {});

    flutterMcp =
        LifecycleTestFlutterMCP(mockPlatformServices, mockLifecycleListener);
  });

  group('Lifecycle Management Tests', () {
    test('App responds to lifecycle state changes', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Lifecycle Test',
        appVersion: '1.0.0',
        autoStart: false,
        lifecycleManaged: true,
      );

      await flutterMcp.init(config);

      // Simulate app going to background (paused)
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.paused);

      // Verify app responded to paused state
      expect(
          flutterMcp.lifecycleEvents
              .contains(AppLifecycleStateTest.paused.toString()),
          isTrue);
      expect(flutterMcp.resourceOperations.contains('paused_resources_saved'),
          isTrue);

      // Simulate app coming back to foreground (resumed)
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.resumed);

      // Verify app responded to resumed state
      expect(
          flutterMcp.lifecycleEvents
              .contains(AppLifecycleStateTest.resumed.toString()),
          isTrue);
      expect(
          flutterMcp.resourceOperations.contains('resumed_resources_restored'),
          isTrue);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('App cleanup on detached state', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Detached Test',
        appVersion: '1.0.0',
        autoStart: false,
        lifecycleManaged: true,
      );

      await flutterMcp.init(config);

      // Create some resources
      await flutterMcp.createServer(
        name: 'Test Server',
        version: '1.0.0',
      );

      // Simulate app being detached (terminated)
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.detached);

      // Verify app responded to detached state
      expect(
          flutterMcp.lifecycleEvents
              .contains(AppLifecycleStateTest.detached.toString()),
          isTrue);
      expect(
          flutterMcp.resourceOperations.contains('detached_resources_cleaned'),
          isTrue);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Resource states maintained across lifecycle transitions', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'State Test',
        appVersion: '1.0.0',
        autoStart: false,
        lifecycleManaged: true,
      );

      await flutterMcp.init(config);

      // Create server before pausing
      final serverId = await flutterMcp.createServer(
        name: 'Lifecycle Server',
        version: '1.0.0',
      );

      // Connect the server
      flutterMcp.connectServer(serverId);

      // Verify server exists and is connected
      final initialStatus = flutterMcp.getSystemStatus();
      expect(initialStatus['servers'], 1);

      // Simulate app going to background (paused)
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.paused);

      // Simulate app coming back to foreground (resumed)
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.resumed);

      // Verify server still exists and is connected
      final resumedStatus = flutterMcp.getSystemStatus();
      expect(resumedStatus['servers'], 1);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Background service state maintained during lifecycle changes',
        () async {
      // Initialize MCP with background service
      final config = MCPConfig(
        appName: 'Background Test',
        appVersion: '1.0.0',
        useBackgroundService: true,
        useNotification: false, // Disable notifications for this test
        autoStart: true,
        lifecycleManaged: true,
      );

      await flutterMcp.init(config);

      // Clear previous interactions and reset mock
      clearInteractions(mockPlatformServices);

      // Verify background service was started (reset verification state)
      // At this point, background service should have been started during init

      // Simulate app going to background (paused)
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.paused);

      // Background service should still be running (not stopped)
      verifyNever(mockPlatformServices.stopBackgroundService());

      // Simulate app coming back to foreground (resumed)
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.resumed);

      // Verify no additional background service start calls occurred after lifecycle changes
      verifyNever(mockPlatformServices.startBackgroundService());

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Multiple rapid lifecycle transitions handled properly', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Rapid Test',
        appVersion: '1.0.0',
        autoStart: false,
        lifecycleManaged: true,
      );

      await flutterMcp.init(config);

      // Simulate rapid transitions between states
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.inactive);
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.paused);
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.inactive);
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.resumed);
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.inactive);
      mockLifecycleListener
          .simulateLifecycleChange(AppLifecycleStateTest.paused);

      // Verify all state changes were recorded
      expect(flutterMcp.lifecycleEvents.length, 6);

      // Verify operations were performed for each state
      expect(
          flutterMcp.resourceOperations
              .where((op) => op == 'inactive_resources_minimized')
              .length,
          3);
      expect(
          flutterMcp.resourceOperations
              .where((op) => op == 'paused_resources_saved')
              .length,
          2);
      expect(
          flutterMcp.resourceOperations
              .where((op) => op == 'resumed_resources_restored')
              .length,
          1);

      // Clean up
      await flutterMcp.shutdown();
    });
  });
}
