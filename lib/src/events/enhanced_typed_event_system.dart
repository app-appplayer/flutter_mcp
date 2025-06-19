/// Enhanced type-safe event system with advanced features
library;

import 'dart:async';
import 'dart:collection';
import '../utils/logger.dart';
import '../metrics/typed_metrics.dart';
import '../utils/performance_monitor.dart';
import 'event_models.dart';

/// Event subscription with metadata
class EventSubscription<T extends McpEvent> {
  final String id;
  final Type eventType;
  final void Function(T) handler;
  final DateTime createdAt;
  final String? description;
  final Map<String, dynamic> metadata;
  final StreamSubscription<McpEvent> _streamSubscription;

  EventSubscription({
    required this.id,
    required this.eventType,
    required this.handler,
    required this.description,
    required this.metadata,
    required StreamSubscription<McpEvent> streamSubscription,
  })  : createdAt = DateTime.now(),
        _streamSubscription = streamSubscription;

  /// Cancel the subscription
  Future<void> cancel() => _streamSubscription.cancel();

  /// Check if subscription is active
  bool get isActive => !_streamSubscription.isPaused;

  /// Pause the subscription
  void pause() => _streamSubscription.pause();

  /// Resume the subscription
  void resume() => _streamSubscription.resume();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'eventType': eventType.toString(),
      'createdAt': createdAt.toIso8601String(),
      'description': description,
      'metadata': metadata,
      'isActive': isActive,
    };
  }
}

/// Event handler with filtering and transformation capabilities
class EventHandler<T extends McpEvent, R> {
  final String id;
  final bool Function(T)? filter;
  final R Function(T)? transform;
  final void Function(R) handler;
  final int? priority;
  final Duration? timeout;
  final int? maxInvocations;

  int _invocations = 0;
  DateTime? _lastInvocation;

  EventHandler({
    required this.id,
    required this.handler,
    this.filter,
    this.transform,
    this.priority = 0,
    this.timeout,
    this.maxInvocations,
  });

  /// Check if handler should process the event
  bool shouldHandle(T event) {
    // Check max invocations
    if (maxInvocations != null && _invocations >= maxInvocations!) {
      return false;
    }

    // Check timeout
    if (timeout != null && _lastInvocation != null) {
      final timeSinceLastInvocation =
          DateTime.now().difference(_lastInvocation!);
      if (timeSinceLastInvocation < timeout!) {
        return false;
      }
    }

    // Check filter
    if (filter != null && !filter!(event)) {
      return false;
    }

    return true;
  }

  /// Handle the event
  void handle(T event) {
    if (!shouldHandle(event)) return;

    _invocations++;
    _lastInvocation = DateTime.now();

    if (transform != null) {
      final transformed = transform!(event);
      handler(transformed);
    } else {
      handler(event as R);
    }
  }

  Map<String, dynamic> getStatistics() {
    return {
      'id': id,
      'invocations': _invocations,
      'lastInvocation': _lastInvocation?.toIso8601String(),
      'priority': priority,
      'hasFilter': filter != null,
      'hasTransform': transform != null,
      'hasTimeout': timeout != null,
      'maxInvocations': maxInvocations,
    };
  }
}

/// Event middleware for intercepting and modifying events
abstract class EventMiddleware {
  String get name;
  int get priority;

  /// Process event before publishing
  FutureOr<McpEvent?> onPublish(McpEvent event);

  /// Process event before delivering to handler
  FutureOr<McpEvent?> onDeliver(McpEvent event, String handlerId);

  /// Handle errors in event processing
  void onError(Object error, StackTrace stackTrace, McpEvent event);
}

/// Event replay system for debugging and testing
class EventReplaySystem {
  final Queue<_ReplayableEvent> _eventHistory = Queue();
  final int _maxHistorySize;
  bool _isRecording = false;

  EventReplaySystem({int maxHistorySize = 1000})
      : _maxHistorySize = maxHistorySize;

  /// Start recording events
  void startRecording() {
    _isRecording = true;
  }

