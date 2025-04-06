import 'dart:async';
import '../utils/logger.dart';

/// Event system for components to communicate across the application
class EventSystem {
  final MCPLogger _logger = MCPLogger('mcp.event_system');

  // Event streams by topic
  final Map<String, StreamController<dynamic>> _eventControllers = {};

  // Event subscriptions by token
  final Map<String, StreamSubscription<dynamic>> _subscriptions = {};

  // Subscription counter for generating unique tokens
  int _subscriptionCounter = 0;

  // Singleton instance
  static final EventSystem _instance = EventSystem._internal();

  /// Get singleton instance
  static EventSystem get instance => _instance;

  /// Internal constructor
  EventSystem._internal();

  /// Publish an event to a topic
  void publish<T>(String topic, T event) {
    if (!_eventControllers.containsKey(topic)) {
      _logger.debug('No subscribers for topic: $topic');
      return;
    }

    _logger.debug('Publishing event to topic: $topic');
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

    // Create subscription
    final subscription = _eventControllers[topic]!.stream.listen((event) {
      if (event is T) {
        handler(event);
      } else {
        _logger.warning(
            'Event type mismatch for topic $topic - expected ${T.toString()}, '
                'got ${event.runtimeType}'
        );
      }
    });

    // Store subscription with token
    _subscriptions[token] = subscription;

    return token;
  }

  /// Unsubscribe using token
  void unsubscribe(String token) {
    if (!_subscriptions.containsKey(token)) {
      _logger.warning('Subscription not found: $token');
      return;
    }

    _logger.debug('Unsubscribing: $token');
    _subscriptions[token]!.cancel();
    _subscriptions.remove(token);

    // Extract topic from token
    final topic = token.split('_').first;

    // Check if this was the last subscription for the topic
    if (_subscriptions.keys.where((k) => k.startsWith('${topic}_')).isEmpty) {
      _logger.debug('No more subscribers for topic: $topic, cleaning up');
      _eventControllers[topic]?.close();
      _eventControllers.remove(topic);
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
  }

  /// Check if a topic has subscribers
  bool hasSubscribers(String topic) {
    return _eventControllers.containsKey(topic) && !_eventControllers[topic]!.isClosed;
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
        .listen((event) {
      handler(event as T);
    });

    // Store subscription with token
    _subscriptions[token] = subscription;

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
    final subscription = _eventControllers[topic]!.stream.listen((event) {
      if (event is T) {
        handler(event);

        // Check if max events reached
        if (maxEvents != null) {
          receivedEvents++;
          if (receivedEvents >= maxEvents) {
            unsubscribe(token);
          }
        }
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
        .map((event) => event as T)
        .debounceTime(duration)
        .listen(handler);

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
    final subscription = _eventControllers[topic]!.stream.listen((event) {
      if (event is T && canEmit) {
        handler(event);
        canEmit = false;

        throttleTimer?.cancel();
        throttleTimer = Timer(duration, () {
          canEmit = true;
        });
      }
    });

    // Store subscription with token
    _subscriptions[token] = subscription;

    return token;
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