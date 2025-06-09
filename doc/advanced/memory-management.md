# Memory Management Guide

This guide covers advanced memory management techniques for Flutter MCP applications.

## Memory Monitoring

### 1. Memory Usage Tracking

Monitor application memory usage:

```dart
// Initialize memory monitoring
MemoryManager.instance.startMonitoring(
  interval: Duration(seconds: 5),
  thresholds: MemoryThresholds(
    low: 100 * 1024 * 1024,      // 100MB
    medium: 200 * 1024 * 1024,   // 200MB
    high: 300 * 1024 * 1024,     // 300MB
    critical: 400 * 1024 * 1024, // 400MB
  ),
);

// Listen to memory events
MemoryManager.instance.memoryStream.listen((event) {
  print('Memory usage: ${event.used / 1024 / 1024}MB');
  print('Memory level: ${event.level}');
  
  switch (event.level) {
    case MemoryLevel.normal:
      // Normal operation
      break;
    case MemoryLevel.low:
      // Start reducing memory usage
      _reduceCaches();
      break;
    case MemoryLevel.medium:
      // More aggressive cleanup
      _clearNonEssentialData();
      break;
    case MemoryLevel.high:
      // Emergency measures
      _emergencyCleanup();
      break;
    case MemoryLevel.critical:
      // Critical - app may be killed
      _criticalMemoryHandler();
      break;
  }
});
```

### 2. Memory Profiling

Profile memory allocations:

```dart
class MemoryProfiler {
  final Map<String, AllocationInfo> _allocations = {};
  bool _isTracking = false;
  
  void startTracking() {
    _isTracking = true;
    _allocations.clear();
  }
  
  void trackAllocation(String tag, int size, {StackTrace? stackTrace}) {
    if (!_isTracking) return;
    
    _allocations.putIfAbsent(tag, () => AllocationInfo(tag))
      ..recordAllocation(size, stackTrace);
  }
  
  void trackDeallocation(String tag, int size) {
    if (!_isTracking) return;
    
    _allocations[tag]?.recordDeallocation(size);
  }
  
  MemoryProfile stopTracking() {
    _isTracking = false;
    
    return MemoryProfile(
      allocations: Map.from(_allocations),
      timestamp: DateTime.now(),
    );
  }
  
  void printReport() {
    print('Memory Allocation Report:');
    print('-' * 50);
    
    final sorted = _allocations.entries.toList()
      ..sort((a, b) => b.value.totalAllocated.compareTo(a.value.totalAllocated));
    
    for (final entry in sorted) {
      final info = entry.value;
      print('${entry.key}:');
      print('  Total allocated: ${info.totalAllocated ~/ 1024}KB');
      print('  Total deallocated: ${info.totalDeallocated ~/ 1024}KB');
      print('  Current usage: ${info.currentUsage ~/ 1024}KB');
      print('  Allocation count: ${info.allocationCount}');
      print('');
    }
  }
}

class AllocationInfo {
  final String tag;
  int totalAllocated = 0;
  int totalDeallocated = 0;
  int allocationCount = 0;
  final List<StackTrace> stackTraces = [];
  
  AllocationInfo(this.tag);
  
  int get currentUsage => totalAllocated - totalDeallocated;
  
  void recordAllocation(int size, StackTrace? stackTrace) {
    totalAllocated += size;
    allocationCount++;
    if (stackTrace != null && stackTraces.length < 10) {
      stackTraces.add(stackTrace);
    }
  }
  
  void recordDeallocation(int size) {
    totalDeallocated += size;
  }
}
```

### 3. Heap Analysis

Analyze heap snapshots:

```dart
class HeapAnalyzer {
  Future<HeapSnapshot> captureSnapshot() async {
    final objects = <HeapObject>[];
    final references = <ObjectReference>[];
    
    // Capture current heap state
    // This is simplified - real implementation would use VM service
    
    return HeapSnapshot(
      objects: objects,
      references: references,
      timestamp: DateTime.now(),
    );
  }
  
  HeapAnalysis analyzeSnapshot(HeapSnapshot snapshot) {
    final analysis = HeapAnalysis();
    
    // Find large objects
    analysis.largeObjects = snapshot.objects
        .where((obj) => obj.size > 1024 * 1024) // > 1MB
        .toList()
      ..sort((a, b) => b.size.compareTo(a.size));
    
    // Find duplicate strings
    final strings = snapshot.objects
        .where((obj) => obj.type == 'String')
        .map((obj) => obj as StringObject)
        .toList();
    
    final stringGroups = <String, List<StringObject>>{};
    for (final str in strings) {
      stringGroups.putIfAbsent(str.value, () => []).add(str);
    }
    
    analysis.duplicateStrings = stringGroups.entries
        .where((e) => e.value.length > 1)
        .map((e) => DuplicateString(
              value: e.key,
              count: e.value.length,
              totalSize: e.value.fold(0, (sum, s) => sum + s.size),
            ))
        .toList()
      ..sort((a, b) => b.totalSize.compareTo(a.totalSize));
    
    // Find memory leaks
    analysis.potentialLeaks = _findPotentialLeaks(snapshot);
    
    return analysis;
  }
  
  List<HeapObject> _findPotentialLeaks(HeapSnapshot snapshot) {
    // Simplified leak detection
    // Look for objects with many references but no strong root
    final leaks = <HeapObject>[];
    
    for (final object in snapshot.objects) {
      final incomingRefs = snapshot.references
          .where((ref) => ref.to == object.id)
          .length;
      
      if (incomingRefs > 10 && !_hasStrongRoot(object, snapshot)) {
        leaks.add(object);
      }
    }
    
    return leaks;
  }
  
  bool _hasStrongRoot(HeapObject object, HeapSnapshot snapshot) {
    // Check if object has path to GC root
    // Simplified implementation
    return true;
  }
}

class HeapSnapshot {
  final List<HeapObject> objects;
  final List<ObjectReference> references;
  final DateTime timestamp;
  
  HeapSnapshot({
    required this.objects,
    required this.references,
    required this.timestamp,
  });
}

class HeapObject {
  final int id;
  final String type;
  final int size;
  final Map<String, dynamic> fields;
  
  HeapObject({
    required this.id,
    required this.type,
    required this.size,
    required this.fields,
  });
}
```

