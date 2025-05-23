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

  // 모든 테스트 전에 한 번만 초기화
  setUpAll(() async {
    // Initialize FlutterMCP
    flutterMcp = FlutterMCP.instance;

    // Create minimal config for testing
    final config = MCPConfig(
      appName: 'MCP Plugin Test',
      appVersion: '1.0.0',
      autoStart: false,
      loggingLevel: MCPLogLevel.debug,
      secure: false,
      autoRegisterLlmPlugins: false,
      registerMcpPluginsWithLlm: false,
      registerCoreLlmPlugins: false,
    );

    await flutterMcp.init(config);
  });

  // 모든 테스트 후에 한 번만 정리
  tearDownAll(() async {
    // Clean up after tests
    await flutterMcp.shutdown();
  });

  // 각 테스트 간에 플러그인 정리
  tearDown(() async {
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

      // Force plugin to be uninitialized (핵)
      toolPlugin._isInitialized = false;

      // Execute and expect error
      expect(
              () => flutterMcp.executeToolPlugin('test_tool', {'input': 'test'}),
          throwsA(isA<Exception>())
      );
    });
  });
}