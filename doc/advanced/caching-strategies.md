# Caching Strategies Guide

Comprehensive guide to implementing efficient caching strategies in Flutter MCP for improved performance and reduced latency.

## Overview

Flutter MCP provides multiple caching layers and strategies:
- **SemanticCache**: AI-powered content similarity caching
- **ResponseCache**: Standard key-value response caching  
- **MemoryCache**: In-memory caching for frequent access
- **PersistentCache**: Disk-based caching for durability
- **DistributedCache**: Multi-instance cache synchronization

## Built-in Cache Types

### SemanticCache

The SemanticCache uses AI embeddings to cache similar queries and responses:

```dart
// Initialize semantic cache
await SemanticCache.instance.initialize(
  embeddingProvider: 'openai',
  similarityThreshold: 0.85,
  maxCacheSize: 1000,
);

// Cache a response
await SemanticCache.instance.put(
  query: 'What is machine learning?',
  response: 'Machine learning is...',
  metadata: {
    'source': 'openai',
    'timestamp': DateTime.now().toIso8601String(),
  },
);

// Check for similar cached responses
final cachedResponse = await SemanticCache.instance.getSimilar(
  'What is ML?', // Will match previous query due to similarity
  similarityThreshold: 0.8,
);

if (cachedResponse != null) {
  print('Cache hit: ${cachedResponse.response}');
}
```

### ResponseCache

Standard key-value caching for exact matches:

```dart
// Basic response caching
final responseCache = ResponseCache.instance;

// Cache with TTL
await responseCache.put(
  key: 'user_profile_123',
  value: userProfileData,
  ttl: Duration(minutes: 30),
);

// Retrieve from cache
final cached = await responseCache.get('user_profile_123');
if (cached != null) {
  print('Using cached data');
} else {
  // Fetch fresh data
  final fresh = await fetchUserProfile(123);
  await responseCache.put('user_profile_123', fresh);
}
```

### Memory Manager Integration

```dart
class CacheAwareService {
  final _memoryManager = MemoryManager.instance;
  final _cache = ResponseCache.instance;
  
  Future<String> getData(String key) async {
    // Check memory pressure before using cache
    final memoryPressure = await _memoryManager.getMemoryPressure();
    
    if (memoryPressure > 0.8) {
      // High memory pressure - clear some cache
      await _cache.clearLeastRecentlyUsed(0.3); // Clear 30% of cache
    }
    
    final cached = await _cache.get(key);
    if (cached != null) {
      return cached;
    }
    
    // Fetch and cache
    final data = await _fetchData(key);
    await _cache.put(key, data, ttl: Duration(hours: 1));
    return data;
  }
  
  Future<String> _fetchData(String key) async {
    // Simulate data fetching
    await Future.delayed(Duration(seconds: 1));
    return 'Data for $key';
  }
}
```

## Advanced Caching Patterns

### Multi-Level Cache

```dart
class MultiLevelCache<T> {
  final MemoryCache<T> _l1Cache;
  final PersistentCache<T> _l2Cache;
  final Duration _l1TTL;
  final Duration _l2TTL;
  
  MultiLevelCache({
    required int l1MaxSize,
    required int l2MaxSize,
    this._l1TTL = const Duration(minutes: 15),
    this._l2TTL = const Duration(hours: 24),
  }) : _l1Cache = MemoryCache<T>(maxSize: l1MaxSize),
       _l2Cache = PersistentCache<T>(maxSize: l2MaxSize);
  
  Future<T?> get(String key) async {
    // Check L1 (memory) first
    T? value = await _l1Cache.get(key);
    if (value != null) {
      print('L1 cache hit: $key');
      return value;
    }
    
    // Check L2 (disk) cache
    value = await _l2Cache.get(key);
    if (value != null) {
      print('L2 cache hit: $key');
      // Promote to L1
      await _l1Cache.put(key, value, _l1TTL);
      return value;
    }
    
    print('Cache miss: $key');
    return null;
  }
  
  Future<void> put(String key, T value) async {
    // Store in both levels
    await _l1Cache.put(key, value, _l1TTL);
    await _l2Cache.put(key, value, _l2TTL);
  }
  
  Future<void> invalidate(String key) async {
    await _l1Cache.remove(key);
    await _l2Cache.remove(key);
  }
  
  Future<void> clear() async {
    await _l1Cache.clear();
    await _l2Cache.clear();
  }
}
```

