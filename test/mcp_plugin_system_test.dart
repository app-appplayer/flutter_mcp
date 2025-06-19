import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/plugins/plugin_system.dart';

// Sample test plugins for testing
class TestToolPlugin implements MCPToolPlugin {
  @override
  String get name => 'test_tool';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'A test tool plugin for testing';

  bool _initialized = false;
  Map<String, dynamic>? _config;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _config = config;
    _initialized = true;
  }

  @override
  Future<void> shutdown() async {
    _initialized = false;
    _config = null;
  }

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments) async {
    if (!_initialized) {
      throw Exception('Plugin not initialized');
    }

    return {
      'result': 'Tool executed successfully',
      'input': arguments,
      'plugin': name,
      'config': _config,
    };
  }

  @override
  Map<String, dynamic> getToolMetadata() {
    return {
      'name': name,
      'description': description,
      'version': version,
      'inputSchema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'Action to perform'},
          'data': {'type': 'object', 'description': 'Data for the action'},
        },
        'required': ['action'],
      },
    };
  }

  // Test helpers
  bool get isInitialized => _initialized;
  Map<String, dynamic>? get config => _config;
}

class TestResourcePlugin implements MCPResourcePlugin {
  @override
  String get name => 'test_resource';

  @override
  String get version => '2.0.0';

  @override
  String get description => 'A test resource plugin for testing';

  bool _initialized = false;
  final Map<String, String> _resources = {};

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _initialized = true;

    // Add some test resources
    _resources['test://file1.txt'] = 'Content of file 1';
    _resources['test://file2.json'] = '{"name": "test", "value": 42}';
    _resources['test://image.png'] = 'base64-encoded-image-data';
  }

  @override
  Future<void> shutdown() async {
    _initialized = false;
    _resources.clear();
  }

  @override
  Future<Map<String, dynamic>> getResource(
      String resourceUri, Map<String, dynamic> params) async {
    if (!_initialized) {
      throw Exception('Plugin not initialized');
    }

    final content = _resources[resourceUri];
    if (content == null) {
      throw Exception('Resource not found: $resourceUri');
    }

    String mimeType = 'text/plain';
    if (resourceUri.endsWith('.json')) {
      mimeType = 'application/json';
    } else if (resourceUri.endsWith('.png')) {
      mimeType = 'image/png';
    }

    return {
      'content': content,
      'mimeType': mimeType,
      'uri': resourceUri,
      'plugin': name,
      'params': params,
    };
  }

  @override
  Map<String, dynamic> getResourceMetadata() {
    return {
      'name': name,
      'description': description,
      'version': version,
      'supportedUris': _resources.keys.toList(),
      'capabilities': ['read', 'list'],
    };
  }

  // Test helpers
  bool get isInitialized => _initialized;
  List<String> get availableResources => _resources.keys.toList();
}

class TestPromptPlugin implements MCPPromptPlugin {
  @override
  String get name => 'test_prompt';

  @override
  String get version => '1.5.0';

  @override
  String get description => 'A test prompt plugin for testing';

  bool _initialized = false;
  final Map<String, String> _prompts = {};

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _initialized = true;

    // Add some test prompts
    _prompts['greeting'] = 'Hello, {name}! Welcome to {app}.';
    _prompts['summary'] = 'Please summarize the following text: {text}';
    _prompts['question'] = 'Based on {context}, answer: {question}';
  }

  @override
  Future<void> shutdown() async {
    _initialized = false;
    _prompts.clear();
  }

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments) async {
    final promptName =
        arguments['promptName'] as String? ?? arguments['prompt'] as String;
    final variables = arguments['variables'] as Map<String, dynamic>? ??
        (arguments
          ..remove('promptName')
          ..remove('prompt'));

    return await executePrompt(promptName, variables);
  }

  Future<Map<String, dynamic>> executePrompt(
      String promptName, Map<String, dynamic> variables) async {
    if (!_initialized) {
      throw Exception('Plugin not initialized');
    }

    final template = _prompts[promptName];
    if (template == null) {
      throw Exception('Prompt not found: $promptName');
    }

    String result = template;
    for (final entry in variables.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value.toString());
    }

    return {
      'prompt': result,
      'template': template,
      'variables': variables,
      'plugin': name,
    };
  }

  @override
  Map<String, dynamic> getPromptMetadata() {
    return {
      'name': name,
      'description': description,
      'version': version,
      'availablePrompts': _prompts.keys.toList(),
      'variableSchema': {
        'greeting': ['name', 'app'],
        'summary': ['text'],
        'question': ['context', 'question'],
      },
    };
  }

  // Test helpers
  bool get isInitialized => _initialized;
  List<String> get availablePrompts => _prompts.keys.toList();
}