  /// Stop recording events
  void stopRecording() {
    _isRecording = false;
  }

  /// Record an event
  void recordEvent(McpEvent event, {Map<String, dynamic>? context}) {
    if (!_isRecording) return;

    _eventHistory.add(_ReplayableEvent(
      event: event,
      timestamp: DateTime.now(),
      context: context ?? {},
    ));

    // Maintain history size
    while (_eventHistory.length > _maxHistorySize) {
      _eventHistory.removeFirst();
    }
  }

  /// Replay events to a target event system
  Future<void> replayEvents(
    EnhancedTypedEventSystem target, {
    DateTime? fromTime,
    DateTime? toTime,
    bool Function(McpEvent)? filter,
  }) async {
    final eventsToReplay = _eventHistory.where((replay) {
      // Time filter
      if (fromTime != null && replay.timestamp.isBefore(fromTime)) {
        return false;
      }
      if (toTime != null && replay.timestamp.isAfter(toTime)) {
        return false;
      }

      // Custom filter
      if (filter != null && !filter(replay.event)) {
        return false;
      }

      return true;
    }).toList();

    for (final replay in eventsToReplay) {
      target.publish(replay.event);

      // Small delay to maintain temporal order
      await Future.delayed(Duration(milliseconds: 1));
    }
  }

  /// Get event history
  List<Map<String, dynamic>> getHistory({
    DateTime? fromTime,
    DateTime? toTime,
  }) {
    return _eventHistory
        .where((replay) {
          if (fromTime != null && replay.timestamp.isBefore(fromTime)) {
            return false;
          }
          if (toTime != null && replay.timestamp.isAfter(toTime)) {
            return false;
          }
          return true;
        })
        .map((replay) => {
              'event': replay.event.toMap(),
              'timestamp': replay.timestamp.toIso8601String(),
              'context': replay.context,
            })
        .toList();
  }

  /// Clear event history
  void clearHistory() {
    _eventHistory.clear();
  }
}

/// Enhanced typed event system with advanced features
class EnhancedTypedEventSystem {
  final Logger _logger = Logger('flutter_mcp.enhanced_typed_event_system');

  // Event streams by event type
  final Map<Type, StreamController<McpEvent>> _eventControllers = {};

  // Event subscriptions with metadata
  final Map<String, EventSubscription> _subscriptions = {};

  // Event handlers with advanced capabilities
  final Map<Type, List<EventHandler>> _handlers = {};

  // Event middleware
  final List<EventMiddleware> _middleware = [];

  // Subscription counter for generating unique IDs
  int _subscriptionCounter = 0;

  // Cached events by type (for late subscribers)
  final Map<Type, Queue<McpEvent>> _cachedEvents = {};

  // Maximum cache size per event type
  final int _maxCacheSize;

  // Whether event system is paused
  bool _isPaused = false;

  // Events queued while paused
  final Queue<McpEvent> _queuedEvents = Queue();

  // Performance monitoring
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor.instance;

  // Event replay system
  final EventReplaySystem _replaySystem;

  // Event statistics
  int _totalEventsPublished = 0;
  int _totalEventsDelivered = 0;
  final Map<Type, int> _eventCounts = {};

  // Singleton instance
  static final EnhancedTypedEventSystem _instance =
      EnhancedTypedEventSystem._internal();

  /// Get singleton instance
  static EnhancedTypedEventSystem get instance => _instance;

  /// Internal constructor
  EnhancedTypedEventSystem._internal()
      : _maxCacheSize = 50,
        _replaySystem = EventReplaySystem();

  /// Publish a typed event with middleware processing
  Future<void> publish<T extends McpEvent>(T event) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Apply middleware preprocessing with timeout to prevent hanging
      McpEvent? processedEvent = event;

