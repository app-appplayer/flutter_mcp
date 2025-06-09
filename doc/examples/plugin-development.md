# Plugin Development Example

This example demonstrates how to create custom MCP plugins for tool, resource, and prompt capabilities.

## Overview

This example shows how to:
- Create custom tool plugins
- Implement resource plugins
- Build prompt plugins
- Register and manage plugins

## Plugin Types

### Tool Plugin Example

```dart
// lib/plugins/calculator_plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class CalculatorPlugin extends MCPToolPlugin {
  @override
  String get name => 'calculator';
  
  @override
  String get description => 'Basic calculator operations';
  
  @override
  List<Tool> get tools => [
    Tool(
      name: 'add',
      description: 'Add two numbers',
      schema: {
        'type': 'object',
        'properties': {
          'a': {'type': 'number', 'description': 'First number'},
          'b': {'type': 'number', 'description': 'Second number'},
        },
        'required': ['a', 'b'],
      },
      handler: _handleAdd,
    ),
    Tool(
      name: 'multiply',
      description: 'Multiply two numbers',
      schema: {
        'type': 'object',
        'properties': {
          'a': {'type': 'number', 'description': 'First number'},
          'b': {'type': 'number', 'description': 'Second number'},
        },
        'required': ['a', 'b'],
      },
      handler: _handleMultiply,
    ),
    Tool(
      name: 'calculate',
      description: 'Evaluate mathematical expression',
      schema: {
        'type': 'object',
        'properties': {
          'expression': {
            'type': 'string',
            'description': 'Mathematical expression to evaluate',
          },
        },
        'required': ['expression'],
      },
      handler: _handleCalculate,
    ),
  ];
  
  Future<dynamic> _handleAdd(Map<String, dynamic> params) async {
    final a = params['a'] as num;
    final b = params['b'] as num;
    return {'result': a + b};
  }
  
  Future<dynamic> _handleMultiply(Map<String, dynamic> params) async {
    final a = params['a'] as num;
    final b = params['b'] as num;
    return {'result': a * b};
  }
  
  Future<dynamic> _handleCalculate(Map<String, dynamic> params) async {
    final expression = params['expression'] as String;
    
    try {
      // Use expression parser library
      final parser = MathExpressionParser();
      final result = parser.evaluate(expression);
      return {'result': result};
    } catch (e) {
      throw MCPException('Invalid expression: $e');
    }
  }
  
  @override
  Future<void> onInitialize() async {
    // Initialize any resources
    logger.info('Calculator plugin initialized');
  }
  
  @override
  Future<void> onDispose() async {
    // Clean up resources
    logger.info('Calculator plugin disposed');
  }
}
```

### Resource Plugin Example

```dart
// lib/plugins/file_system_plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:io';

class FileSystemPlugin extends MCPResourcePlugin {
  @override
  String get name => 'filesystem';
  
  @override
  String get description => 'Access local file system resources';
  
  @override
  List<Resource> get resources => [
    Resource(
      uri: 'file:///*',
      name: 'Local Files',
      description: 'Access local file system',
      mimeType: '*/*',
    ),
  ];
  
  @override
  Future<ResourceContent> readResource(String uri) async {
    final fileUri = Uri.parse(uri);
    
    if (fileUri.scheme != 'file') {
      throw MCPException('Invalid URI scheme: ${fileUri.scheme}');
    }
    
    final file = File(fileUri.path);
    
    if (!await file.exists()) {
      throw MCPException('File not found: ${fileUri.path}');
    }
    
    final content = await file.readAsBytes();
    final mimeType = _getMimeType(fileUri.path);
    
    return ResourceContent(
      uri: uri,
      mimeType: mimeType,
      content: content,
      metadata: {
        'size': content.length,
        'lastModified': (await file.stat()).modified.toIso8601String(),
      },
    );
  }
  
  @override
  Future<List<Resource>> listResources(String? pattern) async {
    final resources = <Resource>[];
    
    if (pattern == null) {
      // Return root directory
      final homeDir = Directory.current;
      await for (final entity in homeDir.list()) {
        resources.add(_createResource(entity));
      }
    } else {
      // Use glob pattern matching
      final glob = Glob(pattern);
      await for (final entity in glob.list()) {
        resources.add(_createResource(entity));
      }
    }
    
    return resources;
  }
  
  @override
  Future<void> subscribeToResource(String uri, ResourceCallback callback) async {
    final fileUri = Uri.parse(uri);
    final file = File(fileUri.path);
    
    // Watch for file changes
    file.watch().listen((event) {
      callback(ResourceEvent(
        uri: uri,
        type: _mapEventType(event.type),
        timestamp: DateTime.now(),
      ));
    });
  }
  
  Resource _createResource(FileSystemEntity entity) {
    final isDirectory = entity is Directory;
    final uri = 'file://${entity.path}';
    
    return Resource(
      uri: uri,
      name: path.basename(entity.path),
      description: isDirectory ? 'Directory' : 'File',
      mimeType: isDirectory ? 'inode/directory' : _getMimeType(entity.path),
    );
  }
  
  String _getMimeType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    
    switch (extension) {
      case '.txt':
        return 'text/plain';
      case '.json':
        return 'application/json';
      case '.xml':
        return 'application/xml';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
  
  ResourceEventType _mapEventType(FileSystemEvent event) {
    if (event == FileSystemEvent.create) return ResourceEventType.created;
    if (event == FileSystemEvent.delete) return ResourceEventType.deleted;
    if (event == FileSystemEvent.modify) return ResourceEventType.modified;
    return ResourceEventType.unknown;
  }
}
```

