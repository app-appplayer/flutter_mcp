import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/config/plugin_config.dart';
import 'package:flutter_mcp/src/plugins/plugin_system.dart';

class _StubPlugin extends MCPPlugin {
  @override
  String get name => 'stub';
  @override
  String get version => '0.0.1';
  @override
  String get description => 'stub plugin';
  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> shutdown() async {}
}

void main() {
  group('PluginConfig', () {
    test('default constructor uses empty config and null targets', () {
      final p = _StubPlugin();
      final cfg = PluginConfig(plugin: p);
      expect(cfg.plugin, p);
      expect(cfg.config, isEmpty);
      expect(cfg.targets, isNull);
    });

    test('constructor preserves config and targets', () {
      final p = _StubPlugin();
      final cfg = PluginConfig(
        plugin: p,
        config: const {'key': 'value'},
        targets: const ['a', 'b'],
      );
      expect(cfg.plugin, p);
      expect(cfg.config, {'key': 'value'});
      expect(cfg.targets, ['a', 'b']);
    });
  });
}
