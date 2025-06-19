import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:mcp_llm/mcp_llm.dart' as llm;
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../utils/enhanced_error_handler.dart';
import '../monitoring/health_monitor.dart';
import '../utils/enhanced_resource_cleanup.dart';
import '../events/event_system.dart';
import '../utils/circuit_breaker.dart';
import '../types/health_types.dart';

/// Enhanced configuration for batch processing
class EnhancedBatchConfig {
  /// Maximum number of requests in a single batch
  final int maxBatchSize;

  /// Minimum batch size before processing (for efficiency)
  final int minBatchSize;

  /// Maximum time to wait before processing a batch
  final Duration maxWaitTime;

  /// Maximum concurrent batches
  final int maxConcurrentBatches;

  /// Whether to retry failed requests
  final bool retryFailedRequests;

  /// Maximum number of retries for failed requests
  final int maxRetries;

  /// Retry delay strategy
  final Duration Function(int attempt) retryDelay;

  /// Priority queue support
  final bool enablePriorityQueue;

  /// Request timeout
  final Duration requestTimeout;

  /// Adaptive batch sizing
  final bool adaptiveBatchSize;

  /// Request deduplication
  final bool deduplicateRequests;

  /// Compression for large batches
  final bool enableCompression;

  /// Circuit breaker configuration
  final int circuitBreakerThreshold;
  final Duration circuitBreakerResetTimeout;

  EnhancedBatchConfig({
    this.maxBatchSize = 100,
    this.minBatchSize = 10,
    this.maxWaitTime = const Duration(milliseconds: 100),
    this.maxConcurrentBatches = 5,
    this.retryFailedRequests = true,
    this.maxRetries = 3,
    Duration Function(int)? retryDelay,
    this.enablePriorityQueue = true,
    this.requestTimeout = const Duration(seconds: 30),
    this.adaptiveBatchSize = true,
    this.deduplicateRequests = true,
    this.enableCompression = false,
    this.circuitBreakerThreshold = 10,
    this.circuitBreakerResetTimeout = const Duration(minutes: 1),
  }) : retryDelay = retryDelay ??
            ((attempt) =>
                Duration(milliseconds: 100 * math.pow(2, attempt).toInt()));

  /// Create optimized config for high throughput
  factory EnhancedBatchConfig.highThroughput() {
    return EnhancedBatchConfig(
      maxBatchSize: 200,
      minBatchSize: 50,
      maxWaitTime: const Duration(milliseconds: 50),
      maxConcurrentBatches: 10,
      adaptiveBatchSize: true,
      enableCompression: true,
    );
  }

  /// Create optimized config for low latency
  factory EnhancedBatchConfig.lowLatency() {
    return EnhancedBatchConfig(
      maxBatchSize: 50,
      minBatchSize: 1,
      maxWaitTime: const Duration(milliseconds: 10),
      maxConcurrentBatches: 3,
      adaptiveBatchSize: false,
    );
  }
}

/// Request priority levels
enum BatchRequestPriority {
  low,
  normal,
  high,
  critical,
}

/// Enhanced batch request with priority and metadata
class EnhancedBatchRequest<T> {
  final String id;
  final Future<T> Function() requestFunction;
  final Completer<T> completer;
  final DateTime createdAt;
  final BatchRequestPriority priority;
  final Map<String, dynamic>? metadata;
  final String? deduplicationKey;
  int retryCount;
  Duration? lastExecutionTime;

  EnhancedBatchRequest({
    required this.id,
    required this.requestFunction,
    required this.completer,
    required this.createdAt,
    this.priority = BatchRequestPriority.normal,
    this.metadata,
    this.deduplicationKey,
    this.retryCount = 0,
  });

  Duration get age => DateTime.now().difference(createdAt);
}

