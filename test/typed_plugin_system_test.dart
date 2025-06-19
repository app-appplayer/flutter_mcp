import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/plugins/typed_plugin_system.dart';
import 'package:flutter_mcp/src/plugins/typed_plugin_interfaces.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'package:flutter_mcp/src/metrics/typed_metrics.dart';

void main() {
  group('Typed Plugin System Tests', () {
    late TypedPluginRegistry registry;

    setUp(() {
      registry = TypedPluginRegistry();
    });

    tearDown(() async {
      await registry.shutdownAll();
    });

    test('should register and unregister tool plugin', () async {
      final plugin = TestToolPlugin();
      final config = DefaultPluginConfig(name: plugin.name);

      // Register plugin
      final registerResult = await registry.registerPlugin(plugin, config);
      expect(registerResult.isSuccess, isTrue);
      expect(registerResult.data, equals('Plugin registered successfully'));

      // Verify plugin is registered
      final retrievedPlugin = registry.getPlugin<TypedToolPlugin>(plugin.name);
      expect(retrievedPlugin, isNotNull);
      expect(retrievedPlugin!.name, equals(plugin.name));

      // Check plugin list
      final allNames = registry.getAllPluginNames();
      expect(allNames, contains(plugin.name));

      // Unregister plugin
      final unregisterResult = await registry.unregisterPlugin(plugin.name);
      expect(unregisterResult.isSuccess, isTrue);

      // Verify plugin is removed
      final removedPlugin = registry.getPlugin<TypedToolPlugin>(plugin.name);
      expect(removedPlugin, isNull);
    });

    test('should execute tool plugin with validation', () async {
      final plugin = TestToolPlugin();
      final config = DefaultPluginConfig(name: plugin.name);

      await registry.registerPlugin(plugin, config);

      // Create valid request
      final request = ToolRequest(
        toolName: plugin.name,
        arguments: {'input': 'test'},
        context: PluginContext(
          requestId: 'test-request',
          pluginName: plugin.name,
          config: config,
        ),
        schema: plugin.inputSchema,
      );

      // Execute tool
      final response = await registry.executeTool(request);
      expect(response.result.isSuccess, isTrue);
      expect(response.toolName, equals(plugin.name));
      expect(response.executionTime.inMilliseconds, greaterThan(0));
    });

    test('should handle plugin validation errors', () async {
      final plugin = TestToolPlugin();
      final config = DefaultPluginConfig(name: plugin.name);

      await registry.registerPlugin(plugin, config);

      // Create invalid request (missing required field)
      final request = ToolRequest(
        toolName: plugin.name,
        arguments: {}, // Missing 'input' field
        context: PluginContext(
          requestId: 'test-request',
          pluginName: plugin.name,
          config: config,
        ),
        schema: plugin.inputSchema,
      );

      // Execute tool should fail validation
      final response = await registry.executeTool(request);
      expect(response.result.isSuccess, isFalse);
      expect(response.result.error, contains('Validation failed'));
    });

    test('should get plugin health status', () async {
      final plugin = TestToolPlugin();
      final config = DefaultPluginConfig(name: plugin.name);

      await registry.registerPlugin(plugin, config);

      final health = await registry.getPluginHealth(plugin.name);
      expect(health.isHealthy, isTrue);
      expect(health.status, equals(PluginStatus.active));
    });

    test('should track plugin metrics', () async {
      final plugin = TestToolPlugin();
      final config = DefaultPluginConfig(name: plugin.name);

      await registry.registerPlugin(plugin, config);

      // Execute tool to generate metrics
      final request = ToolRequest(
        toolName: plugin.name,
        arguments: {'input': 'test'},
        context: PluginContext(
          requestId: 'test-request',
          pluginName: plugin.name,
          config: config,
        ),
        schema: plugin.inputSchema,
      );

      await registry.executeTool(request);

      // Check metrics
      final metrics = registry.getPluginMetrics(plugin.name);
      expect(metrics.length, greaterThan(0));

      final initMetric =
          metrics.firstWhere((m) => m.name == 'plugin.initialization');
      expect(initMetric, isA<TimerMetric>());
      expect((initMetric as TimerMetric).success, isTrue);
    });

    test('should publish plugin lifecycle events', () async {
      final receivedEvents = <PluginLifecycleEvent>[];

      EventSystem.instance.subscribe<PluginLifecycleEvent>((event) {
        receivedEvents.add(event);
      });

      // Wait for subscription to be active
      await Future.delayed(Duration(milliseconds: 200));

      final plugin = TestToolPlugin();
      final config = DefaultPluginConfig(name: plugin.name);

      // Register plugin (should emit events)
      await registry.registerPlugin(plugin, config);

      // Allow events to propagate with increased delay
      await Future.delayed(Duration(milliseconds: 500));

      // Should have lifecycle events
      expect(receivedEvents.length, greaterThanOrEqualTo(2));

      final initEvent = receivedEvents.firstWhere(
        (e) => e.newStatus == PluginStatus.initializing,
      );
      expect(initEvent.pluginName, equals(plugin.name));
      expect(initEvent.oldStatus, equals(PluginStatus.uninitialized));

      final activeEvent = receivedEvents.firstWhere(
        (e) => e.newStatus == PluginStatus.active,
      );
      expect(activeEvent.pluginName, equals(plugin.name));
      expect(activeEvent.oldStatus, equals(PluginStatus.initializing));
    });

    test('should get plugins by type', () async {
      final toolPlugin = TestToolPlugin();
      final resourcePlugin = TestResourcePlugin();
      final toolConfig = DefaultPluginConfig(name: toolPlugin.name);
      final resourceConfig = DefaultPluginConfig(name: resourcePlugin.name);

      await registry.registerPlugin(toolPlugin, toolConfig);
      await registry.registerPlugin(resourcePlugin, resourceConfig);

      final toolPlugins = registry.getPluginsByType<TypedToolPlugin>();
      expect(toolPlugins.length, equals(1));
      expect(toolPlugins.first.name, equals(toolPlugin.name));

      final resourcePlugins = registry.getPluginsByType<TypedResourcePlugin>();
      expect(resourcePlugins.length, equals(1));
      expect(resourcePlugins.first.name, equals(resourcePlugin.name));
    });

    test('should handle duplicate plugin registration', () async {
      final plugin1 = TestToolPlugin();
      final plugin2 = TestToolPlugin(); // Same name
      final config = DefaultPluginConfig(name: plugin1.name);

      // Register first plugin
      final result1 = await registry.registerPlugin(plugin1, config);
      expect(result1.isSuccess, isTrue);

      // Try to register second plugin with same name
      final result2 = await registry.registerPlugin(plugin2, config);
      expect(result2.isSuccess, isFalse);
      expect(result2.error, contains('already registered'));
    });

    test('should shutdown all plugins', () async {
      final plugin1 = TestToolPlugin();
      final plugin2 = TestResourcePlugin();
      final config1 = DefaultPluginConfig(name: plugin1.name);
      final config2 = DefaultPluginConfig(name: plugin2.name);

      await registry.registerPlugin(plugin1, config1);
      await registry.registerPlugin(plugin2, config2);

      expect(registry.getAllPluginNames().length, equals(2));

      final shutdownResult = await registry.shutdownAll();
      expect(shutdownResult.isSuccess, isTrue);

      expect(registry.getAllPluginNames().length, equals(0));
    });
  });
}

