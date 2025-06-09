import 'dart:async';
import 'package:flutter/services.dart';
import '../models/platform_messages.dart';
import 'enhanced_error_handler.dart';
import 'exceptions.dart';
import 'logger.dart';

/// Type-safe wrapper for platform method channel
class TypedPlatformChannel {
  final MethodChannel _channel;
  final Logger _logger;
  final String _name;
  
  /// Event handlers for platform events
  final Map<String, Function(dynamic)> _eventHandlers = {};
  
  /// Constructor
  TypedPlatformChannel(String name)
    : _channel = MethodChannel(name),
      _name = name,
      _logger = Logger('flutter_mcp.typed_channel.$name') {
    _setupMethodCallHandler();
  }
  
  /// Set up method call handler for incoming calls from platform
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((MethodCall call) async {
      _logger.fine('Received method call: ${call.method}');
      
      try {
        final handler = _eventHandlers[call.method];
        if (handler != null) {
          return await handler(call.arguments);
        }
        
        _logger.warning('No handler registered for method: ${call.method}');
        throw MissingPluginException('No handler for method ${call.method}');
      } catch (e, stackTrace) {
        _logger.severe('Error handling method call: ${call.method}', e, stackTrace);
        throw PlatformException(
          code: 'HANDLER_ERROR',
          message: 'Error handling method call',
          details: e.toString(),
        );
      }
    });
  }
  
  /// Register an event handler
  void registerEventHandler(String event, Function(dynamic) handler) {
    _eventHandlers[event] = handler;
    _logger.fine('Registered handler for event: $event');
  }
  
  /// Unregister an event handler
  void unregisterEventHandler(String event) {
    _eventHandlers.remove(event);
    _logger.fine('Unregistered handler for event: $event');
  }
  
  /// Send a typed message to platform
  Future<PlatformResponse> sendMessage(PlatformMessage message) async {
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        _logger.fine('Sending message: ${message.method}');
        
        try {
          final result = await _channel.invokeMethod(
            message.method,
            message.arguments,
          );
          
          final response = PlatformResponse.fromPlatformResponse(result);
          
          if (response.isError && response is ErrorResponse) {
            throw MCPPlatformException(
              'Platform error: ${response.message}',
              code: response.code,
              details: response.details,
            );
          }
          
          _logger.fine('Received response for ${message.method}: ${response.runtimeType}');
          return response;
          
        } on PlatformException catch (e) {
          _logger.severe('Platform exception: ${e.code} - ${e.message}', e);
          
          // Convert to typed error response
          throw MCPPlatformException(
            e.message ?? 'Platform error',
            code: e.code,
            details: e.details,
          );
        } on MissingPluginException catch (e) {
          _logger.severe('Missing plugin implementation', e);
          
          throw MCPPlatformException(
            'Plugin not implemented for platform',
            code: 'MISSING_PLUGIN',
            details: e.message,
          );
        }
      },
      context: 'platform_channel',
      component: _name,
      metadata: {
        'method': message.method,
        'hasArgs': message.arguments != null,
      },
    );
  }
  
  /// Send a raw method call (for backwards compatibility)
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        _logger.fine('Invoking method: $method');
        return await _channel.invokeMethod<T>(method, arguments);
      },
      context: 'platform_channel_raw',
      component: _name,
      metadata: {
        'method': method,
        'hasArgs': arguments != null,
      },
    );
  }
  
  /// Send a list method call
  Future<List<T>?> invokeListMethod<T>(String method, [dynamic arguments]) async {
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        _logger.fine('Invoking list method: $method');
        return await _channel.invokeListMethod<T>(method, arguments);
      },
      context: 'platform_channel_list',
      component: _name,
      metadata: {
        'method': method,
        'hasArgs': arguments != null,
      },
    );
  }
  
  /// Send a map method call
  Future<Map<K, V>?> invokeMapMethod<K, V>(String method, [dynamic arguments]) async {
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        _logger.fine('Invoking map method: $method');
        return await _channel.invokeMapMethod<K, V>(method, arguments);
      },
      context: 'platform_channel_map',
      component: _name,
      metadata: {
        'method': method,
        'hasArgs': arguments != null,
      },
    );
  }
  
  /// Batch send multiple messages
  Future<List<PlatformResponse>> sendBatch(List<PlatformMessage> messages) async {
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        _logger.fine('Sending batch of ${messages.length} messages');
        
        final futures = messages.map((message) => sendMessage(message));
        return await Future.wait(futures);
      },
      context: 'platform_channel_batch',
      component: _name,
      metadata: {
        'messageCount': messages.length,
        'methods': messages.map((m) => m.method).toList(),
      },
    );
  }
  
  /// Create an event channel for streaming data
  EventChannel createEventChannel(String name) {
    return EventChannel('$_name/$name');
  }
  
  /// Subscribe to platform events
  Stream<T> subscribeToEvent<T>(String eventName) {
    final eventChannel = createEventChannel(eventName);
    
    return eventChannel.receiveBroadcastStream().map((dynamic event) {
      _logger.fine('Received event: $eventName');
      
      if (event is T) {
        return event;
      }
      
      // Try to convert if possible
      if (T == String && event != null) {
        return event.toString() as T;
      }
      
      if (event is Map) {
        return Map<String, dynamic>.from(event) as T;
      }
      
      if (event is List) {
        try {
          return event.cast<String>() as T;
        } catch (_) {
          // Not a List<String>
        }
      }
      
      throw MCPPlatformException(
        'Invalid event type. Expected $T but got ${event.runtimeType}',
        code: 'INVALID_EVENT_TYPE',
      );
    }).handleError((error) {
      _logger.severe('Error in event stream: $eventName', error);
      
      if (error is PlatformException) {
        throw MCPPlatformException(
          error.message ?? 'Platform event error',
          code: error.code,
          details: error.details,
        );
      }
      
      throw error;
    });
  }
}

/// Singleton instance for main flutter_mcp channel
class FlutterMCPChannel {
  static TypedPlatformChannel? _instance;
  
  /// Get the singleton instance
  static TypedPlatformChannel get instance {
    _instance ??= TypedPlatformChannel('flutter_mcp');
    return _instance!;
  }
  
  /// Private constructor to prevent instantiation
  FlutterMCPChannel._();
}

/// Platform exception with additional context
class MCPPlatformException extends MCPException {
  final String code;
  final dynamic details;
  
  MCPPlatformException(
    String message, {
    required this.code,
    this.details,
    StackTrace? stackTrace,
  }) : super('[$code] $message', null, stackTrace);
  
  @override
  String toString() {
    var result = 'MCPPlatformException: $message';
    if (details != null) {
      result += '\nDetails: $details';
    }
    return result;
  }
}