/// Batch statistics
class BatchStatistics {
  int totalRequests = 0;
  int successfulRequests = 0;
  int failedRequests = 0;
  int retriedRequests = 0;
  int deduplicatedRequests = 0;
  Duration totalProcessingTime = Duration.zero;
  Duration averageWaitTime = Duration.zero;
  Duration averageExecutionTime = Duration.zero;
  Map<BatchRequestPriority, int> requestsByPriority = {};

  double get successRate =>
      totalRequests > 0 ? successfulRequests / totalRequests : 0.0;
  double get throughput => totalProcessingTime.inMilliseconds > 0
      ? (totalRequests * 1000 / totalProcessingTime.inMilliseconds)
      : 0.0;
}

/// Enhanced batch processor with adaptive optimization
class EnhancedBatchProcessor<T> implements HealthCheckProvider {
  final String processorId;
  final EnhancedBatchConfig config;
  final Future<void> Function(List<EnhancedBatchRequest<T>>) onProcess;
  final Logger logger;

  // Request queues by priority
  final Map<BatchRequestPriority, Queue<EnhancedBatchRequest<T>>>
      _requestQueues = {
    for (var priority in BatchRequestPriority.values)
      priority: Queue<EnhancedBatchRequest<T>>()
  };

  // Deduplication cache
  final Map<String, EnhancedBatchRequest<T>> _deduplicationCache = {};

  // Processing state
  Timer? _processTimer;
  bool _isProcessing = false;
  bool _isRunning = false;

  // Adaptive sizing
  int _currentBatchSize;
  double _lastSuccessRate = 1.0;

  // Statistics
  final BatchStatistics statistics = BatchStatistics();

  // Circuit breaker
  late final CircuitBreaker _circuitBreaker;

  EnhancedBatchProcessor({
    required this.processorId,
    required this.config,
    required this.onProcess,
    Logger? logger,
  })  : logger = logger ?? Logger('flutter_mcp.batch_processor.$processorId'),
        _currentBatchSize = config.maxBatchSize {
    _circuitBreaker = CircuitBreaker(
      name: 'batch_processor_$processorId',
      failureThreshold: config.circuitBreakerThreshold,
      resetTimeout: config.circuitBreakerResetTimeout,
      onOpen: () => this
          .logger
          .warning('Circuit breaker opened for batch processor: $processorId'),
      onClose: () => this
          .logger
          .info('Circuit breaker closed for batch processor: $processorId'),
    );
  }

  @override
  String get componentId => 'batch_processor_$processorId';

