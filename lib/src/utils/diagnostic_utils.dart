import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io' as io;

import 'logger.dart';
import 'platform_utils.dart';
import 'performance_monitor.dart';
import 'memory_manager.dart';

/// Diagnostic utilities for MCP health checking and troubleshooting
class DiagnosticUtils {
  static final MCPLogger _logger = MCPLogger('mcp.diagnostics');

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
      
      _logger.debug('System diagnostics collected');
    } catch (e, stackTrace) {
      _logger.error('Error collecting system diagnostics', e, stackTrace);
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
        _logger.warning('Error collecting detailed platform info', e);
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
      
      // Check client manager info if available
      if (mcp?._clientManager != null) {
        final clients = <String, dynamic>{};
        final clientIds = mcp._clientManager.getAllClientIds();
        for (final id in clientIds) {
          final client = mcp._clientManager.getClientInfo(id);
          if (client != null) {
            clients[id] = {
              'name': client.name,
              'connected': client.client.isConnected,
              'hasTransport': client.transport != null,
            };
          }
        }
        state['clients'] = clients;
        state['clientCount'] = clientIds.length;
      }
      
      // Check server manager info if available
      if (mcp?._serverManager != null) {
        final servers = <String, dynamic>{};
        final serverIds = mcp._serverManager.getAllServerIds();
        for (final id in serverIds) {
          final server = mcp._serverManager.getServerInfo(id);
          if (server != null) {
            servers[id] = {
              'name': server.name,
              'status': server.server.status.toString(),
            };
          }
        }
        state['servers'] = servers;
        state['serverCount'] = serverIds.length;
      }
      
      // Check LLM manager info if available
      if (mcp?._llmManager != null) {
        final llms = <String, dynamic>{};
        final llmIds = mcp._llmManager.getAllLlmIds();
        for (final id in llmIds) {
          final llmInfo = mcp._llmManager.getLlmInfo(id);
          if (llmInfo != null) {
            llms[id] = {
              'provider': llmInfo.providerName,
              'clientCount': llmInfo.llmClients.length,
              'serverCount': llmInfo.llmServers.length,
            };
          }
        }
        state['llms'] = llms;
        state['llmCount'] = llmIds.length;
      }
      
      // Check plugin system info if available
      if (mcp?._pluginSystem != null) {
        state['plugins'] = {
          'count': mcp._pluginSystem.getPluginCount(),
          'types': mcp._pluginSystem.getPluginTypeCounts(),
        };
      }
      
      // Check background service status
      if (mcp?._platformServices != null) {
        state['backgroundServiceRunning'] = mcp._platformServices.isBackgroundServiceRunning;
      }
      
      // Check scheduler info if available
      if (mcp?._scheduler != null) {
        state['scheduler'] = {
          'jobCount': mcp._scheduler.jobCount,
          'runningJobs': mcp._scheduler.activeJobCount,
          'isRunning': mcp._scheduler.isRunning,
        };
      }
      
    } catch (e, stackTrace) {
      _logger.error('Error collecting MCP state', e, stackTrace);
      state['error'] = {
        'message': e.toString(),
        'stackTrace': stackTrace.toString(),
      };
    }
    
    return state;
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
      final thresholdMB = 512; // Default high memory threshold if not configured
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
        health['status'] = health['status'] == 'healthy' ? 'degraded' : health['status'];
      }
      
      // Check client connections if available
      if (mcp?._clientManager != null) {
        final clientIds = mcp._clientManager.getAllClientIds();
        final connectedClients = clientIds.where((id) {
          final client = mcp._clientManager.getClientInfo(id);
          return client?.client.isConnected == true;
        }).length;
        
        final clientStatus = clientIds.isEmpty ? 'pass' : 
                             connectedClients == 0 ? 'fail' :
                             connectedClients < clientIds.length ? 'warn' : 'pass';
                             
        health['checks']['clients'] = {
          'status': clientStatus,
          'details': {
            'total': clientIds.length,
            'connected': connectedClients,
          },
        };
        
        if (clientStatus == 'fail') {
          health['status'] = 'unhealthy';
        } else if (clientStatus == 'warn') {
          health['status'] = health['status'] == 'healthy' ? 'degraded' : health['status'];
        }
      }
      
      // Check server status if available
      if (mcp?._serverManager != null) {
        final serverIds = mcp._serverManager.getAllServerIds();
        int runningServers = 0;
        
        for (final id in serverIds) {
          final server = mcp._serverManager.getServerInfo(id);
          if (server?.server.status.toString() == 'running') {
            runningServers++;
          }
        }
        
        final serverStatus = serverIds.isEmpty ? 'pass' :
                             runningServers == 0 ? 'fail' :
                             runningServers < serverIds.length ? 'warn' : 'pass';
                             
        health['checks']['servers'] = {
          'status': serverStatus,
          'details': {
            'total': serverIds.length,
            'running': runningServers,
          },
        };
        
        if (serverStatus == 'fail') {
          health['status'] = 'unhealthy';
        } else if (serverStatus == 'warn') {
          health['status'] = health['status'] == 'healthy' ? 'degraded' : health['status'];
        }
      }
      
      // Check LLM availability if any
      if (mcp?._llmManager != null) {
        final llmIds = mcp._llmManager.getAllLlmIds();
        health['checks']['llms'] = {
          'status': llmIds.isEmpty ? 'warn' : 'pass',
          'details': {
            'count': llmIds.length,
          },
        };
        
        if (llmIds.isEmpty) {
          health['status'] = health['status'] == 'healthy' ? 'degraded' : health['status'];
        }
      }
      
      _logger.debug('Health check completed with status: ${health['status']}');
    } catch (e, stackTrace) {
      _logger.error('Error performing health check', e, stackTrace);
      health['status'] = 'unhealthy';
      health['error'] = {
        'message': e.toString(),
        'stackTrace': stackTrace.toString(),
      };
    }
    
    return health;
  }
}