## Memory Optimization Techniques

### 1. Object Pooling

Implement object pools for frequently allocated objects:

```dart
class ObjectPool<T> {
  final T Function() _factory;
  final void Function(T)? _reset;
  final int _maxSize;
  
  final Queue<T> _available = Queue();
  final Set<T> _inUse = {};
  
  int _totalCreated = 0;
  int _reuseCount = 0;
  
  ObjectPool({
    required T Function() factory,
    void Function(T)? reset,
    int maxSize = 100,
  })  : _factory = factory,
        _reset = reset,
        _maxSize = maxSize;
  
  T acquire() {
    T object;
    
    if (_available.isNotEmpty) {
      object = _available.removeFirst();
      _reset?.call(object);
      _reuseCount++;
    } else {
      object = _factory();
      _totalCreated++;
    }
    
    _inUse.add(object);
    return object;
  }
  
  void release(T object) {
    if (!_inUse.remove(object)) {
      throw ArgumentError('Object not from this pool');
    }
    
    if (_available.length < _maxSize) {
      _reset?.call(object);
      _available.add(object);
    }
  }
  
  void clear() {
    _available.clear();
    _inUse.clear();
  }
  
  PoolStatistics get statistics => PoolStatistics(
        totalCreated: _totalCreated,
        reuseCount: _reuseCount,
        currentAvailable: _available.length,
        currentInUse: _inUse.length,
      );
}

class PoolStatistics {
  final int totalCreated;
  final int reuseCount;
  final int currentAvailable;
  final int currentInUse;
  
  PoolStatistics({
    required this.totalCreated,
    required this.reuseCount,
    required this.currentAvailable,
    required this.currentInUse,
  });
  
  double get reuseRatio => 
      totalCreated > 0 ? reuseCount / totalCreated : 0;
}

// Usage example
final bufferPool = ObjectPool<ByteBuffer>(
  factory: () => ByteBuffer(1024 * 1024), // 1MB buffers
  reset: (buffer) => buffer.clear(),
  maxSize: 10,
);

// Acquire buffer
final buffer = bufferPool.acquire();
try {
  // Use buffer
  buffer.write(data);
  processBuffer(buffer);
} finally {
  // Always release back to pool
  bufferPool.release(buffer);
}

// Check pool efficiency
final stats = bufferPool.statistics;
print('Buffer reuse ratio: ${stats.reuseRatio * 100}%');
```

### 2. Weak References

Use weak references for caches:

```dart
class WeakCache<K, V> {
  final Map<K, WeakReference<V>> _cache = {};
  final int _maxSize;
  Timer? _cleanupTimer;
  
  // Statistics
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  
  WeakCache({int maxSize = 1000}) : _maxSize = maxSize {
    // Periodic cleanup of dead references
    _cleanupTimer = Timer.periodic(Duration(minutes: 5), (_) => _cleanup());
  }
  
  V? get(K key) {
    final weakRef = _cache[key];
    if (weakRef != null) {
      final value = weakRef.target;
      if (value != null) {
        _hits++;
        return value;
      } else {
        // Reference was garbage collected
        _cache.remove(key);
        _evictions++;
      }
    }
    _misses++;
    return null;
  }
  
  void put(K key, V value) {
    if (_cache.length >= _maxSize) {
      // Evict oldest entries (simple FIFO)
      final keysToRemove = _cache.keys.take(_cache.length ~/ 4).toList();
      keysToRemove.forEach(_cache.remove);
      _evictions += keysToRemove.length;
    }
    
    _cache[key] = WeakReference(value);
  }
  
  void _cleanup() {
    final deadKeys = <K>[];
    _cache.forEach((key, weakRef) {
      if (weakRef.target == null) {
        deadKeys.add(key);
      }
    });
    
    deadKeys.forEach(_cache.remove);
    _evictions += deadKeys.length;
  }
  
  CacheStatistics get statistics => CacheStatistics(
        hits: _hits,
        misses: _misses,
        evictions: _evictions,
        size: _cache.length,
        hitRate: _hits + _misses > 0 ? _hits / (_hits + _misses) : 0,
      );
  
  void dispose() {
    _cleanupTimer?.cancel();
    _cache.clear();
  }
}

// Expando for associating data without preventing GC
class ExpandoCache<T extends Object> {
  final Expando<dynamic> _expando = Expando();
  
  void associate(T object, dynamic data) {
    _expando[object] = data;
  }
  
  dynamic? getAssociated(T object) {
    return _expando[object];
  }
}

// Usage
final cache = WeakCache<String, LargeObject>();
final largeObject = LargeObject();
cache.put('key', largeObject);

// Object may be garbage collected if memory pressure is high
final retrieved = cache.get('key'); // May be null

// Check cache performance
final stats = cache.statistics;
print('Cache hit rate: ${stats.hitRate * 100}%');
```

### 3. Lazy Loading

Implement lazy loading patterns:

```dart
class LazyList<T> {
  final int pageSize;
  final Future<List<T>> Function(int page) loader;
  final Map<int, List<T>> _pages = {};
  final Map<int, Future<List<T>>> _loadingPages = {};
  
  LazyList({
    required this.pageSize,
    required this.loader,
  });
  
  Future<T?> getItem(int index) async {
    final page = index ~/ pageSize;
    final pageIndex = index % pageSize;
    
    final pageData = await _getPage(page);
    return pageIndex < pageData.length ? pageData[pageIndex] : null;
  }
  
  Future<List<T>> _getPage(int page) async {
    // Return cached page
    if (_pages.containsKey(page)) {
      return _pages[page]!;
    }
    
    // Return loading page
    if (_loadingPages.containsKey(page)) {
      return _loadingPages[page]!;
    }
    
    // Load new page
    final future = loader(page);
    _loadingPages[page] = future;
    
    try {
      final data = await future;
      _pages[page] = data;
      _loadingPages.remove(page);
      
      // Evict old pages if needed
      _evictOldPages();
      
      return data;
    } catch (e) {
      _loadingPages.remove(page);
      rethrow;
    }
  }
  
  void _evictOldPages() {
    if (_pages.length <= 5) return; // Keep 5 pages in memory
    
    // Evict least recently used pages
    final sortedPages = _pages.keys.toList()..sort();
    final pagesToEvict = sortedPages.take(_pages.length - 5);
    
    for (final page in pagesToEvict) {
      _pages.remove(page);
    }
  }
  
  void clearCache() {
    _pages.clear();
    _loadingPages.clear();
  }
}

// Lazy image loading
class LazyImage {
  final String url;
  ui.Image? _image;
  Future<ui.Image>? _loadingFuture;
  
  LazyImage(this.url);
  
  Future<ui.Image> get image async {
    if (_image != null) return _image!;
    
    _loadingFuture ??= _loadImage();
    _image = await _loadingFuture!;
    _loadingFuture = null;
    
    return _image!;
  }
  
  Future<ui.Image> _loadImage() async {
    final response = await http.get(Uri.parse(url));
    final codec = await ui.instantiateImageCodec(response.bodyBytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
  
  void dispose() {
    _image?.dispose();
    _image = null;
  }
}
```

