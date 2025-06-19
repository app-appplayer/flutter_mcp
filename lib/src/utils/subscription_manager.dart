import 'dart:async';
import 'package:synchronized/synchronized.dart';
import '../utils/logger.dart';

/// Manages subscriptions to prevent memory leaks
class SubscriptionManager {
  static final Logger _logger = Logger('flutter_mcp.subscription_manager');

  // Track all active subscriptions
  final Map<String, _ManagedSubscription> _subscriptions = {};
  final _lock = Lock();

  // Weak reference support for automatic cleanup
  final Set<String> _autoCleanupTokens = {};
  Timer? _cleanupTimer;

  // Statistics
  int _totalCreated = 0;
  int _totalDisposed = 0;
  int _totalLeaked = 0;

  /// Singleton instance
  static final SubscriptionManager _instance = SubscriptionManager._internal();
  static SubscriptionManager get instance => _instance;

  SubscriptionManager._internal() {
    // Start periodic cleanup
    _startPeriodicCleanup();
  }

  /// Register a subscription for management
  Future<String> register({
    required StreamSubscription subscription,
    required String source,
    String? description,
    bool autoCleanup = true,
  }) async {
    return await _lock.synchronized(() async {
      _totalCreated++;

      final token =
          'sub_${_totalCreated}_${DateTime.now().millisecondsSinceEpoch}';

      _subscriptions[token] = _ManagedSubscription(
        subscription: subscription,
        token: token,
        source: source,
        description: description,
        createdAt: DateTime.now(),
        autoCleanup: autoCleanup,
      );

      // Add weak reference cleanup handler
      if (autoCleanup) {
        _setupWeakReferenceCleanup(token, subscription);
      }

      if (autoCleanup) {
        _autoCleanupTokens.add(token);
      }

      _logger.fine('Registered subscription: $token from $source');
      return token;
    });
  }

  /// Unregister and cancel a subscription
  Future<bool> unregister(String token) async {
    return await _lock.synchronized(() async {
      final managed = _subscriptions.remove(token);
      if (managed == null) {
        _logger.warning('Attempted to unregister unknown subscription: $token');
        return false;
      }

      _totalDisposed++;
      _autoCleanupTokens.remove(token);

      try {
        await managed.subscription.cancel();
        _logger.fine('Unregistered subscription: $token');
        return true;
      } catch (e) {
        _logger.severe('Error canceling subscription $token', e);
        return false;
      }
    });
  }

  /// Unregister all subscriptions from a specific source
  Future<int> unregisterBySource(String source) async {
    // Get tokens outside the lock to avoid deadlock
    final tokensToRemove = await _lock.synchronized(() async {
      final tokens = <String>[];
      _subscriptions.forEach((token, managed) {
        if (managed.source == source) {
          tokens.add(token);
        }
      });
      return tokens;
    });

    // Unregister each token (which will acquire the lock internally)
    int count = 0;
    for (final token in tokensToRemove) {
      if (await unregister(token)) {
        count++;
      }
    }

    _logger.info('Unregistered $count subscriptions from source: $source');
    return count;
  }

  /// Check if a subscription is still active
  Future<bool> isActive(String token) async {
    return await _lock.synchronized(() async {
      return _subscriptions.containsKey(token);
    });
  }

  /// Get information about a subscription
  Future<SubscriptionInfo?> getInfo(String token) async {
    return await _lock.synchronized(() async {
      final managed = _subscriptions[token];
      if (managed == null) return null;

      return SubscriptionInfo(
        token: managed.token,
        source: managed.source,
        description: managed.description,
        createdAt: managed.createdAt,
        age: DateTime.now().difference(managed.createdAt),
        autoCleanup: managed.autoCleanup,
      );
    });
  }

  /// Get all active subscriptions
  Future<List<SubscriptionInfo>> getAllActive() async {
    return await _lock.synchronized(() async {
      return _subscriptions.values
          .map((managed) => SubscriptionInfo(
                token: managed.token,
                source: managed.source,
                description: managed.description,
                createdAt: managed.createdAt,
                age: DateTime.now().difference(managed.createdAt),
                autoCleanup: managed.autoCleanup,
              ))
          .toList();
    });
  }

  /// Get statistics about subscription management
  Future<SubscriptionStatistics> getStatistics() async {
    return await _lock.synchronized(() async {
      final activeCount = _subscriptions.length;
      final bySource = <String, int>{};

      for (final managed in _subscriptions.values) {
        bySource[managed.source] = (bySource[managed.source] ?? 0) + 1;
      }

      return SubscriptionStatistics(
        totalCreated: _totalCreated,
        totalDisposed: _totalDisposed,
        totalActive: activeCount,
        totalLeaked: _totalLeaked,
        bySource: bySource,
      );
    });
  }

