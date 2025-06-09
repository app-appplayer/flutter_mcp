import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/plugins/enhanced_plugin_system.dart';
import 'package:flutter_mcp/src/plugins/plugin_system.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';
import 'package:pub_semver/pub_semver.dart';

// Test plugin implementation
class TestPlugin extends MCPPlugin {
  @override
  final String name;
  
  @override
  final String version;
  
  @override
  String get description => 'Test plugin';
  
  bool initialized = false;
  bool wasShutdown = false;
  
  TestPlugin({required this.name, required this.version});
  
  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    initialized = true;
  }
  
  @override
  Future<void> shutdown() async {
    wasShutdown = true;
  }
}

void main() {
  group('Enhanced Plugin System Tests', () {
    late EnhancedPluginRegistry registry;
    
    setUp(() {
      registry = EnhancedPluginRegistry();
    });
    
    tearDown(() async {
      await registry.shutdownAll();
    });
    
    test('should register plugin with version information', () async {
      final plugin = TestPlugin(name: 'test-plugin', version: '1.0.0');
      
      await registry.registerPlugin(plugin);
      
      final versionInfo = registry.getPluginVersion('test-plugin');
      expect(versionInfo, isNotNull);
      expect(versionInfo!.name, equals('test-plugin'));
      expect(versionInfo.version, equals(Version(1, 0, 0)));
    });
    
    test('should detect version conflicts', () async {
      // Register first plugin
      final plugin1 = TestPlugin(name: 'plugin-a', version: '1.0.0');
      await registry.registerPlugin(plugin1, {
        'dependencies': {
          'plugin-b': '^2.0.0',
        }
      });
      
      // Try to register conflicting plugin
      final plugin2 = TestPlugin(name: 'plugin-b', version: '1.5.0');
      
      expect(
        () => registry.registerPlugin(plugin2),
        throwsA(isA<MCPPluginException>()),
      );
    });
    
    test('should handle SDK version constraints', () async {
      final plugin = TestPlugin(name: 'test-plugin', version: '1.0.0');
      
      // Should fail with incompatible SDK version
      expect(
        () => registry.registerPlugin(plugin, {
          'minSdkVersion': '2.0.0',
        }),
        throwsA(isA<MCPPluginException>()),
      );
      
      // Should succeed with compatible SDK version
      await registry.registerPlugin(plugin, {
        'minSdkVersion': '0.5.0',
        'maxSdkVersion': '2.0.0',
      });
    });
    
    test('should apply sandbox configuration', () async {
      final plugin = TestPlugin(name: 'sandboxed-plugin', version: '1.0.0');
      
      await registry.registerPlugin(plugin, {
        'sandbox': {
          'executionTimeoutMs': 5000,
          'maxMemoryMB': 100,
          'enableNetworkAccess': false,
          'enableFileAccess': true,
        }
      });
      
      final sandboxConfig = registry.getPluginSandboxConfig('sandboxed-plugin');
      expect(sandboxConfig, isNotNull);
      expect(sandboxConfig!.executionTimeout?.inMilliseconds, equals(5000));
      expect(sandboxConfig.maxMemoryMB, equals(100));
      expect(sandboxConfig.enableNetworkAccess, isFalse);
      expect(sandboxConfig.enableFileAccess, isTrue);
    });
    
    test('should execute plugin with timeout in sandbox', () async {
      final plugin = TestPlugin(name: 'timeout-plugin', version: '1.0.0');
      
      await registry.registerPlugin(plugin, {
        'sandbox': {
          'executionTimeoutMs': 100,
        }
      });
      
      // Test timeout
      expect(
        () => registry.executeInSandbox(
          'timeout-plugin',
          () async {
            await Future.delayed(Duration(milliseconds: 200));
            return 'completed';
          },
        ),
        throwsA(isA<MCPPluginException>()),
      );
      
      // Test successful execution within timeout
      final result = await registry.executeInSandbox(
        'timeout-plugin',
        () async {
          await Future.delayed(Duration(milliseconds: 50));
          return 'completed';
        },
      );
      expect(result, equals('completed'));
    });
    
    test('should resolve version conflicts with suggestions', () async {
      // Disable strict version checking to allow conflicting registrations
      registry.strictVersionChecking = false;
      
      // Setup conflicting plugins
      await registry.registerPlugin(
        TestPlugin(name: 'plugin-a', version: '1.0.0'),
        {
          'dependencies': {
            'plugin-b': '^2.0.0',
            'plugin-c': '>=1.5.0 <2.0.0',
          }
        },
      );
      
      await registry.registerPlugin(
        TestPlugin(name: 'plugin-b', version: '1.5.0'),
      );
      
      await registry.registerPlugin(
        TestPlugin(name: 'plugin-c', version: '1.2.0'),
      );
      
      // Get suggestions
      final suggestions = registry.resolveVersionConflicts();
      
      expect(suggestions.length, equals(2));
      expect(suggestions.any((s) => s.pluginName == 'plugin-b'), isTrue);
      expect(suggestions.any((s) => s.pluginName == 'plugin-c'), isTrue);
      
      // Re-enable strict checking for other tests
      registry.strictVersionChecking = true;
    });
    
    test('should handle complex dependency chains', () async {
      // Plugin A depends on B ^1.0.0
      await registry.registerPlugin(
        TestPlugin(name: 'plugin-a', version: '1.0.0'),
        {
          'dependencies': {'plugin-b': '^1.0.0'},
        },
      );
      
      // Plugin B v1.2.0 depends on C ^2.0.0
      await registry.registerPlugin(
        TestPlugin(name: 'plugin-b', version: '1.2.0'),
        {
          'dependencies': {'plugin-c': '^2.0.0'},
        },
      );
      
      // Plugin C v2.1.0 should work
      await registry.registerPlugin(
        TestPlugin(name: 'plugin-c', version: '2.1.0'),
      );
      
      // Verify all plugins are registered
      expect(registry.getPlugin<TestPlugin>('plugin-a'), isNotNull);
      expect(registry.getPlugin<TestPlugin>('plugin-b'), isNotNull);
      expect(registry.getPlugin<TestPlugin>('plugin-c'), isNotNull);
    });
  });
}