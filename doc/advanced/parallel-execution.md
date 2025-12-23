# Parallel Execution Patterns Guide

Master parallel execution patterns in Flutter MCP to maximize performance and efficiently utilize system resources.

## Overview

Flutter MCP provides sophisticated parallel execution capabilities:
- **Isolate-based parallelism** for CPU-intensive tasks
- **Concurrent I/O operations** for network and file operations
- **Stream-based parallel processing** for real-time data
- **Fork-join patterns** for divide-and-conquer algorithms
- **Pipeline parallelism** for multi-stage processing

## Built-in Parallel Execution

### IsolatePool for CPU-Intensive Tasks

```dart
// Initialize isolate pool
final isolatePool = IsolatePool.instance;
await isolatePool.initialize(maxIsolates: Platform.numberOfProcessors);

// Execute CPU-intensive work in parallel
final futures = data.map((item) async {
  return await isolatePool.execute(() {
    // CPU-intensive processing
    return complexCalculation(item);
  });
}).toList();

final results = await Future.wait(futures);
```

### Parallel LLM Queries

```dart
// Query multiple LLMs simultaneously
final responses = await FlutterMCP.instance.executeParallelQuery(
  llmIds: ['openai', 'anthropic', 'google'],
  prompt: 'Analyze this business proposal',
  options: QueryOptions(temperature: 0.7),
);

// Process responses in parallel
final analyses = await Future.wait(
  responses.map((response) async {
    return await processAnalysis(response);
  }),
);
```

## Advanced Parallel Patterns

### Fork-Join Pattern

```dart
class ForkJoinProcessor<T, R> {
  final IsolatePool _isolatePool = IsolatePool.instance;
  final int _threshold;
  
  ForkJoinProcessor({int threshold = 1000}) : _threshold = threshold;
  
  Future<R> process(
    List<T> data,
    R Function(List<T>) sequentialProcessor,
    R Function(R, R) combiner,
  ) async {
    if (data.length <= _threshold) {
      // Process sequentially for small datasets
      return await _isolatePool.execute(() => sequentialProcessor(data));
    }
    
    // Fork: Split data into chunks
    final mid = data.length ~/ 2;
    final leftChunk = data.sublist(0, mid);
    final rightChunk = data.sublist(mid);
    
    // Process chunks in parallel
    final futures = await Future.wait([
      process(leftChunk, sequentialProcessor, combiner),
      process(rightChunk, sequentialProcessor, combiner),
    ]);
    
    // Join: Combine results
    return combiner(futures[0], futures[1]);
  }
}

// Example usage: Parallel sum calculation
class ParallelMathProcessor {
  final _forkJoin = ForkJoinProcessor<int, int>(threshold: 10000);
  
  Future<int> parallelSum(List<int> numbers) async {
    return await _forkJoin.process(
      numbers,
      (chunk) => chunk.fold(0, (a, b) => a + b), // Sequential sum
      (left, right) => left + right,              // Combine results
    );
  }
  
  Future<int> parallelMax(List<int> numbers) async {
    return await _forkJoin.process(
      numbers,
      (chunk) => chunk.reduce(math.max),          // Sequential max
      (left, right) => math.max(left, right),    // Combine results
    );
  }
}
```

### Producer-Consumer Pattern

```dart
class ProducerConsumerPipeline<T> {
  final StreamController<T> _inputController = StreamController<T>();
  final StreamController<T> _outputController = StreamController<T>();
  final int _maxConcurrency;
  int _activeTasks = 0;
  
  ProducerConsumerPipeline({int maxConcurrency = 10}) 
    : _maxConcurrency = maxConcurrency {
    _setupPipeline();
  }
  
  void _setupPipeline() {
    _inputController.stream.listen((data) async {
      // Wait if too many tasks are active
      while (_activeTasks >= _maxConcurrency) {
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      _activeTasks++;
      
      // Process data in parallel
      _processItem(data).then((result) {
        _outputController.add(result);
        _activeTasks--;
      }).catchError((error) {
        print('Processing error: $error');
        _activeTasks--;
      });
    });
  }
  
  Future<T> _processItem(T data) async {
    // Override this method for specific processing
    await Future.delayed(Duration(milliseconds: 100));
    return data;
  }
  
  void addData(T data) {
    _inputController.add(data);
  }
  
  Stream<T> get results => _outputController.stream;
  
  void dispose() {
    _inputController.close();
    _outputController.close();
  }
}

// Example: Parallel image processing
class ParallelImageProcessor extends ProducerConsumerPipeline<ImageData> {
  ParallelImageProcessor() : super(maxConcurrency: 4);
  
  @override
  Future<ImageData> _processItem(ImageData imageData) async {
    return await IsolatePool.instance.execute(() {
      // CPU-intensive image processing
      return processImage(imageData);
    });
  }
}
```

