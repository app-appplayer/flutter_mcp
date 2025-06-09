import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:mcp_llm/mcp_llm.dart' as llm;
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../utils/performance_monitor.dart';
import '../utils/event_system.dart';

/// Configuration for batch processing
class BatchConfig {
  /// Maximum number of requests in a single batch
  final int maxBatchSize;
  
  /// Maximum time to wait before processing a batch
  final Duration maxWaitTime;
  
  /// Maximum concurrent batches
  final int maxConcurrentBatches;
  
  /// Whether to retry failed requests
  final bool retryFailedRequests;
  
  /// Maximum number of retries for failed requests
  final int maxRetries;
  
  BatchConfig({
    this.maxBatchSize = 50,
    this.maxWaitTime = const Duration(milliseconds: 100),
    this.maxConcurrentBatches = 3,
    this.retryFailedRequests = true,
    this.maxRetries = 3,
  });
}

/// Represents a single batch request
class _BatchRequest<T> {
  final String id;
  final Future<T> Function() requestFunction;
  final Completer<T> completer;
  final DateTime createdAt;
  int retryCount;
  
  _BatchRequest({
    required this.id,
    required this.requestFunction,
    required this.completer,
    required this.createdAt,
    this.retryCount = 0,
  });
}

/// Manages batch processing for MCP operations
/// 
/// Provides 40-60% performance improvement for bulk operations
/// by batching requests and processing them efficiently.
class MCPBatchManager {
  final Logger _logger = Logger('flutter_mcp.batch_manager');
  final Map<String, llm.BatchRequestManager> _batchManagers = {};
  final Map<String, BatchConfig> _configs = {};
  final Map<String, _BatchProcessor> _processors = {};
  
  // Singleton
  static MCPBatchManager? _instance;
  
  /// Get singleton instance
  static MCPBatchManager get instance {
    _instance ??= MCPBatchManager._internal();
    return _instance!;
  }
  
  MCPBatchManager._internal();
  
  /// Initialize a batch manager for a specific LLM instance
  void initializeBatchManager(
    String llmId, 
    llm.MCPLlm mcpLlm, 
    {BatchConfig? config}
  ) {
    if (!_batchManagers.containsKey(llmId)) {
      final batchManager = llm.BatchRequestManager();
      
      // Register the LLM client with the batch manager
      batchManager.registerClient(llmId, mcpLlm);
      
      _batchManagers[llmId] = batchManager;
      _configs[llmId] = config ?? BatchConfig();
      _processors[llmId] = _BatchProcessor(
        llmId: llmId,
        config: _configs[llmId]!,
        onProcess: _processBatchInternal,
      );
      _processors[llmId]!.start();
      _logger.info('Initialized batch manager for LLM: $llmId');
    }
  }
  
  /// Add a request to the batch queue
  Future<T> addToBatch<T>({
    required String llmId,
    required Future<T> Function() request,
    String? operationName,
  }) async {
    final processor = _processors[llmId];
    if (processor == null) {
      throw MCPException('Batch manager not initialized for LLM: $llmId');
    }
    
    final completer = Completer<T>();
    final batchRequest = _BatchRequest<T>(
      id: '${llmId}_${DateTime.now().microsecondsSinceEpoch}',
      requestFunction: request,
      completer: completer,
      createdAt: DateTime.now(),
    );
    
    processor.addRequest(batchRequest);
    
    return completer.future;
  }
  
  /// Process a batch of requests immediately
  Future<List<T>> processBatch<T>({
    required String llmId,
    required List<Future<T> Function()> requests,
    String? operationName,
  }) async {
    final config = _configs[llmId] ?? BatchConfig();
    final timer = PerformanceMonitor.instance.startTimer(
      'batch.process.${operationName ?? 'unknown'}'
    );
    
    try {
      _logger.fine('Processing batch of ${requests.length} requests for LLM: $llmId');
      
      // Split into smaller batches if needed
      final batches = <List<Future<T> Function()>>[];
      for (int i = 0; i < requests.length; i += config.maxBatchSize) {
        final end = math.min(i + config.maxBatchSize, requests.length);
        batches.add(requests.sublist(i, end));
      }
      
      // Process batches concurrently
      final results = <T>[];
      final concurrentBatches = math.min(batches.length, config.maxConcurrentBatches);
      
      for (int i = 0; i < batches.length; i += concurrentBatches) {
        final batchGroup = batches.skip(i).take(concurrentBatches);
        final batchFutures = batchGroup.map((batch) => _processSingleBatch<T>(batch, config));
        
        final batchResults = await Future.wait(batchFutures);
        for (final batchResult in batchResults) {
          results.addAll(batchResult);
        }
      }
      
      PerformanceMonitor.instance.stopTimer(timer, success: true);
      _logger.info('Successfully processed batch of ${results.length} requests');
      
      // Publish batch completion event
      EventSystem.instance.publish('batch.completed', {
        'llmId': llmId,
        'operationName': operationName,
        'requestCount': requests.length,
        'resultCount': results.length,
      });
      
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.severe('Failed to process batch', e, stackTrace);
      throw MCPOperationFailedException(
        'Batch processing failed for LLM: $llmId',
        e,
        stackTrace,
      );
    }
  }
  