### Write-Through Cache

```dart
class WriteThroughCache<T> {
  final ResponseCache _cache;
  final Future<void> Function(String key, T value) _writeToDataStore;
  final Future<T?> Function(String key) _readFromDataStore;
  
  WriteThroughCache({
    required Future<void> Function(String key, T value) writeFunction,
    required Future<T?> Function(String key) readFunction,
  }) : _cache = ResponseCache.instance,
       _writeToDataStore = writeFunction,
       _readFromDataStore = readFunction;
  
  Future<T?> get(String key) async {
    // Try cache first
    final cached = await _cache.get(key);
    if (cached != null) {
      return cached as T;
    }
    
    // Cache miss - read from data store
    final value = await _readFromDataStore(key);
    if (value != null) {
      // Cache the result
      await _cache.put(key, value, Duration(hours: 1));
    }
    
    return value;
  }
  
  Future<void> put(String key, T value) async {
    // Write to data store first
    await _writeToDataStore(key, value);
    
    // Then update cache
    await _cache.put(key, value, Duration(hours: 1));
  }
  
  Future<void> delete(String key) async {
    // Remove from data store
    await _writeToDataStore(key, null as T); // Assuming null means delete
    
    // Remove from cache
    await _cache.remove(key);
  }
}
```

### Write-Behind Cache

```dart
class WriteBehindCache<T> {
  final ResponseCache _cache;
  final Queue<WriteOperation<T>> _writeQueue = Queue();
  final Map<String, Timer> _writeTimers = {};
  final Duration _writeDelay;
  final Future<void> Function(String key, T value) _writeToDataStore;
  
  WriteBehindCache({
    required Future<void> Function(String key, T value) writeFunction,
    this._writeDelay = const Duration(seconds: 5),
  }) : _cache = ResponseCache.instance,
       _writeToDataStore = writeFunction;
  
  Future<T?> get(String key) async {
    // Always read from cache first
    return await _cache.get(key) as T?;
  }
  
  Future<void> put(String key, T value) async {
    // Update cache immediately
    await _cache.put(key, value, Duration(hours: 1));
    
    // Schedule delayed write to data store
    _scheduleWrite(key, value);
  }
  
  void _scheduleWrite(String key, T value) {
    // Cancel existing timer for this key
    _writeTimers[key]?.cancel();
    
    // Schedule new write
    _writeTimers[key] = Timer(_writeDelay, () async {
      try {
        await _writeToDataStore(key, value);
        _writeTimers.remove(key);
      } catch (e) {
        print('Failed to write $key to data store: $e');
        // Could implement retry logic here
      }
    });
  }
  
  Future<void> flush() async {
    // Force immediate write of all pending operations
    final pendingWrites = _writeTimers.keys.toList();
    
    for (final key in pendingWrites) {
      _writeTimers[key]?.cancel();
      final value = await _cache.get(key);
      if (value != null) {
        await _writeToDataStore(key, value as T);
      }
    }
    
    _writeTimers.clear();
  }
}
```

## LLM Response Caching

### Intelligent LLM Cache

