import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/platform/tray/macos_tray.dart'
    hide TrayEventListener;
import 'package:flutter_mcp/src/platform/tray/windows_tray.dart';
import 'package:flutter_mcp/src/platform/tray/linux_tray.dart'
    hide TrayEventListener;
import 'dart:async';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Platform System Tray Tests', () {
    late MethodChannel methodChannel;
    final List<MethodCall> methodCalls = [];
    late StreamController<Map<String, dynamic>> eventController;

    setUp(() {
      methodChannel = const MethodChannel('flutter_mcp');
      methodCalls.clear();
      eventController = StreamController<Map<String, dynamic>>.broadcast();

      // Set up method channel mock handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel,
              (MethodCall methodCall) async {
        methodCalls.add(methodCall);

        switch (methodCall.method) {
          case 'showTrayIcon':
            return null;
          case 'hideTrayIcon':
            return null;
          case 'updateTrayTooltip':
            return null;
          case 'setTrayMenu':
            return null;
          case 'getTrayBounds':
            return {'x': 100.0, 'y': 50.0, 'width': 24.0, 'height': 24.0};
          default:
            return null;
        }
      });

      // Mock event channel
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        const EventChannel('flutter_mcp/events'),
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            eventController.stream.listen(events.success);
          },
        ),
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(const EventChannel('flutter_mcp/events'), null);
      eventController.close();
    });

    group('macOS System Tray', () {
      test('Should initialize NSStatusItem with correct properties', () async {
        final trayManager = MacOSTrayManager();

        await trayManager.initialize(TrayConfig(
          iconPath: '/Applications/MyApp.app/Contents/Resources/tray_icon.png',
          tooltip: 'My macOS App',
          menuItems: [
            TrayMenuItem(label: 'Show Window'),
            TrayMenuItem(label: 'Preferences...'),
            TrayMenuItem.separator(),
            TrayMenuItem(label: 'About'),
            TrayMenuItem.separator(),
            TrayMenuItem(label: 'Quit', onTap: () {}),
          ],
        ));

        // Verify icon was set
        expect(
            methodCalls.any((call) =>
                call.method == 'showTrayIcon' &&
                call.arguments['iconPath'] ==
                    '/Applications/MyApp.app/Contents/Resources/tray_icon.png'),
            isTrue);

        // Verify tooltip
        expect(
            methodCalls.any((call) =>
                call.method == 'updateTrayTooltip' &&
                call.arguments['tooltip'] == 'My macOS App'),
            isTrue);

        // Verify menu structure
        final menuCall = methodCalls.firstWhere(
          (call) => call.method == 'setTrayMenu',
        );
        final items = menuCall.arguments['items'] as List;
        expect(items.length, equals(6));
        expect(items[2]['isSeparator'], isTrue);
        expect(items[4]['isSeparator'], isTrue);
      });

      test('Should handle menu item clicks', () async {
        final trayManager = MacOSTrayManager();
        var showWindowCalled = false;
        var preferencesCalled = false;

        await trayManager.initialize(TrayConfig(
          iconPath: '/path/to/icon.png',
          menuItems: [
            TrayMenuItem(
              label: 'Show Window',
              onTap: () => showWindowCalled = true,
            ),
            TrayMenuItem(
              label: 'Preferences',
              onTap: () => preferencesCalled = true,
            ),
          ],
        ));

        // Simulate menu item click event
        eventController.add({
          'type': 'trayEvent',
          'data': {
            'action': 'menuItemClicked',
            'itemId': 'item_0', // First menu item
          },
        });

        await Future.delayed(Duration(milliseconds: 100));
        expect(showWindowCalled, isTrue);

        // Click second item
        eventController.add({
          'type': 'trayEvent',
          'data': {
            'action': 'menuItemClicked',
            'itemId': 'item_1', // Second menu item
          },
        });

        await Future.delayed(Duration(milliseconds: 100));
        expect(preferencesCalled, isTrue);
      });

      test('Should support dynamic menu updates', () async {
        final trayManager = MacOSTrayManager();

        await trayManager.initialize(TrayConfig(
          iconPath: '/path/to/icon.png',
          menuItems: [
            TrayMenuItem(label: 'Item 1'),
          ],
        ));

        methodCalls.clear();

        // Update menu
        await trayManager.setContextMenu([
          TrayMenuItem(label: 'Updated Item 1'),
          TrayMenuItem(label: 'New Item 2'),
        ]);

        final menuCall = methodCalls.firstWhere(
          (call) => call.method == 'setTrayMenu',
        );
        final items = menuCall.arguments['items'] as List;
        expect(items.length, equals(2));
        expect(items[0]['label'], equals('Updated Item 1'));
        expect(items[1]['label'], equals('New Item 2'));
      });
    });

    group('Windows System Tray', () {
      test('Should create Windows tray icon with balloon support', () async {
        final trayManager = WindowsTrayManager();

        await trayManager.initialize(TrayConfig(
          iconPath: 'assets/icons/tray_icon.ico',
          tooltip: 'My Windows App - Click for menu',
          menuItems: [
            TrayMenuItem(label: 'Open'),
            TrayMenuItem(label: 'Minimize to Tray'),
            TrayMenuItem.separator(),
            TrayMenuItem(label: 'Exit'),
          ],
        ));

        // Windows uses ICO format
        expect(
            methodCalls.any((call) =>
                call.method == 'showTrayIcon' &&
                call.arguments['iconPath'] == 'assets/icons/tray_icon.ico'),
            isTrue);

        // Longer tooltips are common on Windows
        expect(
            methodCalls.any((call) =>
                call.method == 'updateTrayTooltip' &&
                call.arguments['tooltip']
                    .toString()
                    .contains('Click for menu')),
            isTrue);
      });

      test('Should handle left and right click events', () async {
        final trayManager = WindowsTrayManager();
        var leftClickCount = 0;
        var rightClickCount = 0;

        final listener = TrayEventListener(
          onTrayMouseDown: () => leftClickCount++,
          onTrayRightMouseDown: () => rightClickCount++,
        );

        await trayManager.initialize(TrayConfig(
          iconPath: 'icon.ico',
        ));

        trayManager.addEventListener(listener);

        // Simulate left click
        eventController.add({
          'type': 'trayEvent',
          'data': {
            'action': 'trayIconClicked',
          },
        });

        await Future.delayed(Duration(milliseconds: 50));
        expect(leftClickCount, equals(1));

        // Simulate right click
        eventController.add({
          'type': 'trayEvent',
          'data': {
            'action': 'trayIconRightClicked',
          },
        });

        await Future.delayed(Duration(milliseconds: 50));
        expect(rightClickCount, equals(1));

        // Remove listener
        trayManager.removeEventListener(listener);

        // Click again - should not increment
        eventController.add({
          'type': 'trayEvent',
          'data': {
            'action': 'trayIconClicked',
          },
        });

        await Future.delayed(Duration(milliseconds: 50));
        expect(leftClickCount, equals(1)); // Still 1
      });

      test('Should support show/hide operations', () async {
        final trayManager = WindowsTrayManager();

        await trayManager.initialize(TrayConfig(
          iconPath: 'icon.ico',
        ));

        methodCalls.clear();

        // Hide
        await trayManager.hide();
        expect(
            methodCalls.any((call) => call.method == 'hideTrayIcon'), isTrue);

        methodCalls.clear();

        // Show
        await trayManager.show();
        expect(
            methodCalls.any((call) => call.method == 'showTrayIcon'), isTrue);
      });
    });

    group('Linux System Tray', () {
      test('Should use AppIndicator on Linux', () async {
        final trayManager = LinuxTrayManager();

        await trayManager.initialize(TrayConfig(
          iconPath: '/usr/share/icons/hicolor/48x48/apps/myapp.png',
          tooltip: 'My Linux App',
          menuItems: [
            TrayMenuItem(label: 'Show'),
            TrayMenuItem(label: 'Settings'),
            TrayMenuItem.separator(),
            TrayMenuItem(label: 'Quit'),
          ],
        ));

        // Linux typically uses full paths for icons
        expect(
            methodCalls.any((call) =>
                call.method == 'showTrayIcon' &&
                call.arguments['iconPath']
                    .toString()
                    .contains('/usr/share/icons')),
            isTrue);
      });

      test('Should handle Unity/GNOME specific features', () async {
        final trayManager = LinuxTrayManager();

        await trayManager.initialize(TrayConfig(
          iconPath: 'myapp-tray', // Icon name from theme
          tooltip: 'Application Status',
          menuItems: [
            TrayMenuItem(label: 'Status: Connected'),
            TrayMenuItem(label: 'Toggle', disabled: false),
          ],
        ));

        // Verify menu items
        final menuCall = methodCalls.firstWhere(
          (call) => call.method == 'setTrayMenu',
        );
        final items = menuCall.arguments['items'] as List;

        expect(items[0]['label'], equals('Status: Connected'));
        expect(items[1]['disabled'], isFalse);
      });
    });

    group('Cross-Platform Tray Features', () {
      test('Should dispose properly on all platforms', () async {
        final managers = [
          MacOSTrayManager(),
          WindowsTrayManager(),
          LinuxTrayManager(),
        ];

        for (final manager in managers) {
          methodCalls.clear();

          await manager.initialize(TrayConfig(
            iconPath: 'test_icon',
          ));

          await manager.dispose();

          // Should hide icon and clean up
          expect(
              methodCalls.any((call) => call.method == 'hideTrayIcon'), isTrue);
        }
      });

      test('Should handle disabled menu items', () async {
        final trayManager = MacOSTrayManager();

        await trayManager.initialize(TrayConfig(
          iconPath: 'icon',
          menuItems: [
            TrayMenuItem(label: 'Enabled Item'),
            TrayMenuItem(label: 'Disabled Item', disabled: true),
          ],
        ));

        final menuCall = methodCalls.firstWhere(
          (call) => call.method == 'setTrayMenu',
        );
        final items = menuCall.arguments['items'] as List;

        expect(items[0]['disabled'], isFalse);
        expect(items[1]['disabled'], isTrue);
      });

      test('Should update menu item properties', () async {
        final trayManager = WindowsTrayManager();

        await trayManager.initialize(TrayConfig(
          iconPath: 'icon',
          menuItems: [
            TrayMenuItem(label: 'Dynamic Item', disabled: false),
          ],
        ));

        methodCalls.clear();

        // Update menu item
        await trayManager.updateMenuItem(
          'item_0',
          label: 'Updated Label',
          disabled: true,
        );

        // Should rebuild menu with updated item
        final menuCall = methodCalls.firstWhere(
          (call) => call.method == 'setTrayMenu',
        );
        final items = menuCall.arguments['items'] as List;

        expect(items[0]['label'], equals('Updated Label'));
        expect(items[0]['disabled'], isTrue);
      });
    });

    group('Tray Error Handling', () {
      test('Should handle missing icon gracefully', () async {
        final trayManager = MacOSTrayManager();

        // Should not throw even with invalid path
        await expectLater(
          trayManager.initialize(TrayConfig(
            iconPath: '/non/existent/path.png',
          )),
          completes,
        );
      });

      test('Should handle platform exceptions', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel,
                (MethodCall methodCall) async {
          if (methodCall.method == 'showTrayIcon') {
            throw PlatformException(
              code: 'TRAY_ERROR',
              message: 'Failed to create tray icon',
            );
          }
          return null;
        });

        final trayManager = WindowsTrayManager();

        expect(
          () => trayManager.initialize(TrayConfig(iconPath: 'icon.ico')),
          throwsA(isA<MCPException>()),
        );
      });
    });
  });
}
