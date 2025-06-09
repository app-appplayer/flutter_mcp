# Plugin Examples

This page contains complete examples of Flutter MCP plugins demonstrating various capabilities.

## Weather Plugin

A complete weather plugin that provides current weather and forecasts.

```dart
// lib/weather_plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class WeatherPlugin extends MCPToolPlugin {
  static const String _apiKey = 'YOUR_API_KEY';
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';
  
  final Map<String, WeatherData> _cache = {};
  Timer? _refreshTimer;
  
  @override
  String get id => 'weather';
  
  @override
  String get name => 'Weather Plugin';
  
  @override
  String get version => '1.0.0';
  
  @override
  String get description => 'Provides weather information and forecasts';
  
  @override
  Map<String, dynamic> get defaultConfig => {
    'apiKey': _apiKey,
    'units': 'metric',
    'cacheTimeout': 600, // 10 minutes
    'autoRefresh': true,
    'refreshInterval': 1800, // 30 minutes
  };
  
  @override
  List<Tool> getTools() {
    return [
      Tool(
        name: 'get_current_weather',
        description: 'Get current weather for a location',
        inputSchema: {
          'type': 'object',
          'properties': {
            'location': {
              'type': 'string',
              'description': 'City name or coordinates',
            },
          },
          'required': ['location'],
        },
      ),
      Tool(
        name: 'get_forecast',
        description: 'Get weather forecast',
        inputSchema: {
          'type': 'object',
          'properties': {
            'location': {
              'type': 'string',
              'description': 'City name or coordinates',
            },
            'days': {
              'type': 'integer',
              'description': 'Number of days (1-5)',
              'minimum': 1,
              'maximum': 5,
            },
          },
          'required': ['location'],
        },
      ),
    ];
  }
  
  @override
  Future<void> initialize(PluginContext context) async {
    await super.initialize(context);
    
    // Validate API key
    final apiKey = context.config['apiKey'] as String?;
    if (apiKey == null || apiKey.isEmpty) {
      throw PluginConfigException('Weather API key is required');
    }
    
    // Set up auto-refresh
    if (context.config['autoRefresh'] == true) {
      final interval = context.config['refreshInterval'] as int;
      _refreshTimer = Timer.periodic(
        Duration(seconds: interval),
        (_) => _refreshCache(),
      );
    }
    
    // Listen for location changes
    context.eventBus.on<LocationChangedEvent>().listen((event) {
      _updateWeatherForLocation(event.location);
    });
    
    context.logger.info('Weather plugin initialized');
  }
  
  @override
  Future<CallToolResult> executeTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    try {
      switch (toolName) {
        case 'get_current_weather':
          return await _getCurrentWeather(arguments);
        case 'get_forecast':
          return await _getForecast(arguments);
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
  
  Future<CallToolResult> _getCurrentWeather(Map<String, dynamic> args) async {
    final location = args['location'] as String;
    
    // Check cache
    final cacheKey = 'current_$location';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return CallToolResult(
        content: [
          TextContent(text: cached.toString()),
        ],
      );
    }
    
    // Fetch from API
    final response = await http.get(
      Uri.parse('$_baseUrl/weather?q=$location&appid=${_apiKey}&units=metric'),
    );
    
    if (response.statusCode != 200) {
      throw WeatherAPIException('Failed to fetch weather: ${response.body}');
    }
    
    final data = json.decode(response.body);
    final weather = WeatherData.fromJson(data);
    
    // Cache result
    _cache[cacheKey] = weather;
    
    // Publish event
    context.eventBus.publish(WeatherUpdatedEvent(
      location: location,
      weather: weather,
    ));
    
    return CallToolResult(
      content: [
        TextContent(text: weather.toString()),
      ],
    );
  }
  
  Future<CallToolResult> _getForecast(Map<String, dynamic> args) async {
    final location = args['location'] as String;
    final days = args['days'] as int? ?? 3;
    
    // Fetch forecast
    final response = await http.get(
      Uri.parse('$_baseUrl/forecast?q=$location&appid=${_apiKey}&units=metric&cnt=${days * 8}'),
    );
    
    if (response.statusCode != 200) {
      throw WeatherAPIException('Failed to fetch forecast: ${response.body}');
    }
    
    final data = json.decode(response.body);
    final forecast = ForecastData.fromJson(data);
    
    return CallToolResult(
      content: [
        TextContent(text: forecast.toString()),
      ],
    );
  }
  
  void _updateWeatherForLocation(String location) async {
    try {
      await _getCurrentWeather({'location': location});
    } catch (e) {
      context.logger.error('Failed to update weather for $location', e);
    }
  }
  
  void _refreshCache() {
    context.logger.debug('Refreshing weather cache');
    
    // Refresh cached locations
    final locations = _cache.keys
        .where((key) => key.startsWith('current_'))
        .map((key) => key.substring(8))
        .toSet();
    
    for (final location in locations) {
      _updateWeatherForLocation(location);
    }
  }
  
  @override
  Future<void> dispose() async {
    _refreshTimer?.cancel();
    _cache.clear();
    await super.dispose();
  }
}

// Data models
class WeatherData {
  final String location;
  final double temperature;
  final String description;
  final double humidity;
  final double windSpeed;
  final DateTime timestamp;
  
  WeatherData({
    required this.location,
    required this.temperature,
    required this.description,
    required this.humidity,
    required this.windSpeed,
  }) : timestamp = DateTime.now();
  
  bool get isExpired {
    return DateTime.now().difference(timestamp).inSeconds > 600;
  }
  
  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      location: json['name'],
      temperature: json['main']['temp'].toDouble(),
      description: json['weather'][0]['description'],
      humidity: json['main']['humidity'].toDouble(),
      windSpeed: json['wind']['speed'].toDouble(),
    );
  }
  
  @override
  String toString() {
    return '''
Weather in $location:
Temperature: ${temperature}°C
Description: $description
Humidity: ${humidity}%
Wind Speed: ${windSpeed} m/s
''';
  }
}

// Events
class WeatherUpdatedEvent extends PluginEvent {
  final String location;
  final WeatherData weather;
  
  WeatherUpdatedEvent({
    required this.location,
    required this.weather,
  }) : super(source: 'weather');
}

class LocationChangedEvent extends PluginEvent {
  final String location;
  
  LocationChangedEvent({required this.location});
}
```

