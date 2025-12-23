# Performance Tuning

Comprehensive guide to optimizing Flutter MCP application performance.

## Performance Analysis

### Built-in Performance Monitor

```dart
// lib/performance/performance_monitor.dart
import 'dart:async';

class MCPPerformanceMonitor {
  static final MCPPerformanceMonitor _instance = MCPPerformanceMonitor._();
  factory MCPPerformanceMonitor() => _instance;
  MCPPerformanceMonitor._();
  
  final Map<String, PerformanceMetrics> _metrics = {};
  final StreamController<PerformanceReport> _reportStream = 
      StreamController.broadcast();
  
  Timer? _reportTimer;
  
  void startMonitoring({
    Duration reportInterval = const Duration(minutes: 1),
  }) {
    _reportTimer?.cancel();
    _reportTimer = Timer.periodic(reportInterval, (_) {
      final report = generateReport();
      _reportStream.add(report);
    });
  }
  
  void stopMonitoring() {
    _reportTimer?.cancel();
  }
  
  void recordOperation(String name, void Function() operation) {
    final stopwatch = Stopwatch()..start();
    
    try {
      operation();
    } finally {
      stopwatch.stop();
      _recordMetric(name, stopwatch.elapsed);
    }
  }
  
  Future<T> recordAsyncOperation<T>(
    String name, 
    Future<T> Function() operation,
  ) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      return await operation();
    } finally {
      stopwatch.stop();
      _recordMetric(name, stopwatch.elapsed);
    }
  }
  
  void _recordMetric(String name, Duration duration) {
    _metrics.putIfAbsent(name, () => PerformanceMetrics(name: name))
      ..addMeasurement(duration);
  }
  
  PerformanceReport generateReport() {
    final report = PerformanceReport(
      timestamp: DateTime.now(),
      metrics: _metrics.values.map((m) => m.toSummary()).toList(),
    );
    
    return report;
  }
  
  Stream<PerformanceReport> get reports => _reportStream.stream;
}

class PerformanceMetrics {
  final String name;
  final List<Duration> measurements = [];
  
  PerformanceMetrics({required this.name});
  
  void addMeasurement(Duration duration) {
    measurements.add(duration);
    
    // Keep only last 1000 measurements
    if (measurements.length > 1000) {
      measurements.removeAt(0);
    }
  }
  
  MetricsSummary toSummary() {
    if (measurements.isEmpty) {
      return MetricsSummary(name: name);
    }
    
    final sortedMs = measurements
        .map((d) => d.inMicroseconds / 1000)
        .toList()
      ..sort();
    
    return MetricsSummary(
      name: name,
      count: measurements.length,
      min: sortedMs.first,
      max: sortedMs.last,
      average: sortedMs.reduce((a, b) => a + b) / sortedMs.length,
      median: sortedMs[sortedMs.length ~/ 2],
      p95: sortedMs[(sortedMs.length * 0.95).floor()],
      p99: sortedMs[(sortedMs.length * 0.99).floor()],
    );
  }
}

class MetricsSummary {
  final String name;
  final int count;
  final double? min;
  final double? max;
  final double? average;
  final double? median;
  final double? p95;
  final double? p99;
  
  MetricsSummary({
    required this.name,
    this.count = 0,
    this.min,
    this.max,
    this.average,
    this.median,
    this.p95,
    this.p99,
  });
}

class PerformanceReport {
  final DateTime timestamp;
  final List<MetricsSummary> metrics;
  
  PerformanceReport({
    required this.timestamp,
    required this.metrics,
  });
}
```

### Performance Profiling

```dart
// lib/performance/profiler.dart
class MCPProfiler {
  static final Map<String, ProfileData> _profiles = {};
  static bool _enabled = false;
  
  static void enable() => _enabled = true;
  static void disable() => _enabled = false;
  
  static ProfileScope profile(String name) {
    if (!_enabled) return ProfileScope.noop(name);
    
    return ProfileScope(name);
  }
  
  static void recordProfile(String name, Duration duration) {
    if (!_enabled) return;
    
    _profiles.putIfAbsent(name, () => ProfileData(name: name))
      ..addSample(duration);
  }
  
  static Map<String, ProfileSummary> getSummary() {
    return _profiles.map((name, data) => 
      MapEntry(name, data.toSummary()));
  }
  
  static void reset() {
    _profiles.clear();
  }
  
  static String generateReport() {
    final buffer = StringBuffer();
    buffer.writeln('Performance Profile Report');
    buffer.writeln('=' * 30);
    
    final summaries = getSummary();
    
    // Sort by total time
    final sorted = summaries.entries.toList()
      ..sort((a, b) => b.value.totalTime.compareTo(a.value.totalTime));
    
    for (final entry in sorted) {
      final summary = entry.value;
      buffer.writeln('\n${summary.name}:');
      buffer.writeln('  Calls: ${summary.count}');
      buffer.writeln('  Total: ${summary.totalTime.toStringAsFixed(2)}ms');
      buffer.writeln('  Average: ${summary.averageTime.toStringAsFixed(2)}ms');
      buffer.writeln('  Min: ${summary.minTime.toStringAsFixed(2)}ms');
      buffer.writeln('  Max: ${summary.maxTime.toStringAsFixed(2)}ms');
    }
    
    return buffer.toString();
  }
}

class ProfileScope {
  final String name;
  final Stopwatch _stopwatch;
  final bool _active;
  
  ProfileScope(this.name) 
      : _stopwatch = Stopwatch()..start(),
        _active = true;
  
  ProfileScope.noop(this.name) 
      : _stopwatch = Stopwatch(),
        _active = false;
  
  void end() {
    if (!_active) return;
    
    _stopwatch.stop();
    MCPProfiler.recordProfile(name, _stopwatch.elapsed);
  }
}

class ProfileData {
  final String name;
  final List<Duration> samples = [];
  
  ProfileData({required this.name});
  
  void addSample(Duration duration) {
    samples.add(duration);
  }
  
  ProfileSummary toSummary() {
    if (samples.isEmpty) {
      return ProfileSummary(name: name);
    }
    
    final milliseconds = samples
        .map((d) => d.inMicroseconds / 1000)
        .toList()
      ..sort();
    
    return ProfileSummary(
      name: name,
      count: samples.length,
      totalTime: milliseconds.reduce((a, b) => a + b),
      averageTime: milliseconds.reduce((a, b) => a + b) / samples.length,
      minTime: milliseconds.first,
      maxTime: milliseconds.last,
    );
  }
}

class ProfileSummary {
  final String name;
  final int count;
  final double totalTime;
  final double averageTime;
  final double minTime;
  final double maxTime;
  
  ProfileSummary({
    required this.name,
    this.count = 0,
    this.totalTime = 0,
    this.averageTime = 0,
    this.minTime = 0,
    this.maxTime = 0,
  });
}

// Usage example
void performOperation() {
  final scope = MCPProfiler.profile('database_query');
  
  try {
    // Perform operation
    database.query('SELECT * FROM users');
  } finally {
    scope.end();
  }
}
```