### Prompt Plugin Example

```dart
// lib/plugins/code_generator_plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class CodeGeneratorPlugin extends MCPPromptPlugin {
  @override
  String get name => 'code_generator';
  
  @override
  String get description => 'Generate code based on templates';
  
  @override
  List<PromptTemplate> get prompts => [
    PromptTemplate(
      name: 'flutter_widget',
      description: 'Generate a Flutter widget',
      template: '''
Generate a Flutter widget with the following specifications:
- Widget name: {{widget_name}}
- Type: {{widget_type}} (Stateless/Stateful)
- Properties: {{properties}}
- Description: {{description}}

Include:
- Proper imports
- Documentation comments
- Property validation
- Build method implementation
''',
      arguments: [
        PromptArgument(
          name: 'widget_name',
          description: 'Name of the widget class',
          required: true,
        ),
        PromptArgument(
          name: 'widget_type',
          description: 'Type of widget (Stateless or Stateful)',
          required: true,
          defaultValue: 'Stateless',
          allowedValues: ['Stateless', 'Stateful'],
        ),
        PromptArgument(
          name: 'properties',
          description: 'List of widget properties',
          required: false,
        ),
        PromptArgument(
          name: 'description',
          description: 'Widget description',
          required: false,
        ),
      ],
    ),
    PromptTemplate(
      name: 'api_client',
      description: 'Generate API client code',
      template: '''
Generate an API client for the following endpoint:
- Base URL: {{base_url}}
- Endpoints: {{endpoints}}
- Authentication: {{auth_type}}

Include:
- Error handling
- Retry logic
- Request/response models
- Proper typing
''',
      arguments: [
        PromptArgument(
          name: 'base_url',
          description: 'API base URL',
          required: true,
        ),
        PromptArgument(
          name: 'endpoints',
          description: 'List of API endpoints',
          required: true,
        ),
        PromptArgument(
          name: 'auth_type',
          description: 'Authentication type',
          required: false,
          defaultValue: 'bearer',
          allowedValues: ['none', 'bearer', 'api_key', 'oauth2'],
        ),
      ],
    ),
  ];
  
  @override
  Future<String> renderPrompt(String templateName, Map<String, dynamic> arguments) async {
    final template = prompts.firstWhere((p) => p.name == templateName);
    
    // Validate required arguments
    for (final arg in template.arguments) {
      if (arg.required && !arguments.containsKey(arg.name)) {
        throw MCPException('Missing required argument: ${arg.name}');
      }
    }
    
    // Render template with arguments
    var rendered = template.template;
    
    for (final entry in arguments.entries) {
      rendered = rendered.replaceAll('{{${entry.key}}}', entry.value.toString());
    }
    
    // Replace any remaining placeholders with defaults
    for (final arg in template.arguments) {
      if (arg.defaultValue != null) {
        rendered = rendered.replaceAll('{{${arg.name}}}', arg.defaultValue!);
      }
    }
    
    return rendered;
  }
  
  @override
  Future<Map<String, dynamic>> executePrompt(
    String templateName, 
    Map<String, dynamic> arguments,
  ) async {
    final prompt = await renderPrompt(templateName, arguments);
    
    // Execute with LLM
    final llm = await LLMManager.getDefaultLLM();
    final response = await llm.complete(prompt);
    
    // Post-process response based on template
    switch (templateName) {
      case 'flutter_widget':
        return _processWidgetGeneration(response, arguments);
      case 'api_client':
        return _processAPIClientGeneration(response, arguments);
      default:
        return {'code': response};
    }
  }
  
  Map<String, dynamic> _processWidgetGeneration(
    String response, 
    Map<String, dynamic> arguments,
  ) {
    // Extract code blocks
    final codePattern = RegExp(r'```dart\n([\s\S]*?)\n```');
    final matches = codePattern.allMatches(response);
    
    if (matches.isEmpty) {
      return {'code': response};
    }
    
    final code = matches.first.group(1)!;
    final widgetName = arguments['widget_name'];
    
    // Create file structure
    return {
      'files': {
        'lib/widgets/${_toSnakeCase(widgetName)}.dart': code,
      },
      'instructions': 'Widget generated successfully. Add to your project.',
    };
  }
  
  Map<String, dynamic> _processAPIClientGeneration(
    String response, 
    Map<String, dynamic> arguments,
  ) {
    // Parse generated code structure
    final files = <String, String>{};
    
    // Extract different sections
    final sections = response.split('---FILE:');
    
    for (final section in sections.skip(1)) {
      final lines = section.trim().split('\n');
      if (lines.isEmpty) continue;
      
      final filename = lines.first.trim();
      final content = lines.skip(1).join('\n');
      
      files[filename] = content;
    }
    
    return {
      'files': files,
      'instructions': 'API client generated. Review and adjust as needed.',
    };
  }
  
  String _toSnakeCase(String camelCase) {
    return camelCase
        .replaceAllMapped(
          RegExp(r'([A-Z])'),
          (match) => '_${match.group(1)!.toLowerCase()}',
        )
        .substring(1);
  }
}
```

