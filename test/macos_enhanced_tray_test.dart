// Coverage tests for MacOSEnhancedTrayManager — every platform* override,
// the shortcut parser, and the native-event dispatcher.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/platform/tray/macos_enhanced_tray.dart';
import 'package:flutter_mcp/src/platform/tray/enhanced_tray_manager.dart';
import 'package:flutter_mcp/src/config/tray_config.dart';
import 'package:flutter_mcp/src/platform/tray/tray_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isMacOS) return; // Only macOS host exercises this path.

  const channel = MethodChannel('flutter_mcp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('MacOSEnhancedTrayManager — initialize / show / hide / dispose', () {
    test('initialize routes through platformInitialize + sets icon/tooltip',
        () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(TrayConfig(
        iconPath: '/I.png',
        tooltip: 'tt',
      ));
      final methods = calls.map((c) => c.method).toList();
      expect(methods, contains('initializeTray'));
      expect(methods, contains('setTrayIcon'));
      expect(methods, contains('setTrayTooltip'));
      await m.dispose();
    });

    test('show / hide route through native methods', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.show();
      await m.hide();
      final methods = calls.map((c) => c.method).toList();
      expect(methods, contains('showTray'));
      expect(methods, contains('hideTray'));
      await m.dispose();
    });

    test('dispose cancels event subscription and calls disposeTray',
        () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.dispose();
      expect(calls.map((c) => c.method), contains('disposeTray'));
    });

    test('setIconFromBytes routes Uint8List payload', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.setIconFromBytes(Uint8List.fromList([1, 2, 3, 4]));
      final call = calls.firstWhere((c) => c.method == 'setTrayIconFromBytes');
      expect((call.arguments as Map)['bytes'], isA<Uint8List>());
      expect((call.arguments as Map)['isTemplate'], false);
      await m.dispose();
    });

    test('Template-named icon path sets isTemplate=true', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.setIcon('/path/IconTemplate.png');
      final call = calls.firstWhere((c) => c.method == 'setTrayIcon');
      expect((call.arguments as Map)['isTemplate'], true);
      await m.dispose();
    });

    test('Non-template icon path sets isTemplate=false', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.setIcon('/path/icon.png');
      final call = calls.firstWhere((c) => c.method == 'setTrayIcon');
      expect((call.arguments as Map)['isTemplate'], false);
      await m.dispose();
    });
  });

  group('MacOSEnhancedTrayManager — context menu + shortcut parser', () {
    test('separator emits {type: separator}', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.platformSetContextMenu([EnhancedTrayMenuItem.separator()]);
      final call = calls.firstWhere((c) => c.method == 'setTrayContextMenu');
      final items = (call.arguments as Map)['items'] as List;
      expect(items.first, {'type': 'separator'});
      await m.dispose();
    });

    test('plain item emits id/label/disabled/visible defaults', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.setContextMenu([TrayMenuItem(label: 'My Item')]);
      final call = calls.firstWhere((c) => c.method == 'setTrayContextMenu');
      final item = ((call.arguments as Map)['items'] as List).first as Map;
      // id derived from label when explicit id is missing.
      expect(item['id'], 'my_item');
      expect(item['label'], 'My Item');
      expect(item['disabled'], isFalse);
      expect(item['visible'], isTrue);
      await m.dispose();
    });

    test('parses Cmd+Q shortcut into modifiers + key', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      // Use the underlying enhanced tray API to set shortcut + checkbox + submenu.
      await m.platformSetContextMenu([
        EnhancedTrayMenuItem(
          id: 'quit',
          label: 'Quit',
          shortcut: 'Cmd+Q',
          iconPath: '/icon.png',
        ),
        EnhancedTrayMenuItem(
          id: 'check',
          label: 'Check',
          type: MenuItemType.checkbox,
          checked: true,
        ),
        EnhancedTrayMenuItem(
          id: 'sub',
          label: 'Sub',
          submenu: [EnhancedTrayMenuItem(id: 'inner', label: 'Inner')],
        ),
      ]);
      final call = calls.firstWhere((c) => c.method == 'setTrayContextMenu');
      final items = (call.arguments as Map)['items'] as List;
      final quit = items[0] as Map;
      final shortcut = quit['shortcut'] as Map;
      expect(shortcut['modifiers'], contains('cmd'));
      expect(shortcut['key'], 'Q');
      expect(quit['icon'], '/icon.png');

      final check = items[1] as Map;
      expect(check['type'], 'checkbox');
      expect(check['checked'], isTrue);

      final sub = items[2] as Map;
      expect(sub['submenu'], hasLength(1));
      await m.dispose();
    });

    test('parses Ctrl+Shift+A and Alt/Option variants', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.platformSetContextMenu([
        EnhancedTrayMenuItem(
          id: 'a',
          label: 'A',
          shortcut: 'Ctrl+Shift+A',
        ),
        EnhancedTrayMenuItem(
          id: 'b',
          label: 'B',
          shortcut: 'Alt+B',
        ),
        EnhancedTrayMenuItem(
          id: 'c',
          label: 'C',
          shortcut: 'Option+Command+C',
        ),
      ]);
      final items = (calls
              .firstWhere((c) => c.method == 'setTrayContextMenu')
              .arguments as Map)['items'] as List;
      expect(((items[0] as Map)['shortcut'] as Map)['modifiers'],
          containsAll(['ctrl', 'shift']));
      expect(((items[1] as Map)['shortcut'] as Map)['modifiers'],
          contains('alt'));
      final cMods = ((items[2] as Map)['shortcut'] as Map)['modifiers'] as List;
      expect(cMods, containsAll(['alt', 'cmd']));
      await m.dispose();
    });
  });

  group('MacOSEnhancedTrayManager — balloon, update, status bar, menu bar',
      () {
    test('platformShowBalloon is a logged no-op on macOS', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.platformShowBalloon(
        title: 't',
        message: 'm',
        iconType: BalloonIconType.info,
      );
      // No native call expected.
      expect(calls.where((c) => c.method.contains('Balloon')), isEmpty);
      await m.dispose();
    });

    test('platformUpdateMenuItem routes payload', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.platformUpdateMenuItem(
        'item-1',
        label: 'New',
        disabled: true,
        checked: true,
        iconPath: '/i.png',
      );
      final call = calls.firstWhere((c) => c.method == 'updateTrayMenuItem');
      final args = call.arguments as Map;
      expect(args['itemId'], 'item-1');
      expect(args['label'], 'New');
      expect(args['disabled'], isTrue);
      expect(args['checked'], isTrue);
      expect(args['iconPath'], '/i.png');
      await m.dispose();
    });

    test('setStatusBarItemProperties forwards args', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.setStatusBarItemProperties(
        width: 30.0,
        highlightMode: true,
        title: 'X',
      );
      final call =
          calls.firstWhere((c) => c.method == 'setStatusBarItemProperties');
      final args = call.arguments as Map;
      expect(args['width'], 30.0);
      expect(args['highlightMode'], isTrue);
      expect(args['title'], 'X');
      await m.dispose();
    });

    test('setMenuBarVisibility forwards arg', () async {
      final m = MacOSEnhancedTrayManager();
      await m.initialize(null);
      calls.clear();
      await m.setMenuBarVisibility(false);
      final call = calls.firstWhere((c) => c.method == 'setMenuBarVisibility');
      expect((call.arguments as Map)['visible'], isFalse);
      await m.dispose();
    });
  });
}
