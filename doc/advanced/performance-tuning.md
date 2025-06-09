# Performance Tuning Guide

This guide covers advanced performance optimization techniques for Flutter MCP applications.

## Performance Analysis

### 1. Performance Monitoring

Enable comprehensive performance monitoring:

```dart
// Initialize with performance monitoring
await FlutterMCP.instance.initialize(
  enablePerformanceMonitoring: true,
  performanceConfig: PerformanceConfig(
    sampleRate: 0.1, // Sample 10% of operations
    slowOperationThreshold: Duration(milliseconds: 100),
    enableMemoryTracking: true,
    enableNetworkTracking: true,
  ),
);

// Monitor specific operations
final monitor = PerformanceMonitor.instance;
final timer = monitor.startTimer('critical_operation');
try {
  await performCriticalOperation();
  monitor.stopTimer(timer, success: true);
} catch (e) {
  monitor.stopTimer(timer, success: false);
  rethrow;
}

// Get performance metrics
final metrics = monitor.getMetrics();
print('Average time: ${metrics['critical_operation'].average}ms');
print('95th percentile: ${metrics['critical_operation'].p95}ms');
```

### 2. Memory Profiling

Monitor memory usage patterns:

```dart
// Enable memory tracking
MemoryManager.instance.enableTracking();

// Set memory thresholds
MemoryManager.instance.setThresholds(
  warningThreshold: 256 * 1024 * 1024, // 256MB
  criticalThreshold: 512 * 1024 * 1024, // 512MB
);

// Monitor memory usage
MemoryManager.instance.memoryStream.listen((info) {
  print('Memory usage: ${info.used / 1024 / 1024}MB');
  
  if (info.pressure > 0.8) {
    // High memory pressure
    _performMemoryCleanup();
  }
});

// Track allocations
final tracker = AllocationTracker();
tracker.startTracking();
// ... perform operations ...
final allocations = tracker.stopTracking();
print('Total allocations: ${allocations.totalSize}');
```

### 3. Network Performance

Optimize network operations:

```dart
// Configure network optimization
final networkConfig = NetworkConfig(
  connectionTimeout: Duration(seconds: 10),
  requestTimeout: Duration(seconds: 30),
  maxConcurrentRequests: 5,
  enableCompression: true,
  enableCaching: true,
  cacheMaxAge: Duration(hours: 1),
);

// Connection pooling
final connectionPool = ConnectionPool(
  maxConnections: 10,
  maxConnectionsPerHost: 2,
  idleTimeout: Duration(minutes: 5),
  connectionTimeout: Duration(seconds: 10),
);

// Batch requests
final batcher = RequestBatcher(
  maxBatchSize: 50,
  batchTimeout: Duration(milliseconds: 100),
  onBatch: (requests) async {
    final response = await http.post(
      '/batch',
      body: json.encode(requests),
    );
    return _processBatchResponse(response);
  },
);

// Use the batcher
final result = await batcher.add(Request(
  method: 'getData',
  params: {'id': 123},
));
```

## Optimization Strategies

### 1. Lazy Loading

Implement lazy loading for resources:

```dart
class LazyResource<T> {
  T? _value;
  bool _isLoading = false;
  final Future<T> Function() _loader;
  final List<Completer<T>> _waiters = [];
  
  LazyResource(this._loader);
  
  Future<T> get value async {
    if (_value != null) {
      return _value!;
    }
    
    if (_isLoading) {
      final completer = Completer<T>();
      _waiters.add(completer);
      return completer.future;
    }
    
    _isLoading = true;
    try {
      _value = await _loader();
      for (final waiter in _waiters) {
        waiter.complete(_value);
      }
      _waiters.clear();
      return _value!;
    } catch (e) {
      for (final waiter in _waiters) {
        waiter.completeError(e);
      }
      _waiters.clear();
      rethrow;
    } finally {
      _isLoading = false;
    }
  }
  
  void invalidate() {
    _value = null;
  }
}

// Usage
final lazyConfig = LazyResource(() async {
  return await loadConfiguration();
});

// First access loads the resource
final config = await lazyConfig.value;

// Subsequent accesses return cached value
final sameConfig = await lazyConfig.value;
```

### 2. Caching Strategies

