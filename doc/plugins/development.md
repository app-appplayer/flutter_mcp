# Plugin Development Guide

This guide covers how to develop custom plugins for Flutter MCP.

## Overview

Flutter MCP plugins extend the core functionality by providing:
- Custom MCP tools
- Additional resources
- New prompt templates
- Background tasks
- Integration with external services
- Platform-specific features

## Getting Started

### Plugin Structure

A basic plugin project structure:

```
my_mcp_plugin/
├── lib/
│   ├── src/
│   │   ├── plugin.dart
│   │   ├── tools/
│   │   │   └── my_tool.dart
│   │   ├── resources/
│   │   │   └── my_resource.dart
│   │   └── config/
│   │       └── plugin_config.dart
│   └── my_mcp_plugin.dart
├── test/
│   └── plugin_test.dart
├── example/
│   └── main.dart
├── pubspec.yaml
├── README.md
├── CHANGELOG.md
└── LICENSE
```

### Basic Plugin Implementation

```dart
// lib/src/plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class MyCustomPlugin extends MCPPlugin {
  @override
  String get id => 'my_custom_plugin';
  
  @override
  String get name => 'My Custom Plugin';
  
  @override
  String get version => '1.0.0';
  
  @override
  String get description => 'A custom MCP plugin';
  
  @override
  List<String> get dependencies => [];
  
  @override
  Map<String, dynamic> get defaultConfig => {
    'apiKey': null,
    'timeout': 30000,
    'retryCount': 3,
  };
  
  @override
  Future<void> initialize(PluginContext context) async {
    context.logger.info('Initializing $name');
    
    // Validate configuration
    final config = context.config;
    if (config['apiKey'] == null) {
      throw PluginConfigException('API key is required');
    }
    
    // Initialize plugin resources
    await _initializeServices(config);
    
    // Register event listeners
    _setupEventListeners(context);
  }
  
  @override
  Future<void> dispose() async {
    context.logger.info('Disposing $name');
    // Clean up resources
    await _cleanup();
  }
  
  // Lifecycle callbacks
  @override
  void onStart() {
    context.logger.debug('Plugin started');
  }
  
  @override
  void onStop() {
    context.logger.debug('Plugin stopped');
  }
}
```

## Plugin Types

### Tool Plugin

Provides MCP tools that can be called by clients.

```dart
class CalculatorPlugin extends MCPToolPlugin {
  @override
  String get id => 'calculator';
  
  @override
  List<Tool> getTools() {
    return [
      Tool(
        name: 'calculate',
        description: 'Perform mathematical calculations',
        inputSchema: {
          'type': 'object',
          'properties': {
            'expression': {
              'type': 'string',
              'description': 'Mathematical expression to evaluate',
            },
          },
          'required': ['expression'],
        },
      ),
      Tool(
        name: 'convert_units',
        description: 'Convert between different units',
        inputSchema: {
          'type': 'object',
          'properties': {
            'value': {'type': 'number'},
            'from': {'type': 'string'},
            'to': {'type': 'string'},
          },
          'required': ['value', 'from', 'to'],
        },
      ),
    ];
  }
  
  @override
  Future<CallToolResult> executeTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    switch (toolName) {
      case 'calculate':
        return _calculate(arguments);
      case 'convert_units':
        return _convertUnits(arguments);
      default:
        throw ToolNotFoundException('Unknown tool: $toolName');
    }
  }
  
  Future<CallToolResult> _calculate(Map<String, dynamic> args) async {
    final expression = args['expression'] as String;
    
    try {
      final result = _evaluateExpression(expression);
      return CallToolResult(
        content: [
          TextContent(text: result.toString()),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(text: 'Error: ${e.toString()}'),
        ],
        isError: true,
      );
    }
  }
}
```

### Resource Plugin

Provides access to resources like files, databases, or APIs.