## Connection Optimization

### Connection Pooling

```dart
// lib/optimization/connection_pool.dart
class ConnectionPool {
  final int maxConnections;
  final Duration connectionTimeout;
  final Duration idleTimeout;
  
  final List<PooledConnection> _connections = [];
  final Queue<Completer<PooledConnection>> _waitingQueue = Queue();
  
  ConnectionPool({
    this.maxConnections = 5,
    this.connectionTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(minutes: 5),
  });
  
  Future<PooledConnection> getConnection() async {
    // Check for available connection
    final available = _connections.firstWhere(
      (conn) => !conn.inUse && conn.isValid,
      orElse: () => null,
    );
    
    if (available != null) {
      available.markInUse();
      return available;
    }
    
    // Create new connection if under limit
    if (_connections.length < maxConnections) {
      final connection = await _createConnection();
      _connections.add(connection);
      return connection;
    }
    
    // Wait for available connection
    final completer = Completer<PooledConnection>();
    _waitingQueue.add(completer);
    
    // Add timeout
    Timer(connectionTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Connection pool timeout'),
        );
      }
    });
    
    return completer.future;
  }
  
  void releaseConnection(PooledConnection connection) {
    connection.markIdle();
    
    // Check waiting queue
    if (_waitingQueue.isNotEmpty) {
      final completer = _waitingQueue.removeFirst();
      connection.markInUse();
      completer.complete(connection);
    }
    
    // Schedule idle timeout
    Timer(idleTimeout, () {
      if (!connection.inUse && connection.isValid) {
        _removeConnection(connection);
      }
    });
  }
  
  Future<PooledConnection> _createConnection() async {
    final connection = await MCPConnection.create();
    return PooledConnection(
      connection: connection,
      pool: this,
    );
  }
  
  void _removeConnection(PooledConnection connection) {
    connection.close();
    _connections.remove(connection);
  }
  
  Future<void> close() async {
    for (final connection in _connections) {
      await connection.close();
    }
    _connections.clear();
    
    for (final completer in _waitingQueue) {
      completer.completeError(
        StateError('Connection pool closed'),
      );
    }
    _waitingQueue.clear();
  }
}

class PooledConnection {
  final MCPConnection connection;
  final ConnectionPool pool;
  
  bool _inUse = true;
  DateTime _lastUsed = DateTime.now();
  
  PooledConnection({
    required this.connection,
    required this.pool,
  });
  
  bool get inUse => _inUse;
  bool get isValid => connection.isOpen;
  
  void markInUse() {
    _inUse = true;
    _lastUsed = DateTime.now();
  }
  
  void markIdle() {
    _inUse = false;
    _lastUsed = DateTime.now();
  }
  
  Future<void> close() async {
    await connection.close();
  }
  
  Future<T> execute<T>(Future<T> Function(MCPConnection) operation) async {
    try {
      return await operation(connection);
    } finally {
      pool.releaseConnection(this);
    }
  }
}

// Usage
class OptimizedMCPClient {
  final ConnectionPool _pool = ConnectionPool(
    maxConnections: 10,
    connectionTimeout: Duration(seconds: 5),
    idleTimeout: Duration(minutes: 2),
  );
  
  Future<ToolResult> callTool({
    required String serverId,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final connection = await _pool.getConnection();
    
    return connection.execute((conn) async {
      return await conn.callTool(
        serverId: serverId,
        name: name,
        arguments: arguments,
      );
    });
  }
}
```

### Request Batching

```dart
// lib/optimization/request_batcher.dart
class RequestBatcher {
  final Duration batchWindow;
  final int maxBatchSize;
  
  final List<BatchRequest> _pendingRequests = [];
  Timer? _batchTimer;
  
  RequestBatcher({
    this.batchWindow = const Duration(milliseconds: 100),
    this.maxBatchSize = 50,
  });
  
  Future<T> queueRequest<T>(BatchRequest<T> request) {
    _pendingRequests.add(request);
    
    // Start batch timer if not running
    _batchTimer ??= Timer(batchWindow, _processBatch);
    
    // Process immediately if batch is full
    if (_pendingRequests.length >= maxBatchSize) {
      _processBatch();
    }
    
    return request.completer.future;
  }
  
  void _processBatch() {
    _batchTimer?.cancel();
    _batchTimer = null;
    
    if (_pendingRequests.isEmpty) return;
    
    final batch = List<BatchRequest>.from(_pendingRequests);
    _pendingRequests.clear();
    
    // Group requests by type and server
    final grouped = <String, List<BatchRequest>>{};
    
    for (final request in batch) {
      final key = '${request.serverId}:${request.type}';
      grouped.putIfAbsent(key, () => []).add(request);
    }
    
    // Process each group
    grouped.forEach((key, requests) {
      _processBatchGroup(requests);
    });
  }
  
  Future<void> _processBatchGroup(List<BatchRequest> requests) async {
    final serverId = requests.first.serverId;
    final type = requests.first.type;
    
    try {
      final batchResult = await mcp.client.callTool(
        serverId: serverId,
        name: '_batch_${type}',
        arguments: {
          'requests': requests.map((r) => r.toJson()).toList(),
        },
      );
      
      // Distribute results
      final results = batchResult.content as List;
      
      for (int i = 0; i < requests.length; i++) {
        if (i < results.length) {
          requests[i].completer.complete(results[i]);
        } else {
          requests[i].completer.completeError(
            StateError('Missing batch result'),
          );
        }
      }
    } catch (e) {
      // Complete all requests with error
      for (final request in requests) {
        request.completer.completeError(e);
      }
    }
  }
}

class BatchRequest<T> {
  final String serverId;
  final String type;
  final Map<String, dynamic> params;
  final Completer<T> completer = Completer<T>();
  
  BatchRequest({
    required this.serverId,
    required this.type,
    required this.params,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'params': params,
  };
}

// Usage
class BatchedMCPClient {
  final RequestBatcher _batcher = RequestBatcher();
  
  Future<ToolResult> callTool({
    required String serverId,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final request = BatchRequest<ToolResult>(
      serverId: serverId,
      type: 'tool_call',
      params: {
        'name': name,
        'arguments': arguments,
      },
    );
    
    return await _batcher.queueRequest(request);
  }
}
```

## Memory Optimization

### Memory-Efficient Caching