Implement intelligent caching:

```dart
// Memory cache with LRU eviction
class LRUCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  
  LRUCache(this.maxSize);
  
  V? get(K key) {
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value; // Move to end
    }
    return value;
  }
  
  void put(K key, V value) {
    _cache.remove(key);
    _cache[key] = value;
    
    if (_cache.length > maxSize) {
      _cache.remove(_cache.keys.first);
    }
  }
}

// Multi-tier cache
class TieredCache<K, V> {
  final LRUCache<K, V> _l1Cache; // Memory
  final DiskCache<K, V> _l2Cache; // Disk
  final RemoteCache<K, V> _l3Cache; // Remote
  
  TieredCache({
    required int l1Size,
    required this._l2Cache,
    required this._l3Cache,
  }) : _l1Cache = LRUCache(l1Size);
  
  Future<V?> get(K key) async {
    // Check L1 (memory)
    var value = _l1Cache.get(key);
    if (value != null) return value;
    
    // Check L2 (disk)
    value = await _l2Cache.get(key);
    if (value != null) {
      _l1Cache.put(key, value);
      return value;
    }
    
    // Check L3 (remote)
    value = await _l3Cache.get(key);
    if (value != null) {
      _l1Cache.put(key, value);
      await _l2Cache.put(key, value);
      return value;
    }
    
    return null;
  }
  
  Future<void> put(K key, V value) async {
    _l1Cache.put(key, value);
    await _l2Cache.put(key, value);
    await _l3Cache.put(key, value);
  }
}
```

### 3. Batch Processing

Optimize bulk operations:

```dart
class BatchProcessor<T, R> {
  final int batchSize;
  final Duration batchTimeout;
  final Future<List<R>> Function(List<T>) processor;
  
  final List<_BatchItem<T, R>> _queue = [];
  Timer? _timer;
  
  BatchProcessor({
    required this.batchSize,
    required this.batchTimeout,
    required this.processor,
  });
  
  Future<R> process(T item) {
    final completer = Completer<R>();
    _queue.add(_BatchItem(item, completer));
    
    if (_queue.length >= batchSize) {
      _processBatch();
    } else {
      _timer ??= Timer(batchTimeout, _processBatch);
    }
    
    return completer.future;
  }
  
  void _processBatch() async {
    _timer?.cancel();
    _timer = null;
    
    if (_queue.isEmpty) return;
    
    final batch = List<_BatchItem<T, R>>.from(_queue);
    _queue.clear();
    
    try {
      final items = batch.map((b) => b.item).toList();
      final results = await processor(items);
      
      for (int i = 0; i < batch.length; i++) {
        batch[i].completer.complete(results[i]);
      }
    } catch (e) {
      for (final item in batch) {
        item.completer.completeError(e);
      }
    }
  }
}

class _BatchItem<T, R> {
  final T item;
  final Completer<R> completer;
  
  _BatchItem(this.item, this.completer);
}
```

### 4. Connection Pooling

Manage connections efficiently:

```dart
class ConnectionPool<T extends Connection> {
  final int maxSize;
  final Duration idleTimeout;
  final Future<T> Function() connectionFactory;
  
  final Queue<_PooledConnection<T>> _available = Queue();
  final Set<_PooledConnection<T>> _inUse = {};
  
  ConnectionPool({
    required this.maxSize,
    required this.idleTimeout,
    required this.connectionFactory,
  });
  
  Future<T> acquire() async {
    // Remove expired connections
    _removeExpired();
    
    // Try to get available connection
    if (_available.isNotEmpty) {
      final pooled = _available.removeFirst();
      _inUse.add(pooled);
      return pooled.connection;
    }
    
    // Create new connection if under limit
    if (_inUse.length < maxSize) {
      final connection = await connectionFactory();
      final pooled = _PooledConnection(connection);
      _inUse.add(pooled);
      return connection;
    }
    
    // Wait for available connection
    await Future.delayed(Duration(milliseconds: 100));
    return acquire(); // Retry
  }
  
  void release(T connection) {
    final pooled = _inUse.firstWhere(
      (p) => p.connection == connection,
      orElse: () => throw StateError('Connection not from pool'),
    );
    
    _inUse.remove(pooled);
    pooled.lastUsed = DateTime.now();
    _available.add(pooled);
  }
  
  void _removeExpired() {
    final now = DateTime.now();
    _available.removeWhere((pooled) {
      return now.difference(pooled.lastUsed) > idleTimeout;
    });
  }
  
  Future<void> close() async {
    for (final pooled in [..._available, ..._inUse]) {
      await pooled.connection.close();
    }
    _available.clear();
    _inUse.clear();
  }
}

class _PooledConnection<T extends Connection> {
  final T connection;
  DateTime lastUsed;
  
  _PooledConnection(this.connection) : lastUsed = DateTime.now();
}
```