## Database Plugin

A plugin that provides database access and management.

```dart
// lib/database_plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabasePlugin extends MCPResourcePlugin {
  Database? _database;
  final Map<String, TableSchema> _schemas = {};
  final StreamController<DatabaseEvent> _eventController = 
      StreamController<DatabaseEvent>.broadcast();
  
  @override
  String get id => 'database';
  
  @override
  String get name => 'Database Plugin';
  
  @override
  String get version => '1.0.0';
  
  @override
  String get description => 'Provides database access and management';
  
  @override
  Map<String, dynamic> get defaultConfig => {
    'databaseName': 'app.db',
    'version': 1,
    'enableForeignKeys': true,
  };
  
  @override
  List<Resource> getResources() {
    return _schemas.entries.map((entry) {
      return Resource(
        uri: 'db://${entry.key}',
        name: '${entry.key} table',
        mimeType: 'application/json',
        description: 'Access to ${entry.key} table',
      );
    }).toList();
  }
  
  @override
  Future<void> initialize(PluginContext context) async {
    await super.initialize(context);
    
    // Open database
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, context.config['databaseName']);
    
    _database = await openDatabase(
      path,
      version: context.config['version'] as int,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
    
    // Load table schemas
    await _loadSchemas();
    
    context.logger.info('Database plugin initialized');
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // Create default tables
    await db.execute('''
      CREATE TABLE IF NOT EXISTS config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        metadata TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }
  
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database migrations
    if (oldVersion < 2) {
      // Migration to version 2
      await db.execute('ALTER TABLE data ADD COLUMN tags TEXT');
    }
  }
  
  Future<void> _onConfigure(Database db) async {
    if (context.config['enableForeignKeys'] == true) {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
  
  Future<void> _loadSchemas() async {
    // Load table schemas from database
    final tables = await _database!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    
    for (final table in tables) {
      final tableName = table['name'] as String;
      if (tableName.startsWith('sqlite_')) continue;
      
      final columns = await _database!.rawQuery(
        'PRAGMA table_info($tableName)',
      );
      
      _schemas[tableName] = TableSchema(
        name: tableName,
        columns: columns.map((col) => ColumnSchema(
          name: col['name'] as String,
          type: col['type'] as String,
          nullable: col['notnull'] == 0,
          primaryKey: col['pk'] == 1,
        )).toList(),
      );
    }
  }
  
  @override
  Future<ResourceContent> readResource(String uri) async {
    final tableName = uri.replaceFirst('db://', '');
    
    if (!_schemas.containsKey(tableName)) {
      throw ResourceNotFoundException('Table not found: $tableName');
    }
    
    final results = await _database!.query(tableName);
    
    return ResourceContent(
      uri: uri,
      mimeType: 'application/json',
      text: json.encode({
        'table': tableName,
        'schema': _schemas[tableName]!.toJson(),
        'data': results,
      }),
    );
  }
  
  @override
  Future<void> writeResource(String uri, ResourceContent content) async {
    final tableName = uri.replaceFirst('db://', '');
    
    if (!_schemas.containsKey(tableName)) {
      throw ResourceNotFoundException('Table not found: $tableName');
    }
    
    final data = json.decode(content.text!) as Map<String, dynamic>;
    final operation = data['operation'] as String;
    
    switch (operation) {
      case 'insert':
        await _insert(tableName, data['data']);
        break;
      case 'update':
        await _update(tableName, data['data'], data['where']);
        break;
      case 'delete':
        await _delete(tableName, data['where']);
        break;
      default:
        throw ArgumentError('Unknown operation: $operation');
    }
  }
  
  @override
  Stream<ResourceEvent> watchResource(String uri) {
    final tableName = uri.replaceFirst('db://', '');
    
    return _eventController.stream
        .where((event) => event.table == tableName)
        .map((event) => ResourceChangedEvent(
          uri: uri,
          changeType: event.type,
        ));
  }
  
  // Database operations
  Future<int> _insert(String table, Map<String, dynamic> data) async {
    final id = await _database!.insert(table, data);
    
    _eventController.add(DatabaseEvent(
      table: table,
      type: ChangeType.insert,
      data: {...data, 'id': id},
    ));
    
    return id;
  }
  
  Future<int> _update(
    String table,
    Map<String, dynamic> data,
    Map<String, dynamic> where,
  ) async {
    final whereClause = where.entries
        .map((e) => '${e.key} = ?')
        .join(' AND ');
    
    final count = await _database!.update(
      table,
      data,
      where: whereClause,
      whereArgs: where.values.toList(),
    );
    
    _eventController.add(DatabaseEvent(
      table: table,
      type: ChangeType.update,
      data: data,
    ));
    
    return count;
  }
  
  Future<int> _delete(String table, Map<String, dynamic> where) async {
    final whereClause = where.entries
        .map((e) => '${e.key} = ?')
        .join(' AND ');
    
    final count = await _database!.delete(
      table,
      where: whereClause,
      whereArgs: where.values.toList(),
    );
    
    _eventController.add(DatabaseEvent(
      table: table,
      type: ChangeType.delete,
      data: where,
    ));
    
    return count;
  }
  
  // Plugin-specific methods
  Future<void> createTable(String name, List<ColumnSchema> columns) async {
    final columnDefs = columns.map((col) {
      var def = '${col.name} ${col.type}';
      if (col.primaryKey) def += ' PRIMARY KEY';
      if (!col.nullable) def += ' NOT NULL';
      return def;
    }).join(', ');
    
    await _database!.execute('CREATE TABLE $name ($columnDefs)');
    
    // Reload schemas
    await _loadSchemas();
    
    context.eventBus.publish(TableCreatedEvent(
      tableName: name,
      schema: _schemas[name]!,
    ));
  }
  
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    return await _database!.rawQuery(sql, arguments);
  }
  
  @override
  Future<void> dispose() async {
    await _database?.close();
    await _eventController.close();
    await super.dispose();
  }
}

// Data models
class TableSchema {
  final String name;
  final List<ColumnSchema> columns;
  
  TableSchema({required this.name, required this.columns});
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'columns': columns.map((c) => c.toJson()).toList(),
  };
}

class ColumnSchema {
  final String name;
  final String type;
  final bool nullable;
  final bool primaryKey;
  
  ColumnSchema({
    required this.name,
    required this.type,
    required this.nullable,
    required this.primaryKey,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'nullable': nullable,
    'primaryKey': primaryKey,
  };
}

// Events
class DatabaseEvent {
  final String table;
  final ChangeType type;
  final Map<String, dynamic> data;
  
  DatabaseEvent({
    required this.table,
    required this.type,
    required this.data,
  });
}

class TableCreatedEvent extends PluginEvent {
  final String tableName;
  final TableSchema schema;
  
  TableCreatedEvent({
    required this.tableName,
    required this.schema,
  }) : super(source: 'database');
}
```

