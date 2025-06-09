import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:universal_html/js_util.dart';

import '../../utils/logger.dart';
import '../../utils/web_memory_monitor.dart';

/// Web platform improvements to address common limitations
class WebPlatformImprovements {
  final Logger _logger = Logger('flutter_mcp.web_platform_improvements');
  
  // Platform capabilities
  bool _supportsStorageQuota = false;
  bool _supportsPerformanceObserver = false;
  bool _supportsNavigationTiming = false;
  bool _supportsVisibilityAPI = false;
  bool _supportsConnectionAPI = false;
  
  // Storage management
  int _storageQuota = 0;
  int _storageUsage = 0;
  
  // Performance metrics
  final List<Map<String, dynamic>> _performanceMetrics = [];
  Timer? _performanceTimer;
  
  // Visibility state
  bool _isVisible = true;
  final StreamController<bool> _visibilityController = StreamController.broadcast();
  
  // Connection state
  bool _isOnline = true;
  String _connectionType = 'unknown';
  final StreamController<Map<String, dynamic>> _connectionController = StreamController.broadcast();
  
  static WebPlatformImprovements? _instance;
  static WebPlatformImprovements get instance => _instance ??= WebPlatformImprovements._internal();
  
  WebPlatformImprovements._internal();
  
  /// Initialize web platform improvements
  Future<void> initialize() async {
    if (!kIsWeb) {
      _logger.info('Not running on web platform, skipping web improvements');
      return;
    }
    
    _logger.info('Initializing web platform improvements');
    
    await _detectCapabilities();
    await _initializeStorageManagement();
    await _initializePerformanceMonitoring();
    await _initializeVisibilityHandling();
    await _initializeConnectionHandling();
    
    // Start enhanced web memory monitoring
    WebMemoryMonitor.instance.startMonitoring(
      interval: Duration(seconds: 10),
    );
    
    _logger.info('Web platform improvements initialized');
  }
  
  /// Detect available web platform capabilities
  Future<void> _detectCapabilities() async {
    try {
      // Check storage quota API
      _supportsStorageQuota = hasProperty(html.window, 'navigator') &&
          hasProperty(getProperty(html.window, 'navigator'), 'storage') &&
          hasProperty(getProperty(getProperty(html.window, 'navigator'), 'storage'), 'estimate');
      
      // Check performance observer API
      _supportsPerformanceObserver = hasProperty(html.window, 'PerformanceObserver');
      
      // Check navigation timing API
      _supportsNavigationTiming = hasProperty(html.window, 'performance') &&
          hasProperty(getProperty(html.window, 'performance'), 'navigation');
      
      // Check page visibility API
      _supportsVisibilityAPI = hasProperty(html.document, 'hidden') &&
          hasProperty(html.document, 'visibilityState');
      
      // Check network connection API
      _supportsConnectionAPI = hasProperty(html.window, 'navigator') &&
          hasProperty(getProperty(html.window, 'navigator'), 'connection');
      
      _logger.info('Web capabilities: '
          'storageQuota=$_supportsStorageQuota, '
          'performanceObserver=$_supportsPerformanceObserver, '
          'navigationTiming=$_supportsNavigationTiming, '
          'visibilityAPI=$_supportsVisibilityAPI, '
          'connectionAPI=$_supportsConnectionAPI');
      
    } catch (e) {
      _logger.warning('Error detecting web capabilities: $e');
    }
  }
  
  /// Initialize storage quota management
  Future<void> _initializeStorageManagement() async {
    if (!_supportsStorageQuota) {
      _logger.info('Storage quota API not supported');
      return;
    }
    
    try {
      await _updateStorageInfo();
      
      // Check storage every 30 seconds
      Timer.periodic(Duration(seconds: 30), (_) {
        _updateStorageInfo();
      });
      
    } catch (e) {
      _logger.warning('Failed to initialize storage management: $e');
    }
  }
  
  /// Update storage quota and usage information
  Future<void> _updateStorageInfo() async {
    try {
      final navigator = getProperty(html.window, 'navigator');
      final storage = getProperty(navigator, 'storage');
      final estimate = await promiseToFuture(callMethod(storage, 'estimate', []));
      
      _storageQuota = (estimate['quota'] as num?)?.toInt() ?? 0;
      _storageUsage = (estimate['usage'] as num?)?.toInt() ?? 0;
      
      final usagePercent = _storageQuota > 0 ? (_storageUsage / _storageQuota * 100) : 0;
      
      if (usagePercent > 80) {
        _logger.warning('Storage usage high: ${usagePercent.toStringAsFixed(1)}% '
            '(${_formatBytes(_storageUsage)} / ${_formatBytes(_storageQuota)})');
      } else {
        _logger.fine('Storage usage: ${usagePercent.toStringAsFixed(1)}% '
            '(${_formatBytes(_storageUsage)} / ${_formatBytes(_storageQuota)})');
      }
      
    } catch (e) {
      _logger.warning('Failed to update storage info: $e');
    }
  }
  