### 4. Memory-Mapped Files

Use memory-mapped files for large data:

```dart
class MemoryMappedFile {
  final String path;
  late final RandomAccessFile _file;
  late final int _size;
  
  MemoryMappedFile(this.path);
  
  Future<void> open() async {
    _file = await File(path).open();
    _size = await _file.length();
  }
  
  Future<Uint8List> read(int offset, int length) async {
    await _file.setPosition(offset);
    return await _file.read(length);
  }
  
  Future<void> write(int offset, Uint8List data) async {
    await _file.setPosition(offset);
    await _file.writeFrom(data);
  }
  
  Future<void> close() async {
    await _file.close();
  }
}

// Virtual list backed by memory-mapped file
class VirtualList<T> {
  final MemoryMappedFile _file;
  final int _itemSize;
  final T Function(Uint8List) _deserializer;
  final Uint8List Function(T) _serializer;
  
  VirtualList({
    required MemoryMappedFile file,
    required int itemSize,
    required T Function(Uint8List) deserializer,
    required Uint8List Function(T) serializer,
  })  : _file = file,
        _itemSize = itemSize,
        _deserializer = deserializer,
        _serializer = serializer;
  
  Future<T> getItem(int index) async {
    final offset = index * _itemSize;
    final data = await _file.read(offset, _itemSize);
    return _deserializer(data);
  }
  
  Future<void> setItem(int index, T item) async {
    final offset = index * _itemSize;
    final data = _serializer(item);
    await _file.write(offset, data);
  }
}
```

## Memory Leak Detection

### 1. Leak Detector

Implement memory leak detection:

```dart
class MemoryLeakDetector {
  final Map<Type, Set<WeakReference<Object>>> _instances = {};
  final Map<Type, int> _leakThresholds = {};
  Timer? _checkTimer;
  
  void startMonitoring({
    Duration checkInterval = const Duration(minutes: 1),
  }) {
    _checkTimer = Timer.periodic(checkInterval, (_) => _checkForLeaks());
  }
  
  void stopMonitoring() {
    _checkTimer?.cancel();
  }
  
  void trackObject<T extends Object>(T object, {int? leakThreshold}) {
    final type = T;
    _instances.putIfAbsent(type, () => {}).add(WeakReference(object));
    
    if (leakThreshold != null) {
      _leakThresholds[type] = leakThreshold;
    }
  }
  
  void _checkForLeaks() {
    final leaks = <Type, int>{};
    
    _instances.forEach((type, references) {
      // Remove dead references
      references.removeWhere((ref) => ref.target == null);
      
      // Check for leaks
      final threshold = _leakThresholds[type] ?? 100;
      if (references.length > threshold) {
        leaks[type] = references.length;
      }
    });
    
    if (leaks.isNotEmpty) {
      _reportLeaks(leaks);
    }
  }
  
  void _reportLeaks(Map<Type, int> leaks) {
    print('Potential memory leaks detected:');
    leaks.forEach((type, count) {
      print('  $type: $count instances (threshold: ${_leakThresholds[type]})');
    });
    
    // Trigger detailed analysis
    _analyzeLeaks(leaks);
  }
  
  void _analyzeLeaks(Map<Type, int> leaks) {
    // Capture heap snapshot and analyze
    // This would integrate with VM service in real implementation
    leaks.forEach((type, count) {
      final samples = _instances[type]!
          .where((ref) => ref.target != null)
          .take(5)
          .map((ref) => ref.target!)
          .toList();
      
      print('Sample instances of $type:');
      for (final instance in samples) {
        print('  ${instance.runtimeType} - ${identityHashCode(instance)}');
      }
    });
  }
}

// Disposable tracker
class DisposableTracker {
  static final Set<WeakReference<Disposable>> _tracked = {};
  static Timer? _checkTimer;
  
  static void track(Disposable object) {
    _tracked.add(WeakReference(object));
    _startChecking();
  }
  
  static void _startChecking() {
    _checkTimer ??= Timer.periodic(Duration(minutes: 5), (_) {
      final undisposed = <Disposable>[];
      
      _tracked.removeWhere((ref) {
        final target = ref.target;
        if (target == null) return true;
        
        if (!target.isDisposed) {
          undisposed.add(target);
        }
        return target.isDisposed;
      });
      
      if (undisposed.isNotEmpty) {
        print('Warning: ${undisposed.length} undisposed objects found');
        for (final obj in undisposed) {
          print('  ${obj.runtimeType} - created at: ${obj.createdAt}');
        }
      }
    });
  }
}

mixin Disposable {
  bool _isDisposed = false;
  final DateTime createdAt = DateTime.now();
  
  bool get isDisposed => _isDisposed;
  
  @mustCallSuper
  void dispose() {
    if (_isDisposed) {
      throw StateError('Already disposed');
    }
    _isDisposed = true;
  }
}
```

### 2. Reference Tracking

Track object references:

