import 'dart:async';
import '../utils/logger.dart';
import 'event_models.dart';

/// Type-safe event system that works alongside the existing event system
class TypedEventSystem {
  final Logger _logger = Logger('flutter_mcp.typed_event_system');

  // Event streams by event type
  final Map<Type, StreamController<McpEvent>> _eventControllers = {};

  // Event subscriptions by token
  final Map<String, StreamSubscription<McpEvent>> _subscriptions = {};

  // Subscription counter for generating unique tokens
  int _subscriptionCounter = 0;

  // Cached events by type (for late subscribers)
  final Map<Type, List<McpEvent>> _cachedEvents = {};

  // Maximum cache size per event type
  final int _maxCacheSize = 10;

  // Whether event system is paused
  bool _isPaused = false;

  // Events queued while paused
  final List<McpEvent> _queuedEvents = [];

  // Singleton instance
  static final TypedEventSystem _instance = TypedEventSystem._internal();

  /// Get singleton instance
  static TypedEventSystem get instance => _instance;

  /// Internal constructor
  TypedEventSystem._internal();

  /// Publish a typed event
  void publish<T extends McpEvent>(T event) {
    if (_isPaused) {
      _queuedEvents.add(event);
      _logger.fine('Event queued: ${event.eventType} (system paused)');
      return;
    }

    final type = T;

    if (!_eventControllers.containsKey(type)) {
      _eventControllers[type] = StreamController<McpEvent>.broadcast();
    }

    // Add to cache for late subscribers
    _addToCache(type, event);

    // Publish event
    _eventControllers[type]!.add(event);

    _logger.fine('Published typed event: ${event.eventType}');
  }

  /// Subscribe to typed events with type safety
  String subscribe<T extends McpEvent>(void Function(T) callback) {
    final type = T;

    if (!_eventControllers.containsKey(type)) {
      _eventControllers[type] = StreamController<McpEvent>.broadcast();
    }

    final token = 'typed_subscription_${_subscriptionCounter++}';

    _subscriptions[token] = _eventControllers[type]!
        .stream
        .where((event) => event is T)
        .cast<T>()
        .listen(callback);

    // Send cached events to new subscriber
    _sendCachedEvents<T>(callback);

    _logger.fine('Added typed subscription for $type with token: $token');

    return token;
  }

  /// Subscribe to multiple event types
  String subscribeMultiple<T extends McpEvent>(
    List<Type> eventTypes,
    void Function(T) callback,
  ) {
    final token = 'typed_multi_subscription_${_subscriptionCounter++}';
    final subscriptions = <StreamSubscription<McpEvent>>[];

    for (final type in eventTypes) {
      if (!_eventControllers.containsKey(type)) {
        _eventControllers[type] = StreamController<McpEvent>.broadcast();
      }

      final subscription = _eventControllers[type]!
          .stream
          .where((event) => event is T)
          .cast<T>()
          .listen(callback);

      subscriptions.add(subscription);
    }

    // Store as a group subscription
    _subscriptions[token] = _GroupSubscription(subscriptions);

    _logger.fine(
        'Added multi-type subscription for ${eventTypes.length} types with token: $token');

    return token;
  }

  /// Unsubscribe from events
  Future<void> unsubscribe(String token) async {
    final subscription = _subscriptions.remove(token);
    if (subscription != null) {
      await subscription.cancel();
      _logger.fine('Cancelled subscription: $token');
    }
  }

  /// Pause event publishing (events will be queued)
  void pause() {
    _isPaused = true;
    _logger.fine('Event system paused');
  }

  /// Resume event publishing and process queued events
  void resume() {
    if (!_isPaused) return;

    _isPaused = false;

    // Process queued events without calling publish (to avoid re-queueing)
    final queuedCount = _queuedEvents.length;
    final eventsToProcess = List<McpEvent>.from(_queuedEvents);
    _queuedEvents.clear();

    for (final event in eventsToProcess) {
      _publishImmediately(event);
    }

    _logger.fine('Event system resumed, processed $queuedCount queued events');
  }

