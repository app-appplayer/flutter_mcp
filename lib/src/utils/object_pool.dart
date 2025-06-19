import 'dart:collection';

/// Generic object pool for reusing expensive objects
class ObjectPool<T> {
  final Queue<T> _pool = Queue<T>();
  final Set<T> _inUse = {};
  final T Function() _create;
  final void Function(T) _reset;
  final int _maxSize;
  int _totalCreated = 0;

  /// Creates a new object pool
  ///
  /// [create]: Factory function to create new objects
  /// [reset]: Function to reset objects before reuse
  /// [initialSize]: Initial number of objects to create
  /// [maxSize]: Maximum size of the pool
  ObjectPool({
    required T Function() create,
    required void Function(T) reset,
    int initialSize = 0,
    int maxSize = 100,
  })  : _create = create,
        _reset = reset,
        _maxSize = maxSize {
    // Pre-populate the pool
    for (var i = 0; i < initialSize; i++) {
      _pool.add(_create());
      _totalCreated++;
    }
  }

  /// Acquires an object from the pool, creating a new one if needed
  T acquire() {
    T object;
    if (_pool.isEmpty) {
      // Create a new object if pool is empty
      object = _create();
      _totalCreated++;
    } else {
      // Get an existing object from the pool
      object = _pool.removeFirst();
    }

    _inUse.add(object);
    return object;
  }

  /// Releases an object back to the pool
  void release(T object) {
    if (!_inUse.contains(object)) {
      return; // Object wasn't acquired from this pool
    }

    _inUse.remove(object);
    _reset(object); // Reset before reuse

    // Only add back to pool if under max size
    if (_pool.length < _maxSize) {
      _pool.add(object);
    }
  }

  /// Clears the pool, not affecting in-use objects
  void clear() {
    _pool.clear();
  }

  /// Trims the pool to half its current size
  void trim() {
    if (_pool.length > 10) {
      // Only trim if it's worth it
      final targetSize = _pool.length ~/ 2;
      while (_pool.length > targetSize) {
        _pool.removeFirst();
      }
    }
  }

  /// Number of objects currently in the pool (not in use)
  int get size => _pool.length;

  /// Number of objects currently in use
  int get inUseCount => _inUse.length;

  /// Total number of objects created by this pool
  int get totalCreated => _totalCreated;
}