```dart
// lib/optimization/memory_cache.dart
import 'dart:async';

class MemoryEfficientCache<K, V> {
  final int maxSize;
  final int maxMemory;
  final Duration ttl;
  final int Function(V) sizeOf;
  
  final Map<K, CacheEntry<V>> _cache = {};
  final Queue<K> _lruQueue = Queue();
  int _currentMemory = 0;
  
  MemoryEfficientCache({
    this.maxSize = 100,
    this.maxMemory = 50 * 1024 * 1024, // 50MB
    this.ttl = const Duration(minutes: 15),
    required this.sizeOf,
  });
  
  V? get(K key) {
    final entry = _cache[key];
    if (entry == null) return null;
    
    // Check expiration
    if (entry.isExpired) {
      remove(key);
      return null;
    }
    
    // Update LRU
    _lruQueue.remove(key);
    _lruQueue.addLast(key);
    entry.lastAccessed = DateTime.now();
    
    return entry.value;
  }
  
  void put(K key, V value) {
    final size = sizeOf(value);
    
    // Check memory limit
    if (size > maxMemory) {
      throw ArgumentError('Value size exceeds memory limit');
    }
    
    // Remove existing entry
    if (_cache.containsKey(key)) {
      remove(key);
    }
    
    // Evict entries if necessary
    while (_cache.length >= maxSize || _currentMemory + size > maxMemory) {
      if (_lruQueue.isEmpty) break;
      remove(_lruQueue.first);
    }
    
    // Add new entry
    _cache[key] = CacheEntry(
      value: value,
      size: size,
      created: DateTime.now(),
      ttl: ttl,
    );
    
    _lruQueue.addLast(key);
    _currentMemory += size;
  }
  
  void remove(K key) {
    final entry = _cache.remove(key);
    if (entry != null) {
      _currentMemory -= entry.size;
      _lruQueue.remove(key);
    }
  }
  
  void clear() {
    _cache.clear();
    _lruQueue.clear();
    _currentMemory = 0;
  }
  
  void evictExpired() {
    final expiredKeys = <K>[];
    
    _cache.forEach((key, entry) {
      if (entry.isExpired) {
        expiredKeys.add(key);
      }
    });
    
    for (final key in expiredKeys) {
      remove(key);
    }
  }
  
  CacheStats getStats() {
    final validEntries = _cache.values.where((e) => !e.isExpired);
    
    return CacheStats(
      size: _cache.length,
      memoryUsage: _currentMemory,
      hitRate: _calculateHitRate(),
      avgEntrySize: validEntries.isEmpty 
          ? 0 
          : _currentMemory ~/ validEntries.length,
      oldestEntry: _lruQueue.isEmpty 
          ? null 
          : _cache[_lruQueue.first]?.created,
    );
  }
  
  double _calculateHitRate() {
    // Simplified hit rate calculation
    // In production, track actual hits/misses
    return _cache.isEmpty ? 0.0 : 0.85;
  }
}

class CacheEntry<V> {
  final V value;
  final int size;
  final DateTime created;
  final Duration ttl;
  DateTime lastAccessed;
  
  CacheEntry({
    required this.value,
    required this.size,
    required this.created,
    required this.ttl,
  }) : lastAccessed = created;
  
  bool get isExpired => DateTime.now().difference(created) > ttl;
}

class CacheStats {
  final int size;
  final int memoryUsage;
  final double hitRate;
  final int avgEntrySize;
  final DateTime? oldestEntry;
  
  CacheStats({
    required this.size,
    required this.memoryUsage,
    required this.hitRate,
    required this.avgEntrySize,
    this.oldestEntry,
  });
}

// Usage
class CachedMCPClient {
  final _cache = MemoryEfficientCache<String, ToolResult>(
    maxSize: 500,
    maxMemory: 100 * 1024 * 1024, // 100MB
    ttl: Duration(minutes: 10),
    sizeOf: (result) => result.content.toString().length * 2, // Rough estimate
  );
  
  Future<ToolResult> callTool({
    required String serverId,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final cacheKey = '$serverId:$name:${jsonEncode(arguments)}';
    
    // Check cache
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      return cached;
    }
    
    // Execute request
    final result = await mcp.client.callTool(
      serverId: serverId,
      name: name,
      arguments: arguments,
    );
    
    // Cache result
    _cache.put(cacheKey, result);
    
    return result;
  }
}
```

### Object Pooling

```dart
// lib/optimization/object_pool.dart
import 'dart:collection';

class ObjectPool<T> {
  final T Function() factory;
  final void Function(T)? reset;
  final int maxSize;
  
  final Queue<T> _available = Queue();
  final Set<T> _inUse = {};
  
  ObjectPool({
    required this.factory,
    this.reset,
    this.maxSize = 10,
  });
  
  T acquire() {
    T object;
    
    if (_available.isNotEmpty) {
      object = _available.removeFirst();
    } else if (_available.length + _inUse.length < maxSize) {
      object = factory();
    } else {
      throw StateError('Object pool exhausted');
    }
    
    _inUse.add(object);
    return object;
  }
  
  void release(T object) {
    if (!_inUse.remove(object)) {
      throw ArgumentError('Object not from this pool');
    }
    
    reset?.call(object);
    _available.addLast(object);
  }
  
  Future<R> use<R>(Future<R> Function(T) operation) async {
    final object = acquire();
    
    try {
      return await operation(object);
    } finally {
      release(object);
    }
  }
  
  void clear() {
    _available.clear();
    _inUse.clear();
  }
  
  PoolStats getStats() {
    return PoolStats(
      available: _available.length,
      inUse: _inUse.length,
      total: _available.length + _inUse.length,
      maxSize: maxSize,
    );
  }
}

class PoolStats {
  final int available;
  final int inUse;
  final int total;
  final int maxSize;
  
  PoolStats({
    required this.available,
    required this.inUse,
    required this.total,
    required this.maxSize,
  });
  
  double get utilizationRate => total / maxSize;
  double get activeRate => inUse / maxSize;
}

// Example: JSON encoder pool
class JsonEncoderPool {
  static final _pool = ObjectPool<JsonEncoder>(
    factory: () => JsonEncoder(),
    maxSize: 20,
  );
  
  static Future<String> encode(Object? object) async {
    return _pool.use((encoder) async {
      return encoder.convert(object);
    });
  }
}

// Example: Buffer pool
class ByteBufferPool {
  static final Map<int, ObjectPool<ByteBuffer>> _pools = {};
  
  static ByteBuffer acquire(int size) {
    // Round to nearest power of 2
    final poolSize = _roundToPowerOfTwo(size);
    
    final pool = _pools.putIfAbsent(poolSize, () => ObjectPool(
      factory: () => ByteBuffer(poolSize),
      reset: (buffer) => buffer.clear(),
      maxSize: 50,
    ));
    
    return pool.acquire();
  }
  
  static void release(ByteBuffer buffer) {
    final poolSize = _roundToPowerOfTwo(buffer.capacity);
    _pools[poolSize]?.release(buffer);
  }
  
  static int _roundToPowerOfTwo(int size) {
    int n = size - 1;
    n |= n >> 1;
    n |= n >> 2;
    n |= n >> 4;
    n |= n >> 8;
    n |= n >> 16;
    return n + 1;
  }
}
```