## Memory Optimization

### 1. Object Pooling

Reuse expensive objects:

```dart
class ObjectPool<T> {
  final Queue<T> _pool = Queue();
  final T Function() _factory;
  final void Function(T)? _reset;
  final int maxSize;
  int _created = 0;
  
  ObjectPool({
    required this._factory,
    this._reset,
    this.maxSize = 10,
  });
  
  T acquire() {
    if (_pool.isEmpty && _created < maxSize) {
      _created++;
      return _factory();
    }
    
    if (_pool.isNotEmpty) {
      final obj = _pool.removeFirst();
      _reset?.call(obj);
      return obj;
    }
    
    throw StateError('Pool exhausted');
  }
  
  void release(T object) {
    if (_pool.length < maxSize) {
      _reset?.call(object);
      _pool.add(object);
    }
  }
  
  void clear() {
    _pool.clear();
    _created = 0;
  }
}

// Usage
final bufferPool = ObjectPool<ByteBuffer>(
  factory: () => ByteBuffer(1024),
  reset: (buffer) => buffer.clear(),
  maxSize: 20,
);

final buffer = bufferPool.acquire();
try {
  // Use buffer
} finally {
  bufferPool.release(buffer);
}
```

### 2. Weak References

Use weak references for caches:

```dart
class WeakCache<K, V> {
  final Map<K, WeakReference<V>> _cache = {};
  final Duration _cleanupInterval;
  Timer? _cleanupTimer;
  
  WeakCache({
    this._cleanupInterval = const Duration(minutes: 5),
  }) {
    _startCleanup();
  }
  
  void put(K key, V value) {
    _cache[key] = WeakReference(value);
  }
  
  V? get(K key) {
    final weakRef = _cache[key];
    if (weakRef != null) {
      final value = weakRef.target;
      if (value != null) {
        return value;
      } else {
        _cache.remove(key);
      }
    }
    return null;
  }
  
  void _startCleanup() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _cache.removeWhere((key, weakRef) => weakRef.target == null);
    });
  }
  
  void dispose() {
    _cleanupTimer?.cancel();
  }
}
```

### 3. Memory Pressure Handling

React to memory pressure:

```dart
class MemoryPressureHandler {
  final List<VoidCallback> _lowHandlers = [];
  final List<VoidCallback> _criticalHandlers = [];
  
  MemoryPressureHandler() {
    MemoryManager.instance.memoryStream.listen((info) {
      if (info.pressure > 0.9) {
        _triggerCritical();
      } else if (info.pressure > 0.7) {
        _triggerLow();
      }
    });
  }
  
  void registerLowHandler(VoidCallback handler) {
    _lowHandlers.add(handler);
  }
  
  void registerCriticalHandler(VoidCallback handler) {
    _criticalHandlers.add(handler);
  }
  
  void _triggerLow() {
    for (final handler in _lowHandlers) {
      try {
        handler();
      } catch (e) {
        print('Low memory handler error: $e');
      }
    }
  }
  
  void _triggerCritical() {
    for (final handler in _criticalHandlers) {
      try {
        handler();
      } catch (e) {
        print('Critical memory handler error: $e');
      }
    }
  }
}

// Usage
final memoryHandler = MemoryPressureHandler();

memoryHandler.registerLowHandler(() {
  // Reduce cache sizes
  imageCache.resize(50);
  dataCache.clear();
});

memoryHandler.registerCriticalHandler(() {
  // Emergency cleanup
  imageCache.clear();
  dataCache.clear();
  connectionPool.reduceSize(5);
});
```

## CPU Optimization

