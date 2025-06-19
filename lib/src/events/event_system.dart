import 'dart:async';
import 'package:synchronized/synchronized.dart';
import '../utils/logger.dart';

/// Event priority levels
enum EventPriority { low, normal, high, critical }

/// Base event class
abstract class Event {
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  Event({DateTime? timestamp, Map<String, dynamic>? metadata})
      : timestamp = timestamp ?? DateTime.now(),
        metadata = metadata ?? {};
}

/// Event handler configuration
class EventHandlerConfig {
  final EventPriority priority;
  final bool Function(Event)? filter;
  final Duration? debounceTime;
  final Duration? throttleTime;
  final int? maxRetries;
  final Duration? timeout;

  const EventHandlerConfig({
    this.priority = EventPriority.normal,
    this.filter,
    this.debounceTime,
    this.throttleTime,
    this.maxRetries,
    this.timeout,
  });
}

/// Event handler wrapper
class EventHandler<T> {
  final void Function(T) handler;
  final EventHandlerConfig config;
  final String? id;

  Timer? _debounceTimer;
  DateTime? _lastThrottleTime;
  bool _isDisposed = false;

  EventHandler({
    required this.handler,
    EventHandlerConfig? config,
    this.id,
  }) : config = config ?? const EventHandlerConfig();

  void handle(T event) {
    if (_isDisposed) return;

    // Apply filter
    if (config.filter != null && event is Event && !config.filter!(event)) {
      return;
    }

    // Apply debounce
    if (config.debounceTime != null) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(config.debounceTime!, () {
        if (!_isDisposed) _executeHandler(event);
      });
      return;
    }

    // Apply throttle
    if (config.throttleTime != null) {
      final now = DateTime.now();
      if (_lastThrottleTime != null &&
          now.difference(_lastThrottleTime!).compareTo(config.throttleTime!) <
              0) {
        return;
      }
      _lastThrottleTime = now;
    }

