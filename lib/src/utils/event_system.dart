import 'dart:async';
import '../utils/logger.dart';
import '../utils/error_recovery.dart';
import '../events/event_models.dart';
import '../events/enhanced_typed_event_system.dart';

/// Type-safe event system for components to communicate across the application
class EventSystem {
  final Logger _logger = Logger('flutter_mcp.event_system');

  // Event streams by topic
  final Map<String, StreamController<dynamic>> _eventControllers = {};

  // Event subscriptions by token
  final Map<String, StreamSubscription<dynamic>> _subscriptions = {};

  // Subscription counter for generating unique tokens
  int _subscriptionCounter = 0;

  // Cached events by topic (for late subscribers)
  final Map<String, List<dynamic>> _cachedEvents = {};

  // Maximum cache size per topic
  final int _maxCacheSize = 10;

  // Whether event system is paused
  bool _isPaused = false;

  // Events queued while paused
  final List<_QueuedEvent> _queuedEvents = [];

  // Enhanced typed event system instance
  final EnhancedTypedEventSystem _enhancedSystem = EnhancedTypedEventSystem.instance;

  // Singleton instance
  static final EventSystem _instance = EventSystem._internal();

  /// Get singleton instance
  static EventSystem get instance => _instance;

  /// Internal constructor
  EventSystem._internal();

  /// Publish a typed MCP event (new enhanced type-safe API)
  Future<void> publishTyped<T extends McpEvent>(T event) async {
    // For ServiceLifecycleEvent and ResourceLifecycleEvent, use the enhanced system directly
    if (event.runtimeType.toString().contains('ServiceLifecycleEvent') || 
        event.runtimeType.toString().contains('ResourceLifecycleEvent')) {
      await _enhancedSystem.publish<T>(event);
      return;
    }
    
    // Temporarily bypass enhanced system for other events due to hanging issues
    // TODO: Fix async handling in EnhancedTypedEventSystem
    // await _enhancedSystem.publish<T>(event);
    
    // Publish to legacy system 
    publish(event.eventType, event.toMap());
  }

  /// Subscribe to typed MCP events (new enhanced type-safe API)
  String subscribeTyped<T extends McpEvent>(void Function(T) handler) {
    // For ServiceLifecycleEvent and ResourceLifecycleEvent, use the enhanced system directly
    if (T.toString().contains('ServiceLifecycleEvent') || T.toString().contains('ResourceLifecycleEvent')) {
      return _enhancedSystem.subscribe<T>(handler);
    }
    
    // Temporarily bypass enhanced system for other events due to hanging issues
    // TODO: Fix async handling in EnhancedTypedEventSystem
    // return _enhancedSystem.subscribe<T>(handler);
    
    // Determine the event type topic
    String topic;
    if (T.toString().contains('ServerEvent')) {
      topic = 'server.status';
    } else if (T.toString().contains('MemoryEvent')) {
      topic = 'memory.high';
    } else if (T.toString().contains('ClientEvent')) {
      topic = 'client.status';
    } else if (T.toString().contains('PerformanceEvent')) {
      topic = 'performance.update';
    } else {
      // Use type name as fallback
      topic = T.toString().toLowerCase();
    }
    
    // Use legacy system with type checking
    return subscribe<Map<String, dynamic>>(topic, (data) {
      try {
        // Create instance from map data
        late T event;
        if (T.toString().contains('ServerEvent')) {
          event = ServerEvent.fromMap(data) as T;
        } else if (T.toString().contains('MemoryEvent')) {
          event = MemoryEvent.fromMap(data) as T;
        } else if (T.toString().contains('ClientEvent')) {
          event = ClientEvent.fromMap(data) as T;
        } else if (T.toString().contains('PerformanceEvent')) {
          event = PerformanceEvent.fromMap(data) as T;
        } else {
          // For other event types, try to use a generic approach
          _logger.warning('Unknown event type: $T');
          return;
        }
        handler(event);
      } catch (e, stackTrace) {
        _logger.severe('Error converting event data to $T', e, stackTrace);
      }
    });
  }

  /// Subscribe with advanced filtering and transformation (enhanced type-safe API)
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
    // Temporarily bypass enhanced system due to hanging issues
    // TODO: Fix async handling in EnhancedTypedEventSystem
    