```dart
class LLMResponseCache {
  final SemanticCache _semanticCache = SemanticCache.instance;
  final ResponseCache _exactCache = ResponseCache.instance;
  
  Future<LLMResponse?> getCachedResponse({
    required String prompt,
    required String llmId,
    QueryOptions? options,
  }) async {
    // Generate cache key
    final cacheKey = _generateCacheKey(prompt, llmId, options);
    
    // Try exact match first (faster)
    final exactMatch = await _exactCache.get(cacheKey);
    if (exactMatch != null) {
      print('Exact cache hit for LLM query');
      return exactMatch as LLMResponse;
    }
    
    // Try semantic similarity match
    final semanticKey = '$llmId:$prompt';
    final similarResponse = await _semanticCache.getSimilar(
      semanticKey,
      similarityThreshold: 0.9, // High threshold for LLM responses
    );
    
    if (similarResponse != null) {
      print('Semantic cache hit for LLM query');
      
      // Also cache as exact match for future requests
      await _exactCache.put(
        cacheKey,
        similarResponse.response,
        Duration(hours: 6),
      );
      
      return similarResponse.response as LLMResponse;
    }
    
    return null;
  }
  
  Future<void> cacheResponse({
    required String prompt,
    required String llmId,
    required LLMResponse response,
    QueryOptions? options,
  }) async {
    final cacheKey = _generateCacheKey(prompt, llmId, options);
    
    // Cache exact match
    await _exactCache.put(
      cacheKey,
      response,
      Duration(hours: 6),
    );
    
    // Cache for semantic similarity
    final semanticKey = '$llmId:$prompt';
    await _semanticCache.put(
      query: semanticKey,
      response: response,
      metadata: {
        'llm_id': llmId,
        'options': options?.toJson() ?? {},
        'cached_at': DateTime.now().toIso8601String(),
      },
    );
  }
  
  String _generateCacheKey(String prompt, String llmId, QueryOptions? options) {
    final optionsJson = options?.toJson() ?? {};
    final combined = '$llmId:$prompt:${jsonEncode(optionsJson)}';
    return sha256.convert(utf8.encode(combined)).toString();
  }
}
```

### Cached LLM Service

```dart
class CachedLLMService {
  final LLMResponseCache _cache = LLMResponseCache();
  
  Future<LLMResponse> query({
    required String llmId,
    required String prompt,
    QueryOptions? options,
    bool useCache = true,
  }) async {
    if (useCache) {
      // Check cache first
      final cached = await _cache.getCachedResponse(
        prompt: prompt,
        llmId: llmId,
        options: options,
      );
      
      if (cached != null) {
        // Mark as cached in response
        cached.metadata ??= {};
        cached.metadata!['cached'] = true;
        cached.metadata!['cache_hit_time'] = DateTime.now().toIso8601String();
        return cached;
      }
    }
    
    // Cache miss - query LLM
    final response = await FlutterMCP.instance.llmManager.query(
      llmId: llmId,
      prompt: prompt,
      options: options,
    );
    
    // Cache the response
    if (useCache && response.text.isNotEmpty) {
      await _cache.cacheResponse(
        prompt: prompt,
        llmId: llmId,
        response: response,
        options: options,
      );
    }
    
    return response;
  }
}
```

## MCP Tool Result Caching

### Tool Response Cache

```dart
class MCPToolCache {
  final ResponseCache _cache = ResponseCache.instance;
  final Set<String> _cacheableTools = {
    'get_weather',
    'get_stock_price',
    'get_news',
    'search_documents',
  };
  
  Future<dynamic> callToolWithCache({
    required String clientId,
    required String toolName,
    required Map<String, dynamic> arguments,
    Duration? cacheTTL,
  }) async {
    // Check if tool is cacheable
    if (!_cacheableTools.contains(toolName)) {
      return await _callToolDirect(clientId, toolName, arguments);
    }
    
    // Generate cache key
    final cacheKey = _generateToolCacheKey(clientId, toolName, arguments);
    
    // Try cache first
    final cached = await _cache.get(cacheKey);
    if (cached != null) {
      print('Tool cache hit: $toolName');
      return cached;
    }
    
    // Cache miss - call tool
    final result = await _callToolDirect(clientId, toolName, arguments);
    
    // Cache the result
    final ttl = cacheTTL ?? _getDefaultTTL(toolName);
    await _cache.put(cacheKey, result, ttl);
    
    return result;
  }
  
  Future<dynamic> _callToolDirect(
    String clientId,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    return await FlutterMCP.instance.clientManager.callTool(
      clientId,
      toolName,
      arguments,
    );
  }
  
  String _generateToolCacheKey(
    String clientId,
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final combined = '$clientId:$toolName:${jsonEncode(arguments)}';
    return 'tool:${sha256.convert(utf8.encode(combined)).toString()}';
  }
  
  Duration _getDefaultTTL(String toolName) {
    switch (toolName) {
      case 'get_weather':
        return Duration(minutes: 15);
      case 'get_stock_price':
        return Duration(minutes: 5);
      case 'get_news':
        return Duration(hours: 1);
      case 'search_documents':
        return Duration(hours: 6);
      default:
        return Duration(minutes: 30);
    }
  }
  
  Future<void> invalidateToolCache(String toolName) async {
    // Find and remove all cache entries for this tool
    final pattern = 'tool:.*:$toolName:';
    await _cache.removeByPattern(pattern);
  }
}
```