### Composite Plugin Example

```dart
// lib/plugins/database_plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:sqflite/sqflite.dart';

class DatabasePlugin extends MCPPlugin
    implements MCPToolPlugin, MCPResourcePlugin {
  late Database _database;
  
  @override
  String get name => 'database';
  
  @override
  String get description => 'SQLite database operations';
  
  // Tool implementation
  @override
  List<Tool> get tools => [
    Tool(
      name: 'query',
      description: 'Execute SQL query',
      schema: {
        'type': 'object',
        'properties': {
          'sql': {'type': 'string', 'description': 'SQL query'},
          'params': {
            'type': 'array',
            'description': 'Query parameters',
            'items': {'type': 'any'},
          },
        },
        'required': ['sql'],
      },
      handler: _handleQuery,
    ),
    Tool(
      name: 'execute',
      description: 'Execute SQL statement',
      schema: {
        'type': 'object',
        'properties': {
          'sql': {'type': 'string', 'description': 'SQL statement'},
          'params': {
            'type': 'array',
            'description': 'Statement parameters',
            'items': {'type': 'any'},
          },
        },
        'required': ['sql'],
      },
      handler: _handleExecute,
    ),
  ];
  
  // Resource implementation
  @override
  List<Resource> get resources => [
    Resource(
      uri: 'db://main/tables',
      name: 'Database Tables',
      description: 'List of database tables',
      mimeType: 'application/json',
    ),
    Resource(
      uri: 'db://main/schema',
      name: 'Database Schema',
      description: 'Complete database schema',
      mimeType: 'application/json',
    ),
  ];
  
  @override
  Future<void> onInitialize() async {
    // Open database
    _database = await openDatabase(
      'app_database.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }
  
  @override
  Future<void> onDispose() async {
    await _database.close();
  }
  
  Future<dynamic> _handleQuery(Map<String, dynamic> params) async {
    final sql = params['sql'] as String;
    final queryParams = params['params'] as List<dynamic>? ?? [];
    
    try {
      final results = await _database.rawQuery(sql, queryParams);
      return {
        'rows': results,
        'count': results.length,
      };
    } catch (e) {
      throw MCPException('Query failed: $e');
    }
  }
  
  Future<dynamic> _handleExecute(Map<String, dynamic> params) async {
    final sql = params['sql'] as String;
    final queryParams = params['params'] as List<dynamic>? ?? [];
    
    try {
      final rowsAffected = await _database.rawUpdate(sql, queryParams);
      return {
        'rowsAffected': rowsAffected,
        'success': true,
      };
    } catch (e) {
      throw MCPException('Execute failed: $e');
    }
  }
  
  @override
  Future<ResourceContent> readResource(String uri) async {
    final parsedUri = Uri.parse(uri);
    
    switch (parsedUri.path) {
      case '/tables':
        final tables = await _getTables();
        return ResourceContent(
          uri: uri,
          mimeType: 'application/json',
          content: jsonEncode(tables).codeUnits,
        );
        
      case '/schema':
        final schema = await _getSchema();
        return ResourceContent(
          uri: uri,
          mimeType: 'application/json',
          content: jsonEncode(schema).codeUnits,
        );
        
      default:
        throw MCPException('Unknown resource: $uri');
    }
  }
  
  @override
  Future<List<Resource>> listResources(String? pattern) async {
    return resources;
  }
  
  @override
  Future<void> subscribeToResource(String uri, ResourceCallback callback) async {
    // Not implemented for this example
  }
  
  Future<List<String>> _getTables() async {
    final results = await _database.query(
      'sqlite_master',
      where: 'type = ?',
      whereArgs: ['table'],
    );
    
    return results.map((r) => r['name'] as String).toList();
  }
  
  Future<Map<String, dynamic>> _getSchema() async {
    final tables = await _getTables();
    final schema = <String, dynamic>{};
    
    for (final table in tables) {
      final columns = await _database.rawQuery(
        'PRAGMA table_info($table)',
      );
      
      schema[table] = columns.map((col) => {
        'name': col['name'],
        'type': col['type'],
        'notNull': col['notnull'] == 1,
        'defaultValue': col['dflt_value'],
        'primaryKey': col['pk'] == 1,
      }).toList();
    }
    
    return schema;
  }
}
```