  /// Start the processor
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _scheduleNextBatch();
    logger.fine('Batch processor started: $processorId');
  }

  /// Stop the processor
  void stop() {
    _isRunning = false;
    _processTimer?.cancel();
    _processTimer = null;
    logger.fine('Batch processor stopped: $processorId');
  }

  /// Add a request to the queue
  void addRequest(EnhancedBatchRequest<T> request) {
    if (!_isRunning) {
      request.completer.completeError(
          MCPException('Batch processor not running: $processorId'));
      return;
    }

    // Check for deduplication
    if (config.deduplicateRequests && request.deduplicationKey != null) {
      final existing = _deduplicationCache[request.deduplicationKey];
      if (existing != null && existing.age < Duration(seconds: 5)) {
        statistics.deduplicatedRequests++;
        // Link completers for deduplication
        existing.completer.future.then(
          request.completer.complete,
          onError: request.completer.completeError,
        );
        return;
      }
      _deduplicationCache[request.deduplicationKey!] = request;
    }

    // Add to priority queue
    _requestQueues[request.priority]!.add(request);
    statistics.totalRequests++;

    // Update priority statistics
    statistics.requestsByPriority[request.priority] =
        (statistics.requestsByPriority[request.priority] ?? 0) + 1;

    // Check if we should process immediately
    if (_shouldProcessImmediately()) {
      _processTimer?.cancel();
      _processBatch();
    }
  }

  /// Check if batch should be processed immediately
  bool _shouldProcessImmediately() {
    final totalPending = _getTotalPendingRequests();

    // Process immediately if we have critical requests
    if (_requestQueues[BatchRequestPriority.critical]!.isNotEmpty) {
      return true;
    }

    // Process if we've reached the batch size
    if (totalPending >= _currentBatchSize) {
      return true;
    }

    // Process if oldest request is timing out
    final oldestRequest = _getOldestRequest();
    if (oldestRequest != null && oldestRequest.age > config.maxWaitTime * 0.8) {
      return true;
    }

    return false;
  }

  /// Get total pending requests across all priorities
  int _getTotalPendingRequests() {
    return _requestQueues.values.fold(0, (sum, queue) => sum + queue.length);
  }

  /// Get oldest request across all queues
  EnhancedBatchRequest<T>? _getOldestRequest() {
    EnhancedBatchRequest<T>? oldest;
    for (final queue in _requestQueues.values) {
      if (queue.isNotEmpty &&
          (oldest == null ||
              queue.first.createdAt.isBefore(oldest.createdAt))) {
        oldest = queue.first;
      }
    }
    return oldest;
  }

  /// Schedule next batch processing
  void _scheduleNextBatch() {
    if (!_isRunning || _processTimer != null) return;

    _processTimer = Timer(config.maxWaitTime, () {
      _processTimer = null;
      if (_getTotalPendingRequests() >= config.minBatchSize ||
          _hasTimedOutRequests()) {
        _processBatch();
      } else {
        _scheduleNextBatch();
      }
    });
  }

  /// Check if any requests have timed out
  bool _hasTimedOutRequests() {
    final oldest = _getOldestRequest();
    return oldest != null && oldest.age > config.maxWaitTime;
  }

  /// Process a batch of requests
  void _processBatch() async {
    if (_isProcessing || !_isRunning) return;

    _isProcessing = true;
    final startTime = DateTime.now();

    try {
      // Collect requests by priority
      final batch = _collectBatch();
      if (batch.isEmpty) {
        _isProcessing = false;
        _scheduleNextBatch();
        return;
      }

      logger.fine('Processing batch of ${batch.length} requests');

      // Process through circuit breaker
      await _circuitBreaker.execute(() async {
        await EnhancedErrorHandler.instance.handleError(
          () => onProcess(batch),
          context: 'batch_processing',
          component: 'batch_processor',
          metadata: {
            'processorId': processorId,
            'batchSize': batch.length,
            'priorities': batch.map((r) => r.priority.name).toSet().toList(),
          },
        );
      });

      // Update statistics
      final processingTime = DateTime.now().difference(startTime);
      statistics.totalProcessingTime += processingTime;

      // Update adaptive batch size
      if (config.adaptiveBatchSize) {
        _updateAdaptiveBatchSize(batch.length, processingTime);
      }
    } catch (e, stackTrace) {
      logger.severe('Batch processing failed', e, stackTrace);
      // Requests will be retried or failed by the processor
    } finally {
      _isProcessing = false;
      _scheduleNextBatch();
    }
  }

  /// Collect a batch of requests prioritizing by priority
  List<EnhancedBatchRequest<T>> _collectBatch() {
    final batch = <EnhancedBatchRequest<T>>[];

    // Process in priority order
    for (final priority in BatchRequestPriority.values.reversed) {
      final queue = _requestQueues[priority]!;

      while (queue.isNotEmpty && batch.length < _currentBatchSize) {
        batch.add(queue.removeFirst());
      }

      if (batch.length >= _currentBatchSize) break;
    }

    // Clean deduplication cache
    if (config.deduplicateRequests) {
      _deduplicationCache
          .removeWhere((key, request) => request.age > Duration(seconds: 10));
    }

    return batch;
  }

  /// Update adaptive batch size based on performance
  void _updateAdaptiveBatchSize(int processedCount, Duration processingTime) {
    final throughput = processedCount / processingTime.inMilliseconds * 1000;

    // Increase batch size if throughput is good and success rate is high
    if (throughput > 100 && _lastSuccessRate > 0.95) {
      _currentBatchSize = math.min(
        (_currentBatchSize * 1.1).round(),
        config.maxBatchSize,
      );
    }
    // Decrease batch size if success rate is low
    else if (_lastSuccessRate < 0.8) {
      _currentBatchSize = math.max(
        (_currentBatchSize * 0.9).round(),
        config.minBatchSize,
      );
    }

    logger.fine('Adaptive batch size updated to: $_currentBatchSize');
  }

  @override
  Future<MCPHealthCheckResult> performHealthCheck() async {
    final pendingCount = _getTotalPendingRequests();
    final oldestRequest = _getOldestRequest();
    final oldestAge = oldestRequest?.age;

    MCPHealthStatus status;
    String message;

    if (!_isRunning) {
      status = MCPHealthStatus.unhealthy;
      message = 'Batch processor not running';
    } else if (_circuitBreaker.state == CircuitBreakerState.open) {
      status = MCPHealthStatus.unhealthy;
      message = 'Circuit breaker is open';
    } else if (oldestAge != null && oldestAge > config.maxWaitTime * 10) {
      status = MCPHealthStatus.unhealthy;
      message = 'Requests stuck in queue for too long';
    } else if (pendingCount > config.maxBatchSize * 5) {
      status = MCPHealthStatus.degraded;
      message = 'Large backlog of pending requests: $pendingCount';
    } else if (statistics.successRate < 0.5) {
      status = MCPHealthStatus.degraded;
      message =
          'Low success rate: ${(statistics.successRate * 100).toStringAsFixed(1)}%';
    } else {
      status = MCPHealthStatus.healthy;
      message = 'Batch processor operational';
    }

    return MCPHealthCheckResult(
      status: status,
      message: message,
      details: {
        'processorId': processorId,
        'isRunning': _isRunning,
        'isProcessing': _isProcessing,
        'pendingRequests': pendingCount,
        'currentBatchSize': _currentBatchSize,
        'statistics': {
          'totalRequests': statistics.totalRequests,
          'successRate': statistics.successRate,
          'throughput': statistics.throughput,
          'deduplicatedRequests': statistics.deduplicatedRequests,
        },
        'circuitBreaker': {
          'state': _circuitBreaker.state.name,
          'failureCount': _circuitBreaker.failureCount,
        },
      },
    );
  }
}

