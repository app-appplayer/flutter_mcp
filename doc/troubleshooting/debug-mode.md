# Debug Mode

Comprehensive guide to debugging Flutter MCP applications.

## Enabling Debug Mode

### Basic Configuration

```dart
void main() {
  // Enable debug mode globally
  FlutterMCP.debugMode = true;
  
  // Configure debug options
  final config = McpConfig(
    debugOptions: DebugOptions(
      logLevel: LogLevel.verbose,
      enableNetworkLogging: true,
      enablePerformanceMonitoring: true,
      enableMemoryTracking: true,
      saveLogsToFile: true,
      logFilePath: 'debug_logs.txt',
    ),
  );
  
  runApp(MyApp());
}
```

### Debug Options

```dart
class DebugOptions {
  final LogLevel logLevel;
  final bool enableNetworkLogging;
  final bool enablePerformanceMonitoring;
  final bool enableMemoryTracking;
  final bool enableEventTracking;
  final bool saveLogsToFile;
  final String? logFilePath;
  final int maxLogSize;
  final bool includeStackTraces;
  final bool prettifyJson;
  
  const DebugOptions({
    this.logLevel = LogLevel.info,
    this.enableNetworkLogging = false,
    this.enablePerformanceMonitoring = false,
    this.enableMemoryTracking = false,
    this.enableEventTracking = false,
    this.saveLogsToFile = false,
    this.logFilePath,
    this.maxLogSize = 10 * 1024 * 1024, // 10MB
    this.includeStackTraces = true,
    this.prettifyJson = true,
  });
}

enum LogLevel {
  none,
  error,
  warning,
  info,
  debug,
  verbose,
}
```

## Logging System

### Custom Logger Implementation

```dart
class MCPLogger {
  static final MCPLogger _instance = MCPLogger._internal();
  factory MCPLogger() => _instance;
  MCPLogger._internal();
  
  final List<LogEntry> _logs = [];
  final StreamController<LogEntry> _logStream = StreamController.broadcast();
  
  LogLevel _currentLevel = LogLevel.info;
  File? _logFile;
  
  void configure({
    required LogLevel level,
    String? logFilePath,
  }) {
    _currentLevel = level;
    if (logFilePath != null) {
      _logFile = File(logFilePath);
    }
  }
  
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    if (level.index < _currentLevel.index) return;
    
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
    
    _logs.add(entry);
    _logStream.add(entry);
    
    // Write to console
    _writeToConsole(entry);
    
    // Write to file
    if (_logFile != null) {
      _writeToFile(entry);
    }
  }
  
  void _writeToConsole(LogEntry entry) {
    final color = _getColorForLevel(entry.level);
    final prefix = '[${entry.level.name.toUpperCase()}]';
    final timestamp = entry.timestamp.toIso8601String();
    
    print('$color$prefix $timestamp ${entry.message}\x1B[0m');
    
    if (entry.error != null) {
      print('$color  Error: ${entry.error}\x1B[0m');
    }
    
    if (entry.stackTrace != null && FlutterMCP.debugMode) {
      print('$color  Stack trace:\n${entry.stackTrace}\x1B[0m');
    }
    
    if (entry.metadata != null && entry.metadata!.isNotEmpty) {
      print('$color  Metadata: ${jsonEncode(entry.metadata)}\x1B[0m');
    }
  }
  
  String _getColorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return '\x1B[31m'; // Red
      case LogLevel.warning:
        return '\x1B[33m'; // Yellow
      case LogLevel.info:
        return '\x1B[34m'; // Blue
      case LogLevel.debug:
        return '\x1B[36m'; // Cyan
      case LogLevel.verbose:
        return '\x1B[37m'; // White
      default:
        return '\x1B[0m';  // Reset
    }
  }
  
  Future<void> _writeToFile(LogEntry entry) async {
    try {
      final json = entry.toJson();
      await _logFile!.writeAsString(
        '${jsonEncode(json)}\n',
        mode: FileMode.append,
      );
      
      // Rotate log file if too large
      final stat = await _logFile!.stat();
      if (stat.size > 10 * 1024 * 1024) { // 10MB
        await _rotateLogFile();
      }
    } catch (e) {
      print('Failed to write log to file: $e');
    }
  }
  
  Future<void> _rotateLogFile() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '${_logFile!.path}.$timestamp';
    await _logFile!.rename(backupPath);
    _logFile = File(_logFile!.path);
  }
  
  Stream<LogEntry> get logStream => _logStream.stream;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  
  void clear() {
    _logs.clear();
  }
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? metadata;
  
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.metadata,
  });
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'message': message,
    if (error != null) 'error': error.toString(),
    if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    if (metadata != null) 'metadata': metadata,
  };
}
```