## Plugin Registration

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'plugins/calculator_plugin.dart';
import 'plugins/file_system_plugin.dart';
import 'plugins/code_generator_plugin.dart';
import 'plugins/database_plugin.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize MCP
  await FlutterMCP.initialize(MCPConfig(
    servers: {
      'plugin-server': ServerConfig(
        uri: 'ws://localhost:3000',
      ),
    },
  ));
  
  // Register plugins
  final pluginSystem = FlutterMCP.pluginSystem;
  
  await pluginSystem.register(CalculatorPlugin());
  await pluginSystem.register(FileSystemPlugin());
  await pluginSystem.register(CodeGeneratorPlugin());
  await pluginSystem.register(DatabasePlugin());
  
  // Initialize all plugins
  await pluginSystem.initialize();
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Plugin Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: PluginDemoScreen(),
    );
  }
}
```

## Plugin Demo UI

```dart
// lib/screens/plugin_demo_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class PluginDemoScreen extends StatefulWidget {
  @override
  _PluginDemoScreenState createState() => _PluginDemoScreenState();
}

class _PluginDemoScreenState extends State<PluginDemoScreen> {
  final _pluginSystem = FlutterMCP.pluginSystem;
  String _result = '';
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Plugin Demo'),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildPluginCard(
            'Calculator Plugin',
            'Basic math operations',
            [
              ElevatedButton(
                onPressed: () => _testCalculator(),
                child: Text('Test Calculator'),
              ),
            ],
          ),
          _buildPluginCard(
            'File System Plugin',
            'Access local files',
            [
              ElevatedButton(
                onPressed: () => _testFileSystem(),
                child: Text('List Files'),
              ),
            ],
          ),
          _buildPluginCard(
            'Code Generator Plugin',
            'Generate code from templates',
            [
              ElevatedButton(
                onPressed: () => _testCodeGenerator(),
                child: Text('Generate Widget'),
              ),
            ],
          ),
          _buildPluginCard(
            'Database Plugin',
            'SQLite database operations',
            [
              ElevatedButton(
                onPressed: () => _testDatabase(),
                child: Text('Query Database'),
              ),
            ],
          ),
          SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Result',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 8),
                  Text(_result.isEmpty ? 'No result yet' : _result),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPluginCard(
    String title,
    String description,
    List<Widget> actions,
  ) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _testCalculator() async {
    try {
      final result = await _pluginSystem.executeTool(
        'calculator',
        'add',
        {'a': 10, 'b': 20},
      );
      
      setState(() {
        _result = 'Calculator result: ${result['result']}';
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    }
  }
  
  Future<void> _testFileSystem() async {
    try {
      final plugin = _pluginSystem.getPlugin('filesystem') as MCPResourcePlugin;
      final resources = await plugin.listResources('*.txt');
      
      setState(() {
        _result = 'Found ${resources.length} text files:\n' +
            resources.map((r) => '- ${r.name}').join('\n');
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    }
  }
  
  Future<void> _testCodeGenerator() async {
    try {
      final plugin = _pluginSystem.getPlugin('code_generator') as MCPPromptPlugin;
      
      final result = await plugin.executePrompt(
        'flutter_widget',
        {
          'widget_name': 'CustomButton',
          'widget_type': 'Stateless',
          'properties': 'onPressed, label, color',
          'description': 'A custom button widget',
        },
      );
      
      setState(() {
        _result = 'Generated files:\n' +
            (result['files'] as Map<String, dynamic>)
                .keys
                .map((f) => '- $f')
                .join('\n');
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    }
  }
  
  Future<void> _testDatabase() async {
    try {
      final result = await _pluginSystem.executeTool(
        'database',
        'query',
        {'sql': 'SELECT name FROM sqlite_master WHERE type="table"'},
      );
      
      setState(() {
        _result = 'Database tables:\n' +
            (result['rows'] as List)
                .map((r) => '- ${r['name']}')
                .join('\n');
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    }
  }
}
```

## Testing Plugins

```dart
// test/plugin_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp_test/flutter_mcp_test.dart';

void main() {
  group('Plugin Tests', () {
    late PluginSystem pluginSystem;
    
    setUp(() {
      pluginSystem = PluginSystem();
    });
    
    test('registers and initializes plugin', () async {
      final plugin = CalculatorPlugin();
      
      await pluginSystem.register(plugin);
      await pluginSystem.initialize();
      
      expect(pluginSystem.getPlugin('calculator'), same(plugin));
    });
    
    test('executes tool plugin method', () async {
      final plugin = CalculatorPlugin();
      await pluginSystem.register(plugin);
      await pluginSystem.initialize();
      
      final result = await pluginSystem.executeTool(
        'calculator',
        'add',
        {'a': 5, 'b': 3},
      );
      
      expect(result['result'], equals(8));
    });
    
    test('handles plugin errors', () async {
      final plugin = CalculatorPlugin();
      await pluginSystem.register(plugin);
      await pluginSystem.initialize();
      
      expect(
        () => pluginSystem.executeTool(
          'calculator',
          'calculate',
          {'expression': 'invalid'},
        ),
        throwsA(isA<MCPException>()),
      );
    });
    
    test('lists resources from resource plugin', () async {
      // Mock file system
      MCPTestEnvironment.mockFileSystem({
        '/home/user/file1.txt': 'content1',
        '/home/user/file2.txt': 'content2',
        '/home/user/image.png': [0, 1, 2, 3],
      });
      
      final plugin = FileSystemPlugin();
      await pluginSystem.register(plugin);
      await pluginSystem.initialize();
      
      final resources = await plugin.listResources('*.txt');
      
      expect(resources.length, equals(2));
      expect(
        resources.map((r) => r.name),
        containsAll(['file1.txt', 'file2.txt']),
      );
    });
  });
}
```

## Best Practices

### Plugin Design

1. **Single Responsibility**: Each plugin should have a focused purpose
2. **Error Handling**: Handle errors gracefully and provide meaningful messages
3. **Resource Management**: Clean up resources in `onDispose`
4. **Documentation**: Document all tools, resources, and prompts
5. **Testing**: Write comprehensive tests for all plugin functionality

### Security Considerations

```dart
class SecurePlugin extends MCPPlugin {
  @override
  Future<void> onInitialize() async {
    // Validate permissions
    if (!await hasRequiredPermissions()) {
      throw MCPException('Insufficient permissions');
    }
    
    // Initialize with security checks
    await initializeSecurely();
  }
  
  Future<bool> hasRequiredPermissions() async {
    // Check platform permissions
    return true;
  }
  
  Future<void> initializeSecurely() async {
    // Secure initialization
  }
}
```

### Performance Optimization

```dart
class OptimizedPlugin extends MCPPlugin {
  final _cache = <String, dynamic>{};
  final _pool = ResourcePool<DatabaseConnection>();
  
  @override
  Future<dynamic> executeTool(String tool, Map<String, dynamic> params) async {
    // Check cache first
    final cacheKey = '$tool:${jsonEncode(params)}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }
    
    // Use connection pool
    final connection = await _pool.acquire();
    try {
      final result = await _executeWithConnection(connection, tool, params);
      _cache[cacheKey] = result;
      return result;
    } finally {
      await _pool.release(connection);
    }
  }
}
```

## Next Steps

- Explore [State Management](./state-management.md)
- Learn about [Real-time Updates](./realtime-updates.md)
- Try [Desktop Applications](./desktop-applications.md)