## Cache Warming Strategies

### Proactive Cache Warming

```dart
class CacheWarmer {
  final LLMResponseCache _llmCache = LLMResponseCache();
  final MCPToolCache _toolCache = MCPToolCache();
  final List<WarmupTask> _warmupTasks = [];
  
  void addWarmupTask(WarmupTask task) {
    _warmupTasks.add(task);
  }
  
  Future<void> warmCaches() async {
    print('Starting cache warmup...');
    
    final futures = _warmupTasks.map((task) async {
      try {
        await _executeWarmupTask(task);
        print('Warmed cache for: ${task.description}');
      } catch (e) {
        print('Failed to warm cache for ${task.description}: $e');
      }
    });
    
    await Future.wait(futures);
    print('Cache warmup completed');
  }
  
  Future<void> _executeWarmupTask(WarmupTask task) async {
    switch (task.type) {
      case WarmupType.llm:
        await _warmLLMCache(task);
        break;
      case WarmupType.tool:
        await _warmToolCache(task);
        break;
      case WarmupType.data:
        await _warmDataCache(task);
        break;
    }
  }
  
  Future<void> _warmLLMCache(WarmupTask task) async {
    final prompts = task.data['prompts'] as List<String>;
    final llmId = task.data['llm_id'] as String;
    
    for (final prompt in prompts) {
      await FlutterMCP.instance.llmManager.query(
        llmId: llmId,
        prompt: prompt,
      );
    }
  }
  
  Future<void> _warmToolCache(WarmupTask task) async {
    final toolName = task.data['tool_name'] as String;
    final clientId = task.data['client_id'] as String;
    final argumentsList = task.data['arguments'] as List<Map<String, dynamic>>;
    
    for (final arguments in argumentsList) {
      await _toolCache.callToolWithCache(
        clientId: clientId,
        toolName: toolName,
        arguments: arguments,
      );
    }
  }
  
  Future<void> _warmDataCache(WarmupTask task) async {
    final keys = task.data['keys'] as List<String>;
    final service = task.data['service'] as CacheableService;
    
    for (final key in keys) {
      await service.getData(key);
    }
  }
}

class WarmupTask {
  final WarmupType type;
  final String description;
  final Map<String, dynamic> data;
  
  WarmupTask({
    required this.type,
    required this.description,
    required this.data,
  });
}

enum WarmupType { llm, tool, data }
```

### Scheduled Cache Warmup