### Logging Extensions

```dart
extension LoggingExtensions on FlutterMCP {
  MCPLogger get logger => MCPLogger();
  
  void logDebug(String message, [Map<String, dynamic>? metadata]) {
    logger.log(message, level: LogLevel.debug, metadata: metadata);
  }
  
  void logInfo(String message, [Map<String, dynamic>? metadata]) {
    logger.log(message, level: LogLevel.info, metadata: metadata);
  }
  
  void logWarning(String message, [Map<String, dynamic>? metadata]) {
    logger.log(message, level: LogLevel.warning, metadata: metadata);
  }
  
  void logError(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    logger.log(
      message,
      level: LogLevel.error,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }
}
```

## Network Debugging

### Request/Response Interceptor

```dart
class NetworkDebugInterceptor {
  final bool logRequests;
  final bool logResponses;
  final bool logHeaders;
  final bool logBody;
  final int maxBodySize;
  
  NetworkDebugInterceptor({
    this.logRequests = true,
    this.logResponses = true,
    this.logHeaders = true,
    this.logBody = true,
    this.maxBodySize = 1024 * 1024, // 1MB
  });
  
  void interceptRequest(MCPRequest request) {
    if (!logRequests) return;
    
    final log = StringBuffer();
    log.writeln('==> REQUEST ${request.method} ${request.url}');
    
    if (logHeaders) {
      log.writeln('Headers:');
      request.headers.forEach((key, value) {
        log.writeln('  $key: $value');
      });
    }
    
    if (logBody && request.body != null) {
      final body = _formatBody(request.body!);
      log.writeln('Body:');
      log.writeln(body);
    }
    
    log.writeln('==> END REQUEST');
    
    MCPLogger().logDebug(log.toString(), {
      'type': 'network_request',
      'method': request.method,
      'url': request.url,
    });
  }
  
  void interceptResponse(MCPResponse response) {
    if (!logResponses) return;
    
    final log = StringBuffer();
    log.writeln('<== RESPONSE ${response.statusCode} ${response.url}');
    
    if (logHeaders) {
      log.writeln('Headers:');
      response.headers.forEach((key, value) {
        log.writeln('  $key: $value');
      });
    }
    
    if (logBody && response.body != null) {
      final body = _formatBody(response.body!);
      log.writeln('Body:');
      log.writeln(body);
    }
    
    log.writeln('<== END RESPONSE (${response.duration}ms)');
    
    MCPLogger().logDebug(log.toString(), {
      'type': 'network_response',
      'statusCode': response.statusCode,
      'url': response.url,
      'duration': response.duration,
    });
  }
  
  String _formatBody(dynamic body) {
    if (body is String) {
      if (body.length > maxBodySize) {
        return '${body.substring(0, maxBodySize)}... (truncated)';
      }
      return body;
    }
    
    if (body is Map || body is List) {
      final json = jsonEncode(body);
      if (json.length > maxBodySize) {
        return '${json.substring(0, maxBodySize)}... (truncated)';
      }
      return JsonEncoder.withIndent('  ').convert(body);
    }
    
    return body.toString();
  }
}
```

### WebSocket Debugging

```dart
class WebSocketDebugger {
  final bool logConnections;
  final bool logMessages;
  final bool logPing;
  final bool logErrors;
  
  WebSocketDebugger({
    this.logConnections = true,
    this.logMessages = true,
    this.logPing = false,
    this.logErrors = true,
  });
  
  void onConnection(String url) {
    if (!logConnections) return;
    
    MCPLogger().logInfo('WebSocket connecting to: $url', {
      'type': 'websocket_connection',
      'url': url,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  void onOpen(String url) {
    if (!logConnections) return;
    
    MCPLogger().logInfo('WebSocket connected: $url', {
      'type': 'websocket_open',
      'url': url,
    });
  }
  
  void onMessage(dynamic message, {bool incoming = true}) {
    if (!logMessages) return;
    
    final direction = incoming ? 'RECEIVED' : 'SENT';
    MCPLogger().logDebug('WebSocket $direction: $message', {
      'type': 'websocket_message',
      'direction': direction.toLowerCase(),
      'message': message,
    });
  }
  
  void onError(dynamic error, String url) {
    if (!logErrors) return;
    
    MCPLogger().logError('WebSocket error', error: error, metadata: {
      'type': 'websocket_error',
      'url': url,
    });
  }
  
  void onClose(String url, int? code, String? reason) {
    if (!logConnections) return;
    
    MCPLogger().logInfo('WebSocket closed: $url', {
      'type': 'websocket_close',
      'url': url,
      'code': code,
      'reason': reason,
    });
  }
}
```