  /// Initialize performance monitoring
  Future<void> _initializePerformanceMonitoring() async {
    if (!_supportsPerformanceObserver) {
      _logger.info('Performance Observer API not supported, using basic monitoring');
      _startBasicPerformanceMonitoring();
      return;
    }
    
    try {
      // Monitor different types of performance entries
      _setupPerformanceObserver('navigation', (entries) {
        for (final entry in entries) {
          _recordPerformanceMetric('navigation', entry);
        }
      });
      
      _setupPerformanceObserver('resource', (entries) {
        for (final entry in entries) {
          _recordPerformanceMetric('resource', entry);
        }
      });
      
      _setupPerformanceObserver('measure', (entries) {
        for (final entry in entries) {
          _recordPerformanceMetric('measure', entry);
        }
      });
      
      _setupPerformanceObserver('mark', (entries) {
        for (final entry in entries) {
          _recordPerformanceMetric('mark', entry);
        }
      });
      
      _logger.info('Performance monitoring initialized');
      
    } catch (e) {
      _logger.warning('Failed to setup performance observer: $e');
      _startBasicPerformanceMonitoring();
    }
  }
  
  /// Set up a performance observer for specific entry types
  void _setupPerformanceObserver(String entryType, Function(List<dynamic>) callback) {
    try {
      final observer = callMethod(html.window, 'PerformanceObserver', [(List<dynamic> entries) {
        callback(entries);
      }]);
      
      callMethod(observer, 'observe', [{'entryTypes': [entryType]}]);
      
    } catch (e) {
      _logger.warning('Failed to setup performance observer for $entryType: $e');
    }
  }
  
  /// Start basic performance monitoring fallback
  void _startBasicPerformanceMonitoring() {
    _performanceTimer = Timer.periodic(Duration(seconds: 15), (_) {
      _collectBasicPerformanceMetrics();
    });
  }
  
  /// Collect basic performance metrics
  void _collectBasicPerformanceMetrics() {
    try {
      final performance = getProperty(html.window, 'performance');
      if (performance == null) return;
      
      final timing = getProperty(performance, 'timing');
      if (timing == null) return;
      
      final now = callMethod(performance, 'now', []) as num;
      
      _recordPerformanceMetric('basic', {
        'type': 'basic-timing',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'performanceNow': now.toDouble(),
        'loadComplete': getProperty(timing, 'loadEventEnd') != null,
      });
      
      // Check memory if available
      final memory = getProperty(performance, 'memory');
      if (memory != null) {
        _recordPerformanceMetric('memory', {
          'type': 'memory-usage',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'usedJSHeapSize': getProperty(memory, 'usedJSHeapSize'),
          'totalJSHeapSize': getProperty(memory, 'totalJSHeapSize'),
          'jsHeapSizeLimit': getProperty(memory, 'jsHeapSizeLimit'),
        });
      }
      
    } catch (e) {
      _logger.warning('Error collecting basic performance metrics: $e');
    }
  }
  
  /// Record a performance metric
  void _recordPerformanceMetric(String category, dynamic entry) {
    try {
      final metric = {
        'category': category,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'entry': _convertPerformanceEntry(entry),
      };
      
      _performanceMetrics.add(metric);
      
      // Keep only recent metrics (last 100)
      if (_performanceMetrics.length > 100) {
        _performanceMetrics.removeAt(0);
      }
      
    } catch (e) {
      _logger.warning('Error recording performance metric: $e');
    }
  }
  
  /// Convert performance entry to serializable format
  Map<String, dynamic> _convertPerformanceEntry(dynamic entry) {
    if (entry is Map) return Map<String, dynamic>.from(entry);
    
    try {
      // Try to extract common properties
      return {
        'name': getProperty(entry, 'name') ?? 'unknown',
        'entryType': getProperty(entry, 'entryType') ?? 'unknown',
        'startTime': getProperty(entry, 'startTime') ?? 0,
        'duration': getProperty(entry, 'duration') ?? 0,
      };
    } catch (e) {
      return {'error': 'Failed to convert entry: $e'};
    }
  }
  
  /// Initialize page visibility handling
  Future<void> _initializeVisibilityHandling() async {
    if (!_supportsVisibilityAPI) {
      _logger.info('Page Visibility API not supported');
      return;
    }
    
    try {
      _isVisible = !html.document.hidden!;
      
      html.document.onVisibilityChange.listen((_) {
        final wasVisible = _isVisible;
        _isVisible = !html.document.hidden!;
        
        if (wasVisible != _isVisible) {
          _visibilityController.add(_isVisible);
          
          if (_isVisible) {
            _logger.fine('Page became visible');
            _onPageVisible();
          } else {
            _logger.fine('Page became hidden');
            _onPageHidden();
          }
        }
      });
      
      _logger.info('Page visibility monitoring initialized');
      
    } catch (e) {
      _logger.warning('Failed to initialize visibility handling: $e');
    }
  }
  