## Translation Plugin

A plugin that provides text translation capabilities.

```dart
// lib/translation_plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:translator/translator.dart';

class TranslationPlugin extends MCPToolPlugin {
  late final GoogleTranslator _translator;
  final Map<String, TranslationCache> _cache = {};
  final Map<String, LanguageInfo> _supportedLanguages = {};
  
  @override
  String get id => 'translator';
  
  @override
  String get name => 'Translation Plugin';
  
  @override
  String get version => '1.0.0';
  
  @override
  String get description => 'Provides text translation between languages';
  
  @override
  Map<String, dynamic> get defaultConfig => {
    'cacheEnabled': true,
    'cacheTimeout': 3600, // 1 hour
    'maxCacheSize': 1000,
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
            'targetLang': {
              'type': 'string',
              'description': 'Target language code (e.g., "en", "es", "fr")',
            },
            'sourceLang': {
              'type': 'string',
              'description': 'Source language code (default: auto-detect)',
            },
          },
          'required': ['text', 'targetLang'],
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
      Tool(
        name: 'list_languages',
        description: 'List supported languages',
        inputSchema: {
          'type': 'object',
          'properties': {},
        },
      ),
    ];
  }
  
  @override
  Future<void> initialize(PluginContext context) async {
    await super.initialize(context);
    
    _translator = GoogleTranslator();
    
    // Load supported languages
    await _loadSupportedLanguages();
    
    // Set up cache cleanup
    if (context.config['cacheEnabled'] == true) {
      Timer.periodic(Duration(hours: 1), (_) => _cleanupCache());
    }
    
    context.logger.info('Translation plugin initialized');
  }
  
  Future<void> _loadSupportedLanguages() async {
    // Define commonly used languages
    _supportedLanguages.addAll({
      'en': LanguageInfo('en', 'English'),
      'es': LanguageInfo('es', 'Spanish'),
      'fr': LanguageInfo('fr', 'French'),
      'de': LanguageInfo('de', 'German'),
      'it': LanguageInfo('it', 'Italian'),
      'pt': LanguageInfo('pt', 'Portuguese'),
      'ru': LanguageInfo('ru', 'Russian'),
      'ja': LanguageInfo('ja', 'Japanese'),
      'ko': LanguageInfo('ko', 'Korean'),
      'zh': LanguageInfo('zh', 'Chinese'),
      'ar': LanguageInfo('ar', 'Arabic'),
      'hi': LanguageInfo('hi', 'Hindi'),
    });
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
        case 'list_languages':
          return await _listLanguages(arguments);
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
    final targetLang = args['targetLang'] as String;
    final sourceLang = args['sourceLang'] as String? ?? 
        context.config['defaultSourceLang'] as String;
    
    // Check cache
    final cacheKey = '$text|$sourceLang|$targetLang';
    if (context.config['cacheEnabled'] == true) {
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired) {
        context.logger.debug('Translation cache hit');
        return CallToolResult(
          content: [
            TextContent(text: json.encode({
              'translatedText': cached.translatedText,
              'sourceLang': cached.sourceLang,
              'targetLang': cached.targetLang,
              'cached': true,
            })),
          ],
        );
      }
    }
    
    // Translate
    final translation = await _translator.translate(
      text,
      from: sourceLang == 'auto' ? 'auto' : sourceLang,
      to: targetLang,
    );
    
    // Cache result
    if (context.config['cacheEnabled'] == true) {
      _cache[cacheKey] = TranslationCache(
        originalText: text,
        translatedText: translation.text,
        sourceLang: translation.sourceLanguage.code,
        targetLang: targetLang,
        timeout: context.config['cacheTimeout'] as int,
      );
      _trimCache();
    }
    
    // Publish event
    context.eventBus.publish(TranslationCompletedEvent(
      originalText: text,
      translatedText: translation.text,
      sourceLang: translation.sourceLanguage.code,
      targetLang: targetLang,
    ));
    
    return CallToolResult(
      content: [
        TextContent(text: json.encode({
          'translatedText': translation.text,
          'sourceLang': translation.sourceLanguage.code,
          'targetLang': targetLang,
          'cached': false,
        })),
      ],
    );
  }
  
  Future<CallToolResult> _detectLanguage(Map<String, dynamic> args) async {
    final text = args['text'] as String;
    
    // Detect language
    final result = await _translator.detectLanguage(text);
    
    return CallToolResult(
      content: [
        TextContent(text: json.encode({
          'language': result.language,
          'confidence': result.confidence,
          'languageName': _supportedLanguages[result.language]?.name ?? 'Unknown',
        })),
      ],
    );
  }
  
  Future<CallToolResult> _listLanguages(Map<String, dynamic> args) async {
    return CallToolResult(
      content: [
        TextContent(text: json.encode({
          'languages': _supportedLanguages.values
              .map((lang) => lang.toJson())
              .toList(),
        })),
      ],
    );
  }
  
  void _trimCache() {
    final maxSize = context.config['maxCacheSize'] as int;
    if (_cache.length > maxSize) {
      // Remove oldest entries
      final entries = _cache.entries.toList()
        ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
      
      final toRemove = entries.length - maxSize;
      for (int i = 0; i < toRemove; i++) {
        _cache.remove(entries[i].key);
      }
    }
  }
  
  void _cleanupCache() {
    context.logger.debug('Cleaning translation cache');
    _cache.removeWhere((key, value) => value.isExpired);
  }
  
  @override
  Future<void> dispose() async {
    _cache.clear();
    await super.dispose();
  }
}

// Data models
class TranslationCache {
  final String originalText;
  final String translatedText;
  final String sourceLang;
  final String targetLang;
  final DateTime timestamp;
  final int timeout;
  
  TranslationCache({
    required this.originalText,
    required this.translatedText,
    required this.sourceLang,
    required this.targetLang,
    required this.timeout,
  }) : timestamp = DateTime.now();
  
  bool get isExpired {
    return DateTime.now().difference(timestamp).inSeconds > timeout;
  }
}

class LanguageInfo {
  final String code;
  final String name;
  
  LanguageInfo(this.code, this.name);
  
  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
  };
}

// Events
class TranslationCompletedEvent extends PluginEvent {
  final String originalText;
  final String translatedText;
  final String sourceLang;
  final String targetLang;
  
  TranslationCompletedEvent({
    required this.originalText,
    required this.translatedText,
    required this.sourceLang,
    required this.targetLang,
  }) : super(source: 'translator');
}
```