## Performance Monitoring

### Performance Tracker

```dart
class PerformanceTracker {
  final Map<String, PerformanceMetric> _metrics = {};
  final StreamController<PerformanceEvent> _eventStream = 
      StreamController.broadcast();
  
  void startOperation(String name, {Map<String, dynamic>? metadata}) {
    _metrics[name] = PerformanceMetric(
      name: name,
      startTime: DateTime.now(),
      metadata: metadata,
    );
    
    _eventStream.add(PerformanceEvent(
      type: PerformanceEventType.start,
      name: name,
      timestamp: DateTime.now(),
      metadata: metadata,
    ));
  }
  
  void endOperation(String name, {bool success = true}) {
    final metric = _metrics.remove(name);
    if (metric == null) return;
    
    final duration = DateTime.now().difference(metric.startTime);
    
    _eventStream.add(PerformanceEvent(
      type: PerformanceEventType.end,
      name: name,
      timestamp: DateTime.now(),
      duration: duration,
      success: success,
      metadata: metric.metadata,
    ));
    
    MCPLogger().logDebug('Performance: $name took ${duration.inMilliseconds}ms', {
      'type': 'performance',
      'operation': name,
      'duration_ms': duration.inMilliseconds,
      'success': success,
      'metadata': metric.metadata,
    });
  }
  
  Stream<PerformanceEvent> get events => _eventStream.stream;
  
  Map<String, dynamic> getStats() {
    final stats = <String, dynamic>{};
    
    // Group events by operation name
    final eventsByName = <String, List<PerformanceEvent>>{};
    
    events.listen((event) {
      if (event.type == PerformanceEventType.end) {
        eventsByName.putIfAbsent(event.name, () => []).add(event);
      }
    });
    
    // Calculate statistics
    eventsByName.forEach((name, events) {
      final durations = events
          .where((e) => e.duration != null)
          .map((e) => e.duration!.inMilliseconds)
          .toList();
      
      if (durations.isNotEmpty) {
        durations.sort();
        
        stats[name] = {
          'count': durations.length,
          'min': durations.first,
          'max': durations.last,
          'average': durations.reduce((a, b) => a + b) / durations.length,
          'median': durations[durations.length ~/ 2],
          'p95': durations[(durations.length * 0.95).floor()],
          'p99': durations[(durations.length * 0.99).floor()],
        };
      }
    });
    
    return stats;
  }
}

class PerformanceMetric {
  final String name;
  final DateTime startTime;
  final Map<String, dynamic>? metadata;
  
  PerformanceMetric({
    required this.name,
    required this.startTime,
    this.metadata,
  });
}

class PerformanceEvent {
  final PerformanceEventType type;
  final String name;
  final DateTime timestamp;
  final Duration? duration;
  final bool? success;
  final Map<String, dynamic>? metadata;
  
  PerformanceEvent({
    required this.type,
    required this.name,
    required this.timestamp,
    this.duration,
    this.success,
    this.metadata,
  });
}

enum PerformanceEventType {
  start,
  end,
}
```

### Frame Performance Monitor

```dart
class FramePerformanceMonitor {
  final List<FrameTiming> _frameTimings = [];
  StreamSubscription? _subscription;
  
  void start() {
    _subscription = WidgetsBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        _frameTimings.add(timing);
        
        // Check for jank
        final buildDuration = timing.buildDuration.inMilliseconds;
        final rasterDuration = timing.rasterDuration.inMilliseconds;
        final totalDuration = timing.totalSpan.inMilliseconds;
        
        if (totalDuration > 16) { // 60fps = 16.67ms per frame
          MCPLogger().logWarning('Frame jank detected', {
            'build_ms': buildDuration,
            'raster_ms': rasterDuration,
            'total_ms': totalDuration,
            'frame_number': timing.frameNumber,
          });
        }
      }
      
      // Keep only last 1000 frames
      if (_frameTimings.length > 1000) {
        _frameTimings.removeRange(0, _frameTimings.length - 1000);
      }
    });
  }
  
  void stop() {
    _subscription?.cancel();
  }
  
  Map<String, dynamic> getStats() {
    if (_frameTimings.isEmpty) return {};
    
    final buildTimes = _frameTimings.map((t) => t.buildDuration.inMicroseconds / 1000).toList();
    final rasterTimes = _frameTimings.map((t) => t.rasterDuration.inMicroseconds / 1000).toList();
    
    return {
      'frame_count': _frameTimings.length,
      'build': _calculateStats(buildTimes),
      'raster': _calculateStats(rasterTimes),
      'jank_frames': _frameTimings.where((t) => t.totalSpan.inMilliseconds > 16).length,
    };
  }
  
  Map<String, double> _calculateStats(List<double> values) {
    values.sort();
    final sum = values.reduce((a, b) => a + b);
    
    return {
      'min': values.first,
      'max': values.last,
      'average': sum / values.length,
      'median': values[values.length ~/ 2],
      'p95': values[(values.length * 0.95).floor()],
      'p99': values[(values.length * 0.99).floor()],
    };
  }
}
```

