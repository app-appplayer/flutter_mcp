import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io' as io;

import 'logger.dart';
import 'platform_utils.dart';
import 'performance_monitor.dart';
import 'memory_manager.dart';

/// Diagnostic utilities for MCP health checking and troubleshooting
class DiagnosticUtils {
  static final Logger _logger = Logger('flutter_mcp.diagnostics');

  /// Collect comprehensive system diagnostics
  static Map<String, dynamic> collectSystemDiagnostics(dynamic mcp) {
    final diagnostics = <String, dynamic>{};

    try {
      // System information
      diagnostics['timestamp'] = DateTime.now().toIso8601String();
      diagnostics['platformInfo'] = _collectPlatformInfo();

      // Flutter MCP state
      if (mcp != null) {
        diagnostics['mcpState'] = getMcpState(mcp);
      }

      // Resource usage
      diagnostics['resources'] = _collectResourceUsage();

      // Performance metrics
      diagnostics['performanceMetrics'] = _collectPerformanceMetrics();

      // Feature availability
      diagnostics['featureSupport'] = PlatformUtils.getFeatureSupport();

      _logger.fine('System diagnostics collected');
    } catch (e, stackTrace) {
      _logger.severe('Error collecting system diagnostics', e, stackTrace);
      diagnostics['error'] = {
        'message': e.toString(),
        'stackTrace': stackTrace.toString(),
      };
    }

    return diagnostics;
  }

  /// Collect platform information
  static Map<String, dynamic> _collectPlatformInfo() {
    final info = <String, dynamic>{
      'platform': PlatformUtils.platformName,
      'isWeb': kIsWeb,
      'isMobile': PlatformUtils.isMobile,
      'isDesktop': PlatformUtils.isDesktop,
    };

    // Add additional non-web platform info when available
    if (!kIsWeb) {
      try {
        info['operatingSystem'] = io.Platform.operatingSystem;
        info['operatingSystemVersion'] = io.Platform.operatingSystemVersion;
        info['localHostname'] = io.Platform.localHostname;
        info['numberOfProcessors'] = io.Platform.numberOfProcessors;
      } catch (e) {
        _logger.warning('Error collecting detailed platform info: $e');
      }
    }

    return info;
  }

  /// Collect resource usage information
  static Map<String, dynamic> _collectResourceUsage() {
    final resources = <String, dynamic>{};

    // Memory usage
    resources['memory'] = {
      'currentUsageMB': MemoryManager.instance.currentMemoryUsageMB,
      'peakUsageMB': MemoryManager.instance.peakMemoryUsageMB,
    };

    return resources;
  }

  /// Collect performance metrics
  static Map<String, dynamic> _collectPerformanceMetrics() {
    return {
      'metrics': PerformanceMonitor.instance.getMetricsSummary(),
    };
  }

  /// Get FlutterMCP state diagnostics
  static Map<String, dynamic> getMcpState(dynamic mcp) {
    final state = <String, dynamic>{};

    try {
      // Extract basic info safely
      state['initialized'] = mcp?.isInitialized ?? false;

      // Use public API instead of private fields
      if (mcp != null && mcp.isInitialized) {
        // Get client manager status
        final clientStatus = mcp.clientManagerStatus;
        state['clients'] = clientStatus['clients'] ?? {};
        state['clientCount'] = clientStatus['total'] ?? 0;

        // Get server manager status
        final serverStatus = mcp.serverManagerStatus;
        state['servers'] = serverStatus['servers'] ?? {};
        state['serverCount'] = serverStatus['total'] ?? 0;

        // Get LLM manager status
        final llmStatus = mcp.llmManagerStatus;
        state['llms'] = llmStatus['llms'] ?? {};
        state['llmCount'] = llmStatus['total'] ?? 0;
        state['registeredPlugins'] = llmStatus['registeredPlugins'] ?? [];

        // Get plugin registry status
        final pluginStatus = mcp.pluginRegistryStatus;
        state['plugins'] = {
          'count': pluginStatus['pluginCount'] ?? 0,
          'names': pluginStatus['plugins'] ?? [],
        };

        // Get platform services status
        final platformStatus = mcp.platformServicesStatus;
        state['backgroundServiceRunning'] =
            platformStatus['backgroundServiceRunning'] ?? false;
        state['platformName'] = platformStatus['platformName'] ?? 'Unknown';

        // Get scheduler status
        state['scheduler'] = mcp.schedulerStatus;
      }
    } catch (e, stackTrace) {
      _logger.severe('Error collecting MCP state', e, stackTrace);
      state['error'] = {
        'message': e.toString(),
        'stackTrace': stackTrace.toString(),
      };
    }

    return state;
  }