```dart
class ReferenceTracker {
  final Map<Object, _ReferenceInfo> _references = {};
  
  void addReference(Object from, Object to, String fieldName) {
    _references.putIfAbsent(to, () => _ReferenceInfo(to))
      .addIncoming(from, fieldName);
    
    _references.putIfAbsent(from, () => _ReferenceInfo(from))
      .addOutgoing(to, fieldName);
  }
  
  void removeReference(Object from, Object to, String fieldName) {
    _references[to]?.removeIncoming(from, fieldName);
    _references[from]?.removeOutgoing(to, fieldName);
  }
  
  List<Object> findRetainCycle(Object start) {
    final visited = <Object>{};
    final path = <Object>[];
    
    bool hasCycle(Object current) {
      if (path.contains(current)) {
        return true;
      }
      
      if (visited.contains(current)) {
        return false;
      }
      
      visited.add(current);
      path.add(current);
      
      final info = _references[current];
      if (info != null) {
        for (final outgoing in info.outgoing.keys) {
          if (hasCycle(outgoing)) {
            return true;
          }
        }
      }
      
      path.removeLast();
      return false;
    }
    
    if (hasCycle(start)) {
      return List.from(path);
    }
    
    return [];
  }
  
  void printReferenceChain(Object from, Object to) {
    final path = _findPath(from, to);
    if (path.isEmpty) {
      print('No reference path from $from to $to');
      return;
    }
    
    print('Reference chain:');
    for (int i = 0; i < path.length - 1; i++) {
      final current = path[i];
      final next = path[i + 1];
      final info = _references[current]!;
      final field = info.outgoing[next]!;
      print('  ${current.runtimeType} --[$field]--> ${next.runtimeType}');
    }
  }
  
  List<Object> _findPath(Object from, Object to) {
    final queue = Queue<List<Object>>();
    final visited = <Object>{};
    
    queue.add([from]);
    visited.add(from);
    
    while (queue.isNotEmpty) {
      final path = queue.removeFirst();
      final current = path.last;
      
      if (current == to) {
        return path;
      }
      
      final info = _references[current];
      if (info != null) {
        for (final outgoing in info.outgoing.keys) {
          if (!visited.contains(outgoing)) {
            visited.add(outgoing);
            queue.add([...path, outgoing]);
          }
        }
      }
    }
    
    return [];
  }
}

class _ReferenceInfo {
  final Object object;
  final Map<Object, String> incoming = {};
  final Map<Object, String> outgoing = {};
  
  _ReferenceInfo(this.object);
  
  void addIncoming(Object from, String field) {
    incoming[from] = field;
  }
  
  void addOutgoing(Object to, String field) {
    outgoing[to] = field;
  }
  
  void removeIncoming(Object from, String field) {
    incoming.remove(from);
  }
  
  void removeOutgoing(Object to, String field) {
    outgoing.remove(to);
  }
}
```

## Garbage Collection

### 1. GC Monitoring

Monitor garbage collection:

```dart
class GCMonitor {
  final List<GCEvent> _events = [];
  Timer? _pollTimer;
  int _lastGCCount = 0;
  
  void startMonitoring() {
    _pollTimer = Timer.periodic(Duration(seconds: 1), (_) => _checkGC());
  }
  
  void stopMonitoring() {
    _pollTimer?.cancel();
  }
  
  void _checkGC() {
    // Check GC count (platform specific)
    final currentGCCount = _getGCCount();
    
    if (currentGCCount > _lastGCCount) {
      final event = GCEvent(
        timestamp: DateTime.now(),
        gcCount: currentGCCount - _lastGCCount,
        memoryBefore: _lastMemoryUsage,
        memoryAfter: MemoryManager.instance.currentMemoryUsage,
      );
      
      _events.add(event);
      _notifyListeners(event);
      
      _lastGCCount = currentGCCount;
    }
    
    _lastMemoryUsage = MemoryManager.instance.currentMemoryUsage;
  }
  
  int _getGCCount() {
    // Platform-specific implementation
    // This is a placeholder
    return DateTime.now().second;
  }
  
  int _lastMemoryUsage = 0;
  
  final _listeners = <void Function(GCEvent)>[];
  
  void addListener(void Function(GCEvent) listener) {
    _listeners.add(listener);
  }
  
  void removeListener(void Function(GCEvent) listener) {
    _listeners.remove(listener);
  }
  
  void _notifyListeners(GCEvent event) {
    for (final listener in _listeners) {
      listener(event);
    }
  }
  
  GCStatistics getStatistics() {
    if (_events.isEmpty) {
      return GCStatistics.empty();
    }
    
    final totalGCs = _events.fold(0, (sum, e) => sum + e.gcCount);
    final totalReclaimed = _events.fold(
      0,
      (sum, e) => sum + (e.memoryBefore - e.memoryAfter),
    );
    
    return GCStatistics(
      totalGCs: totalGCs,
      totalMemoryReclaimed: totalReclaimed,
      averageReclaimed: totalReclaimed ~/ totalGCs,
      events: List.from(_events),
    );
  }
}

class GCEvent {
  final DateTime timestamp;
  final int gcCount;
  final int memoryBefore;
  final int memoryAfter;
  
  GCEvent({
    required this.timestamp,
    required this.gcCount,
    required this.memoryBefore,
    required this.memoryAfter,
  });
  
  int get memoryReclaimed => memoryBefore - memoryAfter;
}

class GCStatistics {
  final int totalGCs;
  final int totalMemoryReclaimed;
  final int averageReclaimed;
  final List<GCEvent> events;
  
  GCStatistics({
    required this.totalGCs,
    required this.totalMemoryReclaimed,
    required this.averageReclaimed,
    required this.events,
  });
  
  factory GCStatistics.empty() => GCStatistics(
        totalGCs: 0,
        totalMemoryReclaimed: 0,
        averageReclaimed: 0,
        events: [],
      );
}
```

### 2. GC Pressure Management

Manage garbage collection pressure:

```dart
class GCPressureManager {
  static const int _lowPressureThreshold = 10;
  static const int _highPressureThreshold = 50;
  
  final _gcMonitor = GCMonitor();
  final _recentGCs = Queue<DateTime>();
  Timer? _analysisTimer;
  
  void startManaging() {
    _gcMonitor.startMonitoring();
    _gcMonitor.addListener(_onGC);
    
    _analysisTimer = Timer.periodic(Duration(seconds: 10), (_) => _analyze());
  }
  
  void stopManaging() {
    _gcMonitor.stopMonitoring();
    _analysisTimer?.cancel();
  }
  
  void _onGC(GCEvent event) {
    _recentGCs.add(event.timestamp);
    
    // Keep only recent GCs
    final cutoff = DateTime.now().subtract(Duration(minutes: 1));
    while (_recentGCs.isNotEmpty && _recentGCs.first.isBefore(cutoff)) {
      _recentGCs.removeFirst();
    }
  }
  
  void _analyze() {
    final gcRate = _recentGCs.length;
    
    if (gcRate < _lowPressureThreshold) {
      _handleLowPressure();
    } else if (gcRate > _highPressureThreshold) {
      _handleHighPressure();
    } else {
      _handleNormalPressure();
    }
  }
  
  void _handleLowPressure() {
    // Can allocate more aggressively
    ObjectPool.setGlobalMaxSize(200);
    CacheManager.setGlobalMaxSize(1000);
  }
  
  void _handleNormalPressure() {
    // Normal operation
    ObjectPool.setGlobalMaxSize(100);
    CacheManager.setGlobalMaxSize(500);
  }
  
  void _handleHighPressure() {
    // Reduce allocations
    ObjectPool.setGlobalMaxSize(50);
    CacheManager.setGlobalMaxSize(200);
    
    // Trigger cleanup
    CacheManager.globalCleanup();
    ObjectPool.globalCleanup();
    
    // Force GC if critical
    if (_recentGCs.length > _highPressureThreshold * 2) {
      _forceGC();
    }
  }
  
  void _forceGC() {
    // Platform-specific GC trigger
    // This is generally not recommended but may be necessary
    print('Forcing garbage collection due to high pressure');
  }
}
```

## Memory Efficient Data Structures

### 1. Compact Collections

Implement memory-efficient collections:

```dart
// Bit set for efficient boolean arrays
class BitSet {
  final Uint32List _data;
  final int _size;
  
  BitSet(int size) 
      : _size = size,
        _data = Uint32List((size + 31) ~/ 32);
  
  void set(int index, bool value) {
    if (index >= _size) throw RangeError.index(index, this);
    
    final wordIndex = index ~/ 32;
    final bitIndex = index % 32;
    
    if (value) {
      _data[wordIndex] |= 1 << bitIndex;
    } else {
      _data[wordIndex] &= ~(1 << bitIndex);
    }
  }
  
  bool get(int index) {
    if (index >= _size) throw RangeError.index(index, this);
    
    final wordIndex = index ~/ 32;
    final bitIndex = index % 32;
    
    return (_data[wordIndex] & (1 << bitIndex)) != 0;
  }
  
  int get sizeInBytes => _data.lengthInBytes;
}

// Compact string storage
class CompactStringSet {
  final List<int> _offsets = [0];
  final List<int> _data = [];
  final Map<String, int> _index = {};
  
  void add(String value) {
    if (_index.containsKey(value)) return;
    
    final index = _offsets.length - 1;
    _index[value] = index;
    
    final bytes = utf8.encode(value);
    _data.addAll(bytes);
    _offsets.add(_data.length);
  }
  
  bool contains(String value) => _index.containsKey(value);
  
  String? get(int index) {
    if (index >= _offsets.length - 1) return null;
    
    final start = _offsets[index];
    final end = _offsets[index + 1];
    final bytes = _data.sublist(start, end);
    
    return utf8.decode(bytes);
  }
  
  int get sizeInBytes => _data.length + _offsets.length * 4;
}

// Compressed integer list
class CompressedIntList {
  final Uint8List _data;
  final int _bitsPerValue;
  final int _length;
  
  CompressedIntList(List<int> values)
      : _length = values.length,
        _bitsPerValue = _calculateBitsNeeded(values),
        _data = _compress(values) {
    if (values.isEmpty) throw ArgumentError('Values cannot be empty');
  }
  
  static int _calculateBitsNeeded(List<int> values) {
    final max = values.reduce(math.max);
    return max.bitLength;
  }
  
  static Uint8List _compress(List<int> values) {
    final bitsNeeded = _calculateBitsNeeded(values);
    final totalBits = values.length * bitsNeeded;
    final bytes = Uint8List((totalBits + 7) ~/ 8);
    
    int bitOffset = 0;
    for (final value in values) {
      _writeBits(bytes, bitOffset, value, bitsNeeded);
      bitOffset += bitsNeeded;
    }
    
    return bytes;
  }
  
  static void _writeBits(
    Uint8List bytes,
    int bitOffset,
    int value,
    int bits,
  ) {
    for (int i = 0; i < bits; i++) {
      final byteIndex = (bitOffset + i) ~/ 8;
      final bitIndex = (bitOffset + i) % 8;
      
      if ((value & (1 << i)) != 0) {
        bytes[byteIndex] |= 1 << bitIndex;
      }
    }
  }
  
  int operator [](int index) {
    if (index >= _length) throw RangeError.index(index, this);
    
    final bitOffset = index * _bitsPerValue;
    return _readBits(_data, bitOffset, _bitsPerValue);
  }
  
  static int _readBits(Uint8List bytes, int bitOffset, int bits) {
    int value = 0;
    
    for (int i = 0; i < bits; i++) {
      final byteIndex = (bitOffset + i) ~/ 8;
      final bitIndex = (bitOffset + i) % 8;
      
      if ((bytes[byteIndex] & (1 << bitIndex)) != 0) {
        value |= 1 << i;
      }
    }
    
    return value;
  }
  
  int get sizeInBytes => _data.lengthInBytes;
}
```

### 2. Flyweight Pattern

Implement flyweight pattern for shared objects:

```dart
// Flyweight factory for immutable objects
class FlyweightFactory<T> {
  final Map<String, T> _instances = {};
  final T Function(String) _factory;
  
  FlyweightFactory(this._factory);
  
  T get(String key) {
    return _instances.putIfAbsent(key, () => _factory(key));
  }
  
  int get instanceCount => _instances.length;
  
  void clear() => _instances.clear();
}

// Example: Color flyweight
class ColorFlyweight {
  static final _factory = FlyweightFactory<Color>((key) {
    final value = int.parse(key, radix: 16);
    return Color(value);
  });
  
  static Color get(int value) {
    final key = value.toRadixString(16).padLeft(8, '0');
    return _factory.get(key);
  }
  
  static void clearCache() => _factory.clear();
  
  static int get cachedCount => _factory.instanceCount;
}

// Example: String intern pool
class StringPool {
  static final _pool = <String, String>{};
  
  static String intern(String value) {
    return _pool.putIfAbsent(value, () => value);
  }
  
  static void clear() => _pool.clear();
  
  static int get poolSize => _pool.length;
  
  static int get memorySaved {
    int saved = 0;
    _pool.forEach((key, value) {
      // Assuming average 2 references per interned string
      saved += key.length * 2;
    });
    return saved;
  }
}
```

### 3. Copy-on-Write

Implement copy-on-write for efficient data sharing:

```dart
class COWList<T> {
  List<T> _data;
  bool _isShared = false;
  
  COWList(this._data);
  
  COWList<T> clone() {
    _isShared = true;
    return COWList(_data).._isShared = true;
  }
  
  T operator [](int index) => _data[index];
  
  void operator []=(int index, T value) {
    _ensureUnique();
    _data[index] = value;
  }
  
  void add(T value) {
    _ensureUnique();
    _data.add(value);
  }
  
  void _ensureUnique() {
    if (_isShared) {
      _data = List.from(_data);
      _isShared = false;
    }
  }
  
  int get length => _data.length;
}

// Copy-on-write map
class COWMap<K, V> {
  Map<K, V> _data;
  bool _isShared = false;
  
  COWMap(this._data);
  
  COWMap<K, V> clone() {
    _isShared = true;
    return COWMap(_data).._isShared = true;
  }
  
  V? operator [](K key) => _data[key];
  
  void operator []=(K key, V value) {
    _ensureUnique();
    _data[key] = value;
  }
  
  void remove(K key) {
    _ensureUnique();
    _data.remove(key);
  }
  
  void _ensureUnique() {
    if (_isShared) {
      _data = Map.from(_data);
      _isShared = false;
    }
  }
  
  int get length => _data.length;
}
```

## Memory Usage Patterns

### 1. Memory Usage Analysis

Analyze memory usage patterns:

```dart
class MemoryUsageAnalyzer {
  final List<MemorySnapshot> _snapshots = [];
  Timer? _snapshotTimer;
  
  void startAnalysis({
    Duration interval = const Duration(minutes: 1),
  }) {
    _snapshotTimer = Timer.periodic(interval, (_) => _takeSnapshot());
  }
  
  void stopAnalysis() {
    _snapshotTimer?.cancel();
  }
  
  void _takeSnapshot() {
    final snapshot = MemorySnapshot(
      timestamp: DateTime.now(),
      totalMemory: MemoryManager.instance.totalMemory,
      usedMemory: MemoryManager.instance.currentMemoryUsage,
      heapUsage: _getHeapUsage(),
      cacheSize: _getCacheSize(),
      objectCounts: _getObjectCounts(),
    );
    
    _snapshots.add(snapshot);
    
    // Analyze trends
    if (_snapshots.length > 1) {
      _analyzeTrends();
    }
  }
  
  Map<String, int> _getObjectCounts() {
    // Platform-specific implementation
    // This is a placeholder
    return {
      'Widget': 1000,
      'RenderObject': 500,
      'Element': 800,
    };
  }
  
  int _getHeapUsage() {
    // Platform-specific implementation
    return MemoryManager.instance.currentMemoryUsage;
  }
  
  int _getCacheSize() {
    // Sum of all cache sizes
    return 0;
  }
  
  void _analyzeTrends() {
    if (_snapshots.length < 2) return;
    
    final recent = _snapshots.last;
    final previous = _snapshots[_snapshots.length - 2];
    
    final memoryGrowth = recent.usedMemory - previous.usedMemory;
    final growthRate = memoryGrowth / previous.usedMemory;
    
    if (growthRate > 0.1) {
      // Memory growing fast
      print('Warning: Memory usage increased by ${(growthRate * 100).toStringAsFixed(1)}%');
      _identifyGrowthSource(recent, previous);
    }
  }
  
  void _identifyGrowthSource(MemorySnapshot recent, MemorySnapshot previous) {
    // Compare object counts
    recent.objectCounts.forEach((type, count) {
      final previousCount = previous.objectCounts[type] ?? 0;
      final growth = count - previousCount;
      
      if (growth > 100) {
        print('  $type instances increased by $growth');
      }
    });
  }
  
  MemoryUsageReport generateReport() {
    if (_snapshots.isEmpty) {
      return MemoryUsageReport.empty();
    }
    
    final first = _snapshots.first;
    final last = _snapshots.last;
    
    return MemoryUsageReport(
      startTime: first.timestamp,
      endTime: last.timestamp,
      initialMemory: first.usedMemory,
      finalMemory: last.usedMemory,
      peakMemory: _snapshots.map((s) => s.usedMemory).reduce(math.max),
      averageMemory: _snapshots.map((s) => s.usedMemory).reduce((a, b) => a + b) ~/ _snapshots.length,
      snapshots: List.from(_snapshots),
    );
  }
}

class MemorySnapshot {
  final DateTime timestamp;
  final int totalMemory;
  final int usedMemory;
  final int heapUsage;
  final int cacheSize;
  final Map<String, int> objectCounts;
  
  MemorySnapshot({
    required this.timestamp,
    required this.totalMemory,
    required this.usedMemory,
    required this.heapUsage,
    required this.cacheSize,
    required this.objectCounts,
  });
}

class MemoryUsageReport {
  final DateTime startTime;
  final DateTime endTime;
  final int initialMemory;
  final int finalMemory;
  final int peakMemory;
  final int averageMemory;
  final List<MemorySnapshot> snapshots;
  
  MemoryUsageReport({
    required this.startTime,
    required this.endTime,
    required this.initialMemory,
    required this.finalMemory,
    required this.peakMemory,
    required this.averageMemory,
    required this.snapshots,
  });
  
  factory MemoryUsageReport.empty() => MemoryUsageReport(
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        initialMemory: 0,
        finalMemory: 0,
        peakMemory: 0,
        averageMemory: 0,
        snapshots: [],
      );
}
```

### 2. Memory Budgets