## Memory Debugging

### Memory Monitor

```dart
class MemoryMonitor {
  Timer? _timer;
  final List<MemorySnapshot> _snapshots = [];
  final StreamController<MemorySnapshot> _snapshotStream = 
      StreamController.broadcast();
  
  void start({Duration interval = const Duration(seconds: 1)}) {
    _timer = Timer.periodic(interval, (_) {
      _takeSnapshot();
    });
  }
  
  void stop() {
    _timer?.cancel();
  }
  
  void _takeSnapshot() {
    final snapshot = MemorySnapshot(
      timestamp: DateTime.now(),
      used: _getUsedMemory(),
      rss: _getRSSMemory(),
      heap: _getHeapMemory(),
    );
    
    _snapshots.add(snapshot);
    _snapshotStream.add(snapshot);
    
    // Check for memory leaks
    if (_snapshots.length > 10) {
      final recentSnapshots = _snapshots.sublist(_snapshots.length - 10);
      final trend = _calculateTrend(recentSnapshots);
      
      if (trend > 0.1) { // 10% increase
        MCPLogger().logWarning('Potential memory leak detected', {
          'trend': trend,
          'current_usage': snapshot.used,
          'increase': trend * 100,
        });
      }
    }
  }
  
  int _getUsedMemory() {
    return ProcessInfo.currentRss;
  }
  
  int _getRSSMemory() {
    return ProcessInfo.currentRss;
  }
  
  int _getHeapMemory() {
    return ProcessInfo.currentRss; // Approximation
  }
  
  double _calculateTrend(List<MemorySnapshot> snapshots) {
    if (snapshots.length < 2) return 0;
    
    final first = snapshots.first.used;
    final last = snapshots.last.used;
    
    return (last - first) / first;
  }
  
  Stream<MemorySnapshot> get snapshots => _snapshotStream.stream;
  
  Map<String, dynamic> getStats() {
    if (_snapshots.isEmpty) return {};
    
    final usedMemory = _snapshots.map((s) => s.used).toList();
    
    return {
      'current': _snapshots.last.used,
      'min': usedMemory.reduce((a, b) => a < b ? a : b),
      'max': usedMemory.reduce((a, b) => a > b ? a : b),
      'average': usedMemory.reduce((a, b) => a + b) / usedMemory.length,
      'trend': _calculateTrend(_snapshots),
    };
  }
}

class MemorySnapshot {
  final DateTime timestamp;
  final int used;
  final int rss;
  final int heap;
  
  MemorySnapshot({
    required this.timestamp,
    required this.used,
    required this.rss,
    required this.heap,
  });
}
```

### Object Tracker

```dart
class ObjectTracker {
  final Map<Type, Set<WeakReference>> _trackedObjects = {};
  final Map<Type, int> _allocationCounts = {};
  
  void track(Object object) {
    final type = object.runtimeType;
    
    _trackedObjects.putIfAbsent(type, () => {}).add(WeakReference(object));
    _allocationCounts[type] = (_allocationCounts[type] ?? 0) + 1;
    
    MCPLogger().logVerbose('Object allocated: $type', {
      'type': 'object_allocation',
      'object_type': type.toString(),
      'count': _allocationCounts[type],
    });
  }
  
  void checkLeaks() {
    _trackedObjects.forEach((type, references) {
      final alive = references.where((ref) => ref.target != null).length;
      final allocated = _allocationCounts[type] ?? 0;
      final deallocated = allocated - alive;
      
      if (alive > 100) { // Threshold for potential leak
        MCPLogger().logWarning('Potential object leak', {
          'type': 'object_leak',
          'object_type': type.toString(),
          'alive': alive,
          'allocated': allocated,
          'deallocated': deallocated,
        });
      }
    });
  }
  
  Map<String, dynamic> getStats() {
    final stats = <String, dynamic>{};
    
    _trackedObjects.forEach((type, references) {
      final alive = references.where((ref) => ref.target != null).length;
      final allocated = _allocationCounts[type] ?? 0;
      
      stats[type.toString()] = {
        'alive': alive,
        'allocated': allocated,
        'deallocated': allocated - alive,
      };
    });
    
    return stats;
  }
}
```