```dart
class ScheduledCacheWarmer {
  final CacheWarmer _warmer = CacheWarmer();
  Timer? _warmupTimer;
  
  void startScheduledWarmup({
    Duration interval = const Duration(hours: 6),
  }) {
    _setupWarmupTasks();
    
    _warmupTimer = Timer.periodic(interval, (_) async {
      await _warmer.warmCaches();
    });
    
    // Initial warmup
    _warmer.warmCaches();
  }
  
  void _setupWarmupTasks() {
    // Warm common LLM queries
    _warmer.addWarmupTask(WarmupTask(
      type: WarmupType.llm,
      description: 'Common LLM queries',
      data: {
        'llm_id': 'openai',
        'prompts': [
          'What is the weather like today?',
          'Summarize this document',
          'Translate this text',
        ],
      },
    ));
    
    // Warm frequent tool calls
    _warmer.addWarmupTask(WarmupTask(
      type: WarmupType.tool,
      description: 'Weather tool',
      data: {
        'client_id': 'weather_client',
        'tool_name': 'get_weather',
        'arguments': [
          {'location': 'New York'},
          {'location': 'London'},
          {'location': 'Tokyo'},
        ],
      },
    ));
  }
  
  void stopScheduledWarmup() {
    _warmupTimer?.cancel();
    _warmupTimer = null;
  }
}
```

## Cache Invalidation Strategies

### Smart Cache Invalidation

```dart
class SmartCacheInvalidator {
  final ResponseCache _cache = ResponseCache.instance;
  final Map<String, Set<String>> _dependencies = {};
  
  void addDependency(String cacheKey, String dependsOn) {
    _dependencies.putIfAbsent(dependsOn, () => <String>{}).add(cacheKey);
  }
  
  Future<void> invalidate(String key) async {
    // Remove the key itself
    await _cache.remove(key);
    
    // Remove all dependent keys
    final dependents = _dependencies[key];
    if (dependents != null) {
      for (final dependent in dependents) {
        await _cache.remove(dependent);
        print('Invalidated dependent cache key: $dependent');
      }
      
      _dependencies.remove(key);
    }
  }
  
  Future<void> invalidateByPattern(String pattern) async {
    await _cache.removeByPattern(pattern);
  }
  
  Future<void> invalidateByTag(String tag) async {
    await _cache.removeByTag(tag);
  }
}
```

### Time-Based Invalidation

```dart
class TimeBasedCacheManager {
  final ResponseCache _cache = ResponseCache.instance;
  final Map<String, CacheEntry> _metadata = {};
  Timer? _cleanupTimer;
  
  void startCleanup({Duration interval = const Duration(minutes: 5)}) {
    _cleanupTimer = Timer.periodic(interval, (_) async {
      await _performCleanup();
    });
  }
  
  Future<void> putWithMetadata(
    String key,
    dynamic value, {
    Duration? ttl,
    List<String>? tags,
    DateTime? invalidateAfter,
  }) async {
    await _cache.put(key, value, ttl);
    
    _metadata[key] = CacheEntry(
      key: key,
      createdAt: DateTime.now(),
      ttl: ttl,
      tags: tags ?? [],
      invalidateAfter: invalidateAfter,
    );
  }
  
  Future<void> _performCleanup() async {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    
    for (final entry in _metadata.entries) {
      final metadata = entry.value;
      
      // Check if TTL expired
      if (metadata.ttl != null) {
        final expiry = metadata.createdAt.add(metadata.ttl!);
        if (now.isAfter(expiry)) {
          keysToRemove.add(entry.key);
          continue;
        }
      }
      
      // Check custom invalidation time
      if (metadata.invalidateAfter != null && 
          now.isAfter(metadata.invalidateAfter!)) {
        keysToRemove.add(entry.key);
      }
    }
    
    // Remove expired entries
    for (final key in keysToRemove) {
      await _cache.remove(key);
      _metadata.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      print('Cleaned up ${keysToRemove.length} expired cache entries');
    }
  }
  
  void dispose() {
    _cleanupTimer?.cancel();
  }
}

class CacheEntry {
  final String key;
  final DateTime createdAt;
  final Duration? ttl;
  final List<String> tags;
  final DateTime? invalidateAfter;
  
  CacheEntry({
    required this.key,
    required this.createdAt,
    this.ttl,
    this.tags = const [],
    this.invalidateAfter,
  });
}
```

## Cache Performance Monitoring

### Cache Metrics

