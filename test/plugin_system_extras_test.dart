// Targeted extras for MCPPluginRegistry — focuses on the paths not covered
// by mcp_plugin_system_test.dart: notification/background/tray plugin
// branches, dependency graph methods, updatePluginConfiguration, shutdownAll
// error aggregation.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/plugins/plugin_system.dart';
import 'package:flutter_mcp/src/platform/tray/tray_manager.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

class _NotifPlugin extends MCPNotificationPlugin {
  bool initialized = false;
  bool shutdownCalled = false;
  String? lastTitle;
  String? lastBody;
  String? lastHidden;
  void Function(String, Map<String, dynamic>?)? clickHandler;
  bool throwOnShow = false;

  @override
  String get name => 'notif';
  @override
  String get version => '1.0.0';
  @override
  String get description => 'test';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    initialized = true;
  }

  @override
  Future<void> shutdown() async {
    shutdownCalled = true;
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? id,
    String? icon,
    Map<String, dynamic>? additionalData,
  }) async {
    if (throwOnShow) throw Exception('show failed');
    lastTitle = title;
    lastBody = body;
  }

  @override
  Future<void> hideNotification(String id) async {
    lastHidden = id;
  }

  @override
  void registerClickHandler(
      Function(String id, Map<String, dynamic>? data) handler) {
    clickHandler = handler;
  }
}

class _BgPlugin extends MCPBackgroundPlugin {
  bool _running = false;
  bool throwOnStart = false;
  bool throwOnStop = false;
  Future<void> Function()? handler;

  @override
  String get name => 'bg';
  @override
  String get version => '1.0.0';
  @override
  String get description => 'test';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> shutdown() async {
    _running = false;
  }

  @override
  Future<bool> start() async {
    if (throwOnStart) throw Exception('start failed');
    _running = true;
    return true;
  }

  @override
  Future<bool> stop() async {
    if (throwOnStop) throw Exception('stop failed');
    _running = false;
    return true;
  }

  @override
  bool get isRunning => _running;

  @override
  void registerTaskHandler(Future<void> Function() h) {
    handler = h;
  }
}

class _TrayPlugin extends MCPTrayPlugin {
  String? icon;
  String? tooltip;
  List<TrayMenuItem>? items;
  bool visible = false;
  bool throwOnSetIcon = false;
  bool throwOnSetMenu = false;

  @override
  String get name => 'tray';
  @override
  String get version => '1.0.0';
  @override
  String get description => 'test';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> shutdown() async {}

  @override
  Future<void> setIcon(String iconPath) async {
    if (throwOnSetIcon) throw Exception('icon failed');
    icon = iconPath;
  }

  @override
  Future<void> setTooltip(String t) async {
    tooltip = t;
  }

  @override
  Future<void> setMenuItems(List<TrayMenuItem> i) async {
    if (throwOnSetMenu) throw Exception('menu failed');
    items = i;
  }

  @override
  Future<void> show() async {
    visible = true;
  }

  @override
  Future<void> hide() async {
    visible = false;
  }

  @override
  bool get isSupported => true;
}

class _BadShutdownPlugin extends MCPNotificationPlugin {
  @override
  String get name => 'bad';
  @override
  String get version => '1.0.0';
  @override
  String get description => 'bad';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> shutdown() async => throw Exception('shutdown explosion');

  @override
  Future<void> showNotification(
      {required String title,
      required String body,
      String? id,
      String? icon,
      Map<String, dynamic>? additionalData}) async {}
  @override
  Future<void> hideNotification(String id) async {}
  @override
  void registerClickHandler(
      Function(String id, Map<String, dynamic>? data) handler) {}
}