## Debug UI

### Debug Overlay

```dart
class DebugOverlay extends StatefulWidget {
  final Widget child;
  
  const DebugOverlay({Key? key, required this.child}) : super(key: key);
  
  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _showOverlay = false;
  final _performanceTracker = PerformanceTracker();
  final _memoryMonitor = MemoryMonitor();
  final _frameMonitor = FramePerformanceMonitor();
  
  @override
  void initState() {
    super.initState();
    _performanceTracker.events.listen((_) => setState(() {}));
    _memoryMonitor.snapshots.listen((_) => setState(() {}));
    _frameMonitor.start();
  }
  
  @override
  void dispose() {
    _frameMonitor.stop();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showOverlay)
          Positioned(
            top: 50,
            right: 10,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Debug Info',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildPerformanceInfo(),
                  const SizedBox(height: 10),
                  _buildMemoryInfo(),
                  const SizedBox(height: 10),
                  _buildFrameInfo(),
                ],
              ),
            ),
          ),
        Positioned(
          top: 50,
          left: 10,
          child: FloatingActionButton(
            mini: true,
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
            child: Icon(_showOverlay ? Icons.close : Icons.bug_report),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPerformanceInfo() {
    final stats = _performanceTracker.getStats();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
        ...stats.entries.map((entry) {
          final metric = entry.value as Map<String, dynamic>;
          return Text(
            '${entry.key}: ${metric['average']?.toStringAsFixed(1)}ms',
            style: TextStyle(color: Colors.white, fontSize: 12),
          );
        }),
      ],
    );
  }
  
  Widget _buildMemoryInfo() {
    final stats = _memoryMonitor.getStats();
    final current = stats['current'] ?? 0;
    final mb = current / (1024 * 1024);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Memory',
          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
        ),
        Text(
          'Current: ${mb.toStringAsFixed(1)} MB',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
        Text(
          'Trend: ${((stats['trend'] ?? 0) * 100).toStringAsFixed(1)}%',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
  
  Widget _buildFrameInfo() {
    final stats = _frameMonitor.getStats();
    final buildStats = stats['build'] as Map<String, double>?;
    final jankFrames = stats['jank_frames'] ?? 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frames',
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
        ),
        if (buildStats != null)
          Text(
            'Build: ${buildStats['average']?.toStringAsFixed(1)}ms',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        Text(
          'Jank frames: $jankFrames',
          style: TextStyle(
            color: jankFrames > 0 ? Colors.red : Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
```

### Debug Console

