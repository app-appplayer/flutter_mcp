import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import '../utils/logger.dart';
import '../utils/performance_monitor.dart';
import '../utils/event_system.dart';

/// Memory management utility for optimizing memory usage in LLM applications
class MemoryManager {
  static final MCPLogger _logger = MCPLogger('mcp.memory_manager');

  // Singleton instance
  static final MemoryManager _instance = MemoryManager._internal();

  /// Get singleton instance
  static MemoryManager get instance => _instance;

  // Private constructor
  MemoryManager._internal();

  // Configuration
  bool _isMonitoring = false;
  Duration _monitoringInterval = Duration(seconds: 30);
  int? _highMemoryThresholdMB;
  Timer? _monitoringTimer;

  // Memory stats
  int _peakMemoryUsageMB = 0;
  int _currentMemoryUsageMB = 0;
  List<int> _recentMemoryReadings = [];
  int _maxReadings = 10;

  // Callback when memory threshold is exceeded
  List<Future<void> Function()> _highMemoryCallbacks = [];

  /// Initialize memory manager
  void initialize({
    bool startMonitoring = true,
    Duration? monitoringInterval,
    int? highMemoryThresholdMB,
  }) {
    if (monitoringInterval != null) {
      _monitoringInterval = monitoringInterval;
    }

    _highMemoryThresholdMB = highMemoryThresholdMB;

    if (startMonitoring) {
      startMemoryMonitoring();
    }
  }

