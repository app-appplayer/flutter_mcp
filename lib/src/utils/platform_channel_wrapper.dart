/// Platform channel wrapper for type-safe method channel interactions
library;

import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../utils/operation_wrapper.dart';

/// Type-safe wrapper for Flutter method channels
class PlatformChannelWrapper with OperationWrapperMixin {
  final MethodChannel _channel;
  
  @override
  final Logger logger;
  
  final String channelName;
  
  PlatformChannelWrapper({
    required this.channelName,
    required MethodChannel channel,
  }) : _channel = channel,
       logger = Logger('flutter_mcp.PlatformChannel.$channelName');
  
  /// Factory constructor with standard MCP channel naming
  factory PlatformChannelWrapper.mcp(String feature) {
    final channelName = 'com.example.flutter_mcp/$feature';
    return PlatformChannelWrapper(
      channelName: channelName,
      channel: MethodChannel(channelName),
    );
  }
  
  /// Invoke a method and return the result with type safety
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration? timeout,
  }) async {
    return await executeAsyncOperation<T>(
      operationName: 'channel_invoke_$method',
      operation: () async {
        final result = await _channel.invokeMethod<T>(method, arguments);
        
        if (result == null) {
          throw MCPPlatformNotSupportedException(
            'Method $method on channel $channelName',
            errorCode: 'METHOD_RETURNED_NULL',
            resolution: 'Check if the native implementation returns a proper value',
          );
        }
        
        return result;
      },
      config: OperationConfig(
        timeout: timeout ?? Duration(seconds: 10),
        errorCode: 'PLATFORM_CHANNEL_ERROR',
      ),
    ).then((result) => result.data as T);
  }
  
  /// Invoke a method that returns a list
  Future<List<T>> invokeList<T>({
    required String method,
    Map<String, dynamic>? arguments,
    required T Function(dynamic) itemParser,
    Duration? timeout,
  }) async {
    return await executeAsyncOperation<List<T>>(
      operationName: 'channel_invoke_list_$method',
      operation: () async {
        final result = await _channel.invokeMethod<List<dynamic>>(method, arguments);
        
        if (result == null) {
          return <T>[];
        }
        
        try {
          return result.map(itemParser).toList();
        } catch (e) {
          throw MCPOperationFailedException.withContext(
            'Failed to parse list items from $method',
            e,
            StackTrace.current,
            errorCode: 'PARSE_ERROR',
          );
        }
      },
      config: OperationConfig(
        timeout: timeout ?? Duration(seconds: 10),
        errorCode: 'PLATFORM_CHANNEL_LIST_ERROR',
      ),
    ).then((result) => result.data!);
  }
  
  /// Invoke a method that returns a map
  Future<Map<String, T>> invokeMap<T>({
    required String method,
    Map<String, dynamic>? arguments,
    required T Function(dynamic) valueParser,
    Duration? timeout,
  }) async {
    return await executeAsyncOperation<Map<String, T>>(
      operationName: 'channel_invoke_map_$method',
      operation: () async {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(method, arguments);
        
        if (result == null) {
          return <String, T>{};
        }
        
        try {
          return result.map((key, value) => MapEntry(key.toString(), valueParser(value)));
        } catch (e) {
          throw MCPOperationFailedException.withContext(
            'Failed to parse map values from $method',
            e,
            StackTrace.current,
            errorCode: 'PARSE_ERROR',
          );
        }
      },
      config: OperationConfig(
        timeout: timeout ?? Duration(seconds: 10),
        errorCode: 'PLATFORM_CHANNEL_MAP_ERROR',
      ),
    ).then((result) => result.data!);
  }
  
  /// Invoke a void method (no return value expected)
  Future<void> invokeVoid({
    required String method,
    Map<String, dynamic>? arguments,
    Duration? timeout,
  }) async {
    await executeAsyncOperation<void>(
      operationName: 'channel_invoke_void_$method',
      operation: () async {
        await _channel.invokeMethod<void>(method, arguments);
      },
      config: OperationConfig(
        timeout: timeout ?? Duration(seconds: 10),
        errorCode: 'PLATFORM_CHANNEL_VOID_ERROR',
      ),
    );
  }
  
  /// Check if a method is available on the platform
  Future<bool> isMethodAvailable(String method) async {
    try {
      await _channel.invokeMethod<bool>('isMethodAvailable', {'method': method});
      return true;
    } catch (e) {
      logger.fine('Method $method is not available on $channelName: $e');
      return false;
    }
  }
  
  /// Get platform version or capability info
  Future<String?> getPlatformInfo(String infoKey) async {
    try {
      return await invoke<String>(
        method: 'getPlatformInfo',
        arguments: {'key': infoKey},
        timeout: Duration(seconds: 5),
      );
    } catch (e) {
      logger.warning('Failed to get platform info for $infoKey: $e');
      return null;
    }
  }
  
  /// Set a method call handler for incoming calls from native side
  void setMethodCallHandler(Future<dynamic> Function(MethodCall call)? handler) {
    _channel.setMethodCallHandler(handler != null 
        ? (call) => _handleIncomingCall(call, handler)
        : null);
  }
  
  /// Handle incoming method calls with logging and error handling
  Future<dynamic> _handleIncomingCall(
    MethodCall call, 
    Future<dynamic> Function(MethodCall call) handler,
  ) async {
    return await executeAsyncOperation<dynamic>(
      operationName: 'handle_incoming_${call.method}',
      operation: () async {
        logger.fine('Handling incoming call: ${call.method} with args: ${call.arguments}');
        final result = await handler(call);
        logger.fine('Incoming call ${call.method} completed successfully');
        return result;
      },
      config: OperationConfig(
        timeout: Duration(seconds: 30),
        errorCode: 'INCOMING_CALL_ERROR',
        throwOnError: false, // Don't throw, return error to platform
      ),
    ).then((result) {
      if (result.isSuccess) {
        return result.data;
      } else {
        logger.severe('Failed to handle incoming call ${call.method}: ${result.error}');
        throw PlatformException(
          code: 'HANDLER_ERROR',
          message: result.error,
          details: {'method': call.method, 'arguments': call.arguments},
        );
      }
    });
  }
}

