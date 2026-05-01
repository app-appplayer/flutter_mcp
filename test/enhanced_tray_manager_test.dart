import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/tray/enhanced_tray_manager.dart';
import 'package:flutter_mcp/src/platform/tray/tray_manager.dart';
import 'package:flutter_mcp/src/config/tray_config.dart';
import 'package:flutter_mcp/src/utils/enhanced_error_handler.dart';
import 'package:flutter_mcp/src/utils/enhanced_resource_cleanup.dart';
import 'package:flutter_mcp/src/types/health_types.dart';

class _StubTrayManager extends EnhancedTrayManager {
  String? lastIcon;
  Uint8List? lastIconBytes;
  String? lastTooltip;
  List<EnhancedTrayMenuItem>? lastContextMenu;
  bool initCalled = false;
  bool disposeCalled = false;
  bool showCalled = false;
  bool hideCalled = false;
  bool balloonShown = false;
  Map<String, dynamic>? lastMenuUpdate;

  _StubTrayManager()
      : super(
          'test',
          supportsAnimation: true,
          supportsColorIcons: true,
          supportsSubmenu: true,
          supportsBalloon: true,
        );

  @override
  Future<void> platformInitialize() async {
    initCalled = true;
  }

  @override
  Future<void> platformSetIcon(String path) async {
    lastIcon = path;
  }

  @override
  Future<void> platformSetIconFromBytes(Uint8List bytes) async {
    lastIconBytes = bytes;
  }

  @override
  Future<void> platformSetTooltip(String tooltip) async {
    lastTooltip = tooltip;
  }

  @override
  Future<void> platformSetContextMenu(List<EnhancedTrayMenuItem> items) async {
    lastContextMenu = items;
  }

  @override
  Future<void> platformShow() async {
    showCalled = true;
  }

  @override
  Future<void> platformHide() async {
    hideCalled = true;
  }

  @override
  Future<void> platformShowBalloon({
    required String title,
    required String message,
    required BalloonIconType iconType,
    Duration? timeout,
  }) async {
    balloonShown = true;
  }

  @override
  Future<void> platformUpdateMenuItem(
    String itemId, {
    String? label,
    bool? disabled,
    bool? checked,
    String? iconPath,
  }) async {
    lastMenuUpdate = {
      'itemId': itemId,
      'label': label,
      'disabled': disabled,
      'checked': checked,
      'iconPath': iconPath,
    };
  }

  @override
  Future<void> platformDispose() async {
    disposeCalled = true;
  }
}