  /// Run comprehensive diagnostic checks for troubleshooting
  static Future<Map<String, dynamic>> runDiagnostics(dynamic mcp) async {
    final diagnostics = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'version': '1.0.0',
      'diagnosticResults': <String, dynamic>{},
    };

    try {
      // Basic connectivity tests
      diagnostics['diagnosticResults']['connectivity'] =
          await _checkConnectivity();

      // Performance benchmarks
      diagnostics['diagnosticResults']['performance'] =
          await _benchmarkPerformance();

      // Resource availability
      diagnostics['diagnosticResults']['resources'] =
          await _checkResourceAvailability();

      // Configuration validation
      diagnostics['diagnosticResults']['configuration'] =
          _validateConfiguration(mcp);

      // Component integrity
      diagnostics['diagnosticResults']['integrity'] =
          await _checkComponentIntegrity(mcp);

      _logger.info('Comprehensive diagnostics completed');
    } catch (e, stackTrace) {
      _logger.severe('Error running diagnostics', e, stackTrace);
      diagnostics['error'] = {
        'message': e.toString(),
        'stackTrace': stackTrace.toString(),
      };
    }

    return diagnostics;
  }

  /// Check network connectivity
  static Future<Map<String, dynamic>> _checkConnectivity() async {
    final connectivity = <String, dynamic>{
      'status': 'checking',
      'tests': <String, dynamic>{},
    };

    try {
      // Test localhost connectivity
      final localTest =
          await _testConnection('127.0.0.1', 80, Duration(seconds: 5));
      connectivity['tests']['localhost'] = localTest;

      // Test external connectivity (if not in restricted environment)
      if (!kIsWeb) {
        final externalTest =
            await _testConnection('8.8.8.8', 53, Duration(seconds: 5));
        connectivity['tests']['external'] = externalTest;
      }

      // Determine overall status
      final allPassed =
          connectivity['tests'].values.every((test) => test['success'] == true);
      connectivity['status'] = allPassed ? 'healthy' : 'degraded';
    } catch (e) {
      connectivity['status'] = 'failed';
      connectivity['error'] = e.toString();
    }

    return connectivity;
  }

  /// Test connection to specific host and port
  static Future<Map<String, dynamic>> _testConnection(
      String host, int port, Duration timeout) async {
    final result = <String, dynamic>{
      'host': host,
      'port': port,
      'success': false,
      'responseTime': 0,
    };

    try {
      final stopwatch = Stopwatch()..start();

      if (!kIsWeb) {
        final socket = await io.Socket.connect(host, port).timeout(timeout);
        await socket.close();
        result['success'] = true;
      } else {
        // For web, we can't do direct socket connections
        result['success'] = true; // Assume connectivity
        result['note'] = 'Web platform - connectivity assumed';
      }

      stopwatch.stop();
      result['responseTime'] = stopwatch.elapsedMilliseconds;
    } catch (e) {
      result['success'] = false;
      result['error'] = e.toString();
    }

    return result;
  }

  /// Run performance benchmarks
  static Future<Map<String, dynamic>> _benchmarkPerformance() async {
    final performance = <String, dynamic>{
      'status': 'running',
      'benchmarks': <String, dynamic>{},
    };

    try {
      // CPU-intensive task benchmark
      final cpuBenchmark = await _benchmarkCpuTask();
      performance['benchmarks']['cpu'] = cpuBenchmark;

      // Memory allocation benchmark
      final memoryBenchmark = _benchmarkMemoryAllocation();
      performance['benchmarks']['memory'] = memoryBenchmark;

      // Async task benchmark
      final asyncBenchmark = await _benchmarkAsyncTasks();
      performance['benchmarks']['async'] = asyncBenchmark;

      performance['status'] = 'completed';
    } catch (e) {
      performance['status'] = 'failed';
      performance['error'] = e.toString();
    }

    return performance;
  }

  /// Benchmark CPU-intensive task
  static Future<Map<String, dynamic>> _benchmarkCpuTask() async {
    final stopwatch = Stopwatch()..start();

    // Perform some CPU-intensive calculations
    var result = 0;
    for (int i = 0; i < 1000000; i++) {
      result += (i * 3) % 97;
    }

    stopwatch.stop();

    return {
      'taskType': 'cpu_intensive',
      'iterations': 1000000,
      'result': result,
      'durationMs': stopwatch.elapsedMilliseconds,
      'operationsPerSecond':
          (1000000 / stopwatch.elapsedMilliseconds * 1000).round(),
    };
  }

  /// Benchmark memory allocation
  static Map<String, dynamic> _benchmarkMemoryAllocation() {
    final stopwatch = Stopwatch()..start();
    final initialMemory = MemoryManager.instance.currentMemoryUsageMB;

    // Allocate and release memory
    final lists = <List<int>>[];
    for (int i = 0; i < 1000; i++) {
      lists.add(List.generate(1000, (index) => index));
    }

    final peakMemory = MemoryManager.instance.currentMemoryUsageMB;

    // Clear allocations
    lists.clear();

    stopwatch.stop();
    final finalMemory = MemoryManager.instance.currentMemoryUsageMB;

    return {
      'taskType': 'memory_allocation',
      'allocations': 1000,
      'durationMs': stopwatch.elapsedMilliseconds,
      'initialMemoryMB': initialMemory,
      'peakMemoryMB': peakMemory,
      'finalMemoryMB': finalMemory,
      'memoryDeltaMB': finalMemory - initialMemory,
    };
  }

  /// Benchmark async task performance
  static Future<Map<String, dynamic>> _benchmarkAsyncTasks() async {
    final stopwatch = Stopwatch()..start();

    // Run multiple async tasks concurrently
    final futures = <Future<int>>[];
    for (int i = 0; i < 100; i++) {
      futures.add(_simulateAsyncWork(i));
    }

    final results = await Future.wait(futures);
    stopwatch.stop();

    return {
      'taskType': 'async_concurrent',
      'taskCount': 100,
      'durationMs': stopwatch.elapsedMilliseconds,
      'averageTaskTime': stopwatch.elapsedMilliseconds / 100,
      'totalResults': results.length,
      'resultSum': results.fold(0, (sum, result) => sum + result),
    };
  }

  /// Simulate async work
  static Future<int> _simulateAsyncWork(int input) async {
    await Future.delayed(Duration(milliseconds: 10));
    return input * 2;
  }

  /// Check resource availability
  static Future<Map<String, dynamic>> _checkResourceAvailability() async {
    final resources = <String, dynamic>{
      'status': 'checking',
      'available': <String, dynamic>{},
    };

    try {
      // Check memory availability
      final memoryInfo = MemoryManager.instance;
      resources['available']['memory'] = {
        'currentUsageMB': memoryInfo.currentMemoryUsageMB,
        'peakUsageMB': memoryInfo.peakMemoryUsageMB,
        'isMemoryPressure': memoryInfo.currentMemoryUsageMB > 512,
      };

      // Check file system (non-web only)
      if (!kIsWeb) {
        resources['available']['filesystem'] = await _checkFileSystemAccess();
      }

      // Check performance monitoring
      try {
        final metricsCount =
            PerformanceMonitor.instance.getMetricsSummary().length;
        resources['available']['performanceMonitoring'] = {
          'enabled': true,
          'metricsCount': metricsCount,
        };
      } catch (e) {
        resources['available']['performanceMonitoring'] = {
          'enabled': false,
          'error': e.toString(),
        };
      }

      resources['status'] = 'available';
    } catch (e) {
      resources['status'] = 'limited';
      resources['error'] = e.toString();
    }

    return resources;
  }

  /// Check file system access
  static Future<Map<String, dynamic>> _checkFileSystemAccess() async {
    final filesystem = <String, dynamic>{
      'readable': false,
      'writable': false,
    };

    try {
      // Test read access to current directory
      final directory = io.Directory.current;
      await directory.list().take(1).toList();
      filesystem['readable'] = true;
      filesystem['currentDirectory'] = directory.path;

      // Test write access with temporary file
      try {
        final tempFile = io.File('${directory.path}/.mcp_diagnostic_temp');
        await tempFile.writeAsString('test');
        await tempFile.delete();
        filesystem['writable'] = true;
      } catch (e) {
        filesystem['writeError'] = e.toString();
      }
    } catch (e) {
      filesystem['readError'] = e.toString();
    }

    return filesystem;
  }

  /// Validate configuration
  static Map<String, dynamic> _validateConfiguration(dynamic mcp) {
    final validation = <String, dynamic>{
      'status': 'validating',
      'issues': <String>[],
      'warnings': <String>[],
    };

    try {
      if (mcp == null) {
        validation['issues'].add('MCP instance is null');
        validation['status'] = 'invalid';
        return validation;
      }

      if (!mcp.isInitialized) {
        validation['issues'].add('MCP is not initialized');
      }

      // Check for common configuration issues
      final platformStatus = mcp.platformServicesStatus;
      if (platformStatus['platformName'] == 'Unknown') {
        validation['warnings'].add('Platform detection may be unreliable');
      }

      // Add more validation checks here based on actual MCP configuration needs

      validation['status'] = validation['issues'].isEmpty ? 'valid' : 'invalid';
    } catch (e) {
      validation['status'] = 'error';
      validation['error'] = e.toString();
    }

    return validation;
  }

  /// Check component integrity
  static Future<Map<String, dynamic>> _checkComponentIntegrity(
      dynamic mcp) async {
    final integrity = <String, dynamic>{
      'status': 'checking',
      'components': <String, dynamic>{},
    };

    try {
      if (mcp != null && mcp.isInitialized) {
        // Check client manager integrity
        final clientStatus = mcp.clientManagerStatus;
        integrity['components']['clientManager'] = {
          'healthy': clientStatus != null,
          'clientCount': clientStatus?['total'] ?? 0,
        };

        // Check server manager integrity
        final serverStatus = mcp.serverManagerStatus;
        integrity['components']['serverManager'] = {
          'healthy': serverStatus != null,
          'serverCount': serverStatus?['total'] ?? 0,
        };

        // Check LLM manager integrity
        final llmStatus = mcp.llmManagerStatus;
        integrity['components']['llmManager'] = {
          'healthy': llmStatus != null,
          'llmCount': llmStatus?['total'] ?? 0,
        };

        // Check plugin registry integrity
        final pluginStatus = mcp.pluginRegistryStatus;
        integrity['components']['pluginRegistry'] = {
          'healthy': pluginStatus != null,
          'pluginCount': pluginStatus?['pluginCount'] ?? 0,
        };
      }

      final allHealthy = integrity['components']
          .values
          .every((component) => component['healthy'] == true);
      integrity['status'] = allHealthy ? 'healthy' : 'degraded';
    } catch (e) {
      integrity['status'] = 'unhealthy';
      integrity['error'] = e.toString();
    }

    return integrity;
  }

  /// Check health of the MCP system
  static Future<Map<String, dynamic>> checkHealth(dynamic mcp) async {
    final health = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'healthy',
      'checks': <String, dynamic>{},
    };

    try {
      // Check initialization
      health['checks']['initialization'] = {
        'status': mcp?.isInitialized == true ? 'pass' : 'fail',
        'details': {'initialized': mcp?.isInitialized ?? false},
      };

      if (mcp?.isInitialized != true) {
        health['status'] = 'unhealthy';
      }

      // Check memory usage
      final currentMemory = MemoryManager.instance.currentMemoryUsageMB;
      final thresholdMB =
          512; // Default high memory threshold if not configured
      final memoryStatus = currentMemory > thresholdMB ? 'warn' : 'pass';
      health['checks']['memory'] = {
        'status': memoryStatus,
        'details': {
          'currentUsageMB': MemoryManager.instance.currentMemoryUsageMB,
          'peakUsageMB': MemoryManager.instance.peakMemoryUsageMB,
          'isHighMemory': currentMemory > thresholdMB,
        },
      };

      if (memoryStatus == 'warn') {
        health['status'] =
            health['status'] == 'healthy' ? 'degraded' : health['status'];
      }

      // Check client connections using public API
      if (mcp != null && mcp.isInitialized) {
        final clientStatus = mcp.clientManagerStatus;
        final totalClients = clientStatus['total'] ?? 0;
        final connectedClients = (clientStatus['clients'] as Map?)
                ?.values
                .where((client) => client['connected'] == true)
                .length ??
            0;

        final statusCode = totalClients == 0
            ? 'pass'
            : connectedClients == 0
                ? 'fail'
                : connectedClients < totalClients
                    ? 'warn'
                    : 'pass';

        health['checks']['clients'] = {
          'status': statusCode,
          'details': {
            'total': totalClients,
            'connected': connectedClients,
          },
        };

        if (statusCode == 'fail') {
          health['status'] = 'unhealthy';
        } else if (statusCode == 'warn') {
          health['status'] =
              health['status'] == 'healthy' ? 'degraded' : health['status'];
        }
      }

      // Check server status using public API
      if (mcp != null && mcp.isInitialized) {
        final serverStatus = mcp.serverManagerStatus;
        final totalServers = serverStatus['total'] ?? 0;
        int runningServers = 0;

        final servers = serverStatus['servers'] as Map?;
        if (servers != null) {
          for (final serverData in servers.values) {
            // Check if server has a running status or assume running if registered
            final isRunning = serverData is Map &&
                (serverData['status'] == 'running' ||
                    serverData['connected'] == true);
            if (isRunning || serverData != null) {
              runningServers++;
            }
          }
        }

        final statusCode = totalServers == 0
            ? 'pass'
            : runningServers == 0
                ? 'fail'
                : runningServers < totalServers
                    ? 'warn'
                    : 'pass';

        health['checks']['servers'] = {
          'status': statusCode,
          'details': {
            'total': totalServers,
            'running': runningServers,
          },
        };

        if (statusCode == 'fail') {
          health['status'] = 'unhealthy';
        } else if (statusCode == 'warn') {
          health['status'] =
              health['status'] == 'healthy' ? 'degraded' : health['status'];
        }
      }

      // Check LLM availability using public API
      if (mcp != null && mcp.isInitialized) {
        final llmStatus = mcp.llmManagerStatus;
        final llmCount = llmStatus['total'] ?? 0;

        health['checks']['llms'] = {
          'status': llmCount == 0 ? 'warn' : 'pass',
          'details': {
            'count': llmCount,
          },
        };

        if (llmCount == 0) {
          health['status'] =
              health['status'] == 'healthy' ? 'degraded' : health['status'];
        }
      }

      _logger.fine('Health check completed with status: ${health['status']}');
    } catch (e, stackTrace) {
      _logger.severe('Error performing health check', e, stackTrace);
      health['status'] = 'unhealthy';
      health['error'] = {
        'message': e.toString(),
        'stackTrace': stackTrace.toString(),
      };
    }

    return health;
  }
}