```dart
class DatabasePlugin extends MCPResourcePlugin {
  late final Database _database;
  
  @override
  String get id => 'database';
  
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    final dbPath = context.config['databasePath'] as String;
    _database = await openDatabase(dbPath);
  }
  
  @override
  List<Resource> getResources() {
    return [
      Resource(
        uri: 'db://users',
        name: 'Users Table',
        mimeType: 'application/json',
        description: 'Access to users table',
      ),
      Resource(
        uri: 'db://products',
        name: 'Products Table',
        mimeType: 'application/json',
        description: 'Access to products table',
      ),
    ];
  }
  
  @override
  Future<ResourceContent> readResource(String uri) async {
    final parts = uri.split('://');
    if (parts[0] != 'db') {
      throw ResourceNotFoundException('Invalid URI scheme');
    }
    
    final table = parts[1];
    final query = 'SELECT * FROM $table';
    final results = await _database.rawQuery(query);
    
    return ResourceContent(
      uri: uri,
      mimeType: 'application/json',
      text: json.encode(results),
    );
  }
  
  @override
  Future<void> writeResource(String uri, ResourceContent content) async {
    // Implement write logic if needed
    throw UnsupportedError('Write not supported');
  }
  
  @override
  Stream<ResourceEvent> watchResource(String uri) {
    // Implement resource watching
    return Stream.periodic(Duration(seconds: 5))
        .map((_) => ResourceChangedEvent(uri: uri));
  }
}
```

### Prompt Plugin

Provides prompt templates for LLMs.

```dart
class CodeGeneratorPlugin extends MCPPromptPlugin {
  @override
  String get id => 'code_generator';
  
  @override
  List<Prompt> getPrompts() {
    return [
      Prompt(
        name: 'generate_flutter_widget',
        description: 'Generate a Flutter widget',
        arguments: [
          PromptArgument(
            name: 'widgetName',
            description: 'Name of the widget',
            required: true,
          ),
          PromptArgument(
            name: 'description',
            description: 'Widget description',
            required: true,
          ),
          PromptArgument(
            name: 'stateful',
            description: 'Whether widget is stateful',
            required: false,
          ),
        ],
      ),
      Prompt(
        name: 'generate_api_client',
        description: 'Generate an API client',
        arguments: [
          PromptArgument(
            name: 'baseUrl',
            description: 'API base URL',
            required: true,
          ),
          PromptArgument(
            name: 'endpoints',
            description: 'List of endpoints',
            required: true,
          ),
        ],
      ),
    ];
  }
  
  @override
  Future<PromptContent> getPrompt(
    String name,
    Map<String, dynamic>? arguments,
  ) async {
    switch (name) {
      case 'generate_flutter_widget':
        return _generateWidgetPrompt(arguments!);
      case 'generate_api_client':
        return _generateApiClientPrompt(arguments!);
      default:
        throw PromptNotFoundException('Unknown prompt: $name');
    }
  }
  
  PromptContent _generateWidgetPrompt(Map<String, dynamic> args) {
    final widgetName = args['widgetName'] as String;
    final description = args['description'] as String;
    final isStateful = args['stateful'] as bool? ?? false;
    
    return PromptContent(
      messages: [
        Message(
          role: MessageRole.system,
          content: 'You are a Flutter expert developer.',
        ),
        Message(
          role: MessageRole.user,
          content: '''
Generate a Flutter ${isStateful ? 'stateful' : 'stateless'} widget named $widgetName.
Description: $description

Requirements:
- Follow Flutter best practices
- Include proper documentation
- Add error handling
- Make it reusable
''',
        ),
      ],
    );
  }
}
```

### Background Plugin

Provides background task execution.

```dart
class SyncPlugin extends MCPBackgroundPlugin {
  @override
  String get id => 'sync';
  
  @override
  void registerTasks(BackgroundTaskRegistry registry) {
    registry.register(
      taskId: 'sync_data',
      handler: () => _syncData(),
      config: TaskConfig(
        requiresNetwork: true,
        minInterval: Duration(minutes: 30),
      ),
    );
    
    registry.register(
      taskId: 'cleanup_cache',
      handler: () => _cleanupCache(),
      config: TaskConfig(
        requiresNetwork: false,
        minInterval: Duration(hours: 24),
      ),
    );
  }
  
  @override
  Future<void> executeTask(String taskId) async {
    context.logger.info('Executing task: $taskId');
    
    switch (taskId) {
      case 'sync_data':
        await _syncData();
        break;
      case 'cleanup_cache':
        await _cleanupCache();
        break;
      default:
        throw TaskNotFoundException('Unknown task: $taskId');
    }
  }
  
  Future<void> _syncData() async {
    // Implement data synchronization
    final localData = await _getLocalData();
    final remoteData = await _fetchRemoteData();
    
    await _mergeData(localData, remoteData);
    
    context.eventBus.publish(SyncCompletedEvent(
      itemsSynced: localData.length,
    ));
  }
  
  Future<void> _cleanupCache() async {
    // Implement cache cleanup
    final cacheDir = await getCacheDirectory();
    final files = cacheDir.listSync();
    
    for (final file in files) {
      final lastModified = file.statSync().modified;
      if (DateTime.now().difference(lastModified).inDays > 7) {
        file.deleteSync();
      }
    }
  }
}
```