  /// Publish event immediately without checking pause state
  void _publishImmediately(McpEvent event) {
    final type = event.runtimeType;

    if (!_eventControllers.containsKey(type)) {
      _eventControllers[type] = StreamController<McpEvent>.broadcast();
    }

    // Add to cache for late subscribers
    _addToCache(type, event);

    // Publish event
    _eventControllers[type]!.add(event);

    _logger.fine('Published queued typed event: ${event.eventType}');
  }

  /// Get cached events of a specific type
  List<T> getCachedEvents<T extends McpEvent>() {
    final type = T;
    final cached = _cachedEvents[type] ?? [];
    return cached.whereType<T>().toList();
  }

  /// Clear cached events for a specific type or all types
  void clearCache([Type? eventType]) {
    if (eventType != null) {
      _cachedEvents.remove(eventType);
      _logger.fine('Cleared cache for $eventType');
    } else {
      _cachedEvents.clear();
      _logger.fine('Cleared all event cache');
    }
  }

  /// Get statistics about the event system
  Map<String, dynamic> getStatistics() {
    final activeControllers = _eventControllers.length;
    final activeSubscriptions = _subscriptions.length;
    final queuedEvents = _queuedEvents.length;
    final cachedEventCounts = _cachedEvents.map(
      (type, events) => MapEntry(type.toString(), events.length),
    );

    return {
      'activeControllers': activeControllers,
      'activeSubscriptions': activeSubscriptions,
      'queuedEvents': queuedEvents,
      'isPaused': _isPaused,
      'cachedEventCounts': cachedEventCounts,
    };
  }

  /// Dispose all resources
  Future<void> dispose() async {
    // Cancel all subscriptions
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // Close all controllers
    for (final controller in _eventControllers.values) {
      await controller.close();
    }
    _eventControllers.clear();

    // Clear caches
    _cachedEvents.clear();
    _queuedEvents.clear();

    _logger.fine('Typed event system disposed');
  }

  /// Add event to cache
  void _addToCache(Type eventType, McpEvent event) {
    if (!_cachedEvents.containsKey(eventType)) {
      _cachedEvents[eventType] = <McpEvent>[];
    }

    final cache = _cachedEvents[eventType]!;
    cache.add(event);

    // Keep only the most recent events
    if (cache.length > _maxCacheSize) {
      cache.removeAt(0);
    }
  }

  /// Send cached events to new subscriber
  void _sendCachedEvents<T extends McpEvent>(void Function(T) callback) {
    final type = T;
    final cached = _cachedEvents[type];

    if (cached != null) {
      for (final event in cached) {
        if (event is T) {
          // Send cached event asynchronously to avoid blocking
          Future.microtask(() => callback(event));
        }
      }
    }
  }
}

/// Helper class to manage multiple subscriptions as a group
class _GroupSubscription implements StreamSubscription<McpEvent> {
  final List<StreamSubscription<McpEvent>> _subscriptions;

  _GroupSubscription(this._subscriptions);

  @override
  Future<void> cancel() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }

  @override
  void onData(void Function(McpEvent data)? handleData) {
    for (final subscription in _subscriptions) {
      subscription.onData(handleData);
    }
  }

  @override
  void onError(Function? handleError) {
    for (final subscription in _subscriptions) {
      subscription.onError(handleError);
    }
  }

  @override
  void onDone(void Function()? handleDone) {
    for (final subscription in _subscriptions) {
      subscription.onDone(handleDone);
    }
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    for (final subscription in _subscriptions) {
      subscription.pause(resumeSignal);
    }
  }

  @override
  void resume() {
    for (final subscription in _subscriptions) {
      subscription.resume();
    }
  }

  @override
  bool get isPaused => _subscriptions.first.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    return _subscriptions.first.asFuture<E>(futureValue);
  }
}