### Pipeline Parallelism

```dart
class ParallelPipeline<T> {
  final List<PipelineStage<dynamic, dynamic>> _stages = [];
  final int _maxConcurrency;
  
  ParallelPipeline({int maxConcurrency = 5}) : _maxConcurrency = maxConcurrency;
  
  void addStage<I, O>(Future<O> Function(I) processor) {
    _stages.add(PipelineStage<I, O>(processor));
  }
  
  Stream<dynamic> process(Stream<T> input) async* {
    Stream<dynamic> current = input;
    
    // Process through each stage
    for (final stage in _stages) {
      current = current.asyncMap((data) async {
        return await stage.process(data);
      });
      
      // Add parallelism to each stage
      current = _addParallelism(current);
    }
    
    yield* current;
  }
  
  Stream<dynamic> _addParallelism(Stream<dynamic> input) {
    final controller = StreamController<dynamic>();
    final activeTasks = <Future<void>>[];
    
    input.listen(
      (data) async {
        // Limit concurrent tasks
        if (activeTasks.length >= _maxConcurrency) {
          await Future.any(activeTasks);
          activeTasks.removeWhere((future) => future.isCompleted);
        }
        
        final task = Future(() async {
          controller.add(data);
        });
        
        activeTasks.add(task);
      },
      onDone: () async {
        // Wait for all remaining tasks
        await Future.wait(activeTasks);
        controller.close();
      },
      onError: (error) => controller.addError(error),
    );
    
    return controller.stream;
  }
}

class PipelineStage<I, O> {
  final Future<O> Function(I) _processor;
  
  PipelineStage(this._processor);
  
  Future<O> process(I input) async {
    return await _processor(input);
  }
}

// Example: Document processing pipeline
class DocumentProcessingPipeline {
  final ParallelPipeline<String> _pipeline = ParallelPipeline<String>();
  
  DocumentProcessingPipeline() {
    _setupPipeline();
  }
  
  void _setupPipeline() {
    // Stage 1: Parse document
    _pipeline.addStage<String, Document>((text) async {
      return await parseDocument(text);
    });
    
    // Stage 2: Extract entities
    _pipeline.addStage<Document, DocumentWithEntities>((doc) async {
      return await extractEntities(doc);
    });
    
    // Stage 3: Generate summary
    _pipeline.addStage<DocumentWithEntities, ProcessedDocument>((doc) async {
      return await generateSummary(doc);
    });
    
    // Stage 4: Store results
    _pipeline.addStage<ProcessedDocument, String>((doc) async {
      await storeDocument(doc);
      return doc.id;
    });
  }
  
  Stream<String> processDocuments(Stream<String> documents) {
    return _pipeline.process(documents).cast<String>();
  }
}
```

## Parallel MCP Operations

### Parallel Tool Execution

```dart
class ParallelMCPTools {
  Future<Map<String, dynamic>> executeToolsInParallel({
    required String clientId,
    required Map<String, Map<String, dynamic>> toolCalls,
  }) async {
    final futures = toolCalls.entries.map((entry) async {
      final toolName = entry.key;
      final arguments = entry.value;
      
      try {
        final result = await FlutterMCP.instance.clientManager.callTool(
          clientId,
          toolName,
          arguments,
        );
        return MapEntry(toolName, {'success': true, 'result': result});
      } catch (e) {
        return MapEntry(toolName, {'success': false, 'error': e.toString()});
      }
    });
    
    final results = await Future.wait(futures);
    return Map.fromEntries(results);
  }
  
  Future<List<dynamic>> batchToolExecution({
    required String clientId,
    required String toolName,
    required List<Map<String, dynamic>> argumentsList,
    int maxConcurrency = 10,
  }) async {
    final semaphore = Semaphore(maxConcurrency);
    
    final futures = argumentsList.map((arguments) async {
      await semaphore.acquire();
      
      try {
        return await FlutterMCP.instance.clientManager.callTool(
          clientId,
          toolName,
          arguments,
        );
      } finally {
        semaphore.release();
      }
    });
    
    return await Future.wait(futures);
  }
}

class Semaphore {
  final int _maxCount;
  int _currentCount = 0;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();
  
  Semaphore(this._maxCount);
  
  Future<void> acquire() async {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return;
    }
    
    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }
  
  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount--;
    }
  }
}
```

