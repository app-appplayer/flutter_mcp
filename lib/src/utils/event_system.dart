import 'dart:async';
import '../utils/logger.dart';
import '../utils/error_recovery.dart';

/// Type-safe event system for components to communicate across the application
class EventSystem {
  final MCPLogger _logger = MCPLogger('mcp.event_system');

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

  // Singleton instance
  static final EventSystem _instance = EventSystem._internal();

  /// Get singleton instance
  static EventSystem get instance => _instance;

  /// Internal constructor
  EventSystem._internal();

  /// Publish an event to a topic
  void publish<T>(String topic, T event) {
    if (_isPaused) {
      _queuedEvents.add(_QueuedEvent<T>(topic, event));
      _logger.debug('Event queued for topic: $topic (system paused)');
      return;
    }

    if (!_eventControllers.containsKey(topic)) {
      // Create a controller if we need to cache but don't have subscribers yet
      if (_shouldCacheTopic(topic)) {
        _eventControllers[topic] = StreamController<dynamic>.broadcast();
      } else {
        _logger.debug('No subscribers for topic: $topic');
        return;
      }
    }

    _logger.debug('Publishing event to topic: $topic');

    // Add to cache if this topic uses caching
    if (_shouldCacheTopic(topic)) {
      _cacheEvent(topic, event);
    }

    // Publish to subscribers
    _eventControllers[topic]!.add(event);
  }

  /// Subscribe to a topic
  String subscribe<T>(String topic, void Function(T) handler) {
    _logger.debug('Subscribing to topic: $topic');

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
        _logger.error('Error in event handler for topic $topic', e, stackTrace);
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

    _logger.debug('Unsubscribing: $token');

    // Cancel subscription
    _subscriptions[token]!.cancel();
    _subscriptions.remove(token);

    // Extract topic from token
    final topic = token.split('_').first;

    // Check if this was the last subscription for the topic
    if (_subscriptions.keys.where((k) => k.startsWith('${topic}_')).isEmpty) {
      _logger.debug('No more subscribers for topic: $topic, cleaning up');
      _eventControllers[topic]?.close();
      _eventControllers.remove(topic);

      // Don't remove cached events - they may be needed for future subscribers
    }
  }

  /// Unsubscribe all handlers from a topic
  void unsubscribeFromTopic(String topic) {
    _logger.debug('Unsubscribing all from topic: $topic');

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
    _logger.debug('Subscribing to topic with filter: $topic');

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
        _logger.error('Error in filtered event handler for topic $topic', e, stackTrace);
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
    _logger.debug('Creating temporary subscription to topic: $topic');

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
        _logger.error('Error in temporary event handler for topic $topic', e, stackTrace);
      }
    });

    // Store subscription with token
    _subscriptions[token] = subscription;

    // Set up timeout if needed
    if (timeout != null) {
      Timer(timeout, () {
        if (_subscriptions.containsKey(token)) {
          _logger.debug('Subscription timeout reached: $token');
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
    _logger.debug('Creating debounced subscription to topic: $topic');

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
        _logger.error('Error in debounced event handler for topic $topic', e, stackTrace);
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
    _logger.debug('Creating throttled subscription to topic: $topic');

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
          _logger.error('Error in throttled event handler for topic $topic', e, stackTrace);
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
    _logger.debug('Event system paused');
  }

  /// Resume event delivery, optionally processing queued events
  void resume({bool processQueued = true}) {
    _isPaused = false;
    _logger.debug('Event system resumed');

    if (processQueued && _queuedEvents.isNotEmpty) {
      _logger.debug('Processing ${_queuedEvents.length} queued events');

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

  /// Clean up resources
  void dispose() {
    _logger.debug('Disposing event system');

    // Cancel all subscriptions
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }

    // Close all controllers
    for (final controller in _eventControllers.values) {
      controller.close();
    }

    // Clear collections
    _subscriptions.clear();
    _eventControllers.clear();
    _cachedEvents.clear();
    _queuedEvents.clear();
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