## Plugin Configuration

### Configuration Schema

Define configuration requirements for your plugin.

```dart
class WeatherPlugin extends MCPPlugin {
  @override
  PluginConfigSchema get configSchema => PluginConfigSchema(
    fields: {
      'apiKey': ConfigField(
        name: 'apiKey',
        type: 'string',
        required: true,
        description: 'Weather API key',
      ),
      'updateInterval': ConfigField(
        name: 'updateInterval',
        type: 'duration',
        defaultValue: Duration(minutes: 30),
        description: 'Weather update interval',
      ),
      'units': ConfigField(
        name: 'units',
        type: 'string',
        defaultValue: 'metric',
        allowedValues: ['metric', 'imperial'],
        description: 'Temperature units',
      ),
      'cacheSize': ConfigField(
        name: 'cacheSize',
        type: 'int',
        defaultValue: 100,
        description: 'Maximum cache entries',
      ),
    },
  );
  
  @override
  Future<void> initialize(PluginContext context) async {
    // Validate configuration
    final errors = configSchema.validate(context.config);
    if (errors.isNotEmpty) {
      throw PluginConfigException(
        'Invalid configuration: ${errors.join(', ')}',
      );
    }
    
    // Access configuration
    final apiKey = context.config['apiKey'] as String;
    final updateInterval = context.config['updateInterval'] as Duration;
    final units = context.config['units'] as String;
    
    // Initialize with configuration
    await _initializeWeatherService(
      apiKey: apiKey,
      updateInterval: updateInterval,
      units: units,
    );
  }
}
```

### Configuration Loading

```dart
// From JSON file
final config = await PluginConfig.fromFile('config/weather.json');

// From code
final config = PluginConfig(
  pluginId: 'weather',
  config: {
    'apiKey': 'your-api-key',
    'updateInterval': Duration(minutes: 15),
    'units': 'metric',
  },
);

// From environment variables
final config = PluginConfig.fromEnvironment(
  pluginId: 'weather',
  mapping: {
    'apiKey': 'WEATHER_API_KEY',
    'units': 'WEATHER_UNITS',
  },
);
```

## Plugin Communication

### Event-Based Communication

Plugins communicate through the event bus.

```dart
// Define custom events
class WeatherUpdateEvent extends PluginEvent {
  final String location;
  final double temperature;
  final String condition;
  
  WeatherUpdateEvent({
    required this.location,
    required this.temperature,
    required this.condition,
  });
}

// Publish events
context.eventBus.publish(WeatherUpdateEvent(
  location: 'New York',
  temperature: 22.5,
  condition: 'Sunny',
));

// Subscribe to events
context.eventBus.on<WeatherUpdateEvent>().listen((event) {
  print('Weather update: ${event.location} - ${event.temperature}°C');
});

// Subscribe to specific plugin events
context.eventBus
    .on<PluginEvent>()
    .where((event) => event.source == 'weather')
    .listen((event) {
      // Handle weather plugin events
    });
```

### Direct Plugin Communication

```dart
class NotificationPlugin extends MCPPlugin {
  @override
  Future<void> initialize(PluginContext context) async {
    // Listen for weather updates
    final weatherPlugin = context.registry.getPlugin<WeatherPlugin>('weather');
    
    if (weatherPlugin != null) {
      // Direct method call
      final currentWeather = await weatherPlugin.getCurrentWeather();
      
      // Subscribe to weather events
      context.eventBus.on<WeatherUpdateEvent>().listen((event) {
        if (event.condition == 'Storm') {
          _showStormWarning(event.location);
        }
      });
    }
  }
  
  void _showStormWarning(String location) {
    context.mcp.notificationManager.show(
      id: 1,
      title: 'Storm Warning',
      body: 'Storm approaching $location',
    );
  }
}
```

## Plugin Testing

### Unit Testing

