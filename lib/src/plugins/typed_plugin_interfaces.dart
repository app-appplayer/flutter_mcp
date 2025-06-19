/// Type-safe plugin interfaces to replace Map`<String, dynamic>` usage
library;

import '../config/typed_config.dart';
import '../metrics/typed_metrics.dart';

/// Result types for plugin operations
abstract class PluginResult<T> {
  bool get isSuccess;
  String? get error;
  DateTime get timestamp;
  T? get data;
  Map<String, dynamic> toMap();
}

/// Successful plugin result
class SuccessResult<T> implements PluginResult<T> {
  @override
  final T data;
  @override
  final DateTime timestamp;

  SuccessResult(this.data, {DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  @override
  bool get isSuccess => true;

  @override
  String? get error => null;

  @override
  Map<String, dynamic> toMap() {
    return {
      'success': true,
      'data': data is Map<String, dynamic> ? data : data?.toString(),
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Failed plugin result
class FailureResult<T> implements PluginResult<T> {
  @override
  final String error;
  @override
  final DateTime timestamp;
  @override
  final T? data = null;
  final String? details;
  final Object? originalError;

  FailureResult(
    this.error, {
    this.details,
    this.originalError,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  bool get isSuccess => false;

  @override
  Map<String, dynamic> toMap() {
    return {
      'success': false,
      'error': error,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Plugin execution context with type safety
class PluginContext {
  final String requestId;
  final String pluginName;
  final PluginConfig config;
  final Map<String, dynamic> metadata;
  final DateTime startTime;

  PluginContext({
    required this.requestId,
    required this.pluginName,
    required this.config,
    this.metadata = const {},
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();

  /// Create a child context for sub-operations
  PluginContext createChild(String operation) {
    return PluginContext(
      requestId: '$requestId.$operation',
      pluginName: pluginName,
      config: config,
      metadata: {...metadata, 'parent': requestId, 'operation': operation},
      startTime: DateTime.now(),
    );
  }
}

/// Plugin configuration types
abstract class PluginConfig {
  String get name;
  String get version;
  bool get enabled;
  Duration get timeout;
  int get maxRetries;
  Map<String, dynamic> toMap();

  factory PluginConfig.fromMap(Map<String, dynamic> map) {
    return DefaultPluginConfig.fromMap(map);
  }
}

class DefaultPluginConfig implements PluginConfig {
  @override
  final String name;
  @override
  final String version;
  @override
  final bool enabled;
  @override
  final Duration timeout;
  @override
  final int maxRetries;
  final Map<String, dynamic> customSettings;

  DefaultPluginConfig({
    required this.name,
    this.version = '1.0.0',
    this.enabled = true,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.customSettings = const {},
  });

  factory DefaultPluginConfig.fromMap(Map<String, dynamic> map) {
    return DefaultPluginConfig(
      name: map['name'] as String,
      version: map['version'] as String? ?? '1.0.0',
      enabled: map['enabled'] as bool? ?? true,
      timeout: Duration(milliseconds: map['timeoutMs'] as int? ?? 30000),
      maxRetries: map['maxRetries'] as int? ?? 3,
      customSettings: Map<String, dynamic>.from(map['customSettings'] ?? {}),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'version': version,
      'enabled': enabled,
      'timeoutMs': timeout.inMilliseconds,
      'maxRetries': maxRetries,
      'customSettings': customSettings,
    };
  }
}

/// Tool execution request with strong typing
class ToolRequest {
  final String toolName;
  final Map<String, dynamic> arguments;
  final PluginContext context;
  final ToolInputSchema schema;

  ToolRequest({
    required this.toolName,
    required this.arguments,
    required this.context,
    required this.schema,
  });

  /// Validate arguments against schema
  List<ValidationError> validate() {
    return schema.validate(arguments);
  }
}

/// Tool execution response with type safety
class ToolResponse {
  final String toolName;
  final PluginResult result;
  final ToolOutputSchema? outputSchema;
  final Duration executionTime;
  final List<PerformanceMetric> metrics;

  ToolResponse({
    required this.toolName,
    required this.result,
    this.outputSchema,
    required this.executionTime,
    this.metrics = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'toolName': toolName,
      'result': result.toMap(),
      'executionTimeMs': executionTime.inMilliseconds,
      'metrics': metrics.map((m) => m.toMap()).toList(),
    };
  }
}

/// Input schema definition for tools
class ToolInputSchema {
  final String name;
  final String description;
  final Map<String, PropertySchema> properties;
  final List<String> required;

  ToolInputSchema({
    required this.name,
    required this.description,
    required this.properties,
    this.required = const [],
  });

  /// Validate input arguments
  List<ValidationError> validate(Map<String, dynamic> arguments) {
    final errors = <ValidationError>[];

    // Check required properties
    for (final requiredProp in required) {
      if (!arguments.containsKey(requiredProp)) {
        errors.add(ValidationError(
          property: requiredProp,
          message: 'Required property missing',
          value: null,
        ));
      }
    }

    // Validate each property
    for (final entry in arguments.entries) {
      final propertySchema = properties[entry.key];
      if (propertySchema != null) {
        final propErrors = propertySchema.validate(entry.key, entry.value);
        errors.addAll(propErrors);
      }
    }

    return errors;
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'type': 'object',
      'properties':
          properties.map((key, schema) => MapEntry(key, schema.toMap())),
      'required': required,
    };
  }
}

/// Output schema definition for tools
class ToolOutputSchema {
  final String description;
  final Map<String, PropertySchema> properties;

  ToolOutputSchema({
    required this.description,
    required this.properties,
  });

  Map<String, dynamic> toMap() {
    return {
      'description': description,
      'type': 'object',
      'properties':
          properties.map((key, schema) => MapEntry(key, schema.toMap())),
    };
  }
}

/// Property schema for validation
class PropertySchema {
  final String type;
  final String? description;
  final bool nullable;
  final dynamic defaultValue;
  final List<dynamic>? enumValues;
  final PropertySchema? items; // For arrays
  final Map<String, PropertySchema>? properties; // For objects

  PropertySchema({
    required this.type,
    this.description,
    this.nullable = false,
    this.defaultValue,
    this.enumValues,
    this.items,
    this.properties,
  });

  List<ValidationError> validate(String property, dynamic value) {
    final errors = <ValidationError>[];

    if (value == null) {
      if (!nullable) {
        errors.add(ValidationError(
          property: property,
          message: 'Value cannot be null',
          value: value,
        ));
      }
      return errors;
    }

    // Type validation
    switch (type) {
      case 'string':
        if (value is! String) {
          errors.add(ValidationError(
            property: property,
            message: 'Expected string, got ${value.runtimeType}',
            value: value,
          ));
        }
        break;
      case 'number':
      case 'integer':
        if (value is! num) {
          errors.add(ValidationError(
            property: property,
            message: 'Expected number, got ${value.runtimeType}',
            value: value,
          ));
        } else if (type == 'integer' && value is! int) {
          errors.add(ValidationError(
            property: property,
            message: 'Expected integer, got double',
            value: value,
          ));
        }
        break;
      case 'boolean':
        if (value is! bool) {
          errors.add(ValidationError(
            property: property,
            message: 'Expected boolean, got ${value.runtimeType}',
            value: value,
          ));
        }
        break;
      case 'array':
        if (value is! List) {
          errors.add(ValidationError(
            property: property,
            message: 'Expected array, got ${value.runtimeType}',
            value: value,
          ));
        } else if (items != null) {
          for (int i = 0; i < value.length; i++) {
            final itemErrors = items!.validate('$property[$i]', value[i]);
            errors.addAll(itemErrors);
          }
        }
        break;
      case 'object':
        if (value is! Map) {
          errors.add(ValidationError(
            property: property,
            message: 'Expected object, got ${value.runtimeType}',
            value: value,
          ));
        } else if (properties != null) {
          final valueMap = value as Map<String, dynamic>;
          for (final entry in valueMap.entries) {
            final propSchema = properties![entry.key];
            if (propSchema != null) {
              final propErrors =
                  propSchema.validate('$property.${entry.key}', entry.value);
              errors.addAll(propErrors);
            }
          }
        }
        break;
    }

    // Enum validation
    if (enumValues != null && !enumValues!.contains(value)) {
      errors.add(ValidationError(
        property: property,
        message: 'Value must be one of: ${enumValues!.join(', ')}',
        value: value,
      ));
    }

    return errors;
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'type': type,
    };

    if (description != null) map['description'] = description;
    if (defaultValue != null) map['default'] = defaultValue;
    if (enumValues != null) map['enum'] = enumValues;
    if (items != null) map['items'] = items!.toMap();
    if (properties != null) {
      map['properties'] =
          properties!.map((key, schema) => MapEntry(key, schema.toMap()));
    }

    return map;
  }
}

/// Validation error
class ValidationError {
  final String property;
  final String message;
  final dynamic value;

  ValidationError({
    required this.property,
    required this.message,
    required this.value,
  });

  @override
  String toString() => '$property: $message (value: $value)';
}

/// Resource request with strong typing
class ResourceRequest {
  final String resourceUri;
  final Map<String, dynamic> parameters;
  final PluginContext context;
  final ResourceInputSchema? schema;

  ResourceRequest({
    required this.resourceUri,
    required this.parameters,
    required this.context,
    this.schema,
  });

  /// Validate parameters against schema
  List<ValidationError> validate() {
    if (schema == null) return [];
    return schema!.validate(parameters);
  }
}

/// Resource response with type safety
class ResourceResponse {
  final String resourceUri;
  final ResourceContent content;
  final String? mimeType;
  final Map<String, String> metadata;
  final Duration retrievalTime;

  ResourceResponse({
    required this.resourceUri,
    required this.content,
    this.mimeType,
    this.metadata = const {},
    required this.retrievalTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'resourceUri': resourceUri,
      'content': content.toMap(),
      'mimeType': mimeType,
      'metadata': metadata,
      'retrievalTimeMs': retrievalTime.inMilliseconds,
    };
  }
}

/// Resource content types
abstract class ResourceContent {
  String get type;
  Map<String, dynamic> toMap();
}

class TextContent implements ResourceContent {
  @override
  final String type = 'text';
  final String text;
  final String? encoding;

  TextContent(this.text, {this.encoding = 'utf-8'});

  @override
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'text': text,
      'encoding': encoding,
    };
  }
}

class BinaryContent implements ResourceContent {
  @override
  final String type = 'binary';
  final List<int> data;
  final String? encoding;

  BinaryContent(this.data, {this.encoding});

  @override
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'data': data,
      'encoding': encoding,
    };
  }
}

class JsonContent implements ResourceContent {
  @override
  final String type = 'json';
  final Map<String, dynamic> data;

  JsonContent(this.data);

  @override
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'data': data,
    };
  }
}

/// Resource input schema
class ResourceInputSchema {
  final Map<String, PropertySchema> parameters;

  ResourceInputSchema({required this.parameters});

  List<ValidationError> validate(Map<String, dynamic> params) {
    final errors = <ValidationError>[];

    for (final entry in params.entries) {
      final schema = parameters[entry.key];
      if (schema != null) {
        final paramErrors = schema.validate(entry.key, entry.value);
        errors.addAll(paramErrors);
      }
    }

    return errors;
  }
}

/// Prompt request with strong typing
class PromptRequest {
  final String promptName;
  final Map<String, dynamic> arguments;
  final PluginContext context;
  final PromptInputSchema schema;

  PromptRequest({
    required this.promptName,
    required this.arguments,
    required this.context,
    required this.schema,
  });

  /// Validate arguments against schema
  List<ValidationError> validate() {
    return schema.validate(arguments);
  }
}

/// Prompt response with type safety
class PromptResponse {
  final String promptName;
  final String description;
  final List<PromptMessage> messages;
  final Duration generationTime;

  PromptResponse({
    required this.promptName,
    required this.description,
    required this.messages,
    required this.generationTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'promptName': promptName,
      'description': description,
      'messages': messages.map((m) => m.toMap()).toList(),
      'generationTimeMs': generationTime.inMilliseconds,
    };
  }
}

/// Prompt message types
class PromptMessage {
  final String role;
  final MessageContent content;
  final Map<String, dynamic> metadata;

  PromptMessage({
    required this.role,
    required this.content,
    this.metadata = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'role': role,
      'content': content.toMap(),
      'metadata': metadata,
    };
  }
}

/// Message content types
abstract class MessageContent {
  String get type;
  Map<String, dynamic> toMap();
}

class TextMessageContent implements MessageContent {
  @override
  final String type = 'text';
  final String text;

  TextMessageContent(this.text);

  @override
  Map<String, dynamic> toMap() {
    return {'type': type, 'text': text};
  }
}

class ImageMessageContent implements MessageContent {
  @override
  final String type = 'image';
  final String url;
  final String? alt;

  ImageMessageContent(this.url, {this.alt});

  @override
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'url': url,
      if (alt != null) 'alt': alt,
    };
  }
}

/// Prompt input schema
class PromptInputSchema {
  final String name;
  final String description;
  final Map<String, PropertySchema> arguments;
  final List<String> required;

  PromptInputSchema({
    required this.name,
    required this.description,
    required this.arguments,
    this.required = const [],
  });

  List<ValidationError> validate(Map<String, dynamic> args) {
    final errors = <ValidationError>[];

    // Check required arguments
    for (final requiredArg in required) {
      if (!args.containsKey(requiredArg)) {
        errors.add(ValidationError(
          property: requiredArg,
          message: 'Required argument missing',
          value: null,
        ));
      }
    }

    // Validate each argument
    for (final entry in args.entries) {
      final argSchema = arguments[entry.key];
      if (argSchema != null) {
        final argErrors = argSchema.validate(entry.key, entry.value);
        errors.addAll(argErrors);
      }
    }

    return errors;
  }
}

/// Background task configuration
class BackgroundTaskConfig {
  final String taskName;
  final Duration interval;
  final int maxRetries;
  final bool autoRestart;
  final Map<String, dynamic> parameters;

  BackgroundTaskConfig({
    required this.taskName,
    required this.interval,
    this.maxRetries = 3,
    this.autoRestart = true,
    this.parameters = const {},
  });

  factory BackgroundTaskConfig.fromMap(Map<String, dynamic> map) {
    return BackgroundTaskConfig(
      taskName: map['taskName'] as String,
      interval: Duration(milliseconds: map['intervalMs'] as int),
      maxRetries: map['maxRetries'] as int? ?? 3,
      autoRestart: map['autoRestart'] as bool? ?? true,
      parameters: Map<String, dynamic>.from(map['parameters'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'taskName': taskName,
      'intervalMs': interval.inMilliseconds,
      'maxRetries': maxRetries,
      'autoRestart': autoRestart,
      'parameters': parameters,
    };
  }
}

/// Background task result
class BackgroundTaskResult {
  final String taskName;
  final bool success;
  final String? error;
  final Map<String, dynamic> output;
  final DateTime completedAt;
  final Duration executionTime;

  BackgroundTaskResult({
    required this.taskName,
    required this.success,
    this.error,
    this.output = const {},
    required this.completedAt,
    required this.executionTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'taskName': taskName,
      'success': success,
      'error': error,
      'output': output,
      'completedAt': completedAt.toIso8601String(),
      'executionTimeMs': executionTime.inMilliseconds,
    };
  }
}

/// Notification request with strong typing
class NotificationRequest {
  final String title;
  final String body;
  final String? id;
  final NotificationPriority priority;
  final String? iconPath;
  final Map<String, dynamic> data;
  final Duration? ttl;

  NotificationRequest({
    required this.title,
    required this.body,
    this.id,
    this.priority = NotificationPriority.medium,
    this.iconPath,
    this.data = const {},
    this.ttl,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'id': id,
      'priority': priority.name,
      'iconPath': iconPath,
      'data': data,
      'ttlMs': ttl?.inMilliseconds,
    };
  }
}

/// Notification response
class NotificationResponse {
  final String notificationId;
  final bool delivered;
  final String? error;
  final DateTime timestamp;

  NotificationResponse({
    required this.notificationId,
    required this.delivered,
    this.error,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'notificationId': notificationId,
      'delivered': delivered,
      'error': error,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Tray menu configuration
class TrayMenuConfig {
  final List<TrayMenuItem> items;
  final String? iconPath;
  final String? tooltip;

  TrayMenuConfig({
    required this.items,
    this.iconPath,
    this.tooltip,
  });

  Map<String, dynamic> toMap() {
    return {
      'items': items.map((item) => item.toMap()).toList(),
      'iconPath': iconPath,
      'tooltip': tooltip,
    };
  }
}

/// Tray menu item
class TrayMenuItem {
  final String id;
  final String label;
  final bool enabled;
  final String? action;
  final List<TrayMenuItem> subItems;
  final String? iconPath;
  final String? shortcut;

  TrayMenuItem({
    required this.id,
    required this.label,
    this.enabled = true,
    this.action,
    this.subItems = const [],
    this.iconPath,
    this.shortcut,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'enabled': enabled,
      'action': action,
      'subItems': subItems.map((item) => item.toMap()).toList(),
      'iconPath': iconPath,
      'shortcut': shortcut,
    };
  }

  factory TrayMenuItem.fromMap(Map<String, dynamic> map) {
    return TrayMenuItem(
      id: map['id'] as String,
      label: map['label'] as String,
      enabled: map['enabled'] as bool? ?? true,
      action: map['action'] as String?,
      subItems: (map['subItems'] as List<dynamic>?)
              ?.map(
                  (item) => TrayMenuItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      iconPath: map['iconPath'] as String?,
      shortcut: map['shortcut'] as String?,
    );
  }
}