### Parallel Server Management

```dart
class ParallelServerManager {
  Future<Map<String, bool>> startServersInParallel(List<String> serverIds) async {
    final futures = serverIds.map((serverId) async {
      try {
        await FlutterMCP.instance.serverManager.startServer(serverId);
        return MapEntry(serverId, true);
      } catch (e) {
        print('Failed to start server $serverId: $e');
        return MapEntry(serverId, false);
      }
    });
    
    final results = await Future.wait(futures);
    return Map.fromEntries(results);
  }
  
  Future<void> gracefulParallelShutdown(List<String> serverIds) async {
    // Start shutdown for all servers in parallel
    final shutdownFutures = serverIds.map((serverId) async {
      try {
        await FlutterMCP.instance.serverManager.stopServer(serverId);
        print('Server $serverId stopped successfully');
      } catch (e) {
        print('Error stopping server $serverId: $e');
      }
    });
    
    // Wait for all to complete with timeout
    try {
      await Future.wait(shutdownFutures).timeout(Duration(seconds: 30));
    } catch (e) {
      print('Timeout during parallel shutdown: $e');
    }
  }
}
```

## Stream-Based Parallel Processing

### Parallel Stream Transformer

```dart
class ParallelStreamTransformer<S, T> extends StreamTransformerBase<S, T> {
  final Future<T> Function(S) _transformer;
  final int _maxConcurrency;
  
  ParallelStreamTransformer(this._transformer, {int maxConcurrency = 10})
    : _maxConcurrency = maxConcurrency;
  
  @override
  Stream<T> bind(Stream<S> stream) {
    final controller = StreamController<T>();
    final activeTasks = <Future<void>>[];
    
    stream.listen(
      (data) async {
        // Wait if too many tasks are active
        while (activeTasks.length >= _maxConcurrency) {
          await Future.any(activeTasks);
          activeTasks.removeWhere((future) => future.isCompleted);
        }
        
        final task = _transformer(data).then((result) {
          controller.add(result);
        }).catchError((error) {
          controller.addError(error);
        });
        
        activeTasks.add(task);
      },
      onDone: () async {
        // Wait for all remaining tasks
        await Future.wait(activeTasks);
        controller.close();
      },
      onError: (error) => controller.addError(error),
    );
    
    return controller.stream;
  }
}

// Example usage
extension ParallelStreamExtension<T> on Stream<T> {
  Stream<R> parallelMap<R>(
    Future<R> Function(T) mapper, {
    int maxConcurrency = 10,
  }) {
    return transform(ParallelStreamTransformer(mapper, maxConcurrency: maxConcurrency));
  }
}

// Usage example
final stream = Stream.fromIterable([1, 2, 3, 4, 5]);
final processedStream = stream.parallelMap(
  (number) async {
    // Simulate async processing
    await Future.delayed(Duration(milliseconds: 100));
    return number * 2;
  },
  maxConcurrency: 3,
);
```

### Real-time Parallel Processing

```dart
class RealTimeParallelProcessor<T> {
  final StreamController<T> _inputController = StreamController<T>.broadcast();
  final StreamController<ProcessedResult<T>> _outputController = 
    StreamController<ProcessedResult<T>>.broadcast();
  
  final Map<String, StreamSubscription> _processors = {};
  final int _maxProcessors;
  
  RealTimeParallelProcessor({int maxProcessors = 5}) 
    : _maxProcessors = maxProcessors {
    _setupProcessing();
  }
  
  void _setupProcessing() {
    // Create multiple parallel processors
    for (int i = 0; i < _maxProcessors; i++) {
      final processorId = 'processor_$i';
      
      _processors[processorId] = _inputController.stream
        .where((data) => data.hashCode % _maxProcessors == i)
        .listen((data) async {
          try {
            final result = await _processData(data, processorId);
            _outputController.add(ProcessedResult(
              data: data,
              result: result,
              processorId: processorId,
              processedAt: DateTime.now(),
            ));
          } catch (e) {
            _outputController.addError(e);
          }
        });
    }
  }
  
  Future<dynamic> _processData(T data, String processorId) async {
    // Override for specific processing logic
    await Future.delayed(Duration(milliseconds: 50));
    return 'Processed by $processorId: $data';
  }
  
  void addData(T data) {
    _inputController.add(data);
  }
  
  Stream<ProcessedResult<T>> get results => _outputController.stream;
  
  void dispose() {
    _processors.values.forEach((subscription) => subscription.cancel());
    _inputController.close();
    _outputController.close();
  }
}

class ProcessedResult<T> {
  final T data;
  final dynamic result;
  final String processorId;
  final DateTime processedAt;
  
  ProcessedResult({
    required this.data,
    required this.result,
    required this.processorId,
    required this.processedAt,
  });
}
```