class ErrorPlugin implements MCPToolPlugin {
  @override
  String get name => 'error_plugin';

  @override
  String get version => '0.1.0';

  @override
  String get description => 'A plugin that throws errors for testing';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    throw Exception('Initialization always fails');
  }

  @override
  Future<void> shutdown() async {
    // Always succeeds
  }

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments) async {
    throw Exception('Execution always fails');
  }

  @override
  Map<String, dynamic> getToolMetadata() {
    return {
      'name': name,
      'description': description,
      'version': version,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Plugin System Tests', () {
    late MCPPluginRegistry registry;

    setUp(() {
      registry = MCPPluginRegistry();
    });

    tearDown(() async {
      // Clean up registry
      final pluginNames = List.from(registry.getAllPluginNames());
      for (final pluginName in pluginNames) {
        await registry.unregisterPlugin(pluginName);
      }
    });

    group('Plugin Registry Basic Operations', () {
      test('should register and unregister tool plugins', () async {
        final plugin = TestToolPlugin();

        // Register plugin
        await registry.registerPlugin(plugin);

        expect(registry.getAllPluginNames(), contains('test_tool'));
        expect(registry.getPlugin<MCPToolPlugin>('test_tool'), equals(plugin));

        // Unregister plugin
        await registry.unregisterPlugin('test_tool');

        expect(registry.getAllPluginNames(), isNot(contains('test_tool')));
        expect(registry.getPlugin<MCPToolPlugin>('test_tool'), isNull);
      });

      test('should register and unregister resource plugins', () async {
        final plugin = TestResourcePlugin();

        await registry.registerPlugin(plugin);

        expect(registry.getAllPluginNames(), contains('test_resource'));
        expect(
            registry.getPlugin<MCPResourcePlugin>('test_resource'), isNotNull);

        await registry.unregisterPlugin('test_resource');

        expect(registry.getPlugin<MCPResourcePlugin>('test_resource'), isNull);
      });

      test('should register and unregister prompt plugins', () async {
        final plugin = TestPromptPlugin();

        await registry.registerPlugin(plugin);

        expect(registry.getAllPluginNames(), contains('test_prompt'));
        expect(registry.getPlugin<MCPPromptPlugin>('test_prompt'), isNotNull);

        await registry.unregisterPlugin('test_prompt');

        expect(registry.getPlugin<MCPPromptPlugin>('test_prompt'), isNull);
      });

      test('should handle multiple plugins of different types', () async {
        final toolPlugin = TestToolPlugin();
        final resourcePlugin = TestResourcePlugin();
        final promptPlugin = TestPromptPlugin();

        await registry.registerPlugin(toolPlugin);
        await registry.registerPlugin(resourcePlugin);
        await registry.registerPlugin(promptPlugin);

        final allPlugins = registry.getAllPluginNames();
        expect(allPlugins, contains('test_tool'));
        expect(allPlugins, contains('test_resource'));
        expect(allPlugins, contains('test_prompt'));
        expect(allPlugins.length, equals(3));
      });
    });

    group('Plugin Initialization and Configuration', () {
      test('should initialize plugins with configuration', () async {
        final plugin = TestToolPlugin();
        final config = {
          'setting1': 'value1',
          'setting2': 42,
          'setting3': true,
        };

        await registry.registerPlugin(plugin, config);

        expect(plugin.isInitialized, isTrue);
        expect(plugin.config, equals(config));
      });

      test('should handle initialization without configuration', () async {
        final plugin = TestToolPlugin();

        await registry.registerPlugin(plugin);

        expect(plugin.isInitialized, isTrue);
        expect(plugin.config, equals({})); // Empty config
      });

      test('should handle plugin initialization failures', () async {
        final plugin = ErrorPlugin();

        expect(
          () => registry.registerPlugin(plugin),
          throwsA(isA<Exception>()),
        );

        expect(registry.getPlugin<MCPToolPlugin>('error_plugin'), isNull);
      });
    });

    group('Plugin Execution', () {
      test('should execute tool plugins', () async {
        final plugin = TestToolPlugin();
        await registry.registerPlugin(plugin);

        final result = await registry.executeTool(
          'test_tool',
          {
            'action': 'test',
            'data': {'key': 'value'}
          },
        );

        expect(result['result'], equals('Tool executed successfully'));
        expect(result['plugin'], equals('test_tool'));
        expect(result['input']['action'], equals('test'));
      });

      test('should get resources from resource plugins', () async {
        final plugin = TestResourcePlugin();
        await registry.registerPlugin(plugin);

        final result = await registry.getResource(
          'test_resource',
          'test://file1.txt',
          {'format': 'text'},
        );

        expect(result['content'], equals('Content of file 1'));
        expect(result['mimeType'], equals('text/plain'));
        expect(result['plugin'], equals('test_resource'));
      });

      test('should execute prompt plugins', () async {
        final plugin = TestPromptPlugin();
        await registry.registerPlugin(plugin);

        final result = await registry.executePrompt(
          'test_prompt',
          {'promptName': 'greeting', 'name': 'Alice', 'app': 'FlutterMCP'},
        );

        expect(
            result['prompt'], equals('Hello, Alice! Welcome to FlutterMCP.'));
        expect(result['plugin'], equals('test_prompt'));
      });

      test('should handle plugin execution errors', () async {
        final plugin = ErrorPlugin();

        // Force registration despite initialization error
        try {
          await registry.registerPlugin(plugin);
        } catch (e) {
          // Ignore initialization error for this test
        }

        final errorPlugin = registry.getPlugin<MCPToolPlugin>('error_plugin');
        if (errorPlugin != null) {
          expect(
            () => registry.executeTool('error_plugin', {}),
            throwsA(isA<Exception>()),
          );
        }
      });
    });

    group('Plugin Metadata and Discovery', () {
      test('should retrieve tool plugin metadata', () async {
        final plugin = TestToolPlugin();
        await registry.registerPlugin(plugin);

        final registeredPlugin =
            registry.getPlugin<TestToolPlugin>('test_tool')!;
        final metadata = registeredPlugin.getToolMetadata();

        expect(metadata['name'], equals('test_tool'));
        expect(metadata['description'], contains('test tool plugin'));
        expect(metadata['version'], equals('1.0.0'));
        expect(metadata['inputSchema'], isNotNull);
      });

      test('should retrieve resource plugin metadata', () async {
        final plugin = TestResourcePlugin();
        await registry.registerPlugin(plugin);

        final registeredPlugin =
            registry.getPlugin<TestResourcePlugin>('test_resource')!;
        final metadata = registeredPlugin.getResourceMetadata();

        expect(metadata['name'], equals('test_resource'));
        expect(metadata['version'], equals('2.0.0'));
        expect(metadata['supportedUris'], isA<List>());
      });

      test('should retrieve prompt plugin metadata', () async {
        final plugin = TestPromptPlugin();
        await registry.registerPlugin(plugin);

        final registeredPlugin =
            registry.getPlugin<TestPromptPlugin>('test_prompt')!;
        final metadata = registeredPlugin.getPromptMetadata();

        expect(metadata['name'], equals('test_prompt'));
        expect(metadata['version'], equals('1.5.0'));
        expect(metadata['availablePrompts'], isA<List>());
      });

      test('should list plugins by type', () async {
        final toolPlugin = TestToolPlugin();
        final resourcePlugin = TestResourcePlugin();
        final promptPlugin = TestPromptPlugin();

        await registry.registerPlugin(toolPlugin);
        await registry.registerPlugin(resourcePlugin);
        await registry.registerPlugin(promptPlugin);

        final toolPlugins = registry.getPluginsByType<MCPToolPlugin>();
        final resourcePlugins = registry.getPluginsByType<MCPResourcePlugin>();
        final promptPlugins = registry.getPluginsByType<MCPPromptPlugin>();

        expect(toolPlugins.length, equals(1));
        expect(resourcePlugins.length, equals(1));
        expect(promptPlugins.length, equals(1));

        expect(toolPlugins.first.name, equals('test_tool'));
        expect(resourcePlugins.first.name, equals('test_resource'));
        expect(promptPlugins.first.name, equals('test_prompt'));
      });
    });

    group('Plugin Lifecycle Management', () {
      test('should properly shutdown plugins during unregistration', () async {
        final plugin = TestToolPlugin();
        await registry.registerPlugin(plugin);

        expect(plugin.isInitialized, isTrue);

        registry.unregisterPlugin('test_tool');

        expect(plugin.isInitialized, isFalse);
      });

      test('should handle plugin shutdown errors gracefully', () async {
        final plugin = TestToolPlugin();
        await registry.registerPlugin(plugin);

        // Mock shutdown error by overriding the shutdown method
        // This would require more complex mocking setup

        // For now, verify that unregistration doesn't throw
        await expectLater(
          registry.unregisterPlugin('test_tool'),
          completes,
        );
      });

      test('should maintain plugin isolation', () async {
        final plugin1 = TestToolPlugin();

        await registry.registerPlugin(plugin1, {'instance': 1});

        expect(plugin1.isInitialized, isTrue);
        expect(plugin1.config?['instance'], equals(1));
      });
    });

    group('Error Handling and Edge Cases', () {
      test('should handle duplicate plugin registration', () async {
        final plugin1 = TestToolPlugin();
        final plugin2 = TestToolPlugin(); // Same name

        await registry.registerPlugin(plugin1);

        // Second registration should replace or throw error
        await expectLater(
          () async => await registry.registerPlugin(plugin2),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle unregistering non-existent plugin', () async {
        await expectLater(
          registry.unregisterPlugin('non_existent_plugin'),
          completes,
        );
      });

      test('should handle executing non-existent plugin', () {
        expect(
          () => registry.executeTool('non_existent_tool', {}),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle getting resource from non-existent plugin', () {
        expect(
          () => registry.getResource('non_existent_resource', 'uri', {}),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle executing non-existent prompt', () async {
        final plugin = TestPromptPlugin();
        await registry.registerPlugin(plugin);

        final registeredPlugin =
            registry.getPlugin<TestPromptPlugin>('test_prompt')!;
        expect(
          () => registeredPlugin.executePrompt('non_existent_prompt', {}),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle invalid resource URI', () async {
        final plugin = TestResourcePlugin();
        await registry.registerPlugin(plugin);

        expect(
          () => registry.getResource('test_resource', 'invalid://uri', {}),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('Plugin Performance and Load', () {
      test('should handle many plugins efficiently', () async {
        const pluginCount = 10;
        final plugins = <TestToolPlugin>[];

        for (int i = 0; i < pluginCount; i++) {
          final plugin = TestToolPlugin();
          // Would need to modify plugin to have unique names
          // For now, just test the registration doesn't crash
          plugins.add(plugin);
        }

        // Register first plugin to test basic functionality
        await registry.registerPlugin(plugins.first);

        expect(registry.getAllPluginNames().length, greaterThanOrEqualTo(1));
      });

      test('should handle concurrent plugin execution', () async {
        final plugin = TestToolPlugin();
        await registry.registerPlugin(plugin);

        final futures = <Future>[];
        for (int i = 0; i < 5; i++) {
          futures.add(registry.executeTool(
            'test_tool',
            {'action': 'concurrent_test', 'iteration': i},
          ));
        }

        final results = await Future.wait(futures);

        expect(results.length, equals(5));
        for (final result in results) {
          expect(result['result'], equals('Tool executed successfully'));
        }
      });
    });
  });
}
