import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:async';

/// Demo page showcasing Flutter MCP v1.0.0 features
class V1FeaturesDemo extends StatefulWidget {
  const V1FeaturesDemo({Key? key}) : super(key: key);

  @override
  State<V1FeaturesDemo> createState() => _V1FeaturesDemoState();
}

class _V1FeaturesDemoState extends State<V1FeaturesDemo> {
  // Results
  final List<String> _logs = [];

  // Health subscription
  StreamSubscription<MCPHealthCheckResult>? _healthSubscription;
  MCPHealthStatus? _currentHealthStatus;

  @override
  void initState() {
    super.initState();
    _subscribeToHealth();
    _checkInitialStatus();
  }

  @override
  void dispose() {
    _healthSubscription?.cancel();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      _logs.add(
          '[${DateTime.now().toLocal().toString().substring(11, 19)}] $message');
      if (_logs.length > 100) {
        _logs.removeAt(0);
      }
    });
  }

  void _subscribeToHealth() {
    try {
      _healthSubscription = FlutterMCP.instance.healthStream.listen(
        (health) {
          setState(() {
            _currentHealthStatus = health.status;
          });
          _addLog('Health: ${health.status.name} - ${health.message}');
        },
        onError: (error) {
          _addLog('Health stream error: $error');
        },
      );
    } catch (e) {
      _addLog('Failed to subscribe to health: $e');
    }
  }

  void _checkInitialStatus() {
    try {
      final status = FlutterMCP.instance.getSystemStatus();
      _addLog('System initialized: ${status['initialized'] ?? false}');
      _addLog(
          'Performance monitoring: ${status['performanceMonitoringEnabled'] ?? false}');
    } catch (e) {
      _addLog('Failed to get status: $e');
    }
  }

  // 1. System Health Check
  Future<void> _checkSystemHealth() async {
    _addLog('Checking system health...');
    try {
      final health = await FlutterMCP.instance.getSystemHealth();
      _addLog('Health status: ${health['status'] ?? 'unknown'}');
      _addLog('Health message: ${health['message'] ?? 'N/A'}');

      if (health['components'] != null) {
        final components = health['components'] as Map;
        _addLog('Components: ${components.keys.join(', ')}');
      }
    } catch (e) {
      _addLog('❌ Health check failed: $e');
    }
  }

  // 2. Batch Processing Demo
  Future<void> _demoBatchProcessing() async {
    _addLog('\n--- Batch Processing Demo ---');
    _addLog('Creating 10 simulated requests...');

    try {
      // Check if we have any LLM configured
      final status = FlutterMCP.instance.getSystemStatus();
      if ((status['llms'] ?? 0) == 0) {
        _addLog('❌ No LLM configured. Start services in main screen first.');
        return;
      }

      // Create simple test requests
      final requests = List.generate(
          10,
          (i) => () async {
                await Future.delayed(Duration(milliseconds: 50 + (i * 10)));
                return 'Result ${i + 1}';
              });

      final stopwatch = Stopwatch()..start();

      // Process batch - use the first available LLM
      final llmIds = FlutterMCP.instance.llmManager.getAllLlmIds();
      if (llmIds.isEmpty) {
        _addLog('❌ No LLM available');
        return;
      }

      final results = await FlutterMCP.instance.processBatch(
        llmId: llmIds.first,
        requests: requests,
      );

      stopwatch.stop();

      _addLog('✅ Batch completed in ${stopwatch.elapsedMilliseconds}ms');
      _addLog('Results: ${results.length} items processed');

      // Get batch statistics
      final stats = FlutterMCP.instance.getBatchStatistics();
      _addLog('Total batches: ${stats['totalBatches'] ?? 0}');
      _addLog(
          'Success rate: ${(stats['successRate'] ?? 0).toStringAsFixed(1)}%');
      _addLog(
          'Avg processing time: ${(stats['averageProcessingTimeMs'] ?? 0).toStringAsFixed(0)}ms');
    } catch (e) {
      _addLog('❌ Batch processing failed: $e');
    }
  }

  // 3. Performance Metrics
  Future<void> _showPerformanceMetrics() async {
    _addLog('\n--- Performance Metrics ---');
    try {
      // Get performance metrics from system status
      final status = FlutterMCP.instance.getSystemStatus();
      final metrics = status['performanceMetrics'] ?? {};

      if (metrics.isEmpty) {
        _addLog('No metrics available');
        return;
      }

      // Operations
      if (metrics['operations'] != null) {
        final ops = metrics['operations'] as Map;
        _addLog('Operations tracked: ${ops.length}');
        ops.forEach((key, value) {
          if (value is Map) {
            _addLog(
                '  $key: ${value['count'] ?? 0} calls, avg ${value['avgDuration'] ?? 0}ms');
          }
        });
      }

      // Resources
      if (metrics['resources'] != null) {
        final resources = metrics['resources'] as Map;
        resources.forEach((key, value) {
          _addLog('  $key: $value');
        });
      }
    } catch (e) {
      _addLog('❌ Failed to get metrics: $e');
    }
  }

  // 4. Memory Management Demo
  Future<void> _checkMemoryUsage() async {
    _addLog('\n--- Memory Management ---');
    try {
      final status = FlutterMCP.instance.getSystemStatus();

      if (status['performanceMetrics'] != null &&
          status['performanceMetrics']['resources'] != null) {
        final memory =
            status['performanceMetrics']['resources']['memory.usageMB'];
        if (memory != null) {
          _addLog('Current memory: ${memory['current']}MB');
          _addLog('Peak memory: ${memory['peak'] ?? 'N/A'}MB');
        }
      }

      // Trigger garbage collection
      _addLog('Triggering cleanup...');
      // In a real scenario, high memory would trigger automatic cleanup
    } catch (e) {
      _addLog('❌ Memory check failed: $e');
    }
  }

  // 5. OAuth Demo (Simulated)
  Future<void> _demoOAuth() async {
    _addLog('\n--- OAuth 2.1 Demo ---');
    _addLog('Note: This is a simulated demo');

    try {
      // Check if we have any LLM configured
      final llmIds = FlutterMCP.instance.llmManager.getAllLlmIds();
      if (llmIds.isEmpty) {
        _addLog('❌ No LLM configured. Start services first.');
        return;
      }

      _addLog('Initializing OAuth configuration...');
      await FlutterMCP.instance.initializeOAuth(
        llmId: llmIds.first,
        config: OAuthConfig(
          clientId: 'demo-client-id',
          clientSecret: 'demo-secret',
          authorizationUrl: 'https://example.com/auth',
          tokenUrl: 'https://example.com/token',
          scopes: ['read', 'write'],
        ),
      );

      _addLog('✅ OAuth configured');
      _addLog('In production: User would be redirected to auth URL');
      _addLog('Token would be stored securely');
      _addLog('Headers would include: Authorization: Bearer [token]');
    } catch (e) {
      _addLog('❌ OAuth demo failed: $e');
    }
  }

  Widget _buildHealthIndicator() {
    Color color;
    IconData icon;
    String text;

    switch (_currentHealthStatus) {
      case MCPHealthStatus.healthy:
        color = Colors.green;
        icon = Icons.check_circle;
        text = 'Healthy';
        break;
      case MCPHealthStatus.degraded:
        color = Colors.orange;
        icon = Icons.warning;
        text = 'Degraded';
        break;
      case MCPHealthStatus.unhealthy:
        color = Colors.red;
        icon = Icons.error;
        text = 'Unhealthy';
        break;
      default:
        color = Colors.grey;
        icon = Icons.help;
        text = 'Unknown';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter MCP v1.0.0 Features'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: _buildHealthIndicator()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Feature Buttons
          Container(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _checkSystemHealth,
                  icon: const Icon(Icons.health_and_safety),
                  label: const Text('Health Check'),
                ),
                ElevatedButton.icon(
                  onPressed: _demoBatchProcessing,
                  icon: const Icon(Icons.batch_prediction),
                  label: const Text('Batch Processing'),
                ),
                ElevatedButton.icon(
                  onPressed: _showPerformanceMetrics,
                  icon: const Icon(Icons.speed),
                  label: const Text('Performance'),
                ),
                ElevatedButton.icon(
                  onPressed: _checkMemoryUsage,
                  icon: const Icon(Icons.memory),
                  label: const Text('Memory'),
                ),
                ElevatedButton.icon(
                  onPressed: _demoOAuth,
                  icon: const Icon(Icons.lock),
                  label: const Text('OAuth Demo'),
                ),
              ],
            ),
          ),
          const Divider(),
          // Log Output
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  return Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: log.contains('❌')
                          ? Colors.red
                          : log.contains('✅')
                              ? Colors.green
                              : log.contains('---')
                                  ? Colors.blue
                                  : Colors.black87,
                      fontWeight: log.contains('---')
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