```dart
class CacheMetrics {
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  Duration _totalRetrievalTime = Duration.zero;
  final List<CacheOperation> _recentOperations = [];
  
  void recordHit(Duration retrievalTime) {
    _hits++;
    _totalRetrievalTime += retrievalTime;
    _recordOperation(CacheOperation.hit, retrievalTime);
  }
  
  void recordMiss(Duration retrievalTime) {
    _misses++;
    _totalRetrievalTime += retrievalTime;
    _recordOperation(CacheOperation.miss, retrievalTime);
  }
  
  void recordEviction() {
    _evictions++;
    _recordOperation(CacheOperation.eviction, Duration.zero);
  }
  
  void _recordOperation(CacheOperation operation, Duration duration) {
    _recentOperations.add(CacheOperationRecord(
      operation: operation,
      timestamp: DateTime.now(),
      duration: duration,
    ));
    
    // Keep only recent operations
    if (_recentOperations.length > 1000) {
      _recentOperations.removeAt(0);
    }
  }
  
  double get hitRate => _totalRequests > 0 ? _hits / _totalRequests : 0.0;
  double get missRate => _totalRequests > 0 ? _misses / _totalRequests : 0.0;
  int get totalRequests => _hits + _misses;
  Duration get averageRetrievalTime => 
    _totalRequests > 0 ? _totalRetrievalTime ~/ _totalRequests : Duration.zero;
  
  Map<String, dynamic> toJson() => {
    'hits': _hits,
    'misses': _misses,
    'evictions': _evictions,
    'hit_rate': hitRate,
    'miss_rate': missRate,
    'total_requests': totalRequests,
    'average_retrieval_time_ms': averageRetrievalTime.inMilliseconds,
  };
  
  void reset() {
    _hits = 0;
    _misses = 0;
    _evictions = 0;
    _totalRetrievalTime = Duration.zero;
    _recentOperations.clear();
  }
}

enum CacheOperation { hit, miss, eviction }

class CacheOperationRecord {
  final CacheOperation operation;
  final DateTime timestamp;
  final Duration duration;
  
  CacheOperationRecord({
    required this.operation,
    required this.timestamp,
    required this.duration,
  });
}
```

### Cache Dashboard

```dart
class CacheDashboard extends StatefulWidget {
  @override
  _CacheDashboardState createState() => _CacheDashboardState();
}

class _CacheDashboardState extends State<CacheDashboard> {
  Timer? _refreshTimer;
  Map<String, CacheMetrics> _cacheMetrics = {};
  
  @override
  void initState() {
    super.initState();
    _loadMetrics();
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _loadMetrics();
    });
  }
  
  void _loadMetrics() {
    setState(() {
      _cacheMetrics = {
        'SemanticCache': SemanticCache.instance.metrics,
        'ResponseCache': ResponseCache.instance.metrics,
        'LLMCache': LLMResponseCache().metrics,
      };
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Cache Performance Dashboard',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.5,
            ),
            itemCount: _cacheMetrics.length,
            itemBuilder: (context, index) {
              final entry = _cacheMetrics.entries.elementAt(index);
              return _buildCacheCard(entry.key, entry.value);
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildCacheCard(String cacheName, CacheMetrics metrics) {
    final hitRate = metrics.hitRate * 100;
    final color = hitRate > 80 ? Colors.green : 
                  hitRate > 60 ? Colors.orange : Colors.red;
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cacheName,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.assessment, color: color, size: 20),
                SizedBox(width: 8),
                Text('Hit Rate: ${hitRate.toStringAsFixed(1)}%'),
              ],
            ),
            Text('Requests: ${metrics.totalRequests}'),
            Text('Avg Time: ${metrics.averageRetrievalTime.inMilliseconds}ms'),
            if (metrics.totalRequests > 0)
              LinearProgressIndicator(
                value: metrics.hitRate,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation(color),
              ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
```

## Best Practices

### 1. Cache Key Design