```dart
class DebugConsole extends StatefulWidget {
  const DebugConsole({Key? key}) : super(key: key);
  
  @override
  State<DebugConsole> createState() => _DebugConsoleState();
}

class _DebugConsoleState extends State<DebugConsole> {
  final _logs = <LogEntry>[];
  final _commandController = TextEditingController();
  LogLevel _filterLevel = LogLevel.info;
  String _searchQuery = '';
  StreamSubscription? _logSubscription;
  
  @override
  void initState() {
    super.initState();
    _logSubscription = MCPLogger().logStream.listen((entry) {
      setState(() {
        _logs.add(entry);
        if (_logs.length > 1000) {
          _logs.removeAt(0);
        }
      });
    });
  }
  
  @override
  void dispose() {
    _logSubscription?.cancel();
    _commandController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final filteredLogs = _logs.where((log) {
      if (log.level.index < _filterLevel.index) return false;
      if (_searchQuery.isNotEmpty && 
          !log.message.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Console'),
        actions: [
          DropdownButton<LogLevel>(
            value: _filterLevel,
            onChanged: (level) {
              setState(() {
                _filterLevel = level!;
              });
            },
            items: LogLevel.values.map((level) {
              return DropdownMenuItem(
                value: level,
                child: Text(level.name.toUpperCase()),
              );
            }).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              setState(() {
                _logs.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search logs...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredLogs.length,
              itemBuilder: (context, index) {
                final log = filteredLogs[index];
                return LogEntryWidget(log: log);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    decoration: const InputDecoration(
                      hintText: 'Enter debug command...',
                    ),
                    onSubmitted: _executeCommand,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _executeCommand(_commandController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _executeCommand(String command) {
    // Parse and execute debug commands
    final parts = command.split(' ');
    final cmd = parts.first;
    final args = parts.skip(1).toList();
    
    switch (cmd) {
      case 'clear':
        setState(() {
          _logs.clear();
        });
        break;
        
      case 'level':
        if (args.isNotEmpty) {
          final level = LogLevel.values.firstWhere(
            (l) => l.name == args.first,
            orElse: () => LogLevel.info,
          );
          setState(() {
            _filterLevel = level;
          });
        }
        break;
        
      case 'export':
        _exportLogs();
        break;
        
      case 'memory':
        _showMemoryStats();
        break;
        
      case 'performance':
        _showPerformanceStats();
        break;
        
      default:
        MCPLogger().logDebug('Unknown command: $command');
    }
    
    _commandController.clear();
  }
  
  void _exportLogs() async {
    final json = _logs.map((log) => log.toJson()).toList();
    final content = JsonEncoder.withIndent('  ').convert(json);
    
    // Save to file or share
    final file = File('debug_logs_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(content);
    
    MCPLogger().logInfo('Logs exported to: ${file.path}');
  }
  
  void _showMemoryStats() {
    // Show memory statistics dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Memory Statistics'),
        content: FutureBuilder<Map<String, dynamic>>(
          future: _getMemoryStats(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            
            final stats = snapshot.data!;
            return Text(
              JsonEncoder.withIndent('  ').convert(stats),
              style: const TextStyle(fontFamily: 'monospace'),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  Future<Map<String, dynamic>> _getMemoryStats() async {
    return {
      'rss': ProcessInfo.currentRss,
      'heap': ProcessInfo.currentRss, // Approximation
      'objects': ObjectTracker().getStats(),
    };
  }
  
  void _showPerformanceStats() {
    // Show performance statistics
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Performance Statistics'),
        content: Text(
          JsonEncoder.withIndent('  ').convert(
            PerformanceTracker().getStats(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class LogEntryWidget extends StatelessWidget {
  final LogEntry log;
  
  const LogEntryWidget({Key? key, required this.log}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(
        log.message,
        style: TextStyle(
          color: _getColorForLevel(log.level),
          fontSize: 14,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${log.timestamp.toString().substring(11, 19)} - ${log.level.name.toUpperCase()}',
        style: const TextStyle(fontSize: 12),
      ),
      children: [
        if (log.error != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Error: ${log.error}',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        if (log.stackTrace != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Stack trace:\n${log.stackTrace}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        if (log.metadata != null && log.metadata!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Metadata:\n${JsonEncoder.withIndent('  ').convert(log.metadata)}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
  
  Color _getColorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return Colors.red;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.debug:
        return Colors.green;
      case LogLevel.verbose:
        return Colors.grey;
      default:
        return Colors.black;
    }
  }
}
```

## Debug Tools Integration

### Flutter Inspector Integration

```dart
void setupFlutterInspector() {
  // Add custom properties to widgets
  debugFillProperties = (DiagnosticPropertiesBuilder properties) {
    if (this is FlutterMCPWidget) {
      properties.add(DiagnosticsProperty<McpConfig>(
        'config',
        (this as FlutterMCPWidget).config,
      ));
      properties.add(FlagProperty(
        'connected',
        value: (this as FlutterMCPWidget).isConnected,
        ifTrue: 'connected',
        ifFalse: 'disconnected',
      ));
    }
  };
}
```

### Chrome DevTools Integration

```dart
class ChromeDevToolsIntegration {
  static void setup() {
    if (kIsWeb) {
      // Register custom timeline events
      Timeline.startSync('MCP Operation');
      
      // Add custom performance marks
      window.performance.mark('mcp_start');
      
      // Enable performance observer
      js.context['MCPPerformanceObserver'] = js.allowInterop((entries) {
        for (final entry in entries) {
          MCPLogger().logDebug('Performance entry: ${entry.name}', {
            'duration': entry.duration,
            'startTime': entry.startTime,
          });
        }
      });
    }
  }
}
```

## Export and Analysis

### Log Exporter