## Lazy Loading

### Lazy Resource Loading

```dart
// lib/optimization/lazy_loader.dart
class LazyLoader<T> {
  final Future<T> Function() loader;
  final Duration? ttl;
  final bool cacheResult;
  
  Future<T>? _loadingFuture;
  T? _value;
  DateTime? _loadedAt;
  
  LazyLoader({
    required this.loader,
    this.ttl,
    this.cacheResult = true,
  });
  
  Future<T> get value async {
    // Check if already loaded and not expired
    if (_value != null && !_isExpired) {
      return _value!;
    }
    
    // Check if already loading
    if (_loadingFuture != null) {
      return _loadingFuture!;
    }
    
    // Start loading
    _loadingFuture = _load();
    
    try {
      final result = await _loadingFuture!;
      return result;
    } finally {
      _loadingFuture = null;
    }
  }
  
  Future<T> _load() async {
    final result = await loader();
    
    if (cacheResult) {
      _value = result;
      _loadedAt = DateTime.now();
    }
    
    return result;
  }
  
  bool get _isExpired {
    if (ttl == null || _loadedAt == null) return false;
    return DateTime.now().difference(_loadedAt!) > ttl!;
  }
  
  void invalidate() {
    _value = null;
    _loadedAt = null;
    _loadingFuture = null;
  }
  
  bool get isLoaded => _value != null && !_isExpired;
  bool get isLoading => _loadingFuture != null;
}

// Example: Lazy configuration loading
class LazyConfiguration {
  static final _serverConfig = LazyLoader<ServerConfig>(
    loader: () async {
      final response = await http.get(
        Uri.parse('https://api.example.com/config'),
      );
      return ServerConfig.fromJson(jsonDecode(response.body));
    },
    ttl: Duration(hours: 1),
  );
  
  static final _featureFlags = LazyLoader<Map<String, bool>>(
    loader: () async {
      final response = await http.get(
        Uri.parse('https://api.example.com/features'),
      );
      return Map<String, bool>.from(jsonDecode(response.body));
    },
    ttl: Duration(minutes: 30),
  );
  
  static Future<ServerConfig> get serverConfig => _serverConfig.value;
  static Future<Map<String, bool>> get featureFlags => _featureFlags.value;
  
  static void refresh() {
    _serverConfig.invalidate();
    _featureFlags.invalidate();
  }
}
```

### Lazy Widget Loading

```dart
// lib/optimization/lazy_widgets.dart
class LazyWidget extends StatefulWidget {
  final Widget Function(BuildContext) builder;
  final Widget placeholder;
  final Duration delay;
  final bool cacheWidget;
  
  const LazyWidget({
    Key? key,
    required this.builder,
    this.placeholder = const SizedBox.shrink(),
    this.delay = const Duration(milliseconds: 200),
    this.cacheWidget = true,
  }) : super(key: key);
  
  @override
  State<LazyWidget> createState() => _LazyWidgetState();
}

class _LazyWidgetState extends State<LazyWidget> {
  Widget? _cachedWidget;
  bool _isLoaded = false;
  
  @override
  void initState() {
    super.initState();
    
    // Delay loading to improve initial render
    Future.delayed(widget.delay, () {
      if (mounted) {
        setState(() {
          _isLoaded = true;
        });
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return widget.placeholder;
    }
    
    if (widget.cacheWidget && _cachedWidget != null) {
      return _cachedWidget!;
    }
    
    final child = widget.builder(context);
    
    if (widget.cacheWidget) {
      _cachedWidget = child;
    }
    
    return child;
  }
}

// Example: Lazy loading list
class LazyList extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final int visibleThreshold;
  
  const LazyList({
    Key? key,
    required this.itemCount,
    required this.itemBuilder,
    this.visibleThreshold = 10,
  }) : super(key: key);
  
  @override
  State<LazyList> createState() => _LazyListState();
}

class _LazyListState extends State<LazyList> {
  final Set<int> _loadedIndices = {};
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }
  
  void _onScroll() {
    final position = _scrollController.position;
    final viewportHeight = position.viewportDimension;
    final scrollOffset = position.pixels;
    
    // Calculate visible range
    final itemHeight = viewportHeight / widget.visibleThreshold;
    final firstVisible = (scrollOffset / itemHeight).floor();
    final lastVisible = ((scrollOffset + viewportHeight) / itemHeight).ceil();
    
    // Preload nearby items
    final preloadStart = (firstVisible - widget.visibleThreshold).clamp(0, widget.itemCount);
    final preloadEnd = (lastVisible + widget.visibleThreshold).clamp(0, widget.itemCount);
    
    for (int i = preloadStart; i < preloadEnd; i++) {
      _loadedIndices.add(i);
    }
    
    setState(() {});
  }
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        if (!_loadedIndices.contains(index)) {
          return Container(
            height: 100,
            alignment: Alignment.center,
            child: CircularProgressIndicator(),
          );
        }
        
        return widget.itemBuilder(context, index);
      },
    );
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
```

## Async Operations

### Throttling and Debouncing

```dart
// lib/optimization/throttle_debounce.dart
class Throttler {
  final Duration duration;
  Timer? _timer;
  bool _isThrottling = false;
  
  Throttler(this.duration);
  
  void run(VoidCallback action) {
    if (_isThrottling) return;
    
    _isThrottling = true;
    action();
    
    _timer = Timer(duration, () {
      _isThrottling = false;
    });
  }
  
  void cancel() {
    _timer?.cancel();
    _isThrottling = false;
  }
}

class Debouncer {
  final Duration duration;
  Timer? _timer;
  
  Debouncer(this.duration);
  
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }
  
  void cancel() {
    _timer?.cancel();
  }
}

// Advanced throttle with return value
class AsyncThrottler<T> {
  final Duration duration;
  final Future<T> Function() operation;
  
  DateTime? _lastRun;
  Future<T>? _pendingFuture;
  
  AsyncThrottler({
    required this.duration,
    required this.operation,
  });
  
  Future<T> run() async {
    final now = DateTime.now();
    
    if (_lastRun != null) {
      final elapsed = now.difference(_lastRun!);
      if (elapsed < duration) {
        // Return pending future if exists
        if (_pendingFuture != null) {
          return _pendingFuture!;
        }
        
        // Wait for remaining time
        await Future.delayed(duration - elapsed);
      }
    }
    
    _lastRun = DateTime.now();
    _pendingFuture = operation();
    
    try {
      return await _pendingFuture!;
    } finally {
      _pendingFuture = null;
    }
  }
}

// Usage example
class SearchWidget extends StatefulWidget {
  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  final _searchDebouncer = Debouncer(Duration(milliseconds: 500));
  final _refreshThrottler = Throttler(Duration(seconds: 1));
  final _apiThrottler = AsyncThrottler(
    duration: Duration(seconds: 2),
    operation: () => mcp.client.callTool(
      serverId: 'server',
      name: 'search',
      arguments: {},
    ),
  );
  
  void _onSearchChanged(String query) {
    _searchDebouncer.run(() {
      _performSearch(query);
    });
  }
  
  void _onRefreshPressed() {
    _refreshThrottler.run(() {
      _refreshResults();
    });
  }
  
  Future<void> _onApiCall() async {
    final result = await _apiThrottler.run();
    // Process result
  }
}
```