Implement memory budgets:

```dart
class MemoryBudgetManager {
  final Map<String, MemoryBudget> _budgets = {};
  final Map<String, int> _usage = {};
  
  void setBudget(String category, int maxBytes) {
    _budgets[category] = MemoryBudget(
      category: category,
      maxBytes: maxBytes,
    );
  }
  
  bool requestMemory(String category, int bytes) {
    final budget = _budgets[category];
    if (budget == null) return true; // No budget set
    
    final currentUsage = _usage[category] ?? 0;
    if (currentUsage + bytes > budget.maxBytes) {
      return false; // Would exceed budget
    }
    
    _usage[category] = currentUsage + bytes;
    budget.currentUsage = currentUsage + bytes;
    
    return true;
  }
  
  void releaseMemory(String category, int bytes) {
    final currentUsage = _usage[category] ?? 0;
    _usage[category] = math.max(0, currentUsage - bytes);
    
    final budget = _budgets[category];
    if (budget != null) {
      budget.currentUsage = _usage[category]!;
    }
  }
  
  Map<String, double> getUsagePercentages() {
    final percentages = <String, double>{};
    
    _budgets.forEach((category, budget) {
      final usage = _usage[category] ?? 0;
      percentages[category] = usage / budget.maxBytes;
    });
    
    return percentages;
  }
  
  void enforcebudgets() {
    _budgets.forEach((category, budget) {
      final usage = _usage[category] ?? 0;
      if (usage > budget.maxBytes) {
        final excess = usage - budget.maxBytes;
        _handleBudgetExcess(category, excess);
      }
    });
  }
  
  void _handleBudgetExcess(String category, int excess) {
    print('Memory budget exceeded for $category by $excess bytes');
    
    // Trigger cleanup for this category
    switch (category) {
      case 'images':
        ImageCache.instance.reduce(excess);
        break;
      case 'data':
        DataCache.instance.evict(excess);
        break;
      default:
        // Generic cleanup
        CacheManager.reduceCategory(category, excess);
    }
  }
}

class MemoryBudget {
  final String category;
  final int maxBytes;
  int currentUsage = 0;
  
  MemoryBudget({
    required this.category,
    required this.maxBytes,
  });
  
  double get usagePercentage => currentUsage / maxBytes;
  int get remaining => maxBytes - currentUsage;
  bool get isExceeded => currentUsage > maxBytes;
}
```

## Best Practices

### 1. Memory Management Guidelines

```dart
// 1. Always dispose resources
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late final StreamController _controller;
  late final Timer _timer;
  StreamSubscription? _subscription;
  
  @override
  void initState() {
    super.initState();
    _controller = StreamController();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      _controller.add(DateTime.now());
    });
    _subscription = _controller.stream.listen((data) {
      // Handle data
    });
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    _timer.cancel();
    _controller.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

// 2. Use weak references for callbacks
class CallbackManager {
  final List<WeakReference<Function>> _callbacks = [];
  
  void addCallback(Function callback) {
    _callbacks.add(WeakReference(callback));
  }
  
  void notifyAll() {
    _callbacks.removeWhere((ref) => ref.target == null);
    
    for (final ref in _callbacks) {
      ref.target?.call();
    }
  }
}

// 3. Implement memory pressure response
class MemoryAwareCache<K, V> {
  final Map<K, V> _cache = {};
  final int _maxSize;
  
  MemoryAwareCache(this._maxSize) {
    MemoryManager.instance.addListener(_onMemoryPressure);
  }
  
  void _onMemoryPressure(MemoryLevel level) {
    switch (level) {
      case MemoryLevel.low:
        // Reduce cache by 25%
        _reduceCacheSize(0.75);
        break;
      case MemoryLevel.medium:
        // Reduce cache by 50%
        _reduceCacheSize(0.5);
        break;
      case MemoryLevel.high:
      case MemoryLevel.critical:
        // Clear cache
        _cache.clear();
        break;
      default:
        break;
    }
  }
  
  void _reduceCacheSize(double factor) {
    final targetSize = (_cache.length * factor).round();
    final keysToRemove = _cache.keys.take(_cache.length - targetSize);
    keysToRemove.forEach(_cache.remove);
  }
  
  void put(K key, V value) {
    if (_cache.length >= _maxSize) {
      // Remove oldest entry (simple FIFO)
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }
  
  V? get(K key) => _cache[key];
}
```

### 2. Memory Profiling

```dart
// Profile memory usage during development
class DevelopmentMemoryProfiler {
  static void profileOperation(String name, VoidCallback operation) {
    if (!kDebugMode) {
      operation();
      return;
    }
    
    final startMemory = MemoryManager.instance.currentMemoryUsage;
    final stopwatch = Stopwatch()..start();
    
    operation();
    
    stopwatch.stop();
    final endMemory = MemoryManager.instance.currentMemoryUsage;
    
    print('Operation: $name');
    print('  Duration: ${stopwatch.elapsedMilliseconds}ms');
    print('  Memory delta: ${(endMemory - startMemory) / 1024}KB');
    print('  Final memory: ${endMemory / 1024 / 1024}MB');
  }
  
  static Future<void> profileAsyncOperation(
    String name,
    Future<void> Function() operation,
  ) async {
    if (!kDebugMode) {
      await operation();
      return;
    }
    
    final startMemory = MemoryManager.instance.currentMemoryUsage;
    final stopwatch = Stopwatch()..start();
    
    await operation();
    
    stopwatch.stop();
    final endMemory = MemoryManager.instance.currentMemoryUsage;
    
    print('Async Operation: $name');
    print('  Duration: ${stopwatch.elapsedMilliseconds}ms');
    print('  Memory delta: ${(endMemory - startMemory) / 1024}KB');
    print('  Final memory: ${endMemory / 1024 / 1024}MB');
  }
}

// Usage
DevelopmentMemoryProfiler.profileOperation('loadImages', () {
  final images = List.generate(100, (i) => loadImage('image_$i.png'));
});
```

### 3. Memory Testing