  /// Start memory monitoring
  void startMemoryMonitoring() {
    if (_isMonitoring) return;

    _logger.debug('Starting memory monitoring with interval: ${_monitoringInterval.inSeconds}s');

    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _checkMemoryUsage();
    });

    _isMonitoring = true;

    // Perform initial check
    _checkMemoryUsage();
  }

  /// Stop memory monitoring
  void stopMemoryMonitoring() {
    if (!_isMonitoring) return;

    _logger.debug('Stopping memory monitoring');

    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _isMonitoring = false;
  }

  /// Add high memory callback
  void addHighMemoryCallback(Future<void> Function() callback) {
    _highMemoryCallbacks.add(callback);
  }

  /// Clear high memory callbacks
  void clearHighMemoryCallbacks() {
    _highMemoryCallbacks.clear();
  }

  /// Check current memory usage
  Future<void> _checkMemoryUsage() async {
    // Get memory usage estimate
    final memoryUsageMB = await _estimateMemoryUsage();

    // Store reading
    _currentMemoryUsageMB = memoryUsageMB;
    _recentMemoryReadings.add(memoryUsageMB);

    // Keep only recent readings
    if (_recentMemoryReadings.length > _maxReadings) {
      _recentMemoryReadings.removeAt(0);
    }

    // Update peak
    if (memoryUsageMB > _peakMemoryUsageMB) {
      _peakMemoryUsageMB = memoryUsageMB;
    }

    // Track memory usage
    PerformanceMonitor.instance.recordResourceUsage(
      'memory.usageMB',
      memoryUsageMB.toDouble(),
      capacity: _highMemoryThresholdMB?.toDouble(),
    );

    _logger.debug('Current memory usage: ${memoryUsageMB}MB (Peak: ${_peakMemoryUsageMB}MB)');

    // Check threshold
    if (_highMemoryThresholdMB != null &&
        memoryUsageMB > _highMemoryThresholdMB!) {
      _logger.warning('High memory usage detected: ${memoryUsageMB}MB exceeds threshold of ${_highMemoryThresholdMB}MB');

      // Publish memory warning event
      EventSystem.instance.publish('memory.high', {
        'currentMB': memoryUsageMB,
        'thresholdMB': _highMemoryThresholdMB,
        'peakMB': _peakMemoryUsageMB,
      });

      // Execute callbacks
      for (final callback in _highMemoryCallbacks) {
        try {
          await callback();
        } catch (e) {
          _logger.error('Error in high memory callback', e);
        }
      }

      // Force garbage collection if supported
      _tryForcedGarbageCollection();
    }
  }

  /// Estimate memory usage (implementation depends on platform)
  Future<int> _estimateMemoryUsage() async {
    // For a real implementation, this would use platform-specific
    // methods to obtain memory information.
    // This is a placeholder implementation.

    // In a real app, you'd typically use:
    // - For web: performance.memory API
    // - For mobile: method channels to query native memory APIs
    // - For desktop: platform-specific libraries via FFI

    // For this example, we'll simulate memory growth over time
    // with occasional "garbage collection" drops

    if (_recentMemoryReadings.isEmpty) {
      return 100; // Start at 100MB
    }

    final lastReading = _recentMemoryReadings.last;
    final shouldGC = math.Random().nextDouble() < 0.2; // 20% chance of GC

    if (shouldGC) {
      // Simulate GC reducing memory
      return math.max(100, lastReading - math.Random().nextInt(50));
    } else {
      // Simulate memory growth
      return lastReading + math.Random().nextInt(20);
    }
  }

  /// Try to trigger a forced garbage collection
  void _tryForcedGarbageCollection() {
    // In Dart, we can't directly force GC, but we can suggest it

    // This is a hint for the VM to collect garbage soon
    // Note: This is not guaranteed to run immediately and is just a hint
    _logger.debug('Suggesting garbage collection');

    if (kDebugMode) {
      // In debug mode, we can often trigger more aggressive GC
      // by running operations known to stress the memory system

      final largeList = List<int>.filled(10000, 0); // Create some garbage
      for (int i = 0; i < largeList.length; i++) {
        largeList[i] = i; // Touch all elements
      }
      // Let the list go out of scope
    }
  }

  /// Process large data in chunks to avoid memory spikes
  static Future<List<R>> processInChunks<T, R>({
    required List<T> items,
    required Future<R> Function(T item) processItem,
    int chunkSize = 10,
    Duration? pauseBetweenChunks,
  }) async {
    final results = <R>[];

    for (int i = 0; i < items.length; i += chunkSize) {
      final end = math.min(i + chunkSize, items.length);
      final chunk = items.sublist(i, end);

      // Process this chunk
      for (final item in chunk) {
        final result = await processItem(item);
        results.add(result);
      }

      // Pause between chunks if requested
      if (pauseBetweenChunks != null && end < items.length) {
        await Future.delayed(pauseBetweenChunks);
      }
    }

    return results;
  }

  /// Process large data in parallel chunks with controlled concurrency
  static Future<List<R>> processInParallelChunks<T, R>({
    required List<T> items,
    required Future<R> Function(T item) processItem,
    int maxConcurrent = 3,
    int chunkSize = 10,
    Duration? pauseBetweenChunks,
  }) async {
    final results = <R>[];
    final semaphore = Semaphore(maxConcurrent);

    for (int i = 0; i < items.length; i += chunkSize) {
      final end = math.min(i + chunkSize, items.length);
      final chunk = items.sublist(i, end);

      // Process chunk in parallel
      final chunkFutures = chunk.map((item) async {
        await semaphore.acquire();
        try {
          return await processItem(item);
        } finally {
          semaphore.release();
        }
      });

      // Wait for chunk to complete
      final chunkResults = await Future.wait(chunkFutures);
      results.addAll(chunkResults);

      // Pause between chunks if requested
      if (pauseBetweenChunks != null && end < items.length) {
        await Future.delayed(pauseBetweenChunks);
      }
    }

    return results;
  }

  /// Stream large data in chunks
  static Stream<R> streamInChunks<T, R>({
    required List<T> items,
    required Future<R> Function(T item) processItem,
    int chunkSize = 10,
    Duration? pauseBetweenChunks,
  }) async* {
    for (int i = 0; i < items.length; i += chunkSize) {
      final end = math.min(i + chunkSize, items.length);
      final chunk = items.sublist(i, end);

      // Process this chunk
      for (final item in chunk) {
        yield await processItem(item);
      }

      // Pause between chunks if requested
      if (pauseBetweenChunks != null && end < items.length) {
        await Future.delayed(pauseBetweenChunks);
      }
    }
  }

  /// Get current memory usage in MB
  int get currentMemoryUsageMB => _currentMemoryUsageMB;

  /// Get peak memory usage in MB
  int get peakMemoryUsageMB => _peakMemoryUsageMB;

  /// Get memory statistics
  Map<String, dynamic> getMemoryStats() {
    return {
      'currentMB': _currentMemoryUsageMB,
      'peakMB': _peakMemoryUsageMB,
      'thresholdMB': _highMemoryThresholdMB,
      'recentReadings': _recentMemoryReadings,
      'isMonitoring': _isMonitoring,
      'monitoringIntervalSeconds': _monitoringInterval.inSeconds,
    };
  }

  /// Dispose resources
  void dispose() {
    stopMemoryMonitoring();
    _highMemoryCallbacks.clear();
    _recentMemoryReadings.clear();
  }
}