### Parallel Execution

```dart
// lib/optimization/parallel_executor.dart
class ParallelExecutor {
  final int maxConcurrency;
  final Queue<_Task> _taskQueue = Queue();
  final Set<Future> _activeTasks = {};
  
  ParallelExecutor({this.maxConcurrency = 5});
  
  Future<T> execute<T>(Future<T> Function() task) async {
    final completer = Completer<T>();
    
    _taskQueue.add(_Task(
      execute: task,
      completer: completer,
    ));
    
    _processTasks();
    
    return completer.future;
  }
  
  void _processTasks() {
    while (_activeTasks.length < maxConcurrency && _taskQueue.isNotEmpty) {
      final task = _taskQueue.removeFirst();
      
      final future = task.execute().then((result) {
        task.completer.complete(result);
      }).catchError((error) {
        task.completer.completeError(error);
      }).whenComplete(() {
        _activeTasks.remove(future);
        _processTasks();
      });
      
      _activeTasks.add(future);
    }
  }
  
  Future<List<T>> executeAll<T>(List<Future<T> Function()> tasks) {
    return Future.wait(tasks.map((task) => execute(task)));
  }
  
  Future<void> drain() async {
    while (_taskQueue.isNotEmpty || _activeTasks.isNotEmpty) {
      await Future.any(_activeTasks.isEmpty 
          ? [Future.delayed(Duration.zero)]
          : _activeTasks);
    }
  }
}

class _Task<T> {
  final Future<T> Function() execute;
  final Completer<T> completer;
  
  _Task({
    required this.execute,
    required this.completer,
  });
}

// Usage
class DataFetcher {
  final _executor = ParallelExecutor(maxConcurrency: 3);
  
  Future<List<UserData>> fetchAllUsers(List<String> userIds) async {
    final tasks = userIds.map((id) => () => fetchUser(id)).toList();
    return await _executor.executeAll(tasks);
  }
  
  Future<UserData> fetchUser(String userId) async {
    return await mcp.client.callTool(
      serverId: 'server',
      name: 'getUser',
      arguments: {'userId': userId},
    );
  }
}
```

## Runtime Optimization

### Ahead-of-Time Compilation

```dart
// lib/optimization/aot_optimization.dart
class AOTOptimizer {
  // Pre-compile regex patterns
  static final Map<String, RegExp> _compiledPatterns = {
    'email': RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$'),
    'phone': RegExp(r'^\+?[\d\s-()]+$'),
    'url': RegExp(r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)$'),
  };
  
  // Pre-calculate constants
  static const Map<String, double> _constants = {
    'golden_ratio': 1.618033988749895,
    'euler': 2.718281828459045,
    'pi': 3.141592653589793,
  };
  
  // Pre-instantiate heavy objects
  static final Map<String, dynamic> _singletons = {
    'json_encoder': JsonEncoder.withIndent('  '),
    'json_decoder': JsonDecoder(),
    'utf8_encoder': utf8.encoder,
    'utf8_decoder': utf8.decoder,
  };
  
  static RegExp getPattern(String name) {
    return _compiledPatterns[name] ?? 
           throw ArgumentError('Unknown pattern: $name');
  }
  
  static double getConstant(String name) {
    return _constants[name] ?? 
           throw ArgumentError('Unknown constant: $name');
  }
  
  static T getSingleton<T>(String name) {
    return _singletons[name] as T? ??
           throw ArgumentError('Unknown singleton: $name');
  }
}

// Pre-compile shaders for Flutter
class ShaderPrecompiler {
  static final Map<String, FragmentProgram> _shaders = {};
  
  static Future<void> precompileShaders() async {
    final shaderNames = [
      'blur',
      'gradient',
      'shadow',
      'ripple',
    ];
    
    for (final name in shaderNames) {
      try {
        final program = await FragmentProgram.fromAsset(
          'shaders/$name.frag',
        );
        _shaders[name] = program;
      } catch (e) {
        print('Failed to compile shader $name: $e');
      }
    }
  }
  
  static FragmentShader? getShader(String name) {
    return _shaders[name]?.fragmentShader();
  }
}
```

### JIT Warmup

```dart
// lib/optimization/jit_warmup.dart
class JITWarmup {
  static final List<Function> _warmupTasks = [];
  
  static void register(Function task) {
    _warmupTasks.add(task);
  }
  
  static Future<void> warmup() async {
    print('Starting JIT warmup...');
    final stopwatch = Stopwatch()..start();
    
    // Run each task multiple times to trigger JIT compilation
    for (final task in _warmupTasks) {
      for (int i = 0; i < 3; i++) {
        try {
          if (task is Future Function()) {
            await task();
          } else {
            task();
          }
        } catch (e) {
          // Ignore errors during warmup
        }
      }
    }
    
    stopwatch.stop();
    print('JIT warmup completed in ${stopwatch.elapsedMilliseconds}ms');
  }
  
  // Common warmup tasks
  static void registerDefaultTasks() {
    // JSON operations
    register(() {
      final data = {'key': 'value', 'list': [1, 2, 3]};
      jsonEncode(data);
      jsonDecode('{"key":"value"}');
    });
    
    // String operations
    register(() {
      'test'.toUpperCase();
      'TEST'.toLowerCase();
      'a,b,c'.split(',');
      ['a', 'b', 'c'].join(',');
    });
    
    // Collection operations
    register(() {
      final list = List.generate(100, (i) => i);
      list.where((x) => x % 2 == 0).toList();
      list.map((x) => x * 2).toList();
      list.fold(0, (a, b) => a + b);
    });
    
    // Regex operations
    register(() {
      final pattern = RegExp(r'\d+');
      pattern.hasMatch('test123');
      pattern.allMatches('a1b2c3');
    });
  }
}

// Use in app initialization
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register warmup tasks
  JITWarmup.registerDefaultTasks();
  
  // Add custom warmup tasks
  JITWarmup.register(() async {
    await mcp.client.getServerInfo();
  });
  
  // Run warmup
  await JITWarmup.warmup();
  
  runApp(MyApp());
}
```