## Task Automation Plugin

A plugin that provides task automation and workflow capabilities.

```dart
// lib/automation_plugin.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:cron/cron.dart';

class AutomationPlugin extends MCPBackgroundPlugin {
  final Map<String, Workflow> _workflows = {};
  final Map<String, ScheduledTask> _scheduledTasks = {};
  final Cron _cron = Cron();
  
  @override
  String get id => 'automation';
  
  @override
  String get name => 'Task Automation Plugin';
  
  @override
  String get version => '1.0.0';
  
  @override
  String get description => 'Automate tasks and create workflows';
  
  @override
  Map<String, dynamic> get defaultConfig => {
    'maxConcurrentTasks': 5,
    'taskTimeout': 300, // 5 minutes
    'retryFailedTasks': true,
    'maxRetries': 3,
  };
  
  @override
  void registerTasks(BackgroundTaskRegistry registry) {
    // Register automation tasks
    registry.register(
      taskId: 'run_workflow',
      handler: () => _runScheduledWorkflows(),
      config: TaskConfig(
        minInterval: Duration(minutes: 1),
      ),
    );
    
    registry.register(
      taskId: 'cleanup_history',
      handler: () => _cleanupTaskHistory(),
      config: TaskConfig(
        minInterval: Duration(hours: 24),
      ),
    );
  }
  
  @override
  Future<void> executeTask(String taskId) async {
    switch (taskId) {
      case 'run_workflow':
        await _runScheduledWorkflows();
        break;
      case 'cleanup_history':
        await _cleanupTaskHistory();
        break;
      default:
        throw TaskNotFoundException('Unknown task: $taskId');
    }
  }
  
  @override
  Future<void> initialize(PluginContext context) async {
    await super.initialize(context);
    
    // Load saved workflows
    await _loadWorkflows();
    
    // Load scheduled tasks
    await _loadScheduledTasks();
    
    // Start cron scheduler
    _startScheduler();
    
    context.logger.info('Automation plugin initialized');
  }
  
  // Public API
  Future<String> createWorkflow(WorkflowConfig config) async {
    final workflow = Workflow(
      id: Uuid().v4(),
      name: config.name,
      description: config.description,
      steps: config.steps,
      triggers: config.triggers,
    );
    
    _workflows[workflow.id] = workflow;
    await _saveWorkflows();
    
    context.eventBus.publish(WorkflowCreatedEvent(
      workflowId: workflow.id,
      name: workflow.name,
    ));
    
    return workflow.id;
  }
  
  Future<void> runWorkflow(String workflowId, Map<String, dynamic>? input) async {
    final workflow = _workflows[workflowId];
    if (workflow == null) {
      throw WorkflowNotFoundException('Workflow not found: $workflowId');
    }
    
    final execution = WorkflowExecution(
      id: Uuid().v4(),
      workflowId: workflowId,
      startTime: DateTime.now(),
      input: input ?? {},
      status: ExecutionStatus.running,
    );
    
    context.eventBus.publish(WorkflowStartedEvent(
      executionId: execution.id,
      workflowId: workflowId,
    ));
    
    try {
      await _executeWorkflow(workflow, execution);
      
      execution.status = ExecutionStatus.completed;
      execution.endTime = DateTime.now();
      
      context.eventBus.publish(WorkflowCompletedEvent(
        executionId: execution.id,
        workflowId: workflowId,
        output: execution.output,
      ));
    } catch (e) {
      execution.status = ExecutionStatus.failed;
      execution.error = e.toString();
      execution.endTime = DateTime.now();
      
      context.eventBus.publish(WorkflowFailedEvent(
        executionId: execution.id,
        workflowId: workflowId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }
  
  Future<void> scheduleTask(ScheduledTaskConfig config) async {
    final task = ScheduledTask(
      id: Uuid().v4(),
      name: config.name,
      workflowId: config.workflowId,
      schedule: config.schedule,
      input: config.input,
      enabled: true,
    );
    
    _scheduledTasks[task.id] = task;
    
    // Schedule with cron
    _cron.schedule(Schedule.parse(task.schedule), () {
      if (task.enabled) {
        runWorkflow(task.workflowId, task.input);
      }
    });
    
    await _saveScheduledTasks();
    
    context.eventBus.publish(TaskScheduledEvent(
      taskId: task.id,
      name: task.name,
      schedule: task.schedule,
    ));
  }
  
  // Private methods
  Future<void> _executeWorkflow(
    Workflow workflow,
    WorkflowExecution execution,
  ) async {
    Map<String, dynamic> stepOutput = {};
    
    for (int i = 0; i < workflow.steps.length; i++) {
      final step = workflow.steps[i];
      
      try {
        context.logger.debug('Executing step ${step.name}');
        
        // Replace variables in step configuration
        final processedConfig = _processVariables(
          step.config,
          {...execution.input, ...stepOutput},
        );
        
        // Execute step based on type
        final output = await _executeStep(step, processedConfig);
        
        // Store output for next steps
        stepOutput[step.name] = output;
        
        context.eventBus.publish(WorkflowStepCompletedEvent(
          executionId: execution.id,
          stepIndex: i,
          stepName: step.name,
          output: output,
        ));
        
      } catch (e) {
        if (step.onError == ErrorHandling.fail) {
          throw WorkflowStepException(
            'Step ${step.name} failed: $e',
          );
        } else if (step.onError == ErrorHandling.retry) {
          // Retry logic
          int retries = 0;
          while (retries < context.config['maxRetries']) {
            retries++;
            try {
              final output = await _executeStep(step, step.config);
              stepOutput[step.name] = output;
              break;
            } catch (e) {
              if (retries >= context.config['maxRetries']) {
                throw WorkflowStepException(
                  'Step ${step.name} failed after $retries retries: $e',
                );
              }
              await Future.delayed(Duration(seconds: retries * 2));
            }
          }
        }
        // ErrorHandling.continue - just continue to next step
      }
    }
    
    execution.output = stepOutput;
  }
  
  Future<Map<String, dynamic>> _executeStep(
    WorkflowStep step,
    Map<String, dynamic> config,
  ) async {
    switch (step.type) {
      case StepType.httpRequest:
        return await _executeHttpRequest(config);
      
      case StepType.toolExecution:
        return await _executeToolCall(config);
      
      case StepType.dataTransform:
        return await _executeDataTransform(config);
      
      case StepType.conditional:
        return await _executeConditional(config);
      
      case StepType.loop:
        return await _executeLoop(config);
      
      default:
        throw UnsupportedError('Unknown step type: ${step.type}');
    }
  }
  
  Future<Map<String, dynamic>> _executeHttpRequest(
    Map<String, dynamic> config,
  ) async {
    final response = await http.request(
      config['method'] as String,
      Uri.parse(config['url'] as String),
      headers: config['headers'] as Map<String, String>?,
      body: config['body'],
    );
    
    return {
      'statusCode': response.statusCode,
      'headers': response.headers,
      'body': response.body,
    };
  }
  
  Future<Map<String, dynamic>> _executeToolCall(
    Map<String, dynamic> config,
  ) async {
    final pluginId = config['pluginId'] as String;
    final toolName = config['toolName'] as String;
    final arguments = config['arguments'] as Map<String, dynamic>;
    
    final plugin = context.registry.getPlugin<MCPToolPlugin>(pluginId);
    if (plugin == null) {
      throw PluginNotFoundException('Plugin not found: $pluginId');
    }
    
    final result = await plugin.executeTool(toolName, arguments);
    
    return {
      'success': !result.isError,
      'content': result.content.map((c) => c.toString()).join('\n'),
    };
  }
  
  Map<String, dynamic> _processVariables(
    Map<String, dynamic> config,
    Map<String, dynamic> variables,
  ) {
    final processed = <String, dynamic>{};
    
    config.forEach((key, value) {
      if (value is String && value.startsWith('\${') && value.endsWith('}')) {
        // Replace variable
        final varName = value.substring(2, value.length - 1);
        processed[key] = _getNestedValue(variables, varName);
      } else if (value is Map<String, dynamic>) {
        // Recursively process nested maps
        processed[key] = _processVariables(value, variables);
      } else if (value is List) {
        // Process lists
        processed[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _processVariables(item, variables);
          }
          return item;
        }).toList();
      } else {
        // Keep value as is
        processed[key] = value;
      }
    });
    
    return processed;
  }
  
  dynamic _getNestedValue(Map<String, dynamic> map, String path) {
    final parts = path.split('.');
    dynamic current = map;
    
    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        current = current[part];
      } else {
        return null;
      }
    }
    
    return current;
  }
  
  @override
  Future<void> dispose() async {
    _cron.close();
    await super.dispose();
  }
}

// Data models
class Workflow {
  final String id;
  final String name;
  final String description;
  final List<WorkflowStep> steps;
  final List<WorkflowTrigger> triggers;
  
  Workflow({
    required this.id,
    required this.name,
    required this.description,
    required this.steps,
    required this.triggers,
  });
}

class WorkflowStep {
  final String name;
  final StepType type;
  final Map<String, dynamic> config;
  final ErrorHandling onError;
  
  WorkflowStep({
    required this.name,
    required this.type,
    required this.config,
    this.onError = ErrorHandling.fail,
  });
}

enum StepType {
  httpRequest,
  toolExecution,
  dataTransform,
  conditional,
  loop,
}

enum ErrorHandling {
  fail,
  continue,
  retry,
}

class ScheduledTask {
  final String id;
  final String name;
  final String workflowId;
  final String schedule;
  final Map<String, dynamic>? input;
  bool enabled;
  
  ScheduledTask({
    required this.id,
    required this.name,
    required this.workflowId,
    required this.schedule,
    this.input,
    this.enabled = true,
  });
}

// Events
class WorkflowCreatedEvent extends PluginEvent {
  final String workflowId;
  final String name;
  
  WorkflowCreatedEvent({
    required this.workflowId,
    required this.name,
  }) : super(source: 'automation');
}

class WorkflowStartedEvent extends PluginEvent {
  final String executionId;
  final String workflowId;
  
  WorkflowStartedEvent({
    required this.executionId,
    required this.workflowId,
  }) : super(source: 'automation');
}
```