  /// Handle page becoming visible
  void _onPageVisible() {
    // Resume memory monitoring with higher frequency
    WebMemoryMonitor.instance.startMonitoring(
      interval: Duration(seconds: 5),
    );
    
    // Update storage info
    _updateStorageInfo();
  }
  
  /// Handle page becoming hidden
  void _onPageHidden() {
    // Reduce memory monitoring frequency
    WebMemoryMonitor.instance.startMonitoring(
      interval: Duration(seconds: 30),
    );
  }
  
  /// Initialize network connection handling
  Future<void> _initializeConnectionHandling() async {
    if (!_supportsConnectionAPI) {
      _logger.info('Network Connection API not supported');
      return;
    }
    
    try {
      final navigator = getProperty(html.window, 'navigator');
      final connection = getProperty(navigator, 'connection');
      
      _isOnline = getProperty(navigator, 'onLine') as bool? ?? true;
      _connectionType = getProperty(connection, 'effectiveType') as String? ?? 'unknown';
      
      // Listen for online/offline events
      html.window.onOnline.listen((_) {
        _isOnline = true;
        _connectionController.add({
          'online': true,
          'type': _connectionType,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        _logger.info('Connection restored');
      });
      
      html.window.onOffline.listen((_) {
        _isOnline = false;
        _connectionController.add({
          'online': false,
          'type': 'none',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        _logger.warning('Connection lost');
      });
      
      // Listen for connection changes
      callMethod(connection, 'addEventListener', ['change', (event) {
        _connectionType = getProperty(connection, 'effectiveType') as String? ?? 'unknown';
        _connectionController.add({
          'online': _isOnline,
          'type': _connectionType,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'downlink': getProperty(connection, 'downlink'),
          'rtt': getProperty(connection, 'rtt'),
        });
        _logger.info('Connection changed to $_connectionType');
      }]);
      
      _logger.info('Network connection monitoring initialized');
      
    } catch (e) {
      _logger.warning('Failed to initialize connection handling: $e');
    }
  }
  
  /// Format bytes in human readable format
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    final size = bytes / math.pow(1024, i);
    
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
  
  /// Get current platform status
  Map<String, dynamic> getPlatformStatus() {
    return {
      'capabilities': {
        'storageQuota': _supportsStorageQuota,
        'performanceObserver': _supportsPerformanceObserver,
        'navigationTiming': _supportsNavigationTiming,
        'visibilityAPI': _supportsVisibilityAPI,
        'connectionAPI': _supportsConnectionAPI,
      },
      'storage': {
        'quota': _storageQuota,
        'usage': _storageUsage,
        'available': _storageQuota - _storageUsage,
        'quotaFormatted': _formatBytes(_storageQuota),
        'usageFormatted': _formatBytes(_storageUsage),
        'usagePercent': _storageQuota > 0 ? (_storageUsage / _storageQuota * 100) : 0.0,
      },
      'visibility': {
        'isVisible': _isVisible,
        'supported': _supportsVisibilityAPI,
      },
      'connection': {
        'isOnline': _isOnline,
        'type': _connectionType,
        'supported': _supportsConnectionAPI,
      },
      'performance': {
        'metricsCount': _performanceMetrics.length,
        'observerSupported': _supportsPerformanceObserver,
      },
    };
  }
  
  /// Get recent performance metrics
  List<Map<String, dynamic>> getPerformanceMetrics({int? limit}) {
    final count = limit ?? _performanceMetrics.length;
    if (count >= _performanceMetrics.length) {
      return List.from(_performanceMetrics);
    }
    
    return _performanceMetrics.sublist(_performanceMetrics.length - count);
  }
  
  /// Clear performance metrics
  void clearPerformanceMetrics() {
    _performanceMetrics.clear();
    _logger.fine('Performance metrics cleared');
  }
  
  /// Stream of visibility changes
  Stream<bool> get onVisibilityChange => _visibilityController.stream;
  
  /// Stream of connection changes
  Stream<Map<String, dynamic>> get onConnectionChange => _connectionController.stream;
  
  /// Current visibility state
  bool get isVisible => _isVisible;
  
  /// Current online state
  bool get isOnline => _isOnline;
  
  /// Current connection type
  String get connectionType => _connectionType;
  
  /// Storage usage percentage
  double get storageUsagePercent => _storageQuota > 0 ? (_storageUsage / _storageQuota * 100) : 0;
  
  /// Dispose resources
  void dispose() {
    _performanceTimer?.cancel();
    _visibilityController.close();
    _connectionController.close();
    WebMemoryMonitor.instance.stopMonitoring();
  }
}