import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/tray/tray_manager.dart';
import 'package:flutter_mcp/src/config/tray_config.dart';

void main() {
  group('TrayMenuItem', () {
    test('default constructor has isSeparator false', () {
      final item = TrayMenuItem(label: 'Show');
      expect(item.label, 'Show');
      expect(item.disabled, isFalse);
      expect(item.isSeparator, isFalse);
    });

    test('separator constructor sets isSeparator true', () {
      final sep = TrayMenuItem.separator();
      expect(sep.label, isNull);
      expect(sep.id, isNull);
      expect(sep.isSeparator, isTrue);
    });

    test('toJson uses provided id when supplied', () {
      final item = TrayMenuItem(label: 'Show', id: 'show_main');
      final json = item.toJson();
      expect(json['label'], 'Show');
      expect(json['id'], 'show_main');
      expect(json['disabled'], isFalse);
      expect(json['isSeparator'], isFalse);
    });

    test('toJson derives id from label when id is null', () {
      final item = TrayMenuItem(label: 'Show Window');
      final json = item.toJson();
      // 'Show Window' → 'show_window'
      expect(json['id'], 'show_window');
    });

    test('toJson handles null label and id', () {
      final sep = TrayMenuItem.separator();
      final json = sep.toJson();
      expect(json['label'], isNull);
      expect(json['id'], isNull);
      expect(json['isSeparator'], isTrue);
    });

    test('disabled is reflected in toJson', () {
      final item = TrayMenuItem(label: 'X', disabled: true);
      expect(item.toJson()['disabled'], isTrue);
    });

    test('onTap is stored on the instance', () {
      var taps = 0;
      final item = TrayMenuItem(label: 'Click', onTap: () => taps++);
      item.onTap?.call();
      expect(taps, 1);
    });
  });

  group('NoOpTrayManager', () {
    test('all methods complete without throwing', () async {
      final m = NoOpTrayManager();
      await m.initialize(null);
      await m.initialize(TrayConfig());
      await m.setIcon('/i.png');
      await m.setTooltip('tip');
      await m.setContextMenu([
        TrayMenuItem(label: 'A'),
        TrayMenuItem.separator(),
      ]);
      await m.dispose();
    });

    test('implements TrayManager', () {
      expect(NoOpTrayManager(), isA<TrayManager>());
    });
  });
}