      // Process middleware with timeout to prevent deadlock
      for (final middleware in _middleware) {
        try {
          final middlewareResult = middleware.onPublish(processedEvent!);
          if (middlewareResult is Future<McpEvent?>) {
            // Add timeout to prevent hanging
            processedEvent = await middlewareResult.timeout(
              Duration(seconds: 5),
              onTimeout: () => processedEvent,
            );
          } else {
            processedEvent = middlewareResult;
          }

          if (processedEvent == null) {
            _logger.fine('Event blocked by middleware: ${middleware.name}');
            return;
          }
        } catch (e) {
          _logger.warning('Middleware ${middleware.name} failed, skipping', e);
          // Continue with original event if middleware fails
        }
      }

      if (_isPaused) {
        _queuedEvents.add(processedEvent!);
        _logger
            .fine('Event queued: ${processedEvent.eventType} (system paused)');
        return;
      }

      // Publish immediately without await to prevent blocking
      _publishImmediately(processedEvent!).catchError((e, stackTrace) {
        _logger.severe('Error in publish immediately', e, stackTrace);
      });

      // Record metrics
      _recordPublishMetric(processedEvent.runtimeType, stopwatch.elapsed, true);
    } catch (e, stackTrace) {
      _logger.severe('Error publishing event', e, stackTrace);
      _recordPublishMetric(event.runtimeType, stopwatch.elapsed, false);
      rethrow;
    }
  }

  /// Subscribe with advanced handler
  String subscribeAdvanced<T extends McpEvent, R>({
    required void Function(R) handler,
    bool Function(T)? filter,
    R Function(T)? transform,
    int priority = 0,
    Duration? timeout,
    int? maxInvocations,
    String? description,
    Map<String, dynamic> metadata = const {},
  }) {
    final handlerId = 'handler_${_subscriptionCounter++}';
    final eventType = T;

    final eventHandler = EventHandler<T, R>(
      id: handlerId,
      handler: handler,
      filter: filter,
      transform: transform,
      priority: priority,
      timeout: timeout,
      maxInvocations: maxInvocations,
    );

    // Add to handlers list (sorted by priority)
    _handlers.putIfAbsent(eventType, () => []).add(eventHandler);
    _handlers[eventType]!
        .sort((a, b) => (b.priority ?? 0).compareTo(a.priority ?? 0));

    // Create stream subscription
    if (!_eventControllers.containsKey(eventType)) {
      _eventControllers[eventType] = StreamController<McpEvent>.broadcast();
    }

    final streamSubscription = _eventControllers[eventType]!
        .stream
        .where((event) => event is T)
        .cast<T>()
        .listen((event) {
      // Process event synchronously to avoid hanging issues
      _processEventDelivery(event, eventHandler, handlerId);
    });

    final subscription = EventSubscription<T>(
      id: handlerId,
      eventType: eventType,
      handler: (event) => eventHandler.handle(event),
      description: description,
      metadata: metadata,
      streamSubscription: streamSubscription,
    );

    _subscriptions[handlerId] = subscription;

    // Send cached events to new subscriber
    _sendCachedEvents<T>(eventHandler);

    _logger
        .fine('Added advanced subscription for $eventType with ID: $handlerId');

    return handlerId;
  }

  /// Simple subscribe method for backward compatibility
  String subscribe<T extends McpEvent>(void Function(T) handler) {
    return subscribeAdvanced<T, T>(handler: handler);
  }

  /// Subscribe to multiple event types with pattern matching
  String subscribePattern({
    required Pattern eventTypePattern,
    required void Function(McpEvent) handler,
    String? description,
    Map<String, dynamic> metadata = const {},
  }) {
    final subscriptionId = 'pattern_${_subscriptionCounter++}';
    final subscriptions = <String>[];

    // Find matching event types from current controllers
    for (final eventType in _eventControllers.keys) {
      if (eventTypePattern.allMatches(eventType.toString()).isNotEmpty) {
        final subId = subscribeAdvanced<McpEvent, McpEvent>(
          handler: handler,
          description: '$description (pattern match for $eventType)',
          metadata: {...metadata, 'patternSubscription': subscriptionId},
        );
        subscriptions.add(subId);
      }
    }

    // Store pattern subscription metadata
    // Create a completer-based dummy subscription that can be properly canceled
    final dummyController = StreamController<McpEvent>();
    final dummySubscription = dummyController.stream.listen((_) {});
    dummyController.close(); // Close immediately to prevent leaks

    _subscriptions[subscriptionId] = EventSubscription<McpEvent>(
      id: subscriptionId,
      eventType: McpEvent,
      handler: handler,
      description: description,
      metadata: {
        ...metadata,
        'type': 'pattern',
        'subSubscriptions': subscriptions
      },
      streamSubscription: dummySubscription,
    );

    return subscriptionId;
  }

  /// Add event middleware
  void addMiddleware(EventMiddleware middleware) {
    _middleware.add(middleware);
    _middleware.sort((a, b) => b.priority.compareTo(a.priority));
    _logger.info(
        'Added middleware: ${middleware.name} (priority: ${middleware.priority})');
  }

  /// Remove event middleware
  void removeMiddleware(String name) {
    _middleware.removeWhere((m) => m.name == name);
    _logger.info('Removed middleware: $name');
  }

  /// Unsubscribe from events
  Future<void> unsubscribe(String subscriptionId) async {
    final subscription = _subscriptions.remove(subscriptionId);
    if (subscription != null) {
      await subscription.cancel();

      // Remove from handlers list
      for (final handlers in _handlers.values) {
        handlers.removeWhere((h) => h.id == subscriptionId);
      }

      _logger.fine('Cancelled subscription: $subscriptionId');
    }
  }

  /// Get subscription information
  EventSubscription? getSubscription(String subscriptionId) {
    return _subscriptions[subscriptionId];
  }

  /// Get all active subscriptions
  List<EventSubscription> getActiveSubscriptions() {
    return _subscriptions.values.toList();
  }

  /// Pause event publishing (events will be queued)
  void pause() {
    _isPaused = true;
    _logger.fine('Enhanced event system paused');
  }

  /// Resume event publishing and process queued events
  Future<void> resume() async {
    if (!_isPaused) return;

    _isPaused = false;

    // Process queued events
    final queuedCount = _queuedEvents.length;
    final eventsToProcess = List<McpEvent>.from(_queuedEvents);
    _queuedEvents.clear();

    for (final event in eventsToProcess) {
      await _publishImmediately(event);
    }

    _logger.fine(
        'Enhanced event system resumed, processed $queuedCount queued events');
  }

  /// Get comprehensive statistics
  Map<String, dynamic> getStatistics() {
    final handlerCounts = <String, int>{};
    for (final entry in _handlers.entries) {
      handlerCounts[entry.key.toString()] = entry.value.length;
    }

    final cachedEventCounts = <String, int>{};
    for (final entry in _cachedEvents.entries) {
      cachedEventCounts[entry.key.toString()] = entry.value.length;
    }

    return {
      'totalEventsPublished': _totalEventsPublished,
      'totalEventsDelivered': _totalEventsDelivered,
      'activeSubscriptions': _subscriptions.length,
      'activeControllers': _eventControllers.length,
      'queuedEvents': _queuedEvents.length,
      'isPaused': _isPaused,
      'middlewareCount': _middleware.length,
      'eventTypeCounts': _eventCounts,
      'handlerCounts': handlerCounts,
      'cachedEventCounts': cachedEventCounts,
      'replaySystemRecording': _replaySystem._isRecording,
      'replayHistorySize': _replaySystem._eventHistory.length,
    };
  }

  /// Get handler statistics
  Map<String, dynamic> getHandlerStatistics() {
    final stats = <String, dynamic>{};

    for (final handlers in _handlers.values) {
      for (final handler in handlers) {
        stats[handler.id] = handler.getStatistics();
      }
    }

    return stats;
  }

  /// Enable event recording for replay
  void startRecording() {
    _replaySystem.startRecording();
  }

  /// Disable event recording
  void stopRecording() {
    _replaySystem.stopRecording();
  }

  /// Replay recorded events
  Future<void> replayEvents({
    DateTime? fromTime,
    DateTime? toTime,
    bool Function(McpEvent)? filter,
  }) async {
    await _replaySystem.replayEvents(
      this,
      fromTime: fromTime,
      toTime: toTime,
      filter: filter,
    );
  }

  /// Get event history
  List<Map<String, dynamic>> getEventHistory({
    DateTime? fromTime,
    DateTime? toTime,
  }) {
    return _replaySystem.getHistory(fromTime: fromTime, toTime: toTime);
  }

  /// Clear all caches and reset system
  Future<void> reset() async {
    // Cancel all subscriptions
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // Clear handlers
    _handlers.clear();

    // Close all controllers
    for (final controller in _eventControllers.values) {
      await controller.close();
    }
    _eventControllers.clear();

    // Clear caches
    _cachedEvents.clear();
    _queuedEvents.clear();

    // Reset statistics
    _totalEventsPublished = 0;
    _totalEventsDelivered = 0;
    _eventCounts.clear();

    // Clear replay history
    _replaySystem.clearHistory();

    _logger.info('Enhanced event system reset');
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await reset();
    _logger.fine('Enhanced typed event system disposed');
  }

  /// Publish event immediately without middleware or pause checks
  Future<void> _publishImmediately(McpEvent event) async {
    final eventType = event.runtimeType;

    if (!_eventControllers.containsKey(eventType)) {
      _eventControllers[eventType] = StreamController<McpEvent>.broadcast();
    }

    // Add to cache for late subscribers
    _addToCache(eventType, event);

    // Record for replay
    _replaySystem.recordEvent(event);

    // Publish event
    _eventControllers[eventType]!.add(event);

    // Update statistics
    _totalEventsPublished++;
    _eventCounts[eventType] = (_eventCounts[eventType] ?? 0) + 1;

    _logger.fine('Published typed event: ${event.eventType}');
  }

  /// Add event to cache
  void _addToCache(Type eventType, McpEvent event) {
    _cachedEvents.putIfAbsent(eventType, () => Queue<McpEvent>());

    final cache = _cachedEvents[eventType]!;
    cache.add(event);

    // Keep only the most recent events
    while (cache.length > _maxCacheSize) {
      cache.removeFirst();
    }
  }

  /// Send cached events to new subscriber
  void _sendCachedEvents<T extends McpEvent>(EventHandler handler) {
    final eventType = T;
    final cached = _cachedEvents[eventType];

    if (cached != null) {
      for (final event in cached) {
        if (event is T) {
          // Send cached event synchronously to avoid timing issues
          try {
            handler.handle(event);
          } catch (e, stackTrace) {
            _logger.severe('Error delivering cached event', e, stackTrace);
          }
        }
      }
    }
  }

  /// Process event delivery synchronously to avoid hanging issues
  void _processEventDelivery<T extends McpEvent, R>(
    T event,
    EventHandler<T, R> eventHandler,
    String handlerId,
  ) {
    // Process synchronously to avoid async timing issues
    try {
      // Skip middleware async processing to prevent deadlocks
      eventHandler.handle(event);
      _totalEventsDelivered++;
    } catch (e, stackTrace) {
      _logger.severe('Error in event handler $handlerId', e, stackTrace);

      // Skip middleware error handling to prevent deadlocks
      // Just log the error and continue
    }
  }

  /// Record publish performance metric
  void _recordPublishMetric(Type eventType, Duration duration, bool success) {
    final metric = TimerMetric(
      name: 'event.publish',
      duration: duration,
      operation: 'publish_${eventType.toString()}',
      success: success,
    );

    _performanceMonitor.recordTypedMetric(metric);
  }
}

/// Replayable event with context
class _ReplayableEvent {
  final McpEvent event;
  final DateTime timestamp;
  final Map<String, dynamic> context;

  _ReplayableEvent({
    required this.event,
    required this.timestamp,
    required this.context,
  });
}
