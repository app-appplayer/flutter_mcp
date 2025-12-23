# Batch Processing Guide

Learn how to efficiently process large volumes of data using Flutter MCP's batch processing capabilities.

## Overview

Flutter MCP provides powerful batch processing features:
- Generic batch processing with load balancing
- Parallel query execution across multiple LLMs
- Fan-out pattern for distributed processing
- Automatic error handling and retries
- Progress tracking and statistics

## Basic Batch Processing

### Simple Batch Operation

```dart
// Define batch items
final items = List.generate(100, (i) => BatchItem(
  id: 'item_$i',
  data: {'value': i, 'type': 'process'},
));

// Process batch with automatic load balancing
final results = await FlutterMCP.instance.processBatch<String>(
  items: items,
  processor: (BatchItem item) async {
    // Simulate processing
    await Future.delayed(Duration(milliseconds: 100));
    
    // Process the item
    final value = item.data['value'] as int;
    return 'Processed: $value';
  },
  maxConcurrency: 5, // Process 5 items simultaneously
  continueOnError: true, // Continue even if some items fail
);

print('Processed ${results.length} items');
```

### Batch Processing with Progress Tracking

```dart
class BatchProcessor {
  final _progressController = StreamController<double>();
  Stream<double> get progress => _progressController.stream;
  
  Future<List<ProcessedData>> processBatchWithProgress(
    List<RawData> rawDataList,
  ) async {
    final items = rawDataList.map((data) => BatchItem(
      id: data.id,
      data: data,
    )).toList();
    
    int processed = 0;
    final totalItems = items.length;
    
    final results = await FlutterMCP.instance.processBatch<ProcessedData>(
      items: items,
      processor: (BatchItem item) async {
        try {
          // Process individual item
          final result = await _processData(item.data as RawData);
          
          // Update progress
          processed++;
          _progressController.add(processed / totalItems);
          
          return result;
        } catch (e) {
          // Log error but continue
          print('Error processing ${item.id}: $e');
          throw e;
        }
      },
      maxConcurrency: 10,
      continueOnError: true,
    );
    
    _progressController.close();
    return results.whereType<ProcessedData>().toList();
  }
  
  Future<ProcessedData> _processData(RawData data) async {
    // Actual processing logic
    return ProcessedData(
      id: data.id,
      processedValue: data.value * 2,
      timestamp: DateTime.now(),
    );
  }
}
```

## Parallel LLM Queries

### Execute Queries Across Multiple LLMs

```dart
// Query multiple LLMs simultaneously
final responses = await FlutterMCP.instance.executeParallelQuery(
  llmIds: ['openai', 'anthropic', 'google'],
  prompt: 'Explain quantum computing in simple terms',
  options: QueryOptions(
    temperature: 0.7,
    maxTokens: 200,
  ),
  timeout: Duration(seconds: 30),
);

// Process responses
for (final response in responses) {
  print('Response from LLM: ${response.text}');
  print('Tokens used: ${response.usage?.totalTokens}');
}
```

### Fan-Out Pattern

```dart
class FanOutProcessor {
  Future<Map<String, dynamic>> processWithFanOut(String query) async {
    // Fan out query to all available LLMs
    final results = await FlutterMCP.instance.fanOutQuery(
      prompt: query,
      options: QueryOptions(
        temperature: 0.5,
        maxTokens: 500,
      ),
      includeFailures: true, // Include failed responses
    );
    
    // Aggregate results
    final aggregated = <String, dynamic>{};
    
    results.forEach((llmId, response) {
      if (response.error != null) {
        aggregated[llmId] = {
          'success': false,
          'error': response.error.toString(),
        };
      } else {
        aggregated[llmId] = {
          'success': true,
          'response': response.text,
          'confidence': response.metadata?['confidence'] ?? 0.0,
        };
      }
    });
    
    return aggregated;
  }
  
  // Select best response based on criteria
  String? selectBestResponse(Map<String, dynamic> results) {
    String? bestResponse;
    double highestConfidence = 0.0;
    
    results.forEach((llmId, data) {
      if (data['success'] == true) {
        final confidence = data['confidence'] as double;
        if (confidence > highestConfidence) {
          highestConfidence = confidence;
          bestResponse = data['response'] as String;
        }
      }
    });
    
    return bestResponse;
  }
}
```