```dart
class LogExporter {
  static Future<File> exportLogs({
    required List<LogEntry> logs,
    required String format,
    String? filePath,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = filePath ?? 'mcp_logs_$timestamp.$format';
    final file = File(path);
    
    String content;
    
    switch (format) {
      case 'json':
        content = JsonEncoder.withIndent('  ').convert(
          logs.map((log) => log.toJson()).toList(),
        );
        break;
        
      case 'csv':
        content = _toCsv(logs);
        break;
        
      case 'txt':
        content = _toPlainText(logs);
        break;
        
      default:
        throw ArgumentError('Unsupported format: $format');
    }
    
    await file.writeAsString(content);
    return file;
  }
  
  static String _toCsv(List<LogEntry> logs) {
    final buffer = StringBuffer();
    
    // Header
    buffer.writeln('Timestamp,Level,Message,Error,Metadata');
    
    // Rows
    for (final log in logs) {
      buffer.writeln([
        log.timestamp.toIso8601String(),
        log.level.name,
        '"${log.message.replaceAll('"', '""')}"',
        log.error != null ? '"${log.error.toString().replaceAll('"', '""')}"' : '',
        log.metadata != null ? '"${jsonEncode(log.metadata).replaceAll('"', '""')}"' : '',
      ].join(','));
    }
    
    return buffer.toString();
  }
  
  static String _toPlainText(List<LogEntry> logs) {
    final buffer = StringBuffer();
    
    for (final log in logs) {
      buffer.writeln('[${log.timestamp.toIso8601String()}] ${log.level.name.toUpperCase()} - ${log.message}');
      
      if (log.error != null) {
        buffer.writeln('  Error: ${log.error}');
      }
      
      if (log.metadata != null && log.metadata!.isNotEmpty) {
        buffer.writeln('  Metadata: ${jsonEncode(log.metadata)}');
      }
      
      buffer.writeln();
    }
    
    return buffer.toString();
  }
}
```

### Performance Analyzer

```dart
class PerformanceAnalyzer {
  static Map<String, dynamic> analyze(List<PerformanceEvent> events) {
    final analysis = <String, dynamic>{};
    
    // Group events by operation
    final operationGroups = <String, List<PerformanceEvent>>{};
    
    for (final event in events) {
      if (event.type == PerformanceEventType.end) {
        operationGroups.putIfAbsent(event.name, () => []).add(event);
      }
    }
    
    // Analyze each operation
    operationGroups.forEach((operation, events) {
      final durations = events
          .where((e) => e.duration != null)
          .map((e) => e.duration!.inMilliseconds)
          .toList();
      
      if (durations.isEmpty) return;
      
      durations.sort();
      
      analysis[operation] = {
        'count': durations.length,
        'total_time': durations.reduce((a, b) => a + b),
        'min': durations.first,
        'max': durations.last,
        'average': durations.reduce((a, b) => a + b) / durations.length,
        'median': durations[durations.length ~/ 2],
        'p95': durations[(durations.length * 0.95).floor()],
        'p99': durations[(durations.length * 0.99).floor()],
      };
    });
    
    // Overall statistics
    final allDurations = events
        .where((e) => e.type == PerformanceEventType.end && e.duration != null)
        .map((e) => e.duration!.inMilliseconds)
        .toList();
    
    if (allDurations.isNotEmpty) {
      analysis['overall'] = {
        'total_operations': allDurations.length,
        'total_time': allDurations.reduce((a, b) => a + b),
        'average_time': allDurations.reduce((a, b) => a + b) / allDurations.length,
      };
    }
    
    return analysis;
  }
  
  static List<String> generateReport(Map<String, dynamic> analysis) {
    final report = <String>[];
    
    report.add('Performance Analysis Report');
    report.add('=' * 30);
    report.add('');
    
    final overall = analysis['overall'] as Map<String, dynamic>?;
    if (overall != null) {
      report.add('Overall Statistics:');
      report.add('  Total operations: ${overall['total_operations']}');
      report.add('  Total time: ${overall['total_time']}ms');
      report.add('  Average time: ${overall['average_time'].toStringAsFixed(2)}ms');
      report.add('');
    }
    
    report.add('Operation Breakdown:');
    analysis.forEach((operation, stats) {
      if (operation == 'overall') return;
      
      final s = stats as Map<String, dynamic>;
      report.add('  $operation:');
      report.add('    Count: ${s['count']}');
      report.add('    Average: ${s['average'].toStringAsFixed(2)}ms');
      report.add('    Min/Max: ${s['min']}ms / ${s['max']}ms');
      report.add('    P95/P99: ${s['p95']}ms / ${s['p99']}ms');
      report.add('');
    });
    
    return report;
  }
}
```

## Best Practices

### Debug Configuration