```dart
class CacheKeyBuilder {
  static String buildUserKey(String userId, String dataType) {
    return 'user:$userId:$dataType';
  }
  
  static String buildLLMKey(String llmId, String prompt, QueryOptions? options) {
    final optionsHash = options != null 
      ? sha256.convert(utf8.encode(jsonEncode(options.toJson()))).toString().substring(0, 8)
      : 'default';
    final promptHash = sha256.convert(utf8.encode(prompt)).toString().substring(0, 16);
    return 'llm:$llmId:$optionsHash:$promptHash';
  }
  
  static String buildToolKey(String clientId, String toolName, Map<String, dynamic> args) {
    final argsHash = sha256.convert(utf8.encode(jsonEncode(args))).toString().substring(0, 12);
    return 'tool:$clientId:$toolName:$argsHash';
  }
}
```

### 2. Cache Size Management

```dart
class AdaptiveCacheManager {
  final int _targetMemoryUsageMB = 100;
  final MemoryManager _memoryManager = MemoryManager.instance;
  
  Future<void> adaptCacheSizes() async {
    final currentUsage = await _memoryManager.getCurrentMemoryUsage();
    final targetUsage = _targetMemoryUsageMB * 1024 * 1024; // Convert to bytes
    
    if (currentUsage > targetUsage * 1.2) {
      // Reduce cache sizes
      await SemanticCache.instance.reduceSize(0.5);
      await ResponseCache.instance.reduceSize(0.5);
    } else if (currentUsage < targetUsage * 0.8) {
      // Can increase cache sizes
      await SemanticCache.instance.increaseSize(1.2);
      await ResponseCache.instance.increaseSize(1.2);
    }
  }
}
```

### 3. Cache Testing

```dart
void main() {
  group('Cache Tests', () {
    test('LLM response caching', () async {
      final cache = LLMResponseCache();
      
      // Cache a response
      final response = LLMResponse(
        text: 'Test response',
        usage: TokenUsage(totalTokens: 100),
      );
      
      await cache.cacheResponse(
        prompt: 'Test prompt',
        llmId: 'test-llm',
        response: response,
      );
      
      // Retrieve from cache
      final cached = await cache.getCachedResponse(
        prompt: 'Test prompt',
        llmId: 'test-llm',
      );
      
      expect(cached, isNotNull);
      expect(cached!.text, equals('Test response'));
    });
    
    test('Cache invalidation', () async {
      final cache = ResponseCache.instance;
      
      await cache.put('test-key', 'test-value');
      expect(await cache.get('test-key'), equals('test-value'));
      
      await cache.remove('test-key');
      expect(await cache.get('test-key'), isNull);
    });
  });
}
```

## Troubleshooting

### Common Issues

1. **Memory pressure from large caches**
   - Monitor cache sizes and implement adaptive sizing
   - Use cache eviction policies (LRU, LFU)
   - Set appropriate TTL values

2. **Cache inconsistency**
   - Implement proper invalidation strategies
   - Use versioning for cache entries
   - Consider eventual consistency requirements

3. **Poor cache hit rates**
   - Analyze access patterns
   - Adjust cache keys for better granularity
   - Review TTL settings

### Debug Cache Performance

```dart
class CacheDebugger {
  static void logCachePerformance() {
    final semanticMetrics = SemanticCache.instance.metrics;
    final responseMetrics = ResponseCache.instance.metrics;
    
    print('=== Cache Performance Report ===');
    print('Semantic Cache:');
    print('  Hit Rate: ${(semanticMetrics.hitRate * 100).toStringAsFixed(1)}%');
    print('  Total Requests: ${semanticMetrics.totalRequests}');
    
    print('Response Cache:');
    print('  Hit Rate: ${(responseMetrics.hitRate * 100).toStringAsFixed(1)}%');
    print('  Total Requests: ${responseMetrics.totalRequests}');
  }
}
```

## See Also

- [Performance Monitoring Guide](../guides/performance-monitoring-guide.md)
- [Memory Management](../advanced/memory-management.md)
- [API Reference - Cache Methods](../api/flutter-mcp-api.md#cache-methods)