/// Strongly-typed method call result
class TypedMethodResult<T> {
  final bool isSuccess;
  final T? data;
  final String? error;
  final String method;
  final Duration executionTime;
  
  const TypedMethodResult._({
    required this.isSuccess,
    required this.method,
    required this.executionTime,
    this.data,
    this.error,
  });
  
  factory TypedMethodResult.success(String method, T data, Duration executionTime) {
    return TypedMethodResult._(
      isSuccess: true,
      method: method,
      data: data,
      executionTime: executionTime,
    );
  }
  
  factory TypedMethodResult.failure(String method, String error, Duration executionTime) {
    return TypedMethodResult._(
      isSuccess: false,
      method: method,
      error: error,
      executionTime: executionTime,
    );
  }
  
  /// Convert to operation result format
  OperationResult<T> toOperationResult() {
    if (isSuccess) {
      return OperationResult.success(data as T, executionTime);
    } else {
      return OperationResult.failure(error!, executionTime);
    }
  }
  
  Map<String, dynamic> toMap() {
    return {
      'isSuccess': isSuccess,
      'method': method,
      'executionTime': executionTime.inMilliseconds,
      'data': data,
      'error': error,
    };
  }
}

/// Channel manager for handling multiple platform channels
class PlatformChannelManager {
  static final Logger _logger = Logger('flutter_mcp.PlatformChannelManager');
  static final Map<String, PlatformChannelWrapper> _channels = {};
  
  /// Get or create a channel wrapper
  static PlatformChannelWrapper getChannel(String channelName) {
    return _channels.putIfAbsent(channelName, () {
      _logger.fine('Creating new platform channel: $channelName');
      return PlatformChannelWrapper(
        channelName: channelName,
        channel: MethodChannel(channelName),
      );
    });
  }
  
  /// Get or create an MCP-specific channel
  static PlatformChannelWrapper getMcpChannel(String feature) {
    final channelName = 'com.example.flutter_mcp/$feature';
    return getChannel(channelName);
  }
  
  /// Check if a channel exists
  static bool hasChannel(String channelName) {
    return _channels.containsKey(channelName);
  }
  
  /// Remove a channel (useful for cleanup)
  static void removeChannel(String channelName) {
    final channel = _channels.remove(channelName);
    if (channel != null) {
      channel.setMethodCallHandler(null);
      _logger.fine('Removed platform channel: $channelName');
    }
  }
  
  /// Get all active channel names
  static List<String> getActiveChannels() {
    return _channels.keys.toList();
  }
  
  /// Clear all channels (useful for testing or cleanup)
  static void clearAllChannels() {
    for (final channel in _channels.values) {
      channel.setMethodCallHandler(null);
    }
    _channels.clear();
    _logger.fine('Cleared all platform channels');
  }
  
  /// Test connectivity for all channels
  static Future<Map<String, bool>> testChannelConnectivity() async {
    final results = <String, bool>{};
    
    for (final entry in _channels.entries) {
      try {
        await entry.value.invoke<String>(
          method: 'ping',
          timeout: Duration(seconds: 2),
        );
        results[entry.key] = true;
      } catch (e) {
        _logger.warning('Channel ${entry.key} connectivity test failed: $e');
        results[entry.key] = false;
      }
    }
    
    return results;
  }
}