/// Enhanced batch manager with advanced optimization
class EnhancedBatchManager implements HealthCheckProvider {
  final Logger _logger = Logger('flutter_mcp.enhanced_batch_manager');
  final Map<String, llm.BatchRequestManager> _batchManagers = {};
  final Map<String, EnhancedBatchConfig> _configs = {};
  final Map<String, EnhancedBatchProcessor> _processors = {};
  final EventSystem _eventSystem = EventSystem.instance;

  // Global statistics
  final Map<String, BatchStatistics> _statistics = {};

  // Singleton
  static EnhancedBatchManager? _instance;

  /// Get singleton instance
  static EnhancedBatchManager get instance {
    _instance ??= EnhancedBatchManager._internal();
    return _instance!;
  }

  EnhancedBatchManager._internal() {
    // Register for resource cleanup
    EnhancedResourceCleanup.instance.registerResource(
      key: 'enhanced_batch_manager',
      resource: this,
      disposeFunction: (_) async => await dispose(),
      type: 'BatchManager',
      description: 'Enhanced batch processing manager',
      priority: 150,
    );
  }

  @override
  String get componentId => 'batch_manager';

  /// Initialize a batch manager for a specific LLM instance
  void initializeBatchManager(
    String llmId,
    llm.MCPLlm mcpLlm, {
    EnhancedBatchConfig? config,
  }) {
    if (!_batchManagers.containsKey(llmId)) {
      final batchManager = llm.BatchRequestManager();

      // Register the LLM client with the batch manager
      batchManager.registerClient(llmId, mcpLlm);

      _batchManagers[llmId] = batchManager;
      _configs[llmId] = config ?? EnhancedBatchConfig();
      _statistics[llmId] = BatchStatistics();

      _processors[llmId] = EnhancedBatchProcessor(
        processorId: llmId,
        config: _configs[llmId]!,
        onProcess: (requests) => _processBatchInternal(llmId, requests),
      );

      _processors[llmId]!.start();
      _logger.info('Initialized enhanced batch manager for LLM: $llmId');
    }
  }