## Advanced Batch Patterns

### Chunked Processing

```dart
class ChunkedBatchProcessor {
  static const int CHUNK_SIZE = 50;
  
  Future<void> processLargeDataset(List<String> documents) async {
    // Process documents in chunks for memory efficiency
    await FlutterMCP.instance.processDocumentsInChunks(
      documents: documents,
      chunkSize: CHUNK_SIZE,
      processor: (List<String> chunk) async {
        // Process each chunk
        for (final doc in chunk) {
          await _processDocument(doc);
        }
        
        // Optional: Force garbage collection between chunks
        if (chunk.length == CHUNK_SIZE) {
          await Future.delayed(Duration(milliseconds: 100));
        }
      },
    );
  }
  
  Future<void> _processDocument(String document) async {
    // Generate embeddings
    final embeddings = await FlutterMCP.instance.generateEmbeddings(document);
    
    // Store in vector database
    await FlutterMCP.instance.addDocument(
      content: document,
      metadata: {
        'embeddings': embeddings,
        'processed_at': DateTime.now().toIso8601String(),
      },
    );
  }
}
```

### Pipeline Processing

```dart
class BatchPipeline {
  Future<List<FinalResult>> runPipeline(List<InputData> inputs) async {
    // Stage 1: Validation
    final validated = await _validateBatch(inputs);
    
    // Stage 2: Enrichment
    final enriched = await _enrichBatch(validated);
    
    // Stage 3: Processing
    final processed = await _processBatch(enriched);
    
    // Stage 4: Post-processing
    final results = await _postProcessBatch(processed);
    
    return results;
  }
  
  Future<List<ValidatedData>> _validateBatch(List<InputData> inputs) async {
    return await FlutterMCP.instance.processBatch<ValidatedData>(
      items: inputs.map((input) => BatchItem(
        id: input.id,
        data: input,
      )).toList(),
      processor: (item) async {
        final input = item.data as InputData;
        if (!_isValid(input)) {
          throw ValidationException('Invalid input: ${input.id}');
        }
        return ValidatedData.from(input);
      },
      maxConcurrency: 20, // Validation is fast, use more concurrency
      continueOnError: false, // Stop on validation errors
    );
  }
  
  Future<List<EnrichedData>> _enrichBatch(List<ValidatedData> validated) async {
    return await FlutterMCP.instance.processBatch<EnrichedData>(
      items: validated.map((v) => BatchItem(id: v.id, data: v)).toList(),
      processor: (item) async {
        final data = item.data as ValidatedData;
        
        // Enrich with external data
        final enrichment = await _fetchEnrichmentData(data.id);
        
        return EnrichedData(
          originalData: data,
          enrichment: enrichment,
        );
      },
      maxConcurrency: 10, // External API calls, moderate concurrency
      continueOnError: true,
    );
  }
  
  Future<List<ProcessedData>> _processBatch(List<EnrichedData> enriched) async {
    // Heavy processing with limited concurrency
    return await FlutterMCP.instance.processBatch<ProcessedData>(
      items: enriched.map((e) => BatchItem(id: e.id, data: e)).toList(),
      processor: (item) async {
        return await _heavyProcessing(item.data as EnrichedData);
      },
      maxConcurrency: 3, // CPU-intensive, limit concurrency
      continueOnError: true,
    );
  }
  
  Future<List<FinalResult>> _postProcessBatch(List<ProcessedData> processed) async {
    // Final stage with cleanup
    return await FlutterMCP.instance.processBatch<FinalResult>(
      items: processed.map((p) => BatchItem(id: p.id, data: p)).toList(),
      processor: (item) async {
        final data = item.data as ProcessedData;
        return FinalResult(
          id: data.id,
          result: data.result,
          metadata: await _generateMetadata(data),
        );
      },
      maxConcurrency: 5,
      continueOnError: false,
    );
  }
  
  bool _isValid(InputData input) => input.value != null;
  
  Future<Map<String, dynamic>> _fetchEnrichmentData(String id) async {
    // Simulate external API call
    return {'enriched': true, 'timestamp': DateTime.now()};
  }
  
  Future<ProcessedData> _heavyProcessing(EnrichedData data) async {
    // Simulate heavy processing
    await Future.delayed(Duration(seconds: 1));
    return ProcessedData(id: data.id, result: 'processed');
  }
  
  Future<Map<String, dynamic>> _generateMetadata(ProcessedData data) async {
    return {
      'processed_at': DateTime.now().toIso8601String(),
      'version': '1.0',
    };
  }
}
```

