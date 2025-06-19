import 'dart:async';
import 'package:synchronized/synchronized.dart';

/// Circuit breaker state
enum CircuitBreakerState {
  closed, // Normal operation
  open, // Failing, rejecting requests
  halfOpen // Testing if system has recovered
}

/// Circuit breaker pattern implementation for preventing cascading failures
class CircuitBreaker {
  final String name;
  final int failureThreshold;
  final Duration resetTimeout;
  final Function? onOpen;
  final Function? onClose;

  int _failures = 0;
  CircuitBreakerState _state = CircuitBreakerState.closed;
  DateTime? _openTime;
  int _successesInHalfOpen = 0;
  int _halfOpenSuccessThreshold = 1;

  // Lock for thread-safe state management
  final _lock = Lock();

  /// Creates a new circuit breaker
  ///
  /// [name]: Circuit breaker name
  /// [failureThreshold]: Number of failures before opening the circuit
  /// [resetTimeout]: How long to keep the circuit open before trying again
  /// [onOpen]: Callback when the circuit opens
  /// [onClose]: Callback when the circuit closes
  CircuitBreaker({
    required this.name,
    required this.failureThreshold,
    required this.resetTimeout,
    this.onOpen,
    this.onClose,
    int? halfOpenSuccessThreshold,
  }) {
    _halfOpenSuccessThreshold = halfOpenSuccessThreshold ?? 1;
  }

  /// Current state of the circuit breaker (thread-safe)
  CircuitBreakerState get state {
    // Direct read is safe for enum values in Dart
    return _state;
  }

  /// Number of consecutive failures (thread-safe)
  int get failureCount {
    // Direct read is safe for int values in Dart
    return _failures;
  }

  /// Execute operation with circuit breaker protection
  Future<T> execute<T>(Future<T> Function() operation) async {
    // Check if circuit is open
    await _lock.synchronized(() async {
      if (_state == CircuitBreakerState.open) {
        if (_openTime == null ||
            DateTime.now().difference(_openTime!) < resetTimeout) {
          throw CircuitBreakerOpenException('Circuit breaker is open: $name');
        } else {
          // Move to half-open state
          _state = CircuitBreakerState.halfOpen;
          _successesInHalfOpen = 0;
        }
      }
    });

    try {
      final result = await operation();
      await recordSuccess();
      return result;
    } catch (e) {
      await recordFailure(e);
      rethrow;
    }
  }

  /// Check if an operation should be allowed
  Future<void> allowOperation() async {
    await _lock.synchronized(() async {
      if (_state == CircuitBreakerState.open) {
        if (_openTime == null ||
            DateTime.now().difference(_openTime!) < resetTimeout) {
          throw CircuitBreakerOpenException('Circuit breaker is open: $name');
        } else {
          // Move to half-open state
          _state = CircuitBreakerState.halfOpen;
          _successesInHalfOpen = 0;
        }
      }
    });
  }

  /// Record a successful operation
  Future<void> recordSuccess() async {
    await _lock.synchronized(() async {
      if (_state == CircuitBreakerState.closed) {
        // Reset failures on success in closed state
        _failures = 0;
      } else if (_state == CircuitBreakerState.halfOpen) {
        _successesInHalfOpen++;

        // If we have enough successes, close the circuit
        if (_successesInHalfOpen >= _halfOpenSuccessThreshold) {
          _state = CircuitBreakerState.closed;
          _failures = 0;
          if (onClose != null) onClose!();
        }
      }
    });
  }

  /// Record a failure
  Future<void> recordFailure(dynamic error) async {
    await _lock.synchronized(() async {
      if (_state == CircuitBreakerState.closed) {
        _failures++;

        // If we've reached the threshold, open the circuit
        if (_failures >= failureThreshold) {
          _state = CircuitBreakerState.open;
          _openTime = DateTime.now();
          if (onOpen != null) onOpen!();
        }
      } else if (_state == CircuitBreakerState.halfOpen) {
        // Any failure in half-open goes back to open
        _state = CircuitBreakerState.open;
        _openTime = DateTime.now();
        if (onOpen != null) onOpen!();
      }
    });
  }

  /// Reset the circuit breaker to closed state
  Future<void> reset() async {
    await _lock.synchronized(() async {
      _state = CircuitBreakerState.closed;
      _failures = 0;
      _openTime = null;
      _successesInHalfOpen = 0;
    });
  }

  /// Force the circuit breaker to open state
  Future<void> forceOpen() async {
    await _lock.synchronized(() async {
      _state = CircuitBreakerState.open;
      _openTime = DateTime.now();
      if (onOpen != null) onOpen!();
    });
  }

  /// Force the circuit breaker to closed state
  Future<void> forceClosed() async {
    await _lock.synchronized(() async {
      _state = CircuitBreakerState.closed;
      _failures = 0;
      if (onClose != null) onClose!();
    });
  }
}

/// Exception thrown when a circuit breaker is open
class CircuitBreakerOpenException implements Exception {
  final String message;

  CircuitBreakerOpenException(this.message);

  @override
  String toString() => 'CircuitBreakerOpenException: $message';
}