/// Cache with memory-aware eviction policies
class MemoryAwareCache<K, V> {
  final Map<K, _CacheEntry<V>> _cache = {};
  final int _maxSize;
  final Duration? _entryTTL;
  final MemoryManager _memoryManager = MemoryManager.instance;

  MemoryAwareCache({
    int maxSize = 100,
    Duration? entryTTL,
  }) : _maxSize = maxSize,
        _entryTTL = entryTTL {
    // Register for high memory notifications
    _memoryManager.addHighMemoryCallback(_onHighMemory);
  }

  /// Put an item in the cache
  void put(K key, V value) {
    final now = DateTime.now();
    _cache[key] = _CacheEntry(
        value: value,
        insertedAt: now,
        lastAccessedAt: now
    );

    // Check if we need to evict entries
    _checkEviction();
  }

  /// Get an item from the cache
  V? get(K key) {
    final entry = _cache[key];

    if (entry != null) {
      // Update last accessed time
      entry.lastAccessedAt = DateTime.now();

      // Check if entry has expired
      if (_isExpired(entry)) {
        _cache.remove(key);
        return null;
      }
    }

    return entry?.value;
  }

  /// Remove an item from the cache
  V? remove(K key) {
    final entry = _cache.remove(key);
    return entry?.value;
  }

  /// Clear the entire cache
  void clear() {
    _cache.clear();
  }

  /// Check if an entry is expired
  bool _isExpired(_CacheEntry<V> entry) {
    if (_entryTTL == null) return false;

    final now = DateTime.now();
    return now.difference(entry.insertedAt) > _entryTTL;
  }

  /// Check if we need to evict entries
  void _checkEviction() {
    // Evict based on max size
    if (_cache.length > _maxSize) {
      _evictOldest();
    }
  }

  /// Evict the oldest entries
  void _evictOldest() {
    if (_cache.isEmpty) return;

    // Find the oldest entry based on insertion time
    K? oldestKey;
    DateTime? oldestTime;

    for (final MapEntry(key: key, value: entry) in _cache.entries) {
      if (oldestTime == null) {
        oldestKey = key;
        oldestTime = entry.insertedAt;
      } else if (entry.insertedAt.isBefore(oldestTime)) {
        oldestKey = key;
        oldestTime = entry.insertedAt;
      }
    }

    // Remove the oldest entry
    if (oldestKey != null) {
      _cache.remove(oldestKey);
    }
  }

  /// Handle high memory situations
  Future<void> _onHighMemory() async {
    // When memory is high, aggressively reduce cache size
    final currentSize = _cache.length;

    if (currentSize <= 10) {
      // Keep at least a few items
      return;
    }

    // Remove older half of the cache
    final keysToKeep = _cache.entries
        .sorted((a, b) => b.value.lastAccessedAt.compareTo(a.value.lastAccessedAt)) // Sort by most recent first
        .take((currentSize / 2).ceil()) // Keep the newer half
        .map((e) => e.key)
        .toSet();

    // Remove keys not in the keysToKeep set
    final keysToRemove = _cache.keys.where((key) => !keysToKeep.contains(key)).toList();

    for (final key in keysToRemove) {
      _cache.remove(key);
    }

    MCPLogger('mcp.memory_cache').info('Cache reduced from $currentSize to ${_cache.length} items due to high memory');
  }

  /// Current cache size
  int get size => _cache.length;

  /// Whether the cache contains a key
  bool containsKey(K key) => _cache.containsKey(key);

  /// All keys in the cache
  Iterable<K> get keys => _cache.keys;
}

/// Internal cache entry to track insertion and access times
class _CacheEntry<V> {
  final V value;
  final DateTime insertedAt;
  DateTime lastAccessedAt;

  _CacheEntry({
    required this.value,
    required this.insertedAt,
    required this.lastAccessedAt,
  });
}

/// Extension for sorted entries
extension SortedEntries<K, V> on Iterable<MapEntry<K, V>> {
  List<MapEntry<K, V>> sorted(int Function(MapEntry<K, V>, MapEntry<K, V>) compare) {
    final list = toList();
    list.sort(compare);
    return list;
  }
}

class Semaphore {
  final int _maxConcurrent;
  int _currentCount = 0;
  final _queue = Queue<Completer<void>>();

  Semaphore(this._maxConcurrent);

  Future<void> acquire() async {
    if (_currentCount < _maxConcurrent) {
      _currentCount++;
      return;
    }

    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final next = _queue.removeFirst();
      next.complete();
    } else {
      _currentCount--;
    }
  }
}