class _NoSupportTray extends _StubTrayManager {
  @override
  bool get supportsAnimation => false;
  @override
  bool get supportsBalloon => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    EnhancedErrorHandler.instance.initialize();
    EnhancedResourceCleanup.instance.initialize();
  });

  group('EnhancedTrayManager — initialize / setters / state', () {
    test('initialize calls platformInitialize and applies config', () async {
      final m = _StubTrayManager();
      await m.initialize(TrayConfig(
        iconPath: '/i.png',
        tooltip: 'tip',
        menuItems: [
          TrayMenuItem(label: 'Show', id: 'show'),
          TrayMenuItem.separator(),
          TrayMenuItem(label: 'Quit', id: 'quit'),
        ],
      ));
      expect(m.initCalled, isTrue);
      expect(m.lastIcon, '/i.png');
      expect(m.lastTooltip, 'tip');
      expect(m.lastContextMenu, hasLength(3));
      expect(m.state.iconPath, '/i.png');
      expect(m.state.tooltip, 'tip');
    });

    test('initialize without config skips applyConfig', () async {
      final m = _StubTrayManager();
      await m.initialize(null);
      expect(m.initCalled, isTrue);
      expect(m.lastIcon, isNull);
      expect(m.lastTooltip, isNull);
    });

    test('setIcon updates platform and state', () async {
      final m = _StubTrayManager();
      await m.setIcon('/img.png');
      expect(m.lastIcon, '/img.png');
      expect(m.state.iconPath, '/img.png');
    });

    test('setIconFromBytes updates state with sentinel <bytes>', () async {
      final m = _StubTrayManager();
      await m.setIconFromBytes(Uint8List.fromList([1, 2, 3]));
      expect(m.lastIconBytes, [1, 2, 3]);
      expect(m.state.iconPath, '<bytes>');
    });

    test('setTooltip updates state', () async {
      final m = _StubTrayManager();
      await m.setTooltip('hover');
      expect(m.lastTooltip, 'hover');
      expect(m.state.tooltip, 'hover');
    });

    test('setContextMenu accepts plain TrayMenuItems and converts', () async {
      final m = _StubTrayManager();
      await m.setContextMenu([
        TrayMenuItem(label: 'A', id: 'a'),
        TrayMenuItem(label: 'B', id: 'b'),
      ]);
      expect(m.lastContextMenu, hasLength(2));
      expect(m.lastContextMenu!.every((e) => e is EnhancedTrayMenuItem),
          isTrue);
    });

    test('setContextMenu preserves EnhancedTrayMenuItems verbatim', () async {
      final m = _StubTrayManager();
      final original = EnhancedTrayMenuItem(
        label: 'A',
        id: 'a',
        type: MenuItemType.checkbox,
      );
      await m.setContextMenu([original]);
      expect(m.lastContextMenu!.first.type, MenuItemType.checkbox);
    });

    test('show / hide flip state and call platform', () async {
      final m = _StubTrayManager();
      await m.show();
      expect(m.showCalled, isTrue);
      expect(m.state.visible, isTrue);
      await m.hide();
      expect(m.hideCalled, isTrue);
      expect(m.state.visible, isFalse);
    });
  });

  group('EnhancedTrayManager — animation', () {
    test('startAnimation does nothing when supportsAnimation is false',
        () async {
      final m = _NoSupportTray();
      await m.startAnimation(['/a.png', '/b.png'], const Duration(seconds: 1));
      expect(m.state.animating, isFalse);
    });

    test('startAnimation sets animating state when supported', () async {
      final m = _StubTrayManager();
      await m.startAnimation(
          ['/a.png', '/b.png'], const Duration(milliseconds: 50));
      expect(m.state.animating, isTrue);
      // Cancel before timer fires to avoid affecting other tests.
      await m.stopAnimation();
      expect(m.state.animating, isFalse);
    });

    test('stopAnimation clears state without throwing if not running',
        () async {
      final m = _StubTrayManager();
      await m.stopAnimation();
      expect(m.state.animating, isFalse);
    });
  });

  group('EnhancedTrayManager — balloon', () {
    test('showBalloon does nothing when supportsBalloon is false', () async {
      final m = _NoSupportTray();
      await m.showBalloon(title: 't', message: 'm');
      expect(m.balloonShown, isFalse);
    });

    test('showBalloon delegates to platform when supported', () async {
      final m = _StubTrayManager();
      await m.showBalloon(
        title: 't',
        message: 'm',
        iconType: BalloonIconType.warning,
        timeout: const Duration(seconds: 5),
      );
      expect(m.balloonShown, isTrue);
    });
  });

  group('EnhancedTrayManager — menu item updates', () {
    test('updateMenuItem warns + no-ops when item is unknown', () async {
      final m = _StubTrayManager();
      await m.updateMenuItem('absent', label: 'x');
      expect(m.lastMenuUpdate, isNull);
    });

    test('updateMenuItem delegates to platform when item exists', () async {
      final m = _StubTrayManager();
      await m.setContextMenu([
        EnhancedTrayMenuItem(label: 'A', id: 'a'),
      ]);
      await m.updateMenuItem(
        'a',
        label: 'A2',
        disabled: true,
        checked: true,
        iconPath: '/i.png',
      );
      expect(m.lastMenuUpdate!['itemId'], 'a');
      expect(m.lastMenuUpdate!['label'], 'A2');
      expect(m.lastMenuUpdate!['disabled'], isTrue);
      expect(m.lastMenuUpdate!['checked'], isTrue);
      expect(m.lastMenuUpdate!['iconPath'], '/i.png');
    });
  });

  group('EnhancedTrayManager — listeners + dispose', () {
    test('add/remove event listener', () {
      final m = _StubTrayManager();
      final l = TrayEventListener(onTrayMouseDown: () {});
      m.addEventListener(l);
      // Statistics should reflect the listener count.
      expect(m.getStatistics()['eventListenerCount'], 1);
      m.removeEventListener(l);
      expect(m.getStatistics()['eventListenerCount'], 0);
    });

    test('dispose calls platformDispose and clears menu/listeners', () async {
      final m = _StubTrayManager();
      m.addEventListener(TrayEventListener());
      await m.setContextMenu([
        EnhancedTrayMenuItem(label: 'A', id: 'a'),
      ]);
      await m.dispose();
      expect(m.disposeCalled, isTrue);
      expect(m.getStatistics()['menuItemCount'], 0);
      expect(m.getStatistics()['eventListenerCount'], 0);
    });
  });

  group('EnhancedTrayManager — health check + statistics', () {
    test('reports healthy when not visible', () async {
      final m = _StubTrayManager();
      final r = await m.performHealthCheck();
      expect(r.status, MCPHealthStatus.healthy);
      expect(r.message, contains('not visible'));
    });

    test('reports healthy after show + tooltip update', () async {
      final m = _StubTrayManager();
      await m.show();
      await m.setTooltip('t');
      final r = await m.performHealthCheck();
      expect(r.status, MCPHealthStatus.healthy);
    });

    test('getStatistics keys include support flags', () {
      final m = _StubTrayManager();
      final s = m.getStatistics();
      expect(s, contains('visible'));
      expect(s, contains('iconPath'));
      expect(s, contains('tooltip'));
      expect(s, contains('animating'));
      expect(s, contains('menuItemCount'));
      expect(s, contains('eventListenerCount'));
      expect(s, contains('updateCount'));
      expect(s, contains('supportsAnimation'));
      expect(s, contains('supportsColorIcons'));
      expect(s, contains('supportsSubmenu'));
      expect(s, contains('supportsBalloon'));
    });
  });
}