### 1. Task Scheduling

Optimize task execution:

```dart
class TaskScheduler {
  final int maxConcurrent;
  final Queue<_Task> _queue = Queue();
  final Set<_Task> _running = {};
  
  TaskScheduler({this.maxConcurrent = 4});
  
  Future<T> schedule<T>(
    Future<T> Function() task, {
    Priority priority = Priority.normal,
  }) async {
    final completer = Completer<T>();
    final taskWrapper = _Task(
      task: task,
      completer: completer,
      priority: priority,
    );
    
    _queue.add(taskWrapper);
    _processQueue();
    
    return completer.future;
  }
  
  void _processQueue() {
    while (_running.length < maxConcurrent && _queue.isNotEmpty) {
      // Get highest priority task
      final task = _getHighestPriorityTask();
      _running.add(task);
      
      task.execute().then((_) {
        _running.remove(task);
        _processQueue();
      });
    }
  }
  
  _Task _getHighestPriorityTask() {
    _Task? highest;
    for (final task in _queue) {
      if (highest == null || task.priority.index > highest.priority.index) {
        highest = task;
      }
    }
    _queue.remove(highest!);
    return highest;
  }
}

class _Task {
  final Future Function() task;
  final Completer completer;
  final Priority priority;
  
  _Task({
    required this.task,
    required this.completer,
    required this.priority,
  });
  
  Future<void> execute() async {
    try {
      final result = await task();
      completer.complete(result);
    } catch (e) {
      completer.completeError(e);
    }
  }
}

enum Priority { low, normal, high, critical }
```

### 2. Computation Offloading

Use isolates for heavy computation:

```dart
class IsolatePool {
  final int size;
  final List<IsolateWorker> _workers = [];
  int _currentWorker = 0;
  
  IsolatePool({this.size = 4});
  
  Future<void> start() async {
    for (int i = 0; i < size; i++) {
      final worker = await IsolateWorker.spawn();
      _workers.add(worker);
    }
  }
  
  Future<R> compute<T, R>(
    ComputeCallback<T, R> callback,
    T message,
  ) async {
    final worker = _workers[_currentWorker];
    _currentWorker = (_currentWorker + 1) % _workers.length;
    
    return await worker.compute(callback, message);
  }
  
  void stop() {
    for (final worker in _workers) {
      worker.kill();
    }
    _workers.clear();
  }
}

class IsolateWorker {
  final Isolate isolate;
  final ReceivePort receivePort;
  final SendPort sendPort;
  
  IsolateWorker._({
    required this.isolate,
    required this.receivePort,
    required this.sendPort,
  });
  
  static Future<IsolateWorker> spawn() async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _isolateEntryPoint,
      receivePort.sendPort,
    );
    
    final sendPort = await receivePort.first as SendPort;
    
    return IsolateWorker._(
      isolate: isolate,
      receivePort: receivePort,
      sendPort: sendPort,
    );
  }
  
  Future<R> compute<T, R>(
    ComputeCallback<T, R> callback,
    T message,
  ) async {
    final responsePort = ReceivePort();
    sendPort.send({
      'callback': callback,
      'message': message,
      'responsePort': responsePort.sendPort,
    });
    
    final result = await responsePort.first;
    responsePort.close();
    
    if (result is _IsolateError) {
      throw result.error;
    }
    
    return result as R;
  }
  
  void kill() {
    isolate.kill();
    receivePort.close();
  }
  
  static void _isolateEntryPoint(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    
    receivePort.listen((message) async {
      final data = message as Map<String, dynamic>;
      final callback = data['callback'] as ComputeCallback;
      final input = data['message'];
      final responsePort = data['responsePort'] as SendPort;
      
      try {
        final result = await callback(input);
        responsePort.send(result);
      } catch (e) {
        responsePort.send(_IsolateError(e));
      }
    });
  }
}

class _IsolateError {
  final dynamic error;
  _IsolateError(this.error);
}
```

### 3. Debouncing and Throttling

Control execution frequency:

```dart
class Debouncer {
  final Duration delay;
  Timer? _timer;
  
  Debouncer({required this.delay});
  
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }
  
  void cancel() {
    _timer?.cancel();
  }
}

class Throttler {
  final Duration interval;
  DateTime? _lastRun;
  Timer? _timer;
  VoidCallback? _pendingAction;
  
  Throttler({required this.interval});
  
  void run(VoidCallback action) {
    final now = DateTime.now();
    
    if (_lastRun == null || now.difference(_lastRun!) >= interval) {
      _lastRun = now;
      action();
    } else {
      _pendingAction = action;
      _timer?.cancel();
      
      final timeToNext = interval - now.difference(_lastRun!);
      _timer = Timer(timeToNext, () {
        _lastRun = DateTime.now();
        _pendingAction?.call();
        _pendingAction = null;
      });
    }
  }
  
  void cancel() {
    _timer?.cancel();
    _pendingAction = null;
  }
}

// Usage
final searchDebouncer = Debouncer(delay: Duration(milliseconds: 300));
final scrollThrottler = Throttler(interval: Duration(milliseconds: 100));

// Search box
void onSearchTextChanged(String text) {
  searchDebouncer.run(() {
    performSearch(text);
  });
}

// Scroll listener
void onScroll(double offset) {
  scrollThrottler.run(() {
    updateScrollPosition(offset);
  });
}
```

## Network Optimization

### 1. Request Deduplication

Prevent duplicate requests:

```dart
class RequestDeduplicator {
  final Map<String, Future<dynamic>> _pending = {};
  
  Future<T> deduplicate<T>(
    String key,
    Future<T> Function() request,
  ) async {
    if (_pending.containsKey(key)) {
      return await _pending[key] as T;
    }
    
    final future = request();
    _pending[key] = future;
    
    try {
      final result = await future;
      _pending.remove(key);
      return result;
    } catch (e) {
      _pending.remove(key);
      rethrow;
    }
  }
}

// Usage
final deduplicator = RequestDeduplicator();

// Multiple simultaneous requests for same data
final future1 = deduplicator.deduplicate(
  'user_123',
  () => fetchUser('123'),
);

final future2 = deduplicator.deduplicate(
  'user_123',
  () => fetchUser('123'),
);

// Only one actual request is made
final user1 = await future1;
final user2 = await future2; // Same result
```

### 2. Request Prioritization

Prioritize critical requests:

```dart
class PriorityRequestQueue {
  final int maxConcurrent;
  final _queue = PriorityQueue<_Request>();
  final _active = <_Request>{};
  
  PriorityRequestQueue({this.maxConcurrent = 3});
  
  Future<T> add<T>(
    Future<T> Function() request, {
    Priority priority = Priority.normal,
  }) async {
    final completer = Completer<T>();
    final req = _Request(
      request: request,
      completer: completer,
      priority: priority,
    );
    
    _queue.add(req);
    _processQueue();
    
    return completer.future;
  }
  
  void _processQueue() {
    while (_active.length < maxConcurrent && _queue.isNotEmpty) {
      final req = _queue.removeFirst();
      _active.add(req);
      
      req.execute().then((_) {
        _active.remove(req);
        _processQueue();
      });
    }
  }
}

class _Request implements Comparable<_Request> {
  final Future Function() request;
  final Completer completer;
  final Priority priority;
  final DateTime timestamp;
  
  _Request({
    required this.request,
    required this.completer,
    required this.priority,
  }) : timestamp = DateTime.now();
  
  Future<void> execute() async {
    try {
      final result = await request();
      completer.complete(result);
    } catch (e) {
      completer.completeError(e);
    }
  }
  
  @override
  int compareTo(_Request other) {
    if (priority != other.priority) {
      return other.priority.index - priority.index;
    }
    return timestamp.compareTo(other.timestamp);
  }
}
```

### 3. Response Compression

Implement response compression:

```dart
class CompressedHttpClient extends http.BaseClient {
  final http.Client _inner;
  
  CompressedHttpClient(this._inner);
  
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Add compression headers
    request.headers['Accept-Encoding'] = 'gzip, deflate';
    
    final response = await _inner.send(request);
    
    // Check if response is compressed
    final encoding = response.headers['content-encoding'];
    if (encoding == 'gzip' || encoding == 'deflate') {
      return _decompressResponse(response);
    }
    
    return response;
  }
  
  http.StreamedResponse _decompressResponse(
    http.StreamedResponse response,
  ) {
    final encoding = response.headers['content-encoding'];
    Stream<List<int>> stream;
    
    if (encoding == 'gzip') {
      stream = response.stream.transform(gzip.decoder);
    } else if (encoding == 'deflate') {
      stream = response.stream.transform(zlib.decoder);
    } else {
      stream = response.stream;
    }
    
    return http.StreamedResponse(
      stream,
      response.statusCode,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
    );
  }
}
```