void main() {
  group('MCPPluginRegistry — notification plugin paths', () {
    test('showNotification routes to plugin', () async {
      final r = MCPPluginRegistry();
      final p = _NotifPlugin();
      await r.registerPlugin(p);
      await r.showNotification('notif', title: 'hello', body: 'world');
      expect(p.lastTitle, 'hello');
      expect(p.lastBody, 'world');
      expect(p.initialized, isTrue);
    });

    test('showNotification on unknown plugin throws', () async {
      final r = MCPPluginRegistry();
      await expectLater(
        r.showNotification('absent', title: 't', body: 'b'),
        throwsA(isA<MCPPluginException>()),
      );
    });

    test('showNotification wraps inner errors as MCPPluginException', () async {
      final r = MCPPluginRegistry();
      final p = _NotifPlugin()..throwOnShow = true;
      await r.registerPlugin(p);
      await expectLater(
        r.showNotification('notif', title: 't', body: 'b'),
        throwsA(isA<MCPPluginException>()),
      );
    });
  });

  group('MCPPluginRegistry — background plugin paths', () {
    test('start and stop dispatch to plugin', () async {
      final r = MCPPluginRegistry();
      final p = _BgPlugin();
      await r.registerPlugin(p);
      expect(await r.startBackgroundPlugin('bg'), isTrue);
      expect(p.isRunning, isTrue);
      expect(await r.stopBackgroundPlugin('bg'), isTrue);
      expect(p.isRunning, isFalse);
    });

    test('start unknown plugin throws', () async {
      final r = MCPPluginRegistry();
      await expectLater(
        r.startBackgroundPlugin('absent'),
        throwsA(isA<MCPPluginException>()),
      );
    });

    test('stop unknown plugin throws', () async {
      final r = MCPPluginRegistry();
      await expectLater(
        r.stopBackgroundPlugin('absent'),
        throwsA(isA<MCPPluginException>()),
      );
    });

    test('start failure wraps as MCPPluginException', () async {
      final r = MCPPluginRegistry();
      final p = _BgPlugin()..throwOnStart = true;
      await r.registerPlugin(p);
      await expectLater(
        r.startBackgroundPlugin('bg'),
        throwsA(isA<MCPPluginException>()),
      );
    });

    test('stop failure wraps as MCPPluginException', () async {
      final r = MCPPluginRegistry();
      final p = _BgPlugin()..throwOnStop = true;
      await r.registerPlugin(p);
      await expectLater(
        r.stopBackgroundPlugin('bg'),
        throwsA(isA<MCPPluginException>()),
      );
    });
  });

  group('MCPPluginRegistry — tray plugin paths', () {
    test('updateTrayIcon dispatches to plugin', () async {
      final r = MCPPluginRegistry();
      final p = _TrayPlugin();
      await r.registerPlugin(p);
      await r.updateTrayIcon('tray', '/some/icon.png');
      expect(p.icon, '/some/icon.png');
    });

    test('updateTrayIcon on unknown plugin throws', () async {
      final r = MCPPluginRegistry();
      await expectLater(
        r.updateTrayIcon('absent', '/i.png'),
        throwsA(isA<MCPPluginException>()),
      );
    });

    test('updateTrayIcon failure wraps as MCPPluginException', () async {
      final r = MCPPluginRegistry();
      final p = _TrayPlugin()..throwOnSetIcon = true;
      await r.registerPlugin(p);
      await expectLater(
        r.updateTrayIcon('tray', '/x'),
        throwsA(isA<MCPPluginException>()),
      );
    });

    test('setTrayMenuItems dispatches to plugin', () async {
      final r = MCPPluginRegistry();
      final p = _TrayPlugin();
      await r.registerPlugin(p);
      final items = [TrayMenuItem(label: 'A')];
      await r.setTrayMenuItems('tray', items);
      expect(p.items, isNotNull);
      expect(p.items!.first.label, 'A');
    });

    test('setTrayMenuItems on unknown plugin throws', () async {
      final r = MCPPluginRegistry();
      await expectLater(
        r.setTrayMenuItems('absent', []),
        throwsA(isA<MCPPluginException>()),
      );
    });

    test('setTrayMenuItems failure wraps as MCPPluginException', () async {
      final r = MCPPluginRegistry();
      final p = _TrayPlugin()..throwOnSetMenu = true;
      await r.registerPlugin(p);
      await expectLater(
        r.setTrayMenuItems('tray', []),
        throwsA(isA<MCPPluginException>()),
      );
    });
  });

  group('MCPPluginRegistry — dependency tracking', () {
    test('addDependency / hasDependency / getDependencies', () {
      final r = MCPPluginRegistry();
      expect(r.hasDependency('a', 'b'), isFalse);
      r.addDependency('a', 'b');
      r.addDependency('a', 'c');
      r.addDependency('a', 'b'); // duplicate ignored
      expect(r.hasDependency('a', 'b'), isTrue);
      expect(r.hasDependency('a', 'c'), isTrue);
      expect(r.getDependencies('a'), containsAll(['b', 'c']));
      expect(r.getDependencies('a'), hasLength(2));
      expect(r.getDependencies('unknown'), isEmpty);
    });

    test('getDependents lists plugins depending on a name', () {
      final r = MCPPluginRegistry();
      r.addDependency('a', 'shared');
      r.addDependency('b', 'shared');
      r.addDependency('c', 'other');
      final deps = r.getDependents('shared');
      expect(deps, containsAll(['a', 'b']));
      expect(deps.contains('c'), isFalse);
    });
  });

  group('MCPPluginRegistry — configuration', () {
    test('getPluginConfiguration returns the registered config', () async {
      final r = MCPPluginRegistry();
      final p = _NotifPlugin();
      await r.registerPlugin(p, {'k': 'v'});
      expect(r.getPluginConfiguration('notif'), {'k': 'v'});
    });

    test('getPluginConfiguration returns null for unknown plugin', () {
      final r = MCPPluginRegistry();
      expect(r.getPluginConfiguration('absent'), isNull);
    });

    test('updatePluginConfiguration re-initialises plugin with new config',
        () async {
      final r = MCPPluginRegistry();
      final p = _NotifPlugin();
      await r.registerPlugin(p, {'a': 1});
      await r.updatePluginConfiguration('notif', {'a': 2});
      expect(r.getPluginConfiguration('notif'), {'a': 2});
      // shutdown was called once during reconfigure.
      expect(p.shutdownCalled, isTrue);
    });

    test('updatePluginConfiguration throws when plugin not found', () async {
      final r = MCPPluginRegistry();
      await expectLater(
        r.updatePluginConfiguration('absent', {}),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('MCPPluginRegistry — shutdownAll', () {
    test('clears registries and runs without error in happy path', () async {
      final r = MCPPluginRegistry();
      await r.registerPlugin(_NotifPlugin());
      await r.registerPlugin(_BgPlugin());
      await r.shutdownAll();
      expect(r.getAllPlugins(), isEmpty);
      expect(r.getAllPluginNames(), isEmpty);
    });

    test('aggregates shutdown errors and throws', () async {
      final r = MCPPluginRegistry();
      await r.registerPlugin(_BadShutdownPlugin());
      await expectLater(r.shutdownAll(), throwsA(isA<MCPException>()));
      // Even when shutdown throws, registry is cleared.
      expect(r.getAllPlugins(), isEmpty);
    });
  });

  group('MCPPluginRegistry — discovery', () {
    test('getAllPlugins returns all registered plugins', () async {
      final r = MCPPluginRegistry();
      await r.registerPlugin(_NotifPlugin());
      await r.registerPlugin(_BgPlugin());
      expect(r.getAllPlugins(), hasLength(2));
    });

    test('getAllPluginNames preserves load order', () async {
      final r = MCPPluginRegistry();
      await r.registerPlugin(_NotifPlugin());
      await r.registerPlugin(_BgPlugin());
      expect(r.getAllPluginNames(), ['notif', 'bg']);
    });

    test('getPluginsByType filters by interface', () async {
      final r = MCPPluginRegistry();
      await r.registerPlugin(_NotifPlugin());
      await r.registerPlugin(_BgPlugin());
      expect(r.getPluginsByType<MCPNotificationPlugin>(), hasLength(1));
      expect(r.getPluginsByType<MCPBackgroundPlugin>(), hasLength(1));
      expect(r.getPluginsByType<MCPToolPlugin>(), isEmpty);
    });

    test('getPlugin returns null when not found', () {
      final r = MCPPluginRegistry();
      expect(r.getPlugin<MCPToolPlugin>('absent'), isNull);
    });
  });

  group('MCPPluginRegistry — unregister edge cases', () {
    test('unregister removes from dependency graphs', () async {
      final r = MCPPluginRegistry();
      await r.registerPlugin(_NotifPlugin());
      r.addDependency('notif', 'other-plugin');
      r.addDependency('peer', 'notif');
      await r.unregisterPlugin('notif');
      expect(r.getAllPluginNames().contains('notif'), isFalse);
      // notif removed from dependencies map; other plugins no longer list it.
      expect(r.getDependencies('peer').contains('notif'), isFalse);
    });

    test('unregister tolerates plugin shutdown errors', () async {
      final r = MCPPluginRegistry();
      await r.registerPlugin(_BadShutdownPlugin());
      await r.unregisterPlugin('bad');
      expect(r.getAllPluginNames().contains('bad'), isFalse);
    });
  });
}