## Usage Examples

### Using Weather Plugin

```dart
// Initialize MCP
final mcp = FlutterMCP();
await mcp.initialize();

// Register weather plugin
final weatherPlugin = WeatherPlugin();
await mcp.pluginRegistry.register(weatherPlugin);

// Use the plugin
final client = mcp.createClient();
final result = await client.callTool(
  name: 'get_current_weather',
  arguments: {
    'location': 'New York',
  },
);

print(result.content.first.text);
```

### Using Database Plugin

```dart
// Register database plugin
final dbPlugin = DatabasePlugin();
await mcp.pluginRegistry.register(dbPlugin);

// Create a table
await dbPlugin.createTable('users', [
  ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true, nullable: false),
  ColumnSchema(name: 'name', type: 'TEXT', nullable: false),
  ColumnSchema(name: 'email', type: 'TEXT', nullable: false),
]);

// Insert data
await dbPlugin.writeResource('db://users', ResourceContent(
  uri: 'db://users',
  mimeType: 'application/json',
  text: json.encode({
    'operation': 'insert',
    'data': {
      'name': 'John Doe',
      'email': 'john@example.com',
    },
  }),
));
```

### Using Translation Plugin

```dart
// Register translation plugin
final translationPlugin = TranslationPlugin();
await mcp.pluginRegistry.register(translationPlugin);

// Translate text
final result = await client.callTool(
  name: 'translate',
  arguments: {
    'text': 'Hello, world!',
    'targetLang': 'es',
  },
);

final translation = json.decode(result.content.first.text);
print(translation['translatedText']); // ¡Hola, mundo!
```

