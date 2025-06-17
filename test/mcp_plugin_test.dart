import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

// Sample tool plugin implementation for testing
class TestToolPlugin implements MCPToolPlugin {
  final String _name;
  final String _version;
  final String _description;
  bool _isInitialized = false;

  TestToolPlugin({
    String name = 'test_tool',
    String version = '1.0.0',
    String description = 'A test tool plugin',
  }) :
        _name = name,
        _version = version,
        _description = description;

  @override
  String get name => _name;

  @override
  String get version => _version;

  @override
  String get description => _description;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _isInitialized = true;
  }

  @override
  Future<void> shutdown() async {
    _isInitialized = false;
  }

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments) async {
    if (!_isInitialized) {
      throw Exception('Plugin not initialized');
    }
    return {
      'result': 'Executed with ${arguments.toString()}',
      'plugin': name
    };
  }

  @override
  Map<String, dynamic> getToolMetadata() {
    return {
      'name': name,
      'description': description,
      'inputSchema': {
        'type': 'object',
        'properties': {
          'input': {'type': 'string', 'description': 'Input parameter'}
        }
      }
    };
  }

  bool get isInitialized => _isInitialized;
}

// Sample resource plugin implementation for testing
class TestResourcePlugin implements MCPResourcePlugin {
  final String _name;
  final String _version;
  final String _description;
  bool _isInitialized = false;

  TestResourcePlugin({
    String name = 'test_resource',
    String version = '1.0.0',
    String description = 'A test resource plugin',
  }) :
        _name = name,
        _version = version,
        _description = description;

  @override
  String get name => _name;

  @override
  String get version => _version;