```dart
// test/plugin_test.dart
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:my_mcp_plugin/my_mcp_plugin.dart';

class MockPluginContext extends Mock implements PluginContext {}
class MockLogger extends Mock implements Logger {}

void main() {
  late MyCustomPlugin plugin;
  late MockPluginContext context;
  late MockLogger logger;
  
  setUp(() {
    plugin = MyCustomPlugin();
    context = MockPluginContext();
    logger = MockLogger();
    
    when(context.logger).thenReturn(logger);
    when(context.config).thenReturn({
      'apiKey': 'test-key',
    });
  });
  
  test('plugin initialization', () async {
    await plugin.initialize(context);
    
    expect(plugin.id, equals('my_custom_plugin'));
    verify(logger.info('Initializing My Custom Plugin')).called(1);
  });
  
  test('tool execution', () async {
    if (plugin is MCPToolPlugin) {
      final result = await plugin.executeTool(
        'my_tool',
        {'input': 'test'},
      );
      
      expect(result.content.first, isA<TextContent>());
    }
  });
}
```

### Integration Testing

```dart
// test/integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:my_mcp_plugin/my_mcp_plugin.dart';

void main() {
  late FlutterMCP mcp;
  late MyCustomPlugin plugin;
  
  setUpAll(() async {
    mcp = FlutterMCP();
    await mcp.initialize();
    
    plugin = MyCustomPlugin();
    await mcp.pluginRegistry.register(plugin);
  });
  
  tearDownAll(() async {
    await mcp.dispose();
  });
  
  test('plugin integration', () async {
    // Test plugin functionality within MCP
    final registeredPlugin = mcp.pluginRegistry.getPlugin('my_custom_plugin');
    expect(registeredPlugin, isNotNull);
    
    // Test tool execution
    if (plugin is MCPToolPlugin) {
      final tools = plugin.getTools();
      expect(tools, isNotEmpty);
      
      final result = await plugin.executeTool(
        tools.first.name,
        {'test': 'data'},
      );
      expect(result, isNotNull);
    }
  });
}
```

### Test Utilities

```dart
// Test harness for plugins
class PluginTestHarness {
  final MockPluginContext context;
  final MCPPlugin plugin;
  
  PluginTestHarness({
    required this.plugin,
    Map<String, dynamic>? config,
  }) : context = MockPluginContext() {
    when(context.config).thenReturn(config ?? {});
    when(context.logger).thenReturn(MockLogger());
    when(context.eventBus).thenReturn(MockEventBus());
  }
  
  Future<void> initialize() async {
    await plugin.initialize(context);
  }
  
  Future<void> dispose() async {
    await plugin.dispose();
  }
  
  void expectEvent<T extends Event>(bool Function(T) matcher) {
    verify(context.eventBus.publish(
      argThat(isA<T>().having((e) => matcher(e), 'matches', true)),
    ));
  }
}

// Usage
final harness = PluginTestHarness(
  plugin: WeatherPlugin(),
  config: {'apiKey': 'test-key'},
);

await harness.initialize();

// Test functionality
final result = await plugin.getWeather('London');
expect(result.temperature, isNotNull);

harness.expectEvent<WeatherUpdateEvent>(
  (e) => e.location == 'London',
);

await harness.dispose();
```

## Plugin Deployment

### Publishing to pub.dev

1. Prepare your plugin:
   ```yaml
   name: my_mcp_plugin
   version: 1.0.0
   description: A custom MCP plugin for Flutter
   homepage: https://github.com/yourusername/my_mcp_plugin
   repository: https://github.com/yourusername/my_mcp_plugin
   issue_tracker: https://github.com/yourusername/my_mcp_plugin/issues
   
   environment:
     sdk: '>=3.0.0 <4.0.0'
   
   dependencies:
     flutter_mcp: ^0.1.0
   
   dev_dependencies:
     test: ^1.24.0
     mockito: ^5.4.0
   ```

2. Add documentation:
   ```markdown
   # My MCP Plugin
   
   A custom MCP plugin that provides...
   
   ## Features
   
   - Feature 1
   - Feature 2
   
   ## Getting Started
   
   Add to your `pubspec.yaml`:
   
   ```yaml
   dependencies:
     my_mcp_plugin: ^1.0.0
   ```
   
   ## Usage
   
   ```dart
   import 'package:flutter_mcp/flutter_mcp.dart';
   import 'package:my_mcp_plugin/my_mcp_plugin.dart';
   
   final mcp = FlutterMCP();
   await mcp.initialize();
   
   final plugin = MyCustomPlugin();
   await mcp.pluginRegistry.register(plugin);
   ```
   ```