## Error Handling in Batch Processing

### Retry Strategy

```dart
class ResilientBatchProcessor {
  Future<List<Result>> processWithRetries(List<Item> items) async {
    final results = <Result>[];
    final failed = <BatchItem>[];
    
    // First attempt
    final firstResults = await FlutterMCP.instance.processBatch<Result>(
      items: items.map((item) => BatchItem(
        id: item.id,
        data: item,
        metadata: {'attempt': 1},
      )).toList(),
      processor: (item) async {
        try {
          return await _processItem(item.data as Item);
        } catch (e) {
          // Collect failed items for retry
          failed.add(item);
          throw e;
        }
      },
      maxConcurrency: 10,
      continueOnError: true,
    );
    
    results.addAll(firstResults.whereType<Result>());
    
    // Retry failed items with exponential backoff
    for (int attempt = 2; attempt <= 3 && failed.isNotEmpty; attempt++) {
      await Future.delayed(Duration(seconds: attempt * 2));
      
      final retryItems = List<BatchItem>.from(failed);
      failed.clear();
      
      final retryResults = await FlutterMCP.instance.processBatch<Result>(
        items: retryItems.map((item) => BatchItem(
          id: item.id,
          data: item.data,
          metadata: {'attempt': attempt},
        )).toList(),
        processor: (item) async {
          try {
            return await _processItem(item.data as Item);
          } catch (e) {
            if (attempt < 3) {
              failed.add(item);
            }
            throw e;
          }
        },
        maxConcurrency: 5, // Reduce concurrency for retries
        continueOnError: true,
      );
      
      results.addAll(retryResults.whereType<Result>());
    }
    
    // Log permanently failed items
    if (failed.isNotEmpty) {
      print('Failed to process ${failed.length} items after 3 attempts');
    }
    
    return results;
  }
  
  Future<Result> _processItem(Item item) async {
    // Processing logic that might fail
    if (Random().nextDouble() < 0.1) {
      throw Exception('Random failure');
    }
    return Result(id: item.id, value: item.value * 2);
  }
}
```

## Performance Optimization

### Adaptive Concurrency

```dart
class AdaptiveBatchProcessor {
  int _optimalConcurrency = 5;
  final _performanceMonitor = EnhancedPerformanceMonitor.instance;
  
  Future<List<T>> processWithAdaptiveConcurrency<T>(
    List<BatchItem> items,
    Future<T> Function(BatchItem) processor,
  ) async {
    final stopwatch = Stopwatch()..start();
    
    // Start with conservative concurrency
    var currentConcurrency = _optimalConcurrency;
    
    // Process in batches to adjust concurrency
    final results = <T>[];
    final batchSize = 50;
    
    for (int i = 0; i < items.length; i += batchSize) {
      final batch = items.skip(i).take(batchSize).toList();
      
      final batchResults = await FlutterMCP.instance.processBatch<T>(
        items: batch,
        processor: processor,
        maxConcurrency: currentConcurrency,
        continueOnError: true,
      );
      
      results.addAll(batchResults.whereType<T>());
      
      // Adjust concurrency based on performance
      final throughput = batchResults.length / stopwatch.elapsed.inSeconds;
      final cpuUsage = await _performanceMonitor.getCpuUsage();
      final memoryUsage = await _performanceMonitor.getMemoryUsage();
      
      if (cpuUsage < 0.7 && memoryUsage < 0.8 && throughput > 0) {
        // Increase concurrency if resources available
        currentConcurrency = (currentConcurrency * 1.2).round();
      } else if (cpuUsage > 0.9 || memoryUsage > 0.9) {
        // Decrease concurrency if overloaded
        currentConcurrency = (currentConcurrency * 0.8).round();
      }
      
      // Keep within reasonable bounds
      currentConcurrency = currentConcurrency.clamp(2, 20);
    }
    
    // Remember optimal concurrency for next time
    _optimalConcurrency = currentConcurrency;
    
    return results;
  }
}
```

