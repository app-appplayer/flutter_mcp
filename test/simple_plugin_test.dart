import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/plugins/enhanced_plugin_system.dart';
import 'package:flutter_mcp/src/plugins/plugin_system.dart';

// Simple test plugin
class SimplePlugin extends MCPPlugin {
  @override
  String get name => 'simple-plugin';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Simple test plugin';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // Simple initialization
  }

  @override
  Future<void> shutdown() async {
    // Simple shutdown
  }
}

void main() {
  test('Enhanced plugin system basic functionality', () async {
    final registry = EnhancedPluginRegistry();
    final plugin = SimplePlugin();

    // Test basic registration
    await registry.registerPlugin(plugin);

    // Verify plugin is registered
    final retrieved = registry.getPlugin<SimplePlugin>('simple-plugin');
    expect(retrieved, isNotNull);
    expect(retrieved!.name, equals('simple-plugin'));
    expect(retrieved.version, equals('1.0.0'));

    // Test version info
    final versionInfo = registry.getPluginVersion('simple-plugin');
    expect(versionInfo, isNotNull);
    expect(versionInfo!.name, equals('simple-plugin'));
    expect(versionInfo.version.toString(), equals('1.0.0'));

    // Clean up
    await registry.unregisterPlugin('simple-plugin');
  });
}