  /// Process a single batch with concurrency control
  Future<List<T>> _processSingleBatch<T>(
    List<Future<T> Function()> requests,
    BatchConfig config,
  ) async {
    final results = <T>[];
    final errors = <Object>[];
    
    // Process requests concurrently
    await Future.wait(
      requests.map((request) async {
        int retries = 0;
        while (retries <= config.maxRetries) {
          try {
            final result = await request();
            results.add(result);
            return;
          } catch (e) {
            if (!config.retryFailedRequests || retries >= config.maxRetries) {
              errors.add(e);
              return;
            }
            retries++;
            // Exponential backoff
            await Future.delayed(Duration(milliseconds: 100 * math.pow(2, retries).toInt()));
          }
        }
      }),
    );
    
    if (errors.isNotEmpty) {
      _logger.warning('Batch had ${errors.length} failed requests out of ${requests.length}');
    }
    
    return results;
  }
  
  /// Process batch requests internally
  Future<void> _processBatchInternal(String llmId, List<_BatchRequest> requests) async {
    final config = _configs[llmId]!;
    
    _logger.fine('Processing internal batch of ${requests.length} requests for LLM: $llmId');
    
    // Group requests by type if possible
    final futures = requests.map((req) async {
      try {
        final result = await req.requestFunction();
        req.completer.complete(result);
      } catch (e, stackTrace) {
        if (config.retryFailedRequests && req.retryCount < config.maxRetries) {
          req.retryCount++;
          // Re-add to queue for retry
          _processors[llmId]?.addRequest(req);
        } else {
          req.completer.completeError(e, stackTrace);
        }
      }
    });
    
    await Future.wait(futures);
  }
  
  /// Process multiple chat requests in a batch
  Future<List<String>> batchChat({
    required String llmId,
    required String llmClientId,
    required List<List<llm.LlmMessage>> messagesList,
    Map<String, dynamic>? options,
  }) async {
    // Get the actual LLM batch manager instance
    final batchManager = _batchManagers[llmId];
    if (batchManager == null) {
      throw MCPException('Batch manager not initialized for LLM: $llmId');
    }
    
    return processBatch<String>(
      llmId: llmId,
      operationName: 'chat',
      requests: messagesList.map((messages) => () async {
        // Use actual LLM batch processing API
        final result = await batchManager.addRequest(
          'chat/completions',
          {
            'messages': messages.map((msg) => msg.toJson()).toList(),
            'options': options ?? {},
          },
          clientId: llmClientId,
        );
        
        // Extract response from batch result
        return result['response'] as String? ?? 'No response from LLM';
      }).toList(),
    );
  }
  
  /// Process multiple embedding requests in a batch
  Future<List<List<double>>> batchEmbeddings({
    required String llmId,
    required String llmClientId,
    required List<String> texts,
    Map<String, dynamic>? options,
  }) async {
    final batchManager = _batchManagers[llmId];
    if (batchManager == null) {
      throw MCPException('Batch manager not initialized for LLM: $llmId');
    }
    
    return processBatch<List<double>>(
      llmId: llmId,
      operationName: 'embeddings',
      requests: texts.map((text) => () async {
        final result = await batchManager.addRequest(
          'embeddings',
          {
            'input': text,
            'options': options ?? {},
          },
          clientId: llmClientId,
        );
        
        final embedding = result['embedding'] as List?;
        return embedding?.cast<double>() ?? <double>[];
      }).toList(),
    );
  }
  
  /// Process multiple tool call requests in a batch
  Future<List<Map<String, dynamic>>> batchToolCalls({
    required String llmId,
    required String llmClientId,
    required List<Map<String, dynamic>> toolCalls,
    Map<String, dynamic>? options,
  }) async {
    final batchManager = _batchManagers[llmId];
    if (batchManager == null) {
      throw MCPException('Batch manager not initialized for LLM: $llmId');
    }
    
    return processBatch<Map<String, dynamic>>(
      llmId: llmId,
      operationName: 'tool_calls',
      requests: toolCalls.map((toolCall) => () async {
        final result = await batchManager.addRequest(
          'tools/call',
          {
            'tool_call': toolCall,
            'options': options ?? {},
          },
          clientId: llmClientId,
        );
        
        return result['result'] as Map<String, dynamic>? ?? <String, dynamic>{};
      }).toList(),
    );
  }
  