  /// Add a request to the batch queue with priority
  Future<T> addToBatch<T>({
    required String llmId,
    required Future<T> Function() request,
    String? operationName,
    BatchRequestPriority priority = BatchRequestPriority.normal,
    Map<String, dynamic>? metadata,
    String? deduplicationKey,
  }) async {
    final processor = _processors[llmId];
    if (processor == null) {
      throw MCPException('Batch manager not initialized for LLM: $llmId');
    }

    final completer = Completer<T>();
    final batchRequest = EnhancedBatchRequest<T>(
      id: '${llmId}_${DateTime.now().microsecondsSinceEpoch}_${_statistics[llmId]!.totalRequests}',
      requestFunction: request,
      completer: completer,
      createdAt: DateTime.now(),
      priority: priority,
      metadata: metadata,
      deduplicationKey: deduplicationKey,
    );

    processor.addRequest(batchRequest);

    return completer.future;
  }

  /// Process batch requests internally
  Future<void> _processBatchInternal<T>(
    String llmId,
    List<EnhancedBatchRequest<T>> requests,
  ) async {
    final config = _configs[llmId]!;
    final stats = _statistics[llmId]!;
    final batchStartTime = DateTime.now();

    _logger.fine(
        'Processing internal batch of ${requests.length} requests for LLM: $llmId');

    // Calculate average wait time
    final waitTimes = requests.map((r) => r.age).toList();
    stats.averageWaitTime = Duration(
        milliseconds:
            waitTimes.map((d) => d.inMilliseconds).reduce((a, b) => a + b) ~/
                waitTimes.length);

    // Process requests with timeout
    final futures = requests.map((req) async {
      final execStartTime = DateTime.now();

      try {
        final result =
            await req.requestFunction().timeout(config.requestTimeout);
        req.completer.complete(result);

        // Update statistics
        stats.successfulRequests++;
        req.lastExecutionTime = DateTime.now().difference(execStartTime);
      } on TimeoutException catch (e) {
        _handleRequestError(
          llmId,
          req,
          MCPTimeoutException(
            'Request timed out after ${config.requestTimeout}',
            config.requestTimeout,
            e,
            StackTrace.current,
          ),
          StackTrace.current,
        );
      } catch (e, stackTrace) {
        _handleRequestError(llmId, req, e, stackTrace);
      }
    });

    await Future.wait(futures);

    // Update execution time statistics
    final batchExecutionTime = DateTime.now().difference(batchStartTime);
    final avgExecTime = requests
        .where((r) => r.lastExecutionTime != null)
        .map((r) => r.lastExecutionTime!.inMilliseconds)
        .fold(0, (sum, time) => sum + time);

    if (avgExecTime > 0) {
      stats.averageExecutionTime = Duration(
          milliseconds: avgExecTime ~/
              requests.where((r) => r.lastExecutionTime != null).length);
    }

    // Update processor's success rate
    final processor = _processors[llmId]!;
    processor._lastSuccessRate = stats.successRate;

    // Publish batch metrics
    _publishBatchMetrics(llmId, requests.length, batchExecutionTime);
  }

  /// Handle request error with retry logic
  void _handleRequestError<T>(
    String llmId,
    EnhancedBatchRequest<T> request,
    dynamic error,
    StackTrace stackTrace,
  ) {
    final config = _configs[llmId]!;
    final stats = _statistics[llmId]!;

    if (config.retryFailedRequests && request.retryCount < config.maxRetries) {
      request.retryCount++;
      stats.retriedRequests++;

      // Schedule retry with delay
      Timer(config.retryDelay(request.retryCount), () {
        _processors[llmId]?.addRequest(request);
      });

      _logger.fine(
          'Retrying request ${request.id} (attempt ${request.retryCount})');
    } else {
      stats.failedRequests++;
      request.completer.completeError(error, stackTrace);

      _logger.warning(
          'Request ${request.id} failed after ${request.retryCount} retries');
    }
  }