    _executeHandler(event);
  }

  void _executeHandler(T event) {
    if (config.timeout != null) {
      Future(() => handler(event)).timeout(config.timeout!).catchError((error) {
        Logger('EventSystem').warning('Handler timeout: $error');
      });
    } else {
      try {
        handler(event);
      } catch (e) {
        Logger('EventSystem').severe('Handler error: $e');
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
  }
}

/// Main event system implementation - combines old and new functionality
class EventSystem {
  static final EventSystem _instance = EventSystem._internal();
  static EventSystem get instance => _instance;

  final Logger _logger = Logger('flutter_mcp.event_system');
  final Lock _lock = Lock();
  final Lock _systemLock = Lock();

  // Topic-based event system (from old version)
  final Map<String, StreamController<dynamic>> _eventControllers = {};
  final Map<String, StreamSubscription<dynamic>> _subscriptions = {};
  final Map<String, List<StreamSubscription<dynamic>>> _subscriptionsByTopic =
      {};

  // Type-based event handlers (from new version)
  final Map<Type, List<EventHandler>> _handlers = {};
  final Map<String, void Function()> _cleanupFunctions = {};

  // Subscription management
  int _subscriptionCounter = 0;

  // Cached events (from old version)
  final Map<String, List<dynamic>> _cachedEvents = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final int _maxCacheSize = 10;
  final Duration _cacheExpiration = Duration(minutes: 5);

  // Statistics
  final Map<Type, int> _eventCounts = {};
  final Map<String, int> _topicCounts = {};

  // System state
  bool _isPaused = false;
  final List<dynamic> _pausedEvents = [];

  // Configuration
  bool _enableCache = true;
  bool _enableLogging = true;
  LogLevel _logLevel = LogLevel.debug;

  EventSystem._internal();

  /// Initialize the event system with configuration
  void initialize({
    bool enableCache = true,
    bool enableLogging = true,
    LogLevel logLevel = LogLevel.debug,
  }) {
    _enableCache = enableCache;
    _enableLogging = enableLogging;
    _logLevel = logLevel;

    if (_enableLogging) {
      _logger.info('Event system initialized');
    }
  }

  // ============= Type-based Event System (New) =============

  /// Subscribe to events of a specific type
  String subscribe<T>(
    void Function(T) handler, {
    EventHandlerConfig? config,
    String? subscriptionId,
  }) {
    final eventHandler = EventHandler<T>(
      handler: handler,
      config: config,
      id: subscriptionId,
    );

    _handlers[T] ??= [];
    _handlers[T]!.add(eventHandler as EventHandler);

    final id =
        subscriptionId ?? 'typed_${DateTime.now().microsecondsSinceEpoch}';

    _cleanupFunctions[id] = () {
      eventHandler.dispose();
      _handlers[T]?.remove(eventHandler);
    };

    _logger.fine('Subscribed to type ${T.toString()} with id: $id');
    return id;
  }

  /// Publish a typed event
  Future<void> publish<T extends Event>(T event) async {
    await _lock.synchronized(() async {
      if (_isPaused) {
        _pausedEvents.add(event);
        return;
      }

      // Update statistics
      _eventCounts[T] = (_eventCounts[T] ?? 0) + 1;

      // Get handlers sorted by priority - check both static type and runtime type
      final staticHandlers = _handlers[T] ?? [];
      final runtimeHandlers = _handlers[event.runtimeType] ?? [];

      // Combine handlers (avoiding duplicates)
      final allHandlers = <EventHandler>{};
      allHandlers.addAll(staticHandlers);
      allHandlers.addAll(runtimeHandlers);

      final sortedHandlers = allHandlers.toList()
        ..sort((a, b) =>
            b.config.priority.index.compareTo(a.config.priority.index));

      // Execute handlers
      for (final handler in sortedHandlers) {
        try {
          handler.handle(event);
        } catch (e) {
          _logger.severe('Error handling event ${T.toString()}: $e');
        }
      }

      _logger.fine('Published typed event: ${T.toString()}');
    });
  }

  /// Publish typed event (backward compatibility)
  Future<void> publishTyped<T>(T event) => publish(event as Event);

  // ============= Topic-based Event System (Old) =============

  /// Subscribe to a topic
  Future<String> subscribeTopic(
    String topic,
    void Function(dynamic) handler, {
    bool Function(dynamic)? filter,
    String? subscriptionId,
  }) {
    return _systemLock.synchronized(() async {
      final controller = _getOrCreateController(topic);

      Stream<dynamic> stream = controller.stream;
      if (filter != null) {
        stream = stream.where(filter);
      }

      final subscription = stream.listen(
        handler,
        onError: (error) => _logger.warning('Topic handler error: $error'),
      );

      final token = subscriptionId ?? 'topic_${++_subscriptionCounter}';
      _subscriptions[token] = subscription;

      _subscriptionsByTopic[topic] ??= [];
      _subscriptionsByTopic[topic]!.add(subscription);

      // Send cached events if any
      if (_enableCache && _cachedEvents.containsKey(topic)) {
        _sendCachedEvents(topic, handler);
      }

      _logger.fine('Subscribed to topic "$topic" with token: $token');
      return token;
    });
  }

  /// Publish to a topic
  Future<void> publishTopic(String topic, dynamic data) async {
    await _systemLock.synchronized(() async {
      if (_isPaused) {
        _pausedEvents.add({'topic': topic, 'data': data});
        return;
      }

      _topicCounts[topic] = (_topicCounts[topic] ?? 0) + 1;

      final controller = _getOrCreateController(topic);
      // Check if controller is closed before adding
      if (!controller.isClosed) {
        controller.add(data);
      } else {
        _logger.warning('Attempted to publish to closed topic: $topic');
        return;
      }

      // Cache event if enabled
      if (_enableCache) {
        _cacheEvent(topic, data);
      }

      if (_enableLogging && _logLevel.index <= LogLevel.debug.index) {
        _logger.fine('Published to topic "$topic"');
      }
    });
  }

  // ============= Common Methods =============

  /// Unsubscribe from events
  Future<void> unsubscribe(String subscriptionId) async {
    await _lock.synchronized(() async {
      // Try typed subscription cleanup
      final cleanup = _cleanupFunctions[subscriptionId];
      if (cleanup != null) {
        cleanup();
        _cleanupFunctions.remove(subscriptionId);
      }

      // Try topic subscription cleanup
      final subscription = _subscriptions[subscriptionId];
      if (subscription != null) {
        await subscription.cancel();
        _subscriptions.remove(subscriptionId);

        // Remove from topic subscriptions
        _subscriptionsByTopic.forEach((topic, subs) {
          subs.remove(subscription);
        });
      }

      _logger.fine('Unsubscribed: $subscriptionId');
    });
  }

  /// Pause event processing
  Future<void> pause() async {
    await _lock.synchronized(() async {
      _isPaused = true;

      // Pause topic subscriptions
      for (final subscriptions in _subscriptionsByTopic.values) {
        for (final sub in subscriptions) {
          sub.pause();
        }
      }

      _logger.info('Event system paused');
    });
  }

  /// Resume event processing
  Future<void> resume() async {
    List<dynamic> eventsToProcess = [];

    await _lock.synchronized(() async {
      _isPaused = false;

      // Resume topic subscriptions
      for (final subscriptions in _subscriptionsByTopic.values) {
        for (final sub in subscriptions) {
          sub.resume();
        }
      }

      // Get paused events to process
      eventsToProcess = List.from(_pausedEvents);
      _pausedEvents.clear();

      _logger.info('Event system resumed');
    });

    // Process paused events outside the lock to avoid deadlock
    for (final event in eventsToProcess) {
      if (event is Event) {
        await publish(event);
      } else if (event is Map && event.containsKey('topic')) {
        await publishTopic(event['topic'], event['data']);
      }
    }
  }

  /// Get event statistics
  Map<String, dynamic> getStatistics() {
    return {
      'eventCounts': Map<String, int>.fromEntries(
        _eventCounts.entries.map((e) => MapEntry(e.key.toString(), e.value)),
      ),
      'topicCounts': Map<String, int>.from(_topicCounts),
      'activeHandlers': _handlers
          .map((type, handlers) => MapEntry(type.toString(), handlers.length)),
      'activeTopics': _eventControllers.keys.toList(),
      'cachedTopics': _cachedEvents.keys.toList(),
      'isPaused': _isPaused,
      'pausedEventCount': _pausedEvents.length,
    };
  }

  /// Clear all subscriptions and reset
  Future<void> reset() async {
    await _lock.synchronized(() async {
      // Dispose all typed handlers
      for (final handlers in _handlers.values) {
        for (final handler in handlers) {
          handler.dispose();
        }
      }
      _handlers.clear();
      _cleanupFunctions.clear();

      // Cancel all topic subscriptions
      for (final subscription in _subscriptions.values) {
        await subscription.cancel();
      }
      _subscriptions.clear();
      _subscriptionsByTopic.clear();

      // Close all controllers
      for (final controller in _eventControllers.values) {
        await controller.close();
      }
      _eventControllers.clear();

      // Clear caches and statistics
      _cachedEvents.clear();
      _cacheTimestamps.clear();
      _eventCounts.clear();
      _topicCounts.clear();
      _pausedEvents.clear();
      _isPaused = false;

      _logger.info('Event system reset');
    });
  }

  /// Dispose the event system
  Future<void> dispose() async {
    await reset();
    _logger.info('Event system disposed');
  }

  // ============= Private Helper Methods =============

  StreamController<dynamic> _getOrCreateController(String topic) {
    if (!_eventControllers.containsKey(topic)) {
      _eventControllers[topic] = StreamController<dynamic>.broadcast();
    }
    return _eventControllers[topic]!;
  }

  void _cacheEvent(String topic, dynamic data) {
    _cachedEvents[topic] ??= [];
    _cachedEvents[topic]!.add(data);

    // Limit cache size
    if (_cachedEvents[topic]!.length > _maxCacheSize) {
      _cachedEvents[topic]!.removeAt(0);
    }

    _cacheTimestamps[topic] = DateTime.now();

    // Clean expired caches
    _cleanExpiredCaches();
  }

  void _sendCachedEvents(String topic, void Function(dynamic) handler) {
    final cached = _cachedEvents[topic];
    if (cached != null && cached.isNotEmpty) {
      for (final event in cached) {
        try {
          handler(event);
        } catch (e) {
          _logger.warning('Failed to deliver cached event: $e');
        }
      }
    }
  }

  void _cleanExpiredCaches() {
    final now = DateTime.now();
    final expiredTopics = <String>[];

    _cacheTimestamps.forEach((topic, timestamp) {
      if (now.difference(timestamp) > _cacheExpiration) {
        expiredTopics.add(topic);
      }
    });

    for (final topic in expiredTopics) {
      _cachedEvents.remove(topic);
      _cacheTimestamps.remove(topic);
    }
  }
}

/// Log levels for event system
enum LogLevel {
  none,
  error,
  warning,
  info,
  debug,
}

/// Convenience extension for publishing events
extension EventPublisher on Event {
  Future<void> publish() => EventSystem.instance.publish(this);
}