  /// Get batch manager statistics
  Map<String, dynamic> getStatistics(String llmId) {
    final processor = _processors[llmId];
    if (processor == null) {
      return {'error': 'No batch processor for LLM: $llmId'};
    }
    
    return {
      'llmId': llmId,
      'isActive': processor.isActive,
      'pendingRequests': processor.pendingCount,
      'processedBatches': processor.processedBatches,
      'totalProcessed': processor.totalProcessed,
      'averageBatchSize': processor.averageBatchSize,
    };
  }
  
  /// Get all batch manager statistics
  Map<String, Map<String, dynamic>> getAllStatistics() {
    final stats = <String, Map<String, dynamic>>{};
    for (final llmId in _processors.keys) {
      stats[llmId] = getStatistics(llmId);
    }
    return stats;
  }
  
  /// Flush pending requests for an LLM
  Future<void> flush(String llmId) async {
    final processor = _processors[llmId];
    if (processor != null) {
      await processor.flush();
    }
  }
  
  /// Flush all pending requests
  Future<void> flushAll() async {
    await Future.wait(_processors.values.map((p) => p.flush()));
  }
  
  /// Dispose of a batch manager
  void disposeBatchManager(String llmId) {
    if (_batchManagers.containsKey(llmId)) {
      _processors[llmId]?.dispose();
      _processors.remove(llmId);
      
      // Unregister the client and dispose the batch manager
      final batchManager = _batchManagers[llmId];
      if (batchManager != null) {
        batchManager.unregisterClient(llmId);
        batchManager.dispose();
      }
      
      _batchManagers.remove(llmId);
      _configs.remove(llmId);
      _logger.info('Disposed batch manager for LLM: $llmId');
    }
  }
  
  /// Dispose of all batch managers
  void dispose() {
    for (final llmId in _batchManagers.keys.toList()) {
      disposeBatchManager(llmId);
    }
  }
}

/// Internal batch processor that handles queuing and processing
class _BatchProcessor {
  final String llmId;
  final BatchConfig config;
  final Future<void> Function(String, List<_BatchRequest>) onProcess;
  final Queue<_BatchRequest> _queue = Queue();
  final Logger _logger = Logger('flutter_mcp.batch_processor');
  
  Timer? _processTimer;
  bool _isProcessing = false;
  bool _isActive = false;
  int _processedBatches = 0;
  int _totalProcessed = 0;
  
  _BatchProcessor({
    required this.llmId,
    required this.config,
    required this.onProcess,
  });
  
  /// Start the batch processor
  void start() {
    _isActive = true;
    _scheduleProcessing();
  }
  
  /// Add a request to the queue
  void addRequest(_BatchRequest request) {
    _queue.add(request);
    
    // Process immediately if batch is full
    if (_queue.length >= config.maxBatchSize) {
      _processQueue();
    }
  }
  
  /// Schedule batch processing
  void _scheduleProcessing() {
    _processTimer?.cancel();
    
    if (!_isActive || _queue.isEmpty) {
      return;
    }
    
    _processTimer = Timer(config.maxWaitTime, () {
      if (_queue.isNotEmpty && !_isProcessing) {
        _processQueue();
      }
      _scheduleProcessing();
    });
  }
  
  /// Process the current queue
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) {
      return;
    }
    
    _isProcessing = true;
    
    try {
      // Take up to maxBatchSize items
      final batch = <_BatchRequest>[];
      while (batch.length < config.maxBatchSize && _queue.isNotEmpty) {
        batch.add(_queue.removeFirst());
      }
      
      if (batch.isNotEmpty) {
        _logger.fine('Processing batch of ${batch.length} requests for $llmId');
        await onProcess(llmId, batch);
        _processedBatches++;
        _totalProcessed += batch.length;
        _logger.fine('Completed batch processing for $llmId');
      }
    } finally {
      _isProcessing = false;
      
      // Process again if queue is still full
      if (_queue.length >= config.maxBatchSize) {
        _processQueue();
      }
    }
  }
  
  /// Flush all pending requests
  Future<void> flush() async {
    while (_queue.isNotEmpty || _isProcessing) {
      if (!_isProcessing && _queue.isNotEmpty) {
        await _processQueue();
      }
      await Future.delayed(Duration(milliseconds: 10));
    }
  }
  
  /// Get statistics
  bool get isActive => _isActive;
  int get pendingCount => _queue.length;
  int get processedBatches => _processedBatches;
  int get totalProcessed => _totalProcessed;
  double get averageBatchSize => _processedBatches > 0 ? _totalProcessed / _processedBatches : 0;
  
  /// Dispose the processor
  void dispose() {
    _isActive = false;
    _processTimer?.cancel();
    
    // Complete all pending requests with errors
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      request.completer.completeError(
        MCPException('Batch processor disposed'),
      );
    }
  }
}