  /// Perform cleanup of old subscriptions
  Future<int> cleanup({Duration? maxAge}) async {
    final maxAgeToUse = maxAge ?? Duration(hours: 1);
    final now = DateTime.now();
    int cleaned = 0;

    final tokensToClean = await _lock.synchronized(() async {
      final tokens = <String>[];

      for (final entry in _subscriptions.entries) {
        if (entry.value.autoCleanup &&
            now.difference(entry.value.createdAt) > maxAgeToUse) {
          tokens.add(entry.key);
        }
      }

      return tokens;
    });

    for (final token in tokensToClean) {
      if (await unregister(token)) {
        cleaned++;
        _totalLeaked++;
      }
    }

    if (cleaned > 0) {
      _logger.warning('Cleaned up $cleaned potentially leaked subscriptions');
    }

    return cleaned;
  }

  /// Track a subscription (simplified interface for EventSystem)
  void trackSubscription(String token, StreamSubscription subscription) {
    _lock.synchronized(() {
      _subscriptions[token] = _ManagedSubscription(
        subscription: subscription,
        token: token,
        source: 'EventSystem',
        description: null,
        createdAt: DateTime.now(),
        autoCleanup: true,
      );
      _autoCleanupTokens.add(token);
      _totalCreated++;
    });
  }

  /// Untrack a subscription (simplified interface for EventSystem)
  void untrackSubscription(String token) {
    _lock.synchronized(() {
      final managed = _subscriptions.remove(token);
      if (managed != null) {
        _autoCleanupTokens.remove(token);
        _totalDisposed++;
      }
    });
  }

  /// Clear all subscriptions
  Future<void> clearAll() async {
    await _lock.synchronized(() async {
      final count = _subscriptions.length;

      for (final managed in _subscriptions.values) {
        try {
          await managed.subscription.cancel();
        } catch (e) {
          _logger.severe('Error canceling subscription during clearAll', e);
        }
      }

      _subscriptions.clear();
      _autoCleanupTokens.clear();

      _logger.info('Cleared all $count subscriptions');
    });
  }

  /// Setup weak reference cleanup for a subscription
  void _setupWeakReferenceCleanup(
      String token, StreamSubscription subscription) {
    // Since Dart doesn't have true weak references, we use the subscription's
    // onDone callback to trigger cleanup
    subscription.onDone(() {
      _lock.synchronized(() {
        if (_subscriptions.containsKey(token)) {
          _subscriptions.remove(token);
          _autoCleanupTokens.remove(token);
          _totalDisposed++;
          _logger.fine('Auto-cleaned subscription: $token');
        }
      });
    });
  }

  /// Start periodic cleanup timer
  void _startPeriodicCleanup() {
    _cleanupTimer?.cancel();

    // Run cleanup every 5 minutes
    _cleanupTimer = Timer.periodic(Duration(minutes: 5), (_) {
      cleanup(maxAge: Duration(hours: 1)).then((cleaned) {
        if (cleaned > 0) {
          _logger.info('Periodic cleanup removed $cleaned subscriptions');
        }
      });
    });
  }

  /// Dispose of the subscription manager
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    await clearAll();
  }
}

/// Information about a managed subscription
class SubscriptionInfo {
  final String token;
  final String source;
  final String? description;
  final DateTime createdAt;
  final Duration age;
  final bool autoCleanup;

  SubscriptionInfo({
    required this.token,
    required this.source,
    this.description,
    required this.createdAt,
    required this.age,
    required this.autoCleanup,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'source': source,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'ageSeconds': age.inSeconds,
        'autoCleanup': autoCleanup,
      };
}

/// Statistics about subscription management
class SubscriptionStatistics {
  final int totalCreated;
  final int totalDisposed;
  final int totalActive;
  final int totalLeaked;
  final Map<String, int> bySource;

  SubscriptionStatistics({
    required this.totalCreated,
    required this.totalDisposed,
    required this.totalActive,
    required this.totalLeaked,
    required this.bySource,
  });

  Map<String, dynamic> toJson() => {
        'totalCreated': totalCreated,
        'totalDisposed': totalDisposed,
        'totalActive': totalActive,
        'totalLeaked': totalLeaked,
        'percentLeaked': totalCreated > 0
            ? (totalLeaked / totalCreated * 100).toStringAsFixed(2)
            : '0.00',
        'bySource': bySource,
      };
}

/// Internal managed subscription wrapper
class _ManagedSubscription {
  final StreamSubscription subscription;
  final String token;
  final String source;
  final String? description;
  final DateTime createdAt;
  final bool autoCleanup;

  _ManagedSubscription({
    required this.subscription,
    required this.token,
    required this.source,
    this.description,
    required this.createdAt,
    required this.autoCleanup,
  });
}