```dart
// config/debug_config.dart
class DebugConfig {
  static const bool enableInProduction = false;
  
  static DebugOptions get developmentOptions => DebugOptions(
    logLevel: LogLevel.debug,
    enableNetworkLogging: true,
    enablePerformanceMonitoring: true,
    enableMemoryTracking: true,
    saveLogsToFile: true,
    prettifyJson: true,
  );
  
  static DebugOptions get productionOptions => DebugOptions(
    logLevel: LogLevel.warning,
    enableNetworkLogging: false,
    enablePerformanceMonitoring: false,
    enableMemoryTracking: false,
    saveLogsToFile: false,
    prettifyJson: false,
  );
  
  static DebugOptions get current {
    return kDebugMode ? developmentOptions : productionOptions;
  }
}
```

### Conditional Debugging

```dart
class ConditionalDebugger {
  static void debugPrint(String message, {bool condition = true}) {
    if (kDebugMode && condition) {
      print('[DEBUG] $message');
    }
  }
  
  static void debugLog(String message, {
    LogLevel level = LogLevel.debug,
    Map<String, dynamic>? metadata,
    bool condition = true,
  }) {
    if (kDebugMode && condition) {
      MCPLogger().log(message, level: level, metadata: metadata);
    }
  }
  
  static void debugBreak({bool condition = true}) {
    if (kDebugMode && condition) {
      debugger();
    }
  }
  
  static T debugTime<T>(String label, T Function() operation) {
    if (!kDebugMode) return operation();
    
    final stopwatch = Stopwatch()..start();
    
    try {
      return operation();
    } finally {
      stopwatch.stop();
      debugPrint('$label took ${stopwatch.elapsed.inMilliseconds}ms');
    }
  }
}
```

### Debug Assertions

```dart
void debugAssertions() {
  assert(() {
    // These only run in debug mode
    final config = FlutterMCP.instance.config;
    
    // Validate configuration
    if (config.servers.isEmpty) {
      throw StateError('No servers configured');
    }
    
    // Check for common issues
    for (final server in config.servers) {
      if (server.url.startsWith('http://') && !server.allowInsecure) {
        print('Warning: Using HTTP without allowInsecure flag');
      }
    }
    
    return true;
  }());
}
```

## Security Considerations

### Sanitizing Debug Output

```dart
class DebugSanitizer {
  static final _sensitivePatterns = [
    RegExp(r'"api_key"\s*:\s*"[^"]*"'),
    RegExp(r'"password"\s*:\s*"[^"]*"'),
    RegExp(r'"token"\s*:\s*"[^"]*"'),
    RegExp(r'"secret"\s*:\s*"[^"]*"'),
    RegExp(r'Bearer\s+[A-Za-z0-9\-._~\+\/]+=*'),
  ];
  
  static String sanitize(String input) {
    var sanitized = input;
    
    for (final pattern in _sensitivePatterns) {
      sanitized = sanitized.replaceAll(pattern, '[REDACTED]');
    }
    
    return sanitized;
  }
  
  static Map<String, dynamic> sanitizeJson(Map<String, dynamic> json) {
    final sanitized = <String, dynamic>{};
    
    json.forEach((key, value) {
      if (_isSensitiveKey(key)) {
        sanitized[key] = '[REDACTED]';
      } else if (value is Map<String, dynamic>) {
        sanitized[key] = sanitizeJson(value);
      } else if (value is String) {
        sanitized[key] = sanitize(value);
      } else {
        sanitized[key] = value;
      }
    });
    
    return sanitized;
  }
  
  static bool _isSensitiveKey(String key) {
    final lowercaseKey = key.toLowerCase();
    return lowercaseKey.contains('password') ||
           lowercaseKey.contains('token') ||
           lowercaseKey.contains('secret') ||
           lowercaseKey.contains('api_key') ||
           lowercaseKey.contains('apikey');
  }
}
```

### Debug Mode Security

```dart
class DebugSecurity {
  static void checkDebugModeSecurity() {
    if (kDebugMode) {
      // Warn about debug mode in production
      if (const String.fromEnvironment('ENVIRONMENT') == 'production') {
        throw StateError('Debug mode enabled in production!');
      }
      
      // Check for exposed debug endpoints
      if (Platform.environment['DEBUG_ENDPOINTS_ENABLED'] == 'true') {
        print('WARNING: Debug endpoints are exposed');
      }
      
      // Ensure debug logs are not persisted in production
      if (kIsWeb && window.location.hostname != 'localhost') {
        MCPLogger().configure(
          level: LogLevel.warning,
          logFilePath: null, // Disable file logging
        );
      }
    }
  }
}
```

## See Also

- [Common Issues](/doc/troubleshooting/common-issues.md)
- [Error Codes Reference](/doc/troubleshooting/error-codes.md)
- [Performance Tuning](/doc/troubleshooting/performance.md)
- [Testing Guide](/doc/advanced/testing.md)