/// Test tool plugin implementation
class TestToolPlugin extends TypedToolPlugin {
  @override
  final String name = 'test_tool';

  @override
  final String version = '1.0.0';

  @override
  final String description = 'Test tool plugin';

  @override
  final List<String> capabilities = ['execute'];

  @override
  PluginStatus status = PluginStatus.uninitialized;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        name: 'test_tool',
        description: 'Test tool schema',
        properties: {
          'input': PropertySchema(
            type: 'string',
            description: 'Input string',
          ),
        },
        required: ['input'],
      );

  @override
  ToolOutputSchema? get outputSchema => ToolOutputSchema(
        description: 'Test tool output',
        properties: {
          'result': PropertySchema(
            type: 'string',
            description: 'Processing result',
          ),
        },
      );

  @override
  Future<PluginResult<bool>> initialize(PluginContext context) async {
    await Future.delayed(Duration(milliseconds: 10)); // Simulate work
    status = PluginStatus.active;
    return SuccessResult<bool>(true);
  }

  @override
  Future<PluginResult<bool>> shutdown(PluginContext context) async {
    status = PluginStatus.inactive;
    return SuccessResult<bool>(true);
  }

  @override
  Future<PluginHealthStatus> getHealth() async {
    return PluginHealthStatus(
      status: status,
      isHealthy: status == PluginStatus.active,
      lastCheck: DateTime.now(),
    );
  }

  @override
  void onEvent(event) {
    // Handle events
  }

  @override
  Future<ToolResponse> execute(ToolRequest request) async {
    final input = request.arguments['input'] as String;
    final result = 'Processed: $input';

    return ToolResponse(
      toolName: name,
      result: SuccessResult<Map<String, dynamic>>({'result': result}),
      executionTime: Duration(milliseconds: 5),
    );
  }

  @override
  Future<List<ValidationError>> validateRequest(ToolRequest request) async {
    return request.validate();
  }
}

/// Test resource plugin implementation
class TestResourcePlugin extends TypedResourcePlugin {
  @override
  final String name = 'test_resource';

  @override
  final String version = '1.0.0';

  @override
  final String description = 'Test resource plugin';

  @override
  final List<String> capabilities = ['read'];

  @override
  PluginStatus status = PluginStatus.uninitialized;

  @override
  String get uriPattern => 'test://.*';

  @override
  ResourceInputSchema? get inputSchema => null;

  @override
  Future<PluginResult<bool>> initialize(PluginContext context) async {
    status = PluginStatus.active;
    return SuccessResult<bool>(true);
  }

  @override
  Future<PluginResult<bool>> shutdown(PluginContext context) async {
    status = PluginStatus.inactive;
    return SuccessResult<bool>(true);
  }

  @override
  Future<PluginHealthStatus> getHealth() async {
    return PluginHealthStatus(
      status: status,
      isHealthy: status == PluginStatus.active,
      lastCheck: DateTime.now(),
    );
  }

  @override
  void onEvent(event) {
    // Handle events
  }

  @override
  Future<ResourceResponse> getResource(ResourceRequest request) async {
    return ResourceResponse(
      resourceUri: request.resourceUri,
      content: TextContent('Test resource content'),
      mimeType: 'text/plain',
      retrievalTime: Duration(milliseconds: 5),
    );
  }

  @override
  Future<List<String>> listResources() async {
    return ['test://resource1', 'test://resource2'];
  }

  @override
  Future<bool> resourceExists(String uri) async {
    return uri.startsWith('test://');
  }
}