## Performance Optimization

### Adaptive Concurrency

```dart
class AdaptiveConcurrencyManager {
  int _currentConcurrency = 5;
  final _performanceMonitor = PerformanceMonitor();
  Timer? _adjustmentTimer;
  
  void startAdaptiveControl() {
    _adjustmentTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _adjustConcurrency();
    });
  }
  
  void _adjustConcurrency() {
    final stats = _performanceMonitor.getStats();
    
    // Increase concurrency if CPU usage is low and throughput is good
    if (stats.cpuUsage < 0.7 && stats.memoryUsage < 0.8 && stats.errorRate < 0.05) {
      _currentConcurrency = (_currentConcurrency * 1.2).round().clamp(1, 20);
    }
    // Decrease if system is overloaded
    else if (stats.cpuUsage > 0.9 || stats.memoryUsage > 0.9 || stats.errorRate > 0.15) {
      _currentConcurrency = (_currentConcurrency * 0.8).round().clamp(1, 20);
    }
    
    print('Adjusted concurrency to: $_currentConcurrency');
  }
  
  int get optimalConcurrency => _currentConcurrency;
  
  void dispose() {
    _adjustmentTimer?.cancel();
  }
}
```

### Work Stealing Queue

```dart
class WorkStealingExecutor<T> {
  final List<Queue<WorkItem<T>>> _queues;
  final List<Isolate> _workers = [];
  final int _numWorkers;
  int _nextQueue = 0;
  
  WorkStealingExecutor({int? numWorkers}) 
    : _numWorkers = numWorkers ?? Platform.numberOfProcessors,
      _queues = List.generate(
        numWorkers ?? Platform.numberOfProcessors, 
        (_) => Queue<WorkItem<T>>()
      );
  
  Future<void> initialize() async {
    for (int i = 0; i < _numWorkers; i++) {
      final isolate = await Isolate.spawn(_workerMain, {
        'workerId': i,
        'queues': _queues,
      });
      _workers.add(isolate);
    }
  }
  
  void submitWork(T data, Future<void> Function(T) processor) {
    final workItem = WorkItem(data, processor);
    
    // Add to next queue (round-robin)
    _queues[_nextQueue].add(workItem);
    _nextQueue = (_nextQueue + 1) % _numWorkers;
  }
  
  static void _workerMain(Map<String, dynamic> args) {
    final workerId = args['workerId'] as int;
    final queues = args['queues'] as List<Queue<WorkItem>>;
    final myQueue = queues[workerId];
    
    while (true) {
      WorkItem? work;
      
      // Try to get work from own queue
      if (myQueue.isNotEmpty) {
        work = myQueue.removeFirst();
      } else {
        // Steal work from other queues
        for (int i = 0; i < queues.length; i++) {
          if (i != workerId && queues[i].isNotEmpty) {
            work = queues[i].removeFirst();
            break;
          }
        }
      }
      
      if (work != null) {
        try {
          work.execute();
        } catch (e) {
          print('Worker $workerId error: $e');
        }
      } else {
        // No work available, sleep briefly
        sleep(Duration(milliseconds: 10));
      }
    }
  }
  
  void dispose() {
    _workers.forEach((isolate) => isolate.kill());
  }
}

class WorkItem<T> {
  final T data;
  final Future<void> Function(T) processor;
  
  WorkItem(this.data, this.processor);
  
  Future<void> execute() async {
    await processor(data);
  }
}
```

## Error Handling in Parallel Execution

### Resilient Parallel Execution