### Memory-Efficient Batch Processing

```dart
class MemoryEfficientProcessor {
  final _memoryManager = MemoryManager.instance;
  
  Future<void> processLargeFile(String filePath) async {
    final file = File(filePath);
    final lines = file.openRead()
      .transform(utf8.decoder)
      .transform(LineSplitter());
    
    final buffer = <String>[];
    const bufferSize = 1000;
    
    await for (final line in lines) {
      buffer.add(line);
      
      if (buffer.length >= bufferSize) {
        // Process buffer
        await _processBuffer(buffer);
        
        // Clear buffer and check memory
        buffer.clear();
        
        final memoryPressure = await _memoryManager.getMemoryPressure();
        if (memoryPressure > 0.8) {
          // High memory pressure, trigger cleanup
          await _memoryManager.performCleanup();
          await Future.delayed(Duration(seconds: 1));
        }
      }
    }
    
    // Process remaining items
    if (buffer.isNotEmpty) {
      await _processBuffer(buffer);
    }
  }
  
  Future<void> _processBuffer(List<String> buffer) async {
    final items = buffer.map((line) => BatchItem(
      id: line.hashCode.toString(),
      data: line,
    )).toList();
    
    await FlutterMCP.instance.processBatch<void>(
      items: items,
      processor: (item) async {
        // Process individual line
        await _processLine(item.data as String);
      },
      maxConcurrency: 5,
      continueOnError: true,
    );
  }
  
  Future<void> _processLine(String line) async {
    // Line processing logic
  }
}
```

## Monitoring Batch Operations

### Batch Statistics

```dart
class BatchMonitor {
  Future<void> monitorBatchOperation() async {
    // Get batch statistics
    final stats = FlutterMCP.instance.getBatchStatistics();
    
    stats.forEach((batchId, statistics) {
      print('Batch: $batchId');
      print('  Total items: ${statistics.totalItems}');
      print('  Processed: ${statistics.processedItems}');
      print('  Failed: ${statistics.failedItems}');
      print('  Duration: ${statistics.totalDuration}');
      print('  Avg per item: ${statistics.averageItemDuration}ms');
    });
    
    // Monitor in real-time
    Timer.periodic(Duration(seconds: 5), (timer) {
      final currentStats = FlutterMCP.instance.getBatchStatistics();
      _updateDashboard(currentStats);
    });
  }
  
  void _updateDashboard(Map<String, BatchStatistics> stats) {
    // Update UI or send to monitoring service
  }
}
```

## Best Practices

### 1. Choose Appropriate Concurrency

```dart
// CPU-bound tasks: limit to CPU cores
final cpuConcurrency = Platform.numberOfProcessors;

// I/O-bound tasks: can use higher concurrency
final ioConcurrency = Platform.numberOfProcessors * 2;

// API calls: respect rate limits
final apiConcurrency = 5; // Based on API limits
```

### 2. Handle Backpressure