## Database Optimization

### 1. Query Optimization

Optimize database queries:

```dart
class OptimizedDatabase {
  final Database _database;
  final Map<String, PreparedStatement> _statements = {};
  
  OptimizedDatabase(this._database);
  
  // Prepare statements for reuse
  Future<void> prepareStatements() async {
    _statements['getUserById'] = await _database.prepare(
      'SELECT * FROM users WHERE id = ?',
    );
    
    _statements['getRecentPosts'] = await _database.prepare(
      'SELECT * FROM posts WHERE created_at > ? ORDER BY created_at DESC LIMIT ?',
    );
  }
  
  // Use prepared statements
  Future<User?> getUserById(int id) async {
    final statement = _statements['getUserById']!;
    final result = await statement.select([id]);
    
    if (result.isEmpty) return null;
    return User.fromRow(result.first);
  }
  
  // Batch operations
  Future<void> insertUsers(List<User> users) async {
    await _database.transaction((txn) async {
      final batch = txn.batch();
      
      for (final user in users) {
        batch.insert('users', user.toMap());
      }
      
      await batch.commit(noResult: true);
    });
  }
  
  // Use indexes efficiently
  Future<List<Post>> searchPosts(String keyword) async {
    // Assuming full-text search index exists
    final results = await _database.rawQuery(
      'SELECT * FROM posts WHERE posts MATCH ? ORDER BY rank',
      [keyword],
    );
    
    return results.map((row) => Post.fromRow(row)).toList();
  }
  
  void close() {
    for (final statement in _statements.values) {
      statement.dispose();
    }
    _statements.clear();
  }
}
```

### 2. Connection Pooling

Database connection pooling:

```dart
class DatabasePool {
  final String path;
  final int minConnections;
  final int maxConnections;
  final Queue<Database> _available = Queue();
  final Set<Database> _inUse = {};
  
  DatabasePool({
    required this.path,
    this.minConnections = 2,
    this.maxConnections = 10,
  });
  
  Future<void> initialize() async {
    for (int i = 0; i < minConnections; i++) {
      final db = await openDatabase(path);
      _available.add(db);
    }
  }
  
  Future<Database> acquire() async {
    if (_available.isNotEmpty) {
      final db = _available.removeFirst();
      _inUse.add(db);
      return db;
    }
    
    if (_inUse.length < maxConnections) {
      final db = await openDatabase(path);
      _inUse.add(db);
      return db;
    }
    
    // Wait for available connection
    await Future.delayed(Duration(milliseconds: 100));
    return acquire();
  }
  
  void release(Database db) {
    _inUse.remove(db);
    _available.add(db);
  }
  
  Future<T> withConnection<T>(
    Future<T> Function(Database) operation,
  ) async {
    final db = await acquire();
    try {
      return await operation(db);
    } finally {
      release(db);
    }
  }
  
  Future<void> close() async {
    for (final db in [..._available, ..._inUse]) {
      await db.close();
    }
    _available.clear();
    _inUse.clear();
  }
}
```

### 3. Write-Ahead Logging

Optimize write performance:

```dart
class WALDatabase {
  final Database _database;
  final _writeQueue = Queue<_WriteOperation>();
  Timer? _flushTimer;
  bool _isProcessing = false;
  
  WALDatabase(this._database);
  
  Future<void> initialize() async {
    // Enable WAL mode
    await _database.execute('PRAGMA journal_mode=WAL');
    await _database.execute('PRAGMA synchronous=NORMAL');
    
    // Start periodic flush
    _flushTimer = Timer.periodic(Duration(seconds: 1), (_) {
      _processQueue();
    });
  }
  
  Future<void> write(String sql, [List<dynamic>? arguments]) async {
    final completer = Completer<void>();
    _writeQueue.add(_WriteOperation(sql, arguments, completer));
    
    if (_writeQueue.length > 100) {
      // Force flush on large queue
      _processQueue();
    }
    
    return completer.future;
  }
  
  void _processQueue() async {
    if (_isProcessing || _writeQueue.isEmpty) return;
    
    _isProcessing = true;
    final operations = List<_WriteOperation>.from(_writeQueue);
    _writeQueue.clear();
    
    try {
      await _database.transaction((txn) async {
        for (final op in operations) {
          try {
            await txn.execute(op.sql, op.arguments);
            op.completer.complete();
          } catch (e) {
            op.completer.completeError(e);
          }
        }
      });
    } catch (e) {
      // Transaction failed, complete all with error
      for (final op in operations) {
        if (!op.completer.isCompleted) {
          op.completer.completeError(e);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }
  
  void close() {
    _flushTimer?.cancel();
    _processQueue(); // Final flush
  }
}

class _WriteOperation {
  final String sql;
  final List<dynamic>? arguments;
  final Completer<void> completer;
  
  _WriteOperation(this.sql, this.arguments, this.completer);
}
```

## Monitoring and Profiling

### 1. Performance Dashboard

Create a performance monitoring dashboard:

```dart
class PerformanceDashboard {
  final Map<String, MetricCollector> _collectors = {};
  final StreamController<DashboardUpdate> _updateController = 
      StreamController<DashboardUpdate>.broadcast();
  
  Stream<DashboardUpdate> get updates => _updateController.stream;
  
  void registerCollector(String name, MetricCollector collector) {
    _collectors[name] = collector;
    collector.updates.listen((metric) {
      _updateController.add(DashboardUpdate(name, metric));
    });
  }
  
  Map<String, Metric> getCurrentMetrics() {
    return _collectors.map((name, collector) => 
        MapEntry(name, collector.currentMetric));
  }
  
  void startRecording() {
    for (final collector in _collectors.values) {
      collector.start();
    }
  }
  
  void stopRecording() {
    for (final collector in _collectors.values) {
      collector.stop();
    }
  }
  
  void reset() {
    for (final collector in _collectors.values) {
      collector.reset();
    }
  }
}

abstract class MetricCollector {
  Stream<Metric> get updates;
  Metric get currentMetric;
  void start();
  void stop();
  void reset();
}

class CPUMetricCollector implements MetricCollector {
  final _controller = StreamController<Metric>.broadcast();
  Timer? _timer;
  double _currentUsage = 0;
  
  @override
  Stream<Metric> get updates => _controller.stream;
  
  @override
  Metric get currentMetric => Metric(
    name: 'CPU Usage',
    value: _currentUsage,
    unit: '%',
  );
  
  @override
  void start() {
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      _currentUsage = _measureCPUUsage();
      _controller.add(currentMetric);
    });
  }
  
  @override
  void stop() {
    _timer?.cancel();
  }
  
  @override
  void reset() {
    _currentUsage = 0;
  }
  
  double _measureCPUUsage() {
    // Platform-specific CPU measurement
    return Random().nextDouble() * 100; // Placeholder
  }
}
```

### 2. Trace Recording

Record detailed performance traces:

```dart
class TraceRecorder {
  final List<TraceEvent> _events = [];
  final Stopwatch _stopwatch = Stopwatch();
  
  void start() {
    _stopwatch.start();
  }
  
  void beginEvent(String name, {Map<String, dynamic>? args}) {
    _events.add(TraceEvent(
      name: name,
      phase: 'B',
      timestamp: _stopwatch.elapsed,
      args: args,
    ));
  }
  
  void endEvent(String name, {Map<String, dynamic>? args}) {
    _events.add(TraceEvent(
      name: name,
      phase: 'E',
      timestamp: _stopwatch.elapsed,
      args: args,
    ));
  }
  
  void instantEvent(String name, {Map<String, dynamic>? args}) {
    _events.add(TraceEvent(
      name: name,
      phase: 'i',
      timestamp: _stopwatch.elapsed,
      args: args,
    ));
  }
  
  void counter(String name, Map<String, num> values) {
    _events.add(TraceEvent(
      name: name,
      phase: 'C',
      timestamp: _stopwatch.elapsed,
      args: values,
    ));
  }
  
  void stop() {
    _stopwatch.stop();
  }
  
  String exportChromeTrace() {
    return json.encode({
      'traceEvents': _events.map((e) => e.toJson()).toList(),
    });
  }
}

class TraceEvent {
  final String name;
  final String phase;
  final Duration timestamp;
  final Map<String, dynamic>? args;
  
  TraceEvent({
    required this.name,
    required this.phase,
    required this.timestamp,
    this.args,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'ph': phase,
    'ts': timestamp.inMicroseconds,
    'pid': 1,
    'tid': 1,
    if (args != null) 'args': args,
  };
}

// Usage
final recorder = TraceRecorder();
recorder.start();

recorder.beginEvent('fetchData');
final data = await fetchData();
recorder.endEvent('fetchData');

recorder.beginEvent('processData');
final result = await processData(data);
recorder.endEvent('processData');

recorder.stop();

// Export for Chrome Tracing
final trace = recorder.exportChromeTrace();
await File('trace.json').writeAsString(trace);
```

## Best Practices

### 1. Measure Before Optimizing

```dart
// Always profile first
final profiler = PerformanceProfiler();
profiler.start();

await performOperation();

final profile = profiler.stop();
print('Operation took: ${profile.duration}');
print('Memory allocated: ${profile.memoryAllocated}');
print('CPU cycles: ${profile.cpuCycles}');

// Identify bottlenecks
final bottlenecks = profile.findBottlenecks();
for (final bottleneck in bottlenecks) {
  print('Bottleneck: ${bottleneck.operation} - ${bottleneck.duration}');
}
```

### 2. Use Appropriate Data Structures

```dart
// Choose the right collection
// For frequent lookups
final map = HashMap<String, Value>(); // O(1) average

// For ordered iteration
final sortedMap = SplayTreeMap<String, Value>(); // O(log n)

// For frequent additions/removals
final linkedList = LinkedList<Entry>(); // O(1)

// For FIFO operations
final queue = Queue<Task>(); // O(1)

// For LIFO operations  
final stack = List<Task>(); // O(1) at end
```

### 3. Avoid Premature Optimization

```dart
// Start with simple, readable code
Future<List<User>> getActiveUsers() async {
  final users = await database.getAllUsers();
  return users.where((user) => user.isActive).toList();
}

// Optimize only when profiling shows it's needed
Future<List<User>> getActiveUsersOptimized() async {
  // Only fetch active users from database
  return await database.query(
    'SELECT * FROM users WHERE is_active = 1',
  );
}
```

### 4. Cache Appropriately

```dart
// Cache expensive computations
class ComputationCache {
  final _cache = <String, Future<dynamic>>{};
  
  Future<T> computeOrCache<T>(
    String key,
    Future<T> Function() computation,
  ) async {
    if (_cache.containsKey(key)) {
      return await _cache[key] as T;
    }
    
    final future = computation();
    _cache[key] = future;
    
    try {
      return await future;
    } catch (e) {
      _cache.remove(key); // Remove on error
      rethrow;
    }
  }
}
```

### 5. Monitor Production Performance

```dart
// Set up production monitoring
class ProductionMonitor {
  static void initialize() {
    // Monitor critical metrics
    PerformanceMonitor.instance.setReporter(
      CloudMetricsReporter(
        endpoint: 'https://metrics.example.com',
        apiKey: 'your-api-key',
      ),
    );
    
    // Set up error reporting
    FlutterError.onError = (details) {
      ErrorReporter.report(
        exception: details.exception,
        stackTrace: details.stack,
        context: details.context,
      );
    };
    
    // Monitor memory
    MemoryManager.instance.onHighMemory(() {
      AnalyticsService.track('high_memory_pressure', {
        'used': MemoryManager.instance.currentMemoryUsage,
        'available': MemoryManager.instance.availableMemory,
      });
    });
  }
}
```

## Next Steps

- [Memory Management](memory-management.md) - Advanced memory optimization
- [Security Guide](security.md) - Security best practices
- [Testing Guide](testing.md) - Performance testing strategies
- [Platform Guides](../platform/README.md) - Platform-specific optimizations