### Using Automation Plugin

```dart
// Register automation plugin
final automationPlugin = AutomationPlugin();
await mcp.pluginRegistry.register(automationPlugin);

// Create a workflow
final workflowId = await automationPlugin.createWorkflow(
  WorkflowConfig(
    name: 'Daily Report',
    description: 'Generate and send daily report',
    steps: [
      WorkflowStep(
        name: 'fetch_data',
        type: StepType.toolExecution,
        config: {
          'pluginId': 'database',
          'toolName': 'query',
          'arguments': {
            'sql': 'SELECT * FROM metrics WHERE date = date("now")',
          },
        },
      ),
      WorkflowStep(
        name: 'generate_report',
        type: StepType.dataTransform,
        config: {
          'template': 'Daily Report: \${fetch_data.result}',
        },
      ),
      WorkflowStep(
        name: 'send_email',
        type: StepType.httpRequest,
        config: {
          'method': 'POST',
          'url': 'https://api.email.com/send',
          'body': {
            'to': 'admin@example.com',
            'subject': 'Daily Report',
            'content': '\${generate_report.output}',
          },
        },
      ),
    ],
  ),
);

// Schedule the workflow
await automationPlugin.scheduleTask(
  ScheduledTaskConfig(
    name: 'Daily Report Schedule',
    workflowId: workflowId,
    schedule: '0 9 * * *', // Every day at 9 AM
  ),
);
```

## Next Steps

- [Development Guide](development.md) - Create your own plugins
- [Lifecycle Guide](lifecycle.md) - Understand plugin lifecycle
- [Communication Guide](communication.md) - Plugin communication patterns
- [API Reference](../api/plugin-system.md) - Complete API documentation