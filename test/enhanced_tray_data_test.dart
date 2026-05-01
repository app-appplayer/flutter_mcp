// Targeted tests for EnhancedTrayMenuItem / TrayIconState / TrayEventListener
// data shapes — testing the abstract EnhancedTrayManager itself requires a
// platform-channel-mocking subclass and is covered indirectly via
// MacOSEnhancedTrayManager (see native_channel_integration_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/tray/enhanced_tray_manager.dart';

void main() {
  group('EnhancedTrayMenuItem', () {
    test('default normal menu item', () {
      final item = EnhancedTrayMenuItem(label: 'Show', id: 'show');
      expect(item.iconPath, isNull);
      expect(item.submenu, isNull);
      expect(item.type, MenuItemType.normal);
      expect(item.checked, isFalse);
      expect(item.shortcut, isNull);
      expect(item.visible, isTrue);
      expect(item.metadata, isNull);
    });

    test('separator factory', () {
      final sep = EnhancedTrayMenuItem.separator();
      expect(sep.isSeparator, isTrue);
      expect(sep.iconPath, isNull);
      expect(sep.submenu, isNull);
      expect(sep.type, MenuItemType.normal);
      expect(sep.checked, isFalse);
      expect(sep.shortcut, isNull);
      expect(sep.visible, isTrue);
      expect(sep.metadata, isNull);
    });

    test('toJson includes all extended fields', () {
      final item = EnhancedTrayMenuItem(
        label: 'Open',
        id: 'open',
        iconPath: '/i.png',
        type: MenuItemType.checkbox,
        checked: true,
        shortcut: 'Cmd+O',
        visible: false,
        metadata: const {'x': 1},
        submenu: [
          EnhancedTrayMenuItem(label: 'Sub', id: 's'),
        ],
      );
      final json = item.toJson();
      expect(json['iconPath'], '/i.png');
      expect(json['type'], 'checkbox');
      expect(json['checked'], isTrue);
      expect(json['shortcut'], 'Cmd+O');
      expect(json['visible'], isFalse);
      expect(json['metadata'], {'x': 1});
      expect(json['submenu'], hasLength(1));
    });
  });

  group('MenuItemType + BalloonIconType', () {
    test('MenuItemType has 3 values', () {
      expect(MenuItemType.values, hasLength(3));
      expect(MenuItemType.values.map((t) => t.name).toList(),
          ['normal', 'checkbox', 'radio']);
    });

    test('BalloonIconType has 4 values', () {
      expect(BalloonIconType.values, hasLength(4));
      expect(BalloonIconType.values.map((t) => t.name).toList(),
          ['none', 'info', 'warning', 'error']);
    });
  });

  group('TrayIconState', () {
    test('default values', () {
      final s = TrayIconState();
      expect(s.visible, isFalse);
      expect(s.iconPath, isNull);
      expect(s.tooltip, isNull);
      expect(s.animating, isFalse);
      expect(s.metadata, isNull);
    });

    test('full constructor preserves fields', () {
      final s = TrayIconState(
        visible: true,
        iconPath: '/i.png',
        tooltip: 't',
        animating: true,
        metadata: const {'k': 'v'},
      );
      expect(s.visible, isTrue);
      expect(s.iconPath, '/i.png');
      expect(s.tooltip, 't');
      expect(s.animating, isTrue);
      expect(s.metadata, {'k': 'v'});
    });
  });

  group('TrayEventListener', () {
    test('all callbacks default to null', () {
      final l = TrayEventListener();
      expect(l.onTrayMouseDown, isNull);
      expect(l.onTrayMouseUp, isNull);
      expect(l.onTrayRightMouseDown, isNull);
      expect(l.onTrayRightMouseUp, isNull);
      expect(l.onTrayMouseDoubleDown, isNull);
      expect(l.onTrayMouseMove, isNull);
    });

    test('callbacks fire when invoked', () {
      var down = false;
      var up = false;
      var rDown = false;
      var rUp = false;
      var dd = false;
      var move = false;

      final l = TrayEventListener(
        onTrayMouseDown: () => down = true,
        onTrayMouseUp: () => up = true,
        onTrayRightMouseDown: () => rDown = true,
        onTrayRightMouseUp: () => rUp = true,
        onTrayMouseDoubleDown: () => dd = true,
        onTrayMouseMove: () => move = true,
      );

      l.onTrayMouseDown!();
      l.onTrayMouseUp!();
      l.onTrayRightMouseDown!();
      l.onTrayRightMouseUp!();
      l.onTrayMouseDoubleDown!();
      l.onTrayMouseMove!();

      expect(down, isTrue);
      expect(up, isTrue);
      expect(rDown, isTrue);
      expect(rUp, isTrue);
      expect(dd, isTrue);
      expect(move, isTrue);
    });
  });
}