  @override
  String get description => _description;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _isInitialized = true;
  }

  @override
  Future<void> shutdown() async {
    _isInitialized = false;
  }

  @override
  Future<Map<String, dynamic>> getResource(String resourceUri, Map<String, dynamic> params) async {
    if (!_isInitialized) {
      throw Exception('Plugin not initialized');
    }
    return {
      'content': 'Resource content for URI: $resourceUri with params: ${params.toString()}',
      'mimeType': 'text/plain',
      'plugin': name
    };
  }

  @override
  Map<String, dynamic> getResourceMetadata() {
    return {
      'name': name,
      'description': description,
      'uri': 'test://resource',
      'mimeType': 'text/plain'
    };
  }

  bool get isInitialized => _isInitialized;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlutterMCP flutterMcp;

  // Initialize once before all tests
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    
    // Mock method channel for platform interface
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_mcp'),
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'initialize':
            return null;
          case 'startBackgroundService':
            return true;
          case 'stopBackgroundService':
            return true;
          case 'showNotification':
            return null;
          case 'cancelAllNotifications':
            return null;
          case 'shutdown':
            return null;
          default:
            return null;
        }
      },
    );
    
    // Initialize FlutterMCP
    flutterMcp = FlutterMCP.instance;

    // Create minimal config for testing
    final config = MCPConfig(
      appName: 'MCP Plugin Test',
      appVersion: '1.0.0',
      autoStart: false,
      loggingLevel: Level.FINE,
      secure: false,
      autoRegisterLlmPlugins: false,
      registerMcpPluginsWithLlm: false,
      registerCoreLlmPlugins: false,
    );

    await flutterMcp.init(config);
  });

  // Clean up once after all tests
  tearDownAll(() async {
    // Clean up after tests
    await flutterMcp.shutdown();
    
    // Clear method channel mock
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_mcp'),
      null,
    );
  });

  // Clean up plugins between tests
  tearDown(() async {
    try {
      // FlutterMCP가 초기화되었는지 확인
      if (flutterMcp.isInitialized) {
        // 모든 플러그인 정보 가져오기
        final pluginInfo = flutterMcp.getAllPluginInfo();

        // 도구 플러그인 정리
        if (pluginInfo['tool_plugins'] != null) {
          for (var plugin in pluginInfo['tool_plugins']!) {
            await flutterMcp.unregisterPlugin(plugin['name'] as String);
          }
        }

        // 리소스 플러그인 정리
        if (pluginInfo['resource_plugins'] != null) {
          for (var plugin in pluginInfo['resource_plugins']!) {
            await flutterMcp.unregisterPlugin(plugin['name'] as String);
          }
        }

        // 프롬프트 플러그인 정리
        if (pluginInfo['prompt_plugins'] != null) {
          for (var plugin in pluginInfo['prompt_plugins']!) {
            await flutterMcp.unregisterPlugin(plugin['name'] as String);
          }
        }
      }
    } catch (e) {
      // FlutterMCP가 종료된 경우 무시
    }
  });

  group('Plugin Registration Tests', () {
    test('Register Tool Plugin', () async {
      // Create a test tool plugin
      final toolPlugin = TestToolPlugin();

      // Register the plugin with the registry
      await flutterMcp.registerPlugin(toolPlugin);

      // Verify plugin is in the registry
      final pluginInfo = flutterMcp.getAllPluginInfo();
      expect(pluginInfo['tool_plugins'], isNotEmpty);
      expect(pluginInfo['tool_plugins']!.any((p) => p['name'] == 'test_tool'), true);
    });

    test('Register Resource Plugin', () async {
      // Create a test resource plugin
      final resourcePlugin = TestResourcePlugin();

      // Register the plugin
      await flutterMcp.registerPlugin(resourcePlugin);

      // Verify plugin is in the registry
      final pluginInfo = flutterMcp.getAllPluginInfo();
      expect(pluginInfo['resource_plugins'], isNotEmpty);
      expect(pluginInfo['resource_plugins']!.any((p) => p['name'] == 'test_resource'), true);
    });

    test('Register Plugin with custom config', () async {
      // Create a test tool plugin
      final toolPlugin = TestToolPlugin();

      // Create custom config
      final config = {
        'customSetting': 'value1',
        'enableFeatureX': true
      };

      // Register the plugin with config
      await flutterMcp.registerPlugin(toolPlugin, config);

      // Verify plugin was initialized
      expect((toolPlugin).isInitialized, true);

      // Verify plugin is in the registry
      final pluginInfo = flutterMcp.getAllPluginInfo();
      expect(pluginInfo['tool_plugins']!.any((p) => p['name'] == 'test_tool'), true);
    });

    test('Unregister Plugin', () async {
      // Create and register a test tool plugin
      final toolPlugin = TestToolPlugin();
      await flutterMcp.registerPlugin(toolPlugin);

      // Verify plugin is in the registry
      final pluginInfoBefore = flutterMcp.getAllPluginInfo();
      expect(pluginInfoBefore['tool_plugins']!.any((p) => p['name'] == 'test_tool'), true);

      // Unregister the plugin
      await flutterMcp.unregisterPlugin(toolPlugin.name);

      // Verify plugin is no longer in the registry
      final pluginInfoAfter = flutterMcp.getAllPluginInfo();
      expect(pluginInfoAfter['tool_plugins']?.any((p) => p['name'] == 'test_tool') ?? false, false);

      // Verify the plugin's shutdown method was called
      expect((toolPlugin).isInitialized, false);
    });
  });

  group('Plugin Execution Tests', () {
    test('Execute Tool Plugin', () async {
      // Create and register a test tool plugin
      final toolPlugin = TestToolPlugin();
      await flutterMcp.registerPlugin(toolPlugin);

      // Execute the tool plugin
      final result = await flutterMcp.executeToolPlugin(
          'test_tool',
          {'input': 'test_value'}
      );

      // Verify execution result
      expect(result, isNotEmpty);
      expect(result['plugin'], 'test_tool');
      expect(result['result'], contains('test_value'));
    });

    test('Get Resource from Plugin', () async {
      // Create and register a test resource plugin
      final resourcePlugin = TestResourcePlugin();
      await flutterMcp.registerPlugin(resourcePlugin);

      // Get resource from the plugin
      final result = await flutterMcp.getPluginResource(
          'test_resource',
          'test://resource',
          {'format': 'json'}
      );

      // Verify resource result
      expect(result, isNotEmpty);
      expect(result['plugin'], 'test_resource');
      expect(result['content'], contains('json'));
      expect(result['mimeType'], 'text/plain');
    });
  });

  group('Error Handling Tests', () {
    test('Handle plugin execution errors', () async {
      // Create a plugin that throws errors when not initialized
      final toolPlugin = TestToolPlugin();
      await flutterMcp.registerPlugin(toolPlugin);

      // Force plugin to be uninitialized (hack)
      toolPlugin._isInitialized = false;

      // Execute and expect error
      expect(
              () => flutterMcp.executeToolPlugin('test_tool', {'input': 'test'}),
          throwsA(isA<Exception>())
      );
    });
  });
}