```dart
class ResilientParallelExecutor<T, R> {
  final int _maxRetries;
  final Duration _retryDelay;
  
  ResilientParallelExecutor({
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 1),
  }) : _maxRetries = maxRetries,
       _retryDelay = retryDelay;
  
  Future<List<ParallelResult<R>>> executeWithResilience(
    List<T> inputs,
    Future<R> Function(T) processor, {
    int maxConcurrency = 10,
  }) async {
    final semaphore = Semaphore(maxConcurrency);
    
    final futures = inputs.map((input) async {
      await semaphore.acquire();
      
      try {
        final result = await _executeWithRetry(input, processor);
        return ParallelResult<R>.success(input, result);
      } catch (e) {
        return ParallelResult<R>.failure(input, e);
      } finally {
        semaphore.release();
      }
    });
    
    return await Future.wait(futures);
  }
  
  Future<R> _executeWithRetry(T input, Future<R> Function(T) processor) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await processor(input);
      } catch (e) {
        if (attempt == _maxRetries) {
          rethrow;
        }
        
        print('Attempt ${attempt + 1} failed for $input: $e');
        await Future.delayed(_retryDelay * (attempt + 1));
      }
    }
    
    throw StateError('Should not reach here');
  }
}

class ParallelResult<R> {
  final dynamic input;
  final R? result;
  final dynamic error;
  final bool isSuccess;
  
  ParallelResult.success(this.input, this.result) 
    : error = null, isSuccess = true;
  
  ParallelResult.failure(this.input, this.error) 
    : result = null, isSuccess = false;
}
```

### Circuit Breaker Integration

```dart
class ParallelCircuitBreakerExecutor<T, R> {
  final Map<String, CircuitBreaker> _breakers = {};
  final Duration _breakerResetTimeout;
  final int _failureThreshold;
  
  ParallelCircuitBreakerExecutor({
    Duration resetTimeout = const Duration(minutes: 1),
    int failureThreshold = 5,
  }) : _breakerResetTimeout = resetTimeout,
       _failureThreshold = failureThreshold;
  
  Future<List<R?>> executeWithCircuitBreaker(
    List<T> inputs,
    Future<R> Function(T) processor,
    String Function(T) categoryExtractor, {
    int maxConcurrency = 10,
  }) async {
    final semaphore = Semaphore(maxConcurrency);
    
    final futures = inputs.map((input) async {
      await semaphore.acquire();
      
      try {
        final category = categoryExtractor(input);
        final breaker = _getOrCreateBreaker(category);
        
        return await breaker.execute(() => processor(input));
      } catch (e) {
        print('Failed to process $input: $e');
        return null;
      } finally {
        semaphore.release();
      }
    });
    
    return await Future.wait(futures);
  }
  
  CircuitBreaker _getOrCreateBreaker(String category) {
    return _breakers.putIfAbsent(category, () => CircuitBreaker(
      failureThreshold: _failureThreshold,
      resetTimeout: _breakerResetTimeout,
    ));
  }
}
```

## Monitoring and Observability

### Parallel Execution Metrics

```dart
class ParallelExecutionMetrics {
  final Map<String, ExecutionStats> _stats = {};
  final _lock = Mutex();
  
  Future<void> recordExecution(
    String operationType,
    Duration duration,
    bool success,
  ) async {
    await _lock.acquire();
    
    try {
      final stats = _stats.putIfAbsent(
        operationType, 
        () => ExecutionStats(operationType)
      );
      
      stats.recordExecution(duration, success);
    } finally {
      _lock.release();
    }
  }
  
  Map<String, ExecutionStats> getStats() {
    return Map.unmodifiable(_stats);
  }
  
  void reset() {
    _stats.clear();
  }
}

class ExecutionStats {
  final String operationType;
  int totalExecutions = 0;
  int successfulExecutions = 0;
  Duration totalDuration = Duration.zero;
  Duration minDuration = Duration(days: 1);
  Duration maxDuration = Duration.zero;
  
  ExecutionStats(this.operationType);
  
  void recordExecution(Duration duration, bool success) {
    totalExecutions++;
    if (success) successfulExecutions++;
    
    totalDuration += duration;
    if (duration < minDuration) minDuration = duration;
    if (duration > maxDuration) maxDuration = duration;
  }
  
  double get successRate => totalExecutions > 0 
    ? successfulExecutions / totalExecutions 
    : 0.0;
  
  Duration get averageDuration => totalExecutions > 0 
    ? totalDuration ~/ totalExecutions 
    : Duration.zero;
  
  Map<String, dynamic> toJson() => {
    'operation_type': operationType,
    'total_executions': totalExecutions,
    'successful_executions': successfulExecutions,
    'success_rate': successRate,
    'average_duration_ms': averageDuration.inMilliseconds,
    'min_duration_ms': minDuration.inMilliseconds,
    'max_duration_ms': maxDuration.inMilliseconds,
  };
}

class Mutex {
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();
  bool _isLocked = false;
  
  Future<void> acquire() async {
    if (!_isLocked) {
      _isLocked = true;
      return;
    }
    
    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }
  
  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _isLocked = false;
    }
  }
}
```