## Build Optimization

### Tree Shaking Configuration

```dart
// lib/optimization/tree_shaking.dart

// Use conditional imports for platform-specific code
// This allows tree shaking to remove unused platform code

// Instead of this:
// import 'dart:io';
// import 'dart:html';

// Do this:
import 'platform/platform_stub.dart'
    if (dart.library.io) 'platform/platform_io.dart'
    if (dart.library.html) 'platform/platform_web.dart';

// Mark unused code for tree shaking
class TreeShakeable {
  // Use @pragma to hint tree shaking
  @pragma('vm:never-inline')
  static void neverInline() {
    // This method will never be inlined
  }
  
  @pragma('vm:prefer-inline')
  static void preferInline() {
    // This method will be inlined when possible
  }
  
  @pragma('vm:entry-point')
  static void keepInBinary() {
    // This method will always be kept in the binary
  }
}

// Conditional features
class ConditionalFeatures {
  static const bool _kEnableAdvancedFeatures = 
      bool.fromEnvironment('ENABLE_ADVANCED', defaultValue: false);
  
  static void useFeature() {
    if (_kEnableAdvancedFeatures) {
      // This code will be removed if ENABLE_ADVANCED is false
      _advancedFeature();
    }
  }
  
  static void _advancedFeature() {
    // Advanced feature implementation
  }
}
```

### Build Flags

```yaml
# flutter build configuration
# pubspec.yaml

# Define build configurations
flutter:
  build:
    defines:
      # Enable specific features
      - ENABLE_ANALYTICS=true
      - ENABLE_CRASH_REPORTING=true
      - API_BASE_URL=https://api.example.com
      
    # Optimization flags
    dart-defines:
      - TREE_SHAKE_ICONS=true
      - NO_DEBUG_BANNER=true
```

```bash
# Build commands with optimization

# Release build with maximum optimization
flutter build apk --release \
  --tree-shake-icons \
  --split-per-abi \
  --obfuscate \
  --split-debug-info=build/symbols \
  --dart-define=ENABLE_ANALYTICS=false

# iOS release build
flutter build ios --release \
  --tree-shake-icons \
  --dart-define=API_BASE_URL=https://prod.api.com

# Web build with optimizations
flutter build web --release \
  --web-renderer canvaskit \
  --tree-shake-icons \
  --no-source-maps \
  --pwa-strategy none
```

## Performance Monitoring

### Production Performance Tracking

```dart
// lib/monitoring/production_monitor.dart
class ProductionMonitor {
  static final ProductionMonitor _instance = ProductionMonitor._();
  factory ProductionMonitor() => _instance;
  ProductionMonitor._();
  
  final _metrics = <String, List<double>>{};
  Timer? _reportTimer;
  
  void startMonitoring() {
    // Report metrics every 5 minutes
    _reportTimer = Timer.periodic(Duration(minutes: 5), (_) {
      _reportMetrics();
    });
    
    // Monitor frame performance
    WidgetsBinding.instance.addTimingsCallback(_onFrameMetrics);
    
    // Monitor memory
    _monitorMemory();
  }
  
  void trackMetric(String name, double value) {
    _metrics.putIfAbsent(name, () => []).add(value);
    
    // Keep only last 1000 values
    if (_metrics[name]!.length > 1000) {
      _metrics[name]!.removeAt(0);
    }
  }
  
  void _onFrameMetrics(List<FrameTiming> timings) {
    for (final timing in timings) {
      trackMetric('frame_build_time', timing.buildDuration.inMicroseconds / 1000);
      trackMetric('frame_raster_time', timing.rasterDuration.inMicroseconds / 1000);
      
      // Track jank
      if (timing.totalSpan.inMilliseconds > 16) {
        trackMetric('jank_frames', 1);
      }
    }
  }
  
  void _monitorMemory() {
    Timer.periodic(Duration(seconds: 30), (_) {
      final usage = ProcessInfo.currentRss;
      trackMetric('memory_usage', usage / 1024 / 1024); // MB
    });
  }
  
  void _reportMetrics() {
    final report = <String, dynamic>{};
    
    _metrics.forEach((name, values) {
      if (values.isEmpty) return;
      
      values.sort();
      report[name] = {
        'count': values.length,
        'min': values.first,
        'max': values.last,
        'avg': values.reduce((a, b) => a + b) / values.length,
        'p50': values[values.length ~/ 2],
        'p95': values[(values.length * 0.95).floor()],
        'p99': values[(values.length * 0.99).floor()],
      };
    });
    
    // Send to analytics service
    _sendToAnalytics(report);
  }
  
  void _sendToAnalytics(Map<String, dynamic> report) {
    // Implementation depends on your analytics service
    try {
      http.post(
        Uri.parse('https://analytics.example.com/metrics'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'app_version': packageInfo.version,
          'platform': Platform.operatingSystem,
          'timestamp': DateTime.now().toIso8601String(),
          'metrics': report,
        }),
      );
    } catch (e) {
      // Fail silently in production
    }
  }
}
```

### Performance Alerts

```dart
// lib/monitoring/performance_alerts.dart
class PerformanceAlerts {
  static final _thresholds = {
    'frame_build_time': 8.0, // ms
    'frame_raster_time': 8.0, // ms
    'memory_usage': 500.0, // MB
    'api_response_time': 2000.0, // ms
    'cpu_usage': 80.0, // percentage
  };
  
  static final _alertCallbacks = <String, List<AlertCallback>>{};
  
  static void registerAlert(
    String metric, 
    AlertCallback callback, {
    double? threshold,
  }) {
    _alertCallbacks.putIfAbsent(metric, () => []).add(callback);
    
    if (threshold != null) {
      _thresholds[metric] = threshold;
    }
  }
  
  static void checkMetric(String metric, double value) {
    final threshold = _thresholds[metric];
    if (threshold == null) return;
    
    if (value > threshold) {
      _triggerAlert(metric, value, threshold);
    }
  }
  
  static void _triggerAlert(String metric, double value, double threshold) {
    final callbacks = _alertCallbacks[metric] ?? [];
    
    for (final callback in callbacks) {
      callback(AlertEvent(
        metric: metric,
        value: value,
        threshold: threshold,
        timestamp: DateTime.now(),
      ));
    }
  }
}

typedef AlertCallback = void Function(AlertEvent event);

class AlertEvent {
  final String metric;
  final double value;
  final double threshold;
  final DateTime timestamp;
  
  AlertEvent({
    required this.metric,
    required this.value,
    required this.threshold,
    required this.timestamp,
  });
}

// Usage
void setupPerformanceAlerts() {
  PerformanceAlerts.registerAlert(
    'memory_usage',
    (event) {
      print('Memory alert: ${event.value}MB (threshold: ${event.threshold}MB)');
      
      // Take action
      if (event.value > 600) {
        // Clear caches
        imageCache.clear();
        imageCache.clearLiveImages();
      }
    },
    threshold: 400.0,
  );
  
  PerformanceAlerts.registerAlert(
    'api_response_time',
    (event) {
      print('Slow API: ${event.value}ms');
      
      // Switch to fallback server
      if (event.value > 5000) {
        mcp.switchToFallbackServer();
      }
    },
  );
}
```