```dart
// Test for memory leaks
class MemoryLeakTest {
  static Future<void> testForLeaks(
    String testName,
    Future<void> Function() setupOperation,
    Future<void> Function() testOperation,
    {int iterations = 10}
  ) async {
    print('Testing for memory leaks: $testName');
    
    // Warm up
    await setupOperation();
    await testOperation();
    
    // Force GC and wait
    await _forceGC();
    await Future.delayed(Duration(seconds: 1));
    
    final initialMemory = MemoryManager.instance.currentMemoryUsage;
    
    // Run test iterations
    for (int i = 0; i < iterations; i++) {
      await testOperation();
    }
    
    // Force GC and wait
    await _forceGC();
    await Future.delayed(Duration(seconds: 1));
    
    final finalMemory = MemoryManager.instance.currentMemoryUsage;
    final memoryGrowth = finalMemory - initialMemory;
    final growthPerIteration = memoryGrowth / iterations;
    
    print('Memory leak test results:');
    print('  Initial memory: ${initialMemory / 1024 / 1024}MB');
    print('  Final memory: ${finalMemory / 1024 / 1024}MB');
    print('  Total growth: ${memoryGrowth / 1024}KB');
    print('  Growth per iteration: ${growthPerIteration / 1024}KB');
    
    if (growthPerIteration > 1024) { // 1KB threshold
      print('  WARNING: Possible memory leak detected!');
    } else {
      print('  No significant memory leak detected');
    }
  }
  
  static Future<void> _forceGC() async {
    // Platform-specific GC trigger
    // This is a placeholder
    await Future.delayed(Duration(milliseconds: 100));
  }
}

// Usage
await MemoryLeakTest.testForLeaks(
  'Widget creation',
  () async {
    // Setup
  },
  () async {
    // Create and destroy widgets
    final widget = MyComplexWidget();
    // Simulate widget lifecycle
  },
  iterations: 100,
);
```

## Common Memory Issues

### 1. Image Memory Management

```dart
class ImageMemoryManager {
  static const int _maxCacheSize = 100 * 1024 * 1024; // 100MB
  static const int _maxCacheCount = 100;
  
  static void configureImageCache() {
    imageCache.maximumSize = _maxCacheCount;
    imageCache.maximumSizeBytes = _maxCacheSize;
  }
  
  static void clearImageCache() {
    imageCache.clear();
    imageCache.clearLiveImages();
  }
  
  static Future<ui.Image> loadOptimizedImage(
    String path, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    final data = await rootBundle.load(path);
    final bytes = data.buffer.asUint8List();
    
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: maxWidth,
      targetHeight: maxHeight,
    );
    
    final frame = await codec.getNextFrame();
    return frame.image;
  }
  
  static void monitorImageCache() {
    Timer.periodic(Duration(seconds: 10), (_) {
      final currentSize = imageCache.currentSizeBytes;
      final maxSize = imageCache.maximumSizeBytes;
      
      if (currentSize > maxSize * 0.8) {
        print('Image cache usage high: ${currentSize / 1024 / 1024}MB');
        // Reduce cache size
        imageCache.maximumSizeBytes = (maxSize * 0.8).round();
      }
    });
  }
}
```

### 2. Large Data Processing

```dart
class LargeDataProcessor {
  static const int _chunkSize = 1000;
  
  static Stream<ProcessedChunk> processLargeDataSet<T, R>(
    List<T> data,
    R Function(T) processor,
  ) async* {
    for (int i = 0; i < data.length; i += _chunkSize) {
      final end = math.min(i + _chunkSize, data.length);
      final chunk = data.sublist(i, end);
      
      final results = <R>[];
      for (final item in chunk) {
        results.add(processor(item));
      }
      
      yield ProcessedChunk(
        startIndex: i,
        endIndex: end,
        results: results,
      );
      
      // Allow other operations to run
      await Future.delayed(Duration.zero);
    }
  }
  
  static Future<void> processInBatches<T>(
    List<T> items,
    Future<void> Function(List<T>) batchProcessor,
    {int batchSize = 100}
  ) async {
    for (int i = 0; i < items.length; i += batchSize) {
      final end = math.min(i + batchSize, items.length);
      final batch = items.sublist(i, end);
      
      await batchProcessor(batch);
      
      // Check memory pressure
      if (MemoryManager.instance.isUnderPressure) {
        await _waitForMemoryRelief();
      }
    }
  }
  
  static Future<void> _waitForMemoryRelief() async {
    print('Waiting for memory pressure to reduce...');
    
    while (MemoryManager.instance.isUnderPressure) {
      await Future.delayed(Duration(seconds: 1));
    }
  }
}

class ProcessedChunk<T> {
  final int startIndex;
  final int endIndex;
  final List<T> results;
  
  ProcessedChunk({
    required this.startIndex,
    required this.endIndex,
    required this.results,
  });
}
```

### 3. Widget Memory Optimization

```dart
class WidgetMemoryOptimizer {
  // Use const constructors where possible
  static const _constWidget = Padding(
    padding: EdgeInsets.all(8.0),
    child: Text('Constant Text'),
  );
  
  // Reuse widget instances
  static final _widgetCache = <String, Widget>{};
  
  static Widget getCachedWidget(String key, Widget Function() builder) {
    return _widgetCache.putIfAbsent(key, builder);
  }
  
  // Optimize list views
  static Widget buildOptimizedListView({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      // Reuse item extents for better performance
      itemExtent: 50.0,
      // Don't keep alive widgets that are off-screen
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
    );
  }
  
  // Use RepaintBoundary for complex widgets
  static Widget wrapWithRepaintBoundary(Widget child, {bool enabled = true}) {
    if (!enabled) return child;
    
    return RepaintBoundary(child: child);
  }
}

// Memory-efficient custom painter
class MemoryEfficientPainter extends CustomPainter {
  // Reuse paint objects
  static final _paint = Paint();
  static final _path = Path();
  
  @override
  void paint(Canvas canvas, Size size) {
    _paint.color = Colors.blue;
    _paint.style = PaintingStyle.fill;
    
    _path.reset();
    _path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    
    canvas.drawPath(_path, _paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
```

## Next Steps

- [Performance Tuning](performance-tuning.md) - General performance optimization
- [Security Guide](security.md) - Security considerations
- [Testing Guide](testing.md) - Memory testing strategies
- [Platform Guides](../platform/README.md) - Platform-specific memory management