```dart
class BackpressureHandler {
  final _queue = Queue<BatchItem>();
  bool _processing = false;
  
  Future<void> addItems(List<BatchItem> items) async {
    _queue.addAll(items);
    
    if (!_processing) {
      _processQueue();
    }
  }
  
  Future<void> _processQueue() async {
    _processing = true;
    
    while (_queue.isNotEmpty) {
      // Process in manageable chunks
      final chunk = <BatchItem>[];
      for (int i = 0; i < 100 && _queue.isNotEmpty; i++) {
        chunk.add(_queue.removeFirst());
      }
      
      await FlutterMCP.instance.processBatch(
        items: chunk,
        processor: _processItem,
        maxConcurrency: 5,
      );
      
      // Allow other operations
      await Future.delayed(Duration(milliseconds: 10));
    }
    
    _processing = false;
  }
  
  Future<void> _processItem(BatchItem item) async {
    // Process individual item
  }
}
```

### 3. Implement Circuit Breakers

```dart
class BatchCircuitBreaker {
  final _circuitBreaker = CircuitBreaker(
    failureThreshold: 5,
    resetTimeout: Duration(seconds: 30),
  );
  
  Future<List<T>> processWithCircuitBreaker<T>(
    List<BatchItem> items,
    Future<T> Function(BatchItem) processor,
  ) async {
    return await _circuitBreaker.execute(() async {
      return await FlutterMCP.instance.processBatch<T>(
        items: items,
        processor: processor,
        maxConcurrency: 10,
        continueOnError: false,
      );
    });
  }
}
```

## Examples

### Data Migration

```dart
class DataMigrator {
  Future<void> migrateData(
    List<OldFormat> oldData,
    Database targetDb,
  ) async {
    print('Starting migration of ${oldData.length} records...');
    
    final migrated = await FlutterMCP.instance.processBatch<NewFormat>(
      items: oldData.map((data) => BatchItem(
        id: data.id,
        data: data,
      )).toList(),
      processor: (item) async {
        final old = item.data as OldFormat;
        
        // Transform data
        final transformed = NewFormat(
          id: old.id,
          name: old.fullName,
          email: old.emailAddress,
          createdAt: old.timestamp,
          metadata: _extractMetadata(old),
        );
        
        // Save to new database
        await targetDb.insert(transformed);
        
        return transformed;
      },
      maxConcurrency: 10,
      continueOnError: true,
    );
    
    print('Migrated ${migrated.length} records successfully');
  }
  
  Map<String, dynamic> _extractMetadata(OldFormat old) {
    // Extract and transform metadata
    return {
      'source': 'legacy_system',
      'migrated_at': DateTime.now().toIso8601String(),
    };
  }
}
```

### Bulk API Operations

```dart
class BulkApiClient {
  Future<void> bulkUpdate(List<UpdateRequest> requests) async {
    // Group by operation type for efficiency
    final grouped = groupBy(requests, (r) => r.operationType);
    
    for (final entry in grouped.entries) {
      final operationType = entry.key;
      final items = entry.value;
      
      print('Processing ${items.length} $operationType operations...');
      
      await FlutterMCP.instance.processBatch<void>(
        items: items.map((req) => BatchItem(
          id: req.id,
          data: req,
        )).toList(),
        processor: (item) async {
          final request = item.data as UpdateRequest;
          
          switch (operationType) {
            case 'create':
              await _apiCreate(request);
              break;
            case 'update':
              await _apiUpdate(request);
              break;
            case 'delete':
              await _apiDelete(request);
              break;
          }
        },
        maxConcurrency: _getConcurrencyForOperation(operationType),
        continueOnError: true,
      );
    }
  }
  
  int _getConcurrencyForOperation(String operationType) {
    switch (operationType) {
      case 'create':
        return 5; // API might be slower for creates
      case 'update':
        return 10;
      case 'delete':
        return 15; // Deletes are usually fast
      default:
        return 5;
    }
  }
  
  Future<void> _apiCreate(UpdateRequest request) async {
    // API create implementation
  }
  
  Future<void> _apiUpdate(UpdateRequest request) async {
    // API update implementation
  }
  
  Future<void> _apiDelete(UpdateRequest request) async {
    // API delete implementation
  }
}
```

## See Also

- [Parallel Execution Patterns](parallel-execution.md)
- [Performance Monitoring](../guides/performance-monitoring-guide.md)
- [API Reference - Batch Methods](../api/flutter-mcp-api.md#advanced-query-methods)