    // Use legacy system with manual filtering and transformation
    int invocations = 0;
    return subscribeTyped<T>((event) {
      if (maxInvocations != null && invocations >= maxInvocations) {
        return;
      }
      
      if (filter != null && !filter(event)) {
        return;
      }
      
      invocations++;
      
      final result = transform != null ? transform(event) : event as R;
      handler(result);
    });
  }

  /// Subscribe to multiple event types with pattern matching
  String subscribePattern({
    required Pattern eventTypePattern,
    required void Function(McpEvent) handler,
    String? description,
    Map<String, dynamic> metadata = const {},
  }) {
    // Temporarily bypass enhanced system due to hanging issues
    // TODO: Fix async handling in EnhancedTypedEventSystem
    _logger.warning('Pattern subscriptions temporarily disabled');
    return 'pattern_disabled';
  }

  /// Publish an event to a topic
  void publish<T>(String topic, T event) {
    if (_isPaused) {
      _queuedEvents.add(_QueuedEvent<T>(topic, event));
      _logger.fine('Event queued for topic: $topic (system paused)');
      return;
    }

    if (!_eventControllers.containsKey(topic)) {
      // Create a controller if we need to cache but don't have subscribers yet
      if (_shouldCacheTopic(topic)) {
        _eventControllers[topic] = StreamController<dynamic>.broadcast();
      } else {
        _logger.fine('No subscribers for topic: $topic');
        return;
      }
    }

    _logger.fine('Publishing event to topic: $topic');

    // Add to cache if this topic uses caching
    if (_shouldCacheTopic(topic)) {
      _cacheEvent(topic, event);
    }

    // Publish to subscribers
    _eventControllers[topic]!.add(event);
  }

  /// Subscribe to a topic
  String subscribe<T>(String topic, void Function(T) handler) {
    _logger.fine('Subscribing to topic: $topic');

    // Create stream controller if it doesn't exist
    if (!_eventControllers.containsKey(topic)) {
      _eventControllers[topic] = StreamController<dynamic>.broadcast();
    }

    // Generate unique token
    final token = '${topic}_${++_subscriptionCounter}';

    // Create subscription with type checking
    final subscription = _eventControllers[topic]!.stream
        .where((event) => event is T)
        .cast<T>()
        .listen((event) {
      try {
        handler(event);
      } catch (e, stackTrace) {
        _logger.severe('Error in event handler for topic $topic', e, stackTrace);
      }
    });

    // Store subscription with token
    _subscriptions[token] = subscription;

    // Deliver cached events if available
    _deliverCachedEvents<T>(topic, handler);

    return token;
  }

  /// Unsubscribe using token
  void unsubscribe(String token) {
    if (!_subscriptions.containsKey(token)) {
      _logger.warning('Subscription not found: $token');
      return;
    }

    _logger.fine('Unsubscribing: $token');

    // Cancel subscription
    _subscriptions[token]!.cancel();
    _subscriptions.remove(token);

    // Extract topic from token
    final topic = token.split('_').first;

    // Check if this was the last subscription for the topic
    if (_subscriptions.keys.where((k) => k.startsWith('${topic}_')).isEmpty) {
      _logger.fine('No more subscribers for topic: $topic, cleaning up');
      _eventControllers[topic]?.close();
      _eventControllers.remove(topic);

      // Don't remove cached events - they may be needed for future subscribers
    }
  }

  /// Unsubscribe all handlers from a topic
  void unsubscribeFromTopic(String topic) {
    _logger.fine('Unsubscribing all from topic: $topic');

    // Find all tokens for this topic
    final tokensToRemove = _subscriptions.keys
        .where((token) => token.startsWith('${topic}_'))
        .toList();

    // Cancel each subscription
    for (final token in tokensToRemove) {
      _subscriptions[token]!.cancel();
      _subscriptions.remove(token);
    }

    // Clean up controller
    _eventControllers[topic]?.close();
    _eventControllers.remove(topic);

    // Don't remove cached events
  }

  /// Check if a topic has subscribers
  bool hasSubscribers(String topic) {
    return _eventControllers.containsKey(topic) &&
        !_eventControllers[topic]!.isClosed &&
        _subscriptions.keys.where((token) => token.startsWith('${topic}_')).isNotEmpty;
  }

  /// Get number of subscribers for a topic
  int subscriberCount(String topic) {
    if (!_eventControllers.containsKey(topic)) {
      return 0;
    }

    return _subscriptions.keys.where((token) => token.startsWith('${topic}_')).length;
  }

  /// Create a filterable subscription
  String subscribeWithFilter<T>(
      String topic,
      void Function(T) handler,
      bool Function(T) filter,
      ) {
    _logger.fine('Subscribing to topic with filter: $topic');

    // Create stream controller if it doesn't exist
    if (!_eventControllers.containsKey(topic)) {
      _eventControllers[topic] = StreamController<dynamic>.broadcast();
    }

    // Generate unique token
    final token = '${topic}_${++_subscriptionCounter}';

    // Create subscription with filter
    final subscription = _eventControllers[topic]!.stream
        .where((event) => event is T && filter(event))
        .cast<T>()
        .listen((event) {
      try {
        handler(event);
      } catch (e, stackTrace) {
        _logger.severe('Error in filtered event handler for topic $topic', e, stackTrace);
      }
    });

    // Store subscription with token
    _subscriptions[token] = subscription;

    // Deliver cached events that match the filter
    if (_cachedEvents.containsKey(topic)) {
      for (final event in _cachedEvents[topic]!) {
        if (event is T && filter(event)) {
          ErrorRecovery.tryCatch(
                () => handler(event),
            operationName: 'cached event delivery with filter for $topic',
          );
        }
      }
    }

    return token;
  }

  /// Create a subscription that automatically expires after maxEvents or timeout
  String subscribeTemporary<T>(
      String topic,
      void Function(T) handler, {
        int? maxEvents,
        Duration? timeout,
      }) {
    _logger.fine('Creating temporary subscription to topic: $topic');

    // Create stream controller if it doesn't exist
    if (!_eventControllers.containsKey(topic)) {
      _eventControllers[topic] = StreamController<dynamic>.broadcast();
    }

    // Generate unique token
    final token = '${topic}_${++_subscriptionCounter}';

    // Track received events
    int receivedEvents = 0;

    // Create subscription
    final subscription = _eventControllers[topic]!.stream
        .where((event) => event is T)
        .cast<T>()
        .listen((event) {
      try {
        handler(event);

        // Check if max events reached
        if (maxEvents != null) {
          receivedEvents++;
          if (receivedEvents >= maxEvents) {
            unsubscribe(token);
          }
        }
      } catch (e, stackTrace) {
        _logger.severe('Error in temporary event handler for topic $topic', e, stackTrace);
      }
    });

    // Store subscription with token
    _subscriptions[token] = subscription;

    // Set up timeout if needed
    if (timeout != null) {
      Timer(timeout, () {
        if (_subscriptions.containsKey(token)) {
          _logger.fine('Subscription timeout reached: $token');
          unsubscribe(token);
        }
      });
    }

    // Deliver cached events (count towards maxEvents)
    if (_cachedEvents.containsKey(topic) && maxEvents != null) {
      for (final event in _cachedEvents[topic]!) {
        if (event is T) {
          ErrorRecovery.tryCatch(
                () => handler(event),
            operationName: 'cached event delivery for temporary subscription to $topic',
          );

          receivedEvents++;
          if (receivedEvents >= maxEvents) {
            unsubscribe(token);
            break;
          }
        }
      }
    }

    return token;
  }

  /// Create a one-time subscription that automatically unsubscribes after first event
  String subscribeOnce<T>(String topic, void Function(T) handler) {
    return subscribeTemporary<T>(topic, handler, maxEvents: 1);
  }

  /// Create a subscription with debounce
  String subscribeWithDebounce<T>(
      String topic,
      void Function(T) handler,
      Duration duration,
      ) {
    _logger.fine('Creating debounced subscription to topic: $topic');

    // Create stream controller if it doesn't exist
    if (!_eventControllers.containsKey(topic)) {
      _eventControllers[topic] = StreamController<dynamic>.broadcast();
    }

    // Generate unique token
    final token = '${topic}_${++_subscriptionCounter}';

    // Create subscription with debounce
    final subscription = _eventControllers[topic]!.stream
        .where((event) => event is T)
        .cast<T>()
        .debounceTime(duration)
        .listen((event) {
      try {
        handler(event);
      } catch (e, stackTrace) {
        _logger.severe('Error in debounced event handler for topic $topic', e, stackTrace);
      }
    });

    // Store subscription with token
    _subscriptions[token] = subscription;

    return token;
  }

  /// Create a subscription with throttle
  String subscribeWithThrottle<T>(
      String topic,
      void Function(T) handler,
      Duration duration,
      ) {
    _logger.fine('Creating throttled subscription to topic: $topic');

    // Create stream controller if it doesn't exist
    if (!_eventControllers.containsKey(topic)) {
      _eventControllers[topic] = StreamController<dynamic>.broadcast();
    }

    // Generate unique token
    final token = '${topic}_${++_subscriptionCounter}';

    // Timer for throttling
    Timer? throttleTimer;
    bool canEmit = true;

    // Create subscription with manual throttle
    final subscription = _eventControllers[topic]!.stream
        .where((event) => event is T)
        .cast<T>()
        .listen((event) {
      if (canEmit) {
        try {
          handler(event);
          canEmit = false;

          throttleTimer?.cancel();
          throttleTimer = Timer(duration, () {
            canEmit = true;
          });
        } catch (e, stackTrace) {
          _logger.severe('Error in throttled event handler for topic $topic', e, stackTrace);
        }
      }
    });

    // Store subscription with token
    _subscriptions[token] = subscription;

    return token;
  }

  /// Enable event caching for a topic
  void enableCaching(String topic) {
    if (!_cachedEvents.containsKey(topic)) {
      _cachedEvents[topic] = [];
    }
  }

  /// Disable event caching for a topic
  void disableCaching(String topic) {
    _cachedEvents.remove(topic);
  }

  /// Clear cached events for a topic
  void clearCache(String topic) {
    if (_cachedEvents.containsKey(topic)) {
      _cachedEvents[topic]!.clear();
    }
  }

  /// Cache an event
  void _cacheEvent<T>(String topic, T event) {
    if (!_shouldCacheTopic(topic)) {
      return;
    }

    // Ensure cache exists
    _cachedEvents.putIfAbsent(topic, () => []);

    // Add to cache
    _cachedEvents[topic]!.add(event);

    // Trim cache if needed
    if (_cachedEvents[topic]!.length > _maxCacheSize) {
      _cachedEvents[topic]!.removeAt(0);
    }
  }

  /// Deliver cached events to a new subscriber
  void _deliverCachedEvents<T>(String topic, void Function(T) handler) {
    if (!_cachedEvents.containsKey(topic)) {
      return;
    }

    for (final event in _cachedEvents[topic]!) {
      if (event is T) {
        ErrorRecovery.tryCatch(
              () => handler(event),
          operationName: 'cached event delivery for $topic',
        );
      }
    }
  }

  /// Check if a topic should cache events
  bool _shouldCacheTopic(String topic) {
    return _cachedEvents.containsKey(topic);
  }

  /// Pause event delivery
  void pause() {
    _isPaused = true;
    // Temporarily bypass enhanced system due to hanging issues
    // _enhancedSystem.pause();
    _logger.fine('Event system paused');
  }

  /// Resume event delivery, optionally processing queued events
  Future<void> resume({bool processQueued = true}) async {
    _isPaused = false;
    // Temporarily bypass enhanced system due to hanging issues
    // await _enhancedSystem.resume();
    _logger.fine('Event system resumed');

    if (processQueued && _queuedEvents.isNotEmpty) {
      _logger.fine('Processing ${_queuedEvents.length} queued events');

      // Take a copy to avoid concurrent modification issues
      final queuedEvents = List<_QueuedEvent>.from(_queuedEvents);
      _queuedEvents.clear();

      // Process queued events
      for (final queuedEvent in queuedEvents) {
        queuedEvent.publish(this);
      }
    } else if (!processQueued) {
      // Clear queued events without processing
      _queuedEvents.clear();
    }
  }

  /// Get a list of active topics
  List<String> getActiveTopics() {
    final Set<String> topics = {};

    // Add topics with controllers
    topics.addAll(_eventControllers.keys);

    // Add topics with cached events
    topics.addAll(_cachedEvents.keys);

    return topics.toList();
  }

  /// Get enhanced event system statistics
  Map<String, dynamic> getEnhancedStatistics() {
    // Temporarily bypass enhanced system due to hanging issues
    return {
      'totalEventsPublished': 0,
      'totalEventsDelivered': 0,
      'activeSubscriptions': _subscriptions.length,
      'isPaused': _isPaused,
    };
  }

  /// Get handler statistics from enhanced system
  Map<String, dynamic> getHandlerStatistics() {
    // Temporarily bypass enhanced system due to hanging issues
    return {};
  }

  /// Start event recording for replay
  void startRecording() {
    // Temporarily bypass enhanced system due to hanging issues
    _logger.warning('Event recording temporarily disabled');
  }

  /// Stop event recording
  void stopRecording() {
    // Temporarily bypass enhanced system due to hanging issues
    _logger.warning('Event recording temporarily disabled');
  }

  /// Replay recorded events
  Future<void> replayEvents({
    DateTime? fromTime,
    DateTime? toTime,
    bool Function(McpEvent)? filter,
  }) async {
    // Temporarily bypass enhanced system due to hanging issues
    _logger.warning('Event replay temporarily disabled');
  }

  /// Get event history
  List<Map<String, dynamic>> getEventHistory({
    DateTime? fromTime,
    DateTime? toTime,
  }) {
    // Temporarily bypass enhanced system due to hanging issues
    return [];
  }

  /// Add event middleware to enhanced system
  void addMiddleware(EventMiddleware middleware) {
    // Temporarily bypass enhanced system due to hanging issues
    _logger.warning('Middleware temporarily disabled');
  }

  /// Remove event middleware from enhanced system
  void removeMiddleware(String name) {
    // Temporarily bypass enhanced system due to hanging issues
    _logger.warning('Middleware temporarily disabled');
  }

  /// Get enhanced subscription information
  EventSubscription? getEnhancedSubscription(String subscriptionId) {
    // Temporarily bypass enhanced system due to hanging issues
    return null;
  }

  /// Get all active enhanced subscriptions
  List<EventSubscription> getActiveEnhancedSubscriptions() {
    // Temporarily bypass enhanced system due to hanging issues
    return [];
  }

  /// Reset the event system for testing purposes
  Future<void> reset() async {
    _logger.fine('Resetting event system');

    // Cancel all subscriptions
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }

    // Close all controllers
    for (final controller in _eventControllers.values) {
      await controller.close();
    }

    // Clear collections
    _subscriptions.clear();
    _eventControllers.clear();
    _cachedEvents.clear();
    _queuedEvents.clear();
    _subscriptionCounter = 0;
    _isPaused = false;

    // Temporarily skip enhanced system reset due to hanging issues
    // TODO: Fix async handling in EnhancedTypedEventSystem
    // await _enhancedSystem.reset();
  }

  /// Clean up resources
  Future<void> dispose() async {
    await reset();
    _logger.fine('Event system disposed');
  }
}

/// Extension method for Stream debounce
extension DebounceExtension<T> on Stream<T> {
  Stream<T> debounceTime(Duration duration) {
    StreamController<T>? controller;
    Timer? timer;
    StreamSubscription<T>? subscription;

    controller = StreamController<T>(
      sync: true,
      onListen: () {
        subscription = listen(
              (data) {
            timer?.cancel();
            timer = Timer(duration, () {
              controller?.add(data);
            });
          },
          onError: controller?.addError,
          onDone: () {
            timer?.cancel();
            controller?.close();
          },
        );
      },
      onCancel: () {
        timer?.cancel();
        subscription?.cancel();
      },
    );

    return controller.stream;
  }
}

/// Queued event for when system is paused
class _QueuedEvent<T> {
  final String topic;
  final T event;

  _QueuedEvent(this.topic, this.event);

  /// Publish the event to the event system
  void publish(EventSystem eventSystem) {
    eventSystem.publish<T>(topic, event);
  }
}