## Platform-Specific Optimization

### Android Optimization

```dart
// lib/platform/android_optimization.dart
class AndroidOptimization {
  static Future<void> optimize() async {
    if (!Platform.isAndroid) return;
    
    // Enable hardware acceleration
    await SystemChannels.platform.invokeMethod('enableHardwareAcceleration');
    
    // Configure render threading
    await SystemChannels.platform.invokeMethod('setRenderThreadPriority', {
      'priority': -4, // THREAD_PRIORITY_DISPLAY
    });
    
    // Enable GPU rasterization
    await SystemChannels.platform.invokeMethod('enableGPURasterization');
    
    // Configure memory trim callbacks
    await SystemChannels.platform.invokeMethod('setMemoryTrimCallbacks');
  }
  
  static Future<void> configureART() async {
    // Configure Android Runtime for better performance
    await SystemChannels.platform.invokeMethod('configureART', {
      'gcType': 'CMS', // Concurrent Mark Sweep
      'heapGrowthLimit': 256, // MB
      'targetUtilization': 0.75,
    });
  }
}
```

```java
// android/app/src/main/java/com/example/app/OptimizationPlugin.java
public class OptimizationPlugin implements MethodCallHandler {
    @Override
    public void onMethodCall(MethodCall call, Result result) {
        switch (call.method) {
            case "enableHardwareAcceleration":
                enableHardwareAcceleration();
                result.success(null);
                break;
                
            case "setRenderThreadPriority":
                int priority = call.argument("priority");
                Process.setThreadPriority(priority);
                result.success(null);
                break;
                
            case "enableGPURasterization":
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    // Enable GPU rasterization
                }
                result.success(null);
                break;
        }
    }
}
```

### iOS Optimization

```dart
// lib/platform/ios_optimization.dart
class IOSOptimization {
  static Future<void> optimize() async {
    if (!Platform.isIOS) return;
    
    // Configure Metal rendering
    await SystemChannels.platform.invokeMethod('configureMetal', {
      'preferredFramesPerSecond': 60,
      'enableMultithreading': true,
    });
    
    // Enable ProMotion display support
    await SystemChannels.platform.invokeMethod('enableProMotion');
    
    // Configure background modes
    await SystemChannels.platform.invokeMethod('configureBackgroundModes', {
      'audioSession': true,
      'location': false,
      'fetch': true,
    });
  }
  
  static Future<void> optimizeMemory() async {
    // Configure iOS memory management
    await SystemChannels.platform.invokeMethod('configureMemory', {
      'imageDecodingThreads': 2,
      'maxCacheSize': 100 * 1024 * 1024, // 100MB
      'aggressivePurging': true,
    });
  }
}
```

```swift
// ios/Runner/OptimizationPlugin.swift
@objc class OptimizationPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "optimization",
            binaryMessenger: registrar.messenger()
        )
        let instance = OptimizationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configureMetal":
            configureMetal(call.arguments as? [String: Any])
            result(nil)
            
        case "enableProMotion":
            if #available(iOS 15.0, *) {
                CADisplayLink.preferredFramesPerSecond = 120
            }
            result(nil)
            
        case "configureMemory":
            configureMemory(call.arguments as? [String: Any])
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
```

## Best Practices

### 1. Measure Before Optimizing

```dart
class OptimizationHelper {
  static Future<OptimizationResult> analyzePerformance(
    VoidCallback operation,
  ) async {
    // Baseline measurement
    final baseline = await _measurePerformance(operation, warmup: true);
    
    // Actual measurement
    final actual = await _measurePerformance(operation, warmup: false);
    
    return OptimizationResult(
      baseline: baseline,
      actual: actual,
      improvement: (baseline.avgTime - actual.avgTime) / baseline.avgTime,
    );
  }
  
  static Future<PerformanceData> _measurePerformance(
    VoidCallback operation, {
    required bool warmup,
  }) async {
    final measurements = <Duration>[];
    final runs = warmup ? 3 : 10;
    
    for (int i = 0; i < runs; i++) {
      final stopwatch = Stopwatch()..start();
      operation();
      stopwatch.stop();
      measurements.add(stopwatch.elapsed);
    }
    
    return PerformanceData(measurements: measurements);
  }
}
```

### 2. Progressive Optimization

```dart
class ProgressiveOptimizer {
  static const List<OptimizationLevel> _levels = [
    OptimizationLevel.none,
    OptimizationLevel.basic,
    OptimizationLevel.aggressive,
    OptimizationLevel.extreme,
  ];
  
  static OptimizationLevel _currentLevel = OptimizationLevel.none;
  
  static void optimizeBasedOnMetrics(PerformanceMetrics metrics) {
    if (metrics.frameRate < 30) {
      // Poor performance, increase optimization
      _increaseOptimization();
    } else if (metrics.frameRate > 55 && _currentLevel != OptimizationLevel.none) {
      // Good performance, can reduce optimization
      _decreaseOptimization();
    }
  }
  
  static void _increaseOptimization() {
    final currentIndex = _levels.indexOf(_currentLevel);
    if (currentIndex < _levels.length - 1) {
      _currentLevel = _levels[currentIndex + 1];
      _applyOptimizationLevel(_currentLevel);
    }
  }
  
  static void _decreaseOptimization() {
    final currentIndex = _levels.indexOf(_currentLevel);
    if (currentIndex > 0) {
      _currentLevel = _levels[currentIndex - 1];
      _applyOptimizationLevel(_currentLevel);
    }
  }
  
  static void _applyOptimizationLevel(OptimizationLevel level) {
    switch (level) {
      case OptimizationLevel.none:
        // No optimizations
        break;
        
      case OptimizationLevel.basic:
        // Basic optimizations
        PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
        break;
        
      case OptimizationLevel.aggressive:
        // Aggressive optimizations
        PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
        // Reduce animation complexity
        break;
        
      case OptimizationLevel.extreme:
        // Extreme optimizations
        PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024;
        // Disable animations
        // Reduce visual quality
        break;
    }
  }
}

enum OptimizationLevel {
  none,
  basic,
  aggressive,
  extreme,
}
```