  /// Publish batch processing metrics
  void _publishBatchMetrics(
      String llmId, int batchSize, Duration executionTime) {
    _eventSystem.publishTopic('batch.processed', {
      'llmId': llmId,
      'batchSize': batchSize,
      'executionTimeMs': executionTime.inMilliseconds,
      'statistics': {
        'successRate': _statistics[llmId]!.successRate,
        'throughput': _statistics[llmId]!.throughput,
        'averageWaitTimeMs': _statistics[llmId]!.averageWaitTime.inMilliseconds,
        'averageExecutionTimeMs':
            _statistics[llmId]!.averageExecutionTime.inMilliseconds,
      },
    });
  }

  /// Get batch statistics for an LLM
  BatchStatistics? getStatistics(String llmId) {
    return _statistics[llmId];
  }

  /// Get all batch statistics
  Map<String, BatchStatistics> getAllStatistics() {
    return Map.from(_statistics);
  }

  /// Stop batch processing for an LLM
  void stopBatchProcessing(String llmId) {
    _processors[llmId]?.stop();
    _logger.info('Stopped batch processing for LLM: $llmId');
  }

  /// Resume batch processing for an LLM
  void resumeBatchProcessing(String llmId) {
    _processors[llmId]?.start();
    _logger.info('Resumed batch processing for LLM: $llmId');
  }

  /// Dispose all resources
  Future<void> dispose() async {
    for (final processor in _processors.values) {
      processor.stop();
    }

    _processors.clear();
    _batchManagers.clear();
    _configs.clear();
    _statistics.clear();

    _logger.info('Enhanced batch manager disposed');
  }

  @override
  Future<MCPHealthCheckResult> performHealthCheck() async {
    if (_processors.isEmpty) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.healthy,
        message: 'No batch processors configured',
      );
    }

    // Check health of all processors
    final processorHealths =
        await Future.wait(_processors.entries.map((e) async => {
              'llmId': e.key,
              'health': await e.value.performHealthCheck(),
            }));

    // Aggregate health status
    MCPHealthStatus overallStatus = MCPHealthStatus.healthy;
    final unhealthyProcessors = <String>[];
    final degradedProcessors = <String>[];

    for (final health in processorHealths) {
      final llmId = health['llmId'] as String;
      final result = health['health'] as MCPHealthCheckResult;

      if (result.status == MCPHealthStatus.unhealthy) {
        overallStatus = MCPHealthStatus.unhealthy;
        unhealthyProcessors.add(llmId);
      } else if (result.status == MCPHealthStatus.degraded) {
        if (overallStatus != MCPHealthStatus.unhealthy) {
          overallStatus = MCPHealthStatus.degraded;
        }
        degradedProcessors.add(llmId);
      }
    }

    String message;
    if (unhealthyProcessors.isNotEmpty) {
      message = 'Unhealthy processors: ${unhealthyProcessors.join(', ')}';
    } else if (degradedProcessors.isNotEmpty) {
      message = 'Degraded processors: ${degradedProcessors.join(', ')}';
    } else {
      message = 'All batch processors operational';
    }

    return MCPHealthCheckResult(
      status: overallStatus,
      message: message,
      details: {
        'processorCount': _processors.length,
        'unhealthyProcessors': unhealthyProcessors,
        'degradedProcessors': degradedProcessors,
        'globalStatistics': _statistics.map((k, v) => MapEntry(k, {
              'totalRequests': v.totalRequests,
              'successRate': v.successRate,
              'throughput': v.throughput,
            })),
      },
    );
  }
}