3. Publish:
   ```bash
   dart pub publish
   ```

### Local Installation

For development or private plugins:

```yaml
dependencies:
  my_mcp_plugin:
    path: ../my_mcp_plugin
```

Or from Git:

```yaml
dependencies:
  my_mcp_plugin:
    git:
      url: https://github.com/yourusername/my_mcp_plugin.git
      ref: main
```

## Best Practices

### 1. Error Handling

```dart
@override
Future<CallToolResult> executeTool(
  String toolName,
  Map<String, dynamic> arguments,
) async {
  try {
    // Validate arguments
    _validateArguments(toolName, arguments);
    
    // Execute tool
    final result = await _executeToolInternal(toolName, arguments);
    
    return CallToolResult(
      content: [TextContent(text: result)],
    );
  } on ToolException catch (e) {
    return CallToolResult(
      content: [TextContent(text: 'Tool error: ${e.message}')],
      isError: true,
    );
  } catch (e, stackTrace) {
    context.logger.error('Tool execution failed', e, stackTrace);
    return CallToolResult(
      content: [TextContent(text: 'Internal error: $e')],
      isError: true,
    );
  }
}
```

### 2. Resource Management

```dart
class DatabasePlugin extends MCPPlugin {
  Database? _database;
  Timer? _cleanupTimer;
  
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    // Initialize resources
    _database = await _openDatabase();
    
    // Set up periodic cleanup
    _cleanupTimer = Timer.periodic(
      Duration(minutes: 30),
      (_) => _performCleanup(),
    );
  }
  
  @override
  Future<void> dispose() async {
    // Clean up resources
    _cleanupTimer?.cancel();
    await _database?.close();
    
    super.dispose();
  }
}
```

### 3. Configuration Validation

```dart
@override
Future<void> initialize(PluginContext context) async {
  // Validate required configuration
  final apiKey = context.config['apiKey'] as String?;
  if (apiKey == null || apiKey.isEmpty) {
    throw PluginConfigException(
      'API key is required for $name',
    );
  }
  
  // Validate configuration types
  final timeout = context.config['timeout'];
  if (timeout != null && timeout is! int) {
    throw PluginConfigException(
      'Timeout must be an integer (milliseconds)',
    );
  }
  
  // Apply defaults
  final finalConfig = {
    ...defaultConfig,
    ...context.config,
  };
  
  await _initializeWithConfig(finalConfig);
}
```

### 4. Logging

```dart
class MyPlugin extends MCPPlugin {
  @override
  Future<void> initialize(PluginContext context) async {
    context.logger.info('Starting initialization');
    
    try {
      await _initialize();
      context.logger.info('Initialization complete');
    } catch (e, stackTrace) {
      context.logger.error(
        'Initialization failed',
        e,
        stackTrace,
      );
      rethrow;
    }
  }
  
  void _performOperation() {
    context.logger.debug('Performing operation');
    
    final startTime = DateTime.now();
    // ... operation ...
    final duration = DateTime.now().difference(startTime);
    
    context.logger.info(
      'Operation completed',
      data: {'duration': duration.inMilliseconds},
    );
  }
}
```

### 5. Testing

```dart
// Make your plugin testable
class WeatherPlugin extends MCPPlugin {
  final WeatherService weatherService;
  
  // Allow injection for testing
  WeatherPlugin({
    WeatherService? weatherService,
  }) : weatherService = weatherService ?? WeatherService();
  
  @override
  Future<void> initialize(PluginContext context) async {
    // Use injected service
    await weatherService.initialize(
      apiKey: context.config['apiKey'] as String,
    );
  }
}

// In tests
test('weather plugin with mock service', () async {
  final mockService = MockWeatherService();
  final plugin = WeatherPlugin(weatherService: mockService);
  
  when(mockService.getWeather(any))
      .thenAnswer((_) async => Weather(temperature: 20));
  
  // Test plugin behavior
});
```

## Example: Complete Plugin

Here's a complete example of a translation plugin:

```dart
// lib/src/translation_plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:translator/translator.dart';

class TranslationPlugin extends MCPToolPlugin {
  late final GoogleTranslator _translator;
  final Map<String, String> _cache = {};
  
  @override
  String get id => 'translator';
  
  @override
  String get name => 'Translation Plugin';
  
  @override
  String get version => '1.0.0';
  
  @override
  String get description => 'Provides text translation capabilities';
  
  @override
  Map<String, dynamic> get defaultConfig => {
    'cacheEnabled': true,
    'cacheSize': 1000,
    'defaultSourceLang': 'auto',
    'defaultTargetLang': 'en',
  };
  
  @override
  List<Tool> getTools() {
    return [
      Tool(
        name: 'translate',
        description: 'Translate text between languages',
        inputSchema: {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description': 'Text to translate',
            },
            'from': {
              'type': 'string',
              'description': 'Source language code (default: auto)',
            },
            'to': {
              'type': 'string',
              'description': 'Target language code',
            },
          },
          'required': ['text', 'to'],
        },
      ),
      Tool(
        name: 'detect_language',
        description: 'Detect the language of text',
        inputSchema: {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description': 'Text to analyze',
            },
          },
          'required': ['text'],
        },
      ),
    ];
  }
  
  @override
  Future<void> initialize(PluginContext context) async {
    await super.initialize(context);
    
    context.logger.info('Initializing translator');
    _translator = GoogleTranslator();
    
    // Set up cache cleanup
    if (context.config['cacheEnabled'] == true) {
      Timer.periodic(Duration(hours: 1), (_) => _cleanupCache());
    }
  }
  
  @override
  Future<CallToolResult> executeTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    try {
      switch (toolName) {
        case 'translate':
          return await _translate(arguments);
        case 'detect_language':
          return await _detectLanguage(arguments);
        default:
          throw ToolNotFoundException('Unknown tool: $toolName');
      }
    } catch (e) {
      context.logger.error('Tool execution failed', e);
      return CallToolResult(
        content: [
          TextContent(text: 'Error: ${e.toString()}'),
        ],
        isError: true,
      );
    }
  }
  
  Future<CallToolResult> _translate(Map<String, dynamic> args) async {
    final text = args['text'] as String;
    final from = args['from'] as String? ?? 'auto';
    final to = args['to'] as String;
    
    // Check cache
    final cacheKey = '$text|$from|$to';
    if (_cache.containsKey(cacheKey)) {
      return CallToolResult(
        content: [
          TextContent(text: _cache[cacheKey]!),
        ],
      );
    }
    
    // Translate
    final translation = await _translator.translate(
      text,
      from: from,
      to: to,
    );
    
    // Cache result
    if (context.config['cacheEnabled'] == true) {
      _cache[cacheKey] = translation.text;
      _trimCache();
    }
    
    // Publish event
    context.eventBus.publish(TranslationCompletedEvent(
      sourceText: text,
      translatedText: translation.text,
      sourceLang: from,
      targetLang: to,
    ));
    
    return CallToolResult(
      content: [
        TextContent(text: translation.text),
      ],
    );
  }
  
  Future<CallToolResult> _detectLanguage(Map<String, dynamic> args) async {
    final text = args['text'] as String;
    
    // Detect language
    final detection = await _translator.detectLanguage(text);
    
    return CallToolResult(
      content: [
        TextContent(
          text: json.encode({
            'language': detection.language,
            'confidence': detection.confidence,
          }),
        ),
      ],
    );
  }
  
  void _trimCache() {
    final maxSize = context.config['cacheSize'] as int;
    if (_cache.length > maxSize) {
      // Remove oldest entries
      final entriesToRemove = _cache.length - maxSize;
      final keys = _cache.keys.take(entriesToRemove).toList();
      keys.forEach(_cache.remove);
    }
  }
  
  void _cleanupCache() {
    context.logger.debug('Cleaning translation cache');
    _cache.clear();
  }
  
  @override
  Future<void> dispose() async {
    _cache.clear();
    await super.dispose();
  }
}

// Event definition
class TranslationCompletedEvent extends PluginEvent {
  final String sourceText;
  final String translatedText;
  final String sourceLang;
  final String targetLang;
  
  TranslationCompletedEvent({
    required this.sourceText,
    required this.translatedText,
    required this.sourceLang,
    required this.targetLang,
  });
}
```

## Next Steps

- [Plugin Lifecycle](lifecycle.md) - Understanding plugin lifecycle
- [Plugin Communication](communication.md) - Inter-plugin communication
- [Plugin Examples](examples.md) - More plugin examples
- [API Reference](../api/plugin-system.md) - Plugin system API