### 3. Optimization Checklist

```dart
class OptimizationChecklist {
  static final List<OptimizationItem> checklist = [
    OptimizationItem(
      name: 'Image Optimization',
      check: () => PaintingBinding.instance.imageCache.maximumSizeBytes > 0,
      optimize: () {
        PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
        PaintingBinding.instance.imageCache.maximumSize = 100;
      },
    ),
    OptimizationItem(
      name: 'Widget Building',
      check: () => true, // Always check widget optimization
      optimize: () {
        // Use const constructors
        // Implement shouldRebuild properly
        // Use keys effectively
      },
    ),
    OptimizationItem(
      name: 'Network Requests',
      check: () => ConnectionPool().maxConnections > 1,
      optimize: () {
        // Implement connection pooling
        // Enable request batching
        // Add caching layer
      },
    ),
    OptimizationItem(
      name: 'Memory Management',
      check: () => ObjectPool != null,
      optimize: () {
        // Implement object pooling
        // Add memory monitoring
        // Configure garbage collection
      },
    ),
  ];
  
  static Future<OptimizationReport> runChecklist() async {
    final results = <OptimizationResult>[];
    
    for (final item in checklist) {
      final result = OptimizationResult(
        name: item.name,
        isOptimized: item.check(),
        recommendation: item.optimize,
      );
      results.add(result);
    }
    
    return OptimizationReport(
      results: results,
      score: results.where((r) => r.isOptimized).length / results.length,
    );
  }
}

class OptimizationItem {
  final String name;
  final bool Function() check;
  final VoidCallback optimize;
  
  OptimizationItem({
    required this.name,
    required this.check,
    required this.optimize,
  });
}
```

## Performance Testing

### Load Testing

```dart
// lib/testing/load_test.dart
class LoadTester {
  static Future<LoadTestResult> runLoadTest({
    required int concurrent,
    required int duration,
    required Future<void> Function() operation,
  }) async {
    final startTime = DateTime.now();
    final endTime = startTime.add(Duration(seconds: duration));
    
    int successCount = 0;
    int errorCount = 0;
    final responseTimes = <Duration>[];
    
    // Create concurrent operations
    final futures = List.generate(concurrent, (index) async {
      while (DateTime.now().isBefore(endTime)) {
        final opStart = DateTime.now();
        
        try {
          await operation();
          successCount++;
          responseTimes.add(DateTime.now().difference(opStart));
        } catch (e) {
          errorCount++;
        }
      }
    });
    
    await Future.wait(futures);
    
    return LoadTestResult(
      duration: DateTime.now().difference(startTime),
      successCount: successCount,
      errorCount: errorCount,
      responseTimes: responseTimes,
      throughput: successCount / duration,
    );
  }
}

class LoadTestResult {
  final Duration duration;
  final int successCount;
  final int errorCount;
  final List<Duration> responseTimes;
  final double throughput;
  
  LoadTestResult({
    required this.duration,
    required this.successCount,
    required this.errorCount,
    required this.responseTimes,
    required this.throughput,
  });
  
  Map<String, dynamic> toJson() {
    responseTimes.sort();
    
    return {
      'duration': duration.inSeconds,
      'success_count': successCount,
      'error_count': errorCount,
      'throughput': throughput,
      'response_times': {
        'min': responseTimes.first.inMilliseconds,
        'max': responseTimes.last.inMilliseconds,
        'avg': responseTimes.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / responseTimes.length,
        'p50': responseTimes[responseTimes.length ~/ 2].inMilliseconds,
        'p95': responseTimes[(responseTimes.length * 0.95).floor()].inMilliseconds,
        'p99': responseTimes[(responseTimes.length * 0.99).floor()].inMilliseconds,
      },
    };
  }
}
```

### Stress Testing

```dart
// lib/testing/stress_test.dart
class StressTester {
  static Future<StressTestResult> runStressTest({
    required Future<void> Function() operation,
    required int initialLoad,
    required int increment,
    required Duration incrementInterval,
    required double maxErrorRate,
  }) async {
    int currentLoad = initialLoad;
    final results = <StressTestSnapshot>[];
    
    while (true) {
      final snapshot = await _runSnapshot(
        operation: operation,
        load: currentLoad,
        duration: incrementInterval,
      );
      
      results.add(snapshot);
      
      if (snapshot.errorRate > maxErrorRate) {
        // Found breaking point
        break;
      }
      
      currentLoad += increment;
    }
    
    return StressTestResult(
      snapshots: results,
      breakingPoint: currentLoad - increment,
      maxSustainableLoad: _findMaxSustainableLoad(results, maxErrorRate),
    );
  }
  
  static Future<StressTestSnapshot> _runSnapshot({
    required Future<void> Function() operation,
    required int load,
    required Duration duration,
  }) async {
    final result = await LoadTester.runLoadTest(
      concurrent: load,
      duration: duration.inSeconds,
      operation: operation,
    );
    
    return StressTestSnapshot(
      load: load,
      timestamp: DateTime.now(),
      successRate: result.successCount / (result.successCount + result.errorCount),
      errorRate: result.errorCount / (result.successCount + result.errorCount),
      avgResponseTime: result.responseTimes.isEmpty 
          ? Duration.zero
          : result.responseTimes.reduce((a, b) => a + b) ~/ result.responseTimes.length,
    );
  }
  
  static int _findMaxSustainableLoad(
    List<StressTestSnapshot> snapshots,
    double maxErrorRate,
  ) {
    final sustainable = snapshots
        .where((s) => s.errorRate <= maxErrorRate)
        .toList();
    
    return sustainable.isEmpty ? 0 : sustainable.last.load;
  }
}

class StressTestResult {
  final List<StressTestSnapshot> snapshots;
  final int breakingPoint;
  final int maxSustainableLoad;
  
  StressTestResult({
    required this.snapshots,
    required this.breakingPoint,
    required this.maxSustainableLoad,
  });
}

class StressTestSnapshot {
  final int load;
  final DateTime timestamp;
  final double successRate;
  final double errorRate;
  final Duration avgResponseTime;
  
  StressTestSnapshot({
    required this.load,
    required this.timestamp,
    required this.successRate,
    required this.errorRate,
    required this.avgResponseTime,
  });
}
```

## See Also

- [Common Issues](/doc/troubleshooting/common-issues.md)
- [Debug Mode](/doc/troubleshooting/debug-mode.md)
- [Error Codes Reference](/doc/troubleshooting/error-codes.md)
- [Memory Management](/doc/advanced/memory-management.md)