## Best Practices

### 1. Choose Right Parallelism Level

```dart
class ParallelismOptimizer {
  static int calculateOptimalConcurrency({
    required TaskType taskType,
    required int dataSize,
  }) {
    switch (taskType) {
      case TaskType.cpuBound:
        return Platform.numberOfProcessors;
      
      case TaskType.ioBound:
        return Platform.numberOfProcessors * 2;
      
      case TaskType.network:
        // Higher concurrency for network calls
        return math.min(20, dataSize ~/ 10);
      
      case TaskType.mixed:
        return Platform.numberOfProcessors + 2;
    }
  }
}

enum TaskType { cpuBound, ioBound, network, mixed }
```

### 2. Memory-Aware Parallel Execution

```dart
class MemoryAwareParallelExecutor<T, R> {
  final MemoryManager _memoryManager = MemoryManager.instance;
  
  Future<List<R>> execute(
    List<T> inputs,
    Future<R> Function(T) processor,
  ) async {
    final chunkSize = await _calculateOptimalChunkSize(inputs.length);
    final results = <R>[];
    
    for (int i = 0; i < inputs.length; i += chunkSize) {
      final chunk = inputs.skip(i).take(chunkSize).toList();
      
      // Check memory pressure before processing chunk
      final memoryPressure = await _memoryManager.getMemoryPressure();
      if (memoryPressure > 0.8) {
        await _memoryManager.performCleanup();
        await Future.delayed(Duration(seconds: 1));
      }
      
      // Process chunk in parallel
      final chunkFutures = chunk.map(processor);
      final chunkResults = await Future.wait(chunkFutures);
      results.addAll(chunkResults);
    }
    
    return results;
  }
  
  Future<int> _calculateOptimalChunkSize(int totalItems) async {
    final memoryStats = await _memoryManager.getMemoryStats();
    final availableMemory = memoryStats.available;
    
    // Adjust chunk size based on available memory
    if (availableMemory > 1024 * 1024 * 1024) { // > 1GB
      return math.min(100, totalItems);
    } else if (availableMemory > 512 * 1024 * 1024) { // > 512MB
      return math.min(50, totalItems);
    } else {
      return math.min(20, totalItems);
    }
  }
}
```

### 3. Testing Parallel Code

```dart
void main() {
  group('Parallel Execution Tests', () {
    test('Fork-join pattern', () async {
      final processor = ForkJoinProcessor<int, int>();
      final data = List.generate(1000, (i) => i);
      
      final result = await processor.process(
        data,
        (chunk) => chunk.fold(0, (a, b) => a + b),
        (left, right) => left + right,
      );
      
      final expected = data.fold(0, (a, b) => a + b);
      expect(result, equals(expected));
    });
    
    test('Producer-consumer pipeline', () async {
      final pipeline = ProducerConsumerPipeline<int>();
      final results = <int>[];
      
      pipeline.results.listen((result) {
        results.add(result);
      });
      
      // Add test data
      for (int i = 0; i < 10; i++) {
        pipeline.addData(i);
      }
      
      // Wait for processing
      await Future.delayed(Duration(seconds: 2));
      
      expect(results.length, equals(10));
    });
  });
}
```

## Common Patterns Summary

### 1. Data Parallelism
- Split data across multiple workers
- Each worker processes a subset
- Combine results at the end

### 2. Task Parallelism
- Different tasks run concurrently
- Tasks may have dependencies
- Coordination through futures/streams

### 3. Pipeline Parallelism
- Multi-stage processing
- Each stage runs concurrently
- Data flows through pipeline

### 4. Event-Driven Parallelism
- React to events as they occur
- Multiple event handlers run in parallel
- Suitable for real-time systems

## See Also

- [Batch Processing Guide](batch-processing.md)
- [Performance Monitoring](../guides/performance-monitoring-guide.md)
- [Circuit Breaker Guide](circuit-breaker.md)
- [API Reference - Parallel Methods](../api/flutter-mcp-api.md#advanced-query-methods)