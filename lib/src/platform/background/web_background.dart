import 'dart:async';
import 'dart:convert';
import 'package:universal_html/html.dart';
import 'package:universal_html/js_util.dart';

import '../../config/background_config.dart';
import '../../utils/logger.dart';
import '../../utils/error_recovery.dart';
import 'background_service.dart';

/// Web background service implementation using Web Workers
class WebBackgroundService implements BackgroundService {
  bool _isRunning = false;
  Worker? _worker;
  Timer? _periodicTimer;
  final Logger _logger = Logger('flutter_mcp.web_background');

  // Configuration
  int _intervalMs = 5000;
  BackgroundConfig? _config;

  // Worker event handlers
  bool _workerInitialized = false;
  final List<Function(dynamic)> _pendingCallbacks = [];

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.fine('Initializing web background service');

    _config = config;
    if (config != null) {
      _intervalMs = config.intervalMs;
    }

    // Check if Web Workers are supported
    if (!_supportsWebWorkers()) {
      _logger.warning('Web Workers are not supported in this browser, using fallback Timer');
    } else {
      _logger.fine('Web Workers are supported');
    }
  }

  @override
  Future<bool> start() async {
    _logger.fine('Starting web background service');

    if (_isRunning) {
      _logger.fine('Web background service is already running');
      return true;
    }

    try {
      return await ErrorRecovery.tryWithRetry(
            () async {
          if (_supportsWebWorkers()) {
            await _startWithWorker();
          } else {
            _startWithTimer();
          }

          _isRunning = true;
          return true;
        },
        operationName: 'start web background service',
        maxRetries: 2,
      );
    } catch (e, stackTrace) {
      _logger.severe('Failed to start web background service', e, stackTrace);
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    _logger.fine('Stopping web background service');

    if (!_isRunning) {
      _logger.fine('Web background service is not running');
      return true;
    }

    try {
      return await ErrorRecovery.tryWithRetry(
            () async {
          if (_worker != null) {
            // Send stop command to worker first
            if (_workerInitialized) {
              _worker!.postMessage(jsonEncode({'command': 'stop'}));
              // Wait a short period for worker to process the stop command
              await Future.delayed(Duration(milliseconds: 100));
            }

            _worker!.terminate();
            _worker = null;
            _workerInitialized = false;
          }

          if (_periodicTimer != null) {
            _periodicTimer!.cancel();
            _periodicTimer = null;
          }

          _isRunning = false;
          _pendingCallbacks.clear();
          return true;
        },
        operationName: 'stop web background service',
        maxRetries: 2,
      );
    } catch (e, stackTrace) {
      _logger.severe('Failed to stop web background service', e, stackTrace);
      return false;
    }
  }

  /// Start background service using a Web Worker with improved error handling
  Future<void> _startWithWorker() async {
    _logger.fine('Starting web background service with Web Worker');

    // Create a proper worker script with more robust error handling
    final workerScript = '''
      // Web Worker for MCP Background Service
      
      let intervalId = null;
      let keepAlive = true;
      let interval = 5000;
      
      // Handle incoming messages
      self.onmessage = function(e) {
        try {
          const data = JSON.parse(e.data);
          
          if (data.command === 'start') {
            interval = data.interval || 5000;
            keepAlive = data.keepAlive !== undefined ? data.keepAlive : true;
            
            // Clear any existing interval
            if (intervalId) {
              clearInterval(intervalId);
            }
            
            // Set up the interval
            intervalId = setInterval(() => {
              self.postMessage(JSON.stringify({ type: 'task', timestamp: Date.now() }));
            }, interval);
            
            self.postMessage(JSON.stringify({ 
              type: 'started', 
              timestamp: Date.now(),
              config: { interval, keepAlive }
            }));
          } 
          else if (data.command === 'stop') {
            if (intervalId) {
              clearInterval(intervalId);
              intervalId = null;
            }
            self.postMessage(JSON.stringify({ type: 'stopped', timestamp: Date.now() }));
          }
          else if (data.command === 'ping') {
            // Health check
            self.postMessage(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
          }
          else if (data.command === 'updateInterval') {
            interval = data.interval || interval;
            
            // Update the interval
            if (intervalId) {
              clearInterval(intervalId);
              intervalId = setInterval(() => {
                self.postMessage(JSON.stringify({ type: 'task', timestamp: Date.now() }));
              }, interval);
            }
            
            self.postMessage(JSON.stringify({ 
              type: 'intervalUpdated', 
              timestamp: Date.now(),
              interval: interval
            }));
          }
        } catch (error) {
          self.postMessage(JSON.stringify({ 
            type: 'error', 
            error: error.toString(), 
            timestamp: Date.now() 
          }));
        }
      };
      
      // Send an initialization message
      self.postMessage(JSON.stringify({ type: 'initialized', timestamp: Date.now() }));
      
      // Error handler
      self.onerror = function(event) {
        self.postMessage(JSON.stringify({ 
          type: 'error', 
          error: event.message,
          lineno: event.lineno,
          filename: event.filename,
          timestamp: Date.now()
        }));
      };
    ''';

    // Create a blob URL with the worker script
    final blob = Blob([workerScript]);
    final url = Url.createObjectUrlFromBlob(blob);

    try {
      // Create the worker
      _worker = Worker(url);

      // Set up message handler
      final completer = Completer<void>();

      // Use addEventListener for better compatibility
      _worker!.onMessage.listen((MessageEvent event) {
        String dataStr = event.data as String;
        Map<String, dynamic> data = jsonDecode(dataStr);

        if (data.containsKey('type') && data['type'] == 'initialized') {
          _workerInitialized = true;

          // Send the start command
          _worker!.postMessage(jsonEncode({
            'command': 'start',
            'interval': _intervalMs,
            'keepAlive': _config?.keepAlive ?? true
          }));

          // Process any pending callbacks
          for (final callback in _pendingCallbacks) {
            try {
              callback(data);
            } catch (e) {
              _logger.severe('Error in pending worker callback', e);
            }
          }
          _pendingCallbacks.clear();

          if (!completer.isCompleted) {
            completer.complete();
          }
        } else {
          _handleWorkerMessage(data);
        }
      });

      // Set up error handler
      _worker!.onError.listen((Event event) {
        final errorEvent = event as ErrorEvent;
        _logger.severe('Web Worker error: ${errorEvent.message}');

        if (!completer.isCompleted) {
          completer.completeError(Exception('Web Worker initialization failed: ${errorEvent.message}'));
        }
      });

      // Wait for worker to initialize or timeout
      return await ErrorRecovery.tryWithTimeout(
              () => completer.future,
          Duration(seconds: 5),
          operationName: 'initialize web worker',
          onTimeout: () {
            _logger.warning('Web Worker initialization timed out, falling back to timer');
            _worker?.terminate();
            _worker = null;
            _workerInitialized = false;
            _startWithTimer();
          }
      );
    } catch (e, stackTrace) {
      _logger.severe('Failed to create Web Worker, falling back to timer', e, stackTrace);

      // Clean up
      if (_worker != null) {
        _worker!.terminate();
        _worker = null;
      }

      // Fall back to timer
      _startWithTimer();

      // Revoke the URL
      Url.revokeObjectUrl(url);
    }
  }

  /// Start background service using a Timer (fallback)
  void _startWithTimer() {
    _logger.fine('Starting web background service with Timer (fallback)');

    // Cancel any existing timer
    _periodicTimer?.cancel();

    // Start a periodic timer as a fallback for browsers without Web Worker support
    _periodicTimer = Timer.periodic(Duration(milliseconds: _intervalMs), (timer) {
      _performBackgroundTask();
    });
  }

  /// Handle messages from the Web Worker with improved error handling
  void _handleWorkerMessage(dynamic data) {
    try {
      if (data == null || data is! Map || !data.containsKey('type')) {
        _logger.warning('Received invalid message from Web Worker: $data');
        return;
      }
      final type = data['type'];
      final timestamp = data['timestamp'];

      switch (type) {
        case 'task':
          _performBackgroundTask();
          break;

        case 'started':
          _logger.fine('Web Worker started successfully at ${DateTime.fromMillisecondsSinceEpoch(timestamp)}');
          break;

        case 'stopped':
          _logger.fine('Web Worker stopped successfully at ${DateTime.fromMillisecondsSinceEpoch(timestamp)}');
          break;

        case 'error':
          final error = data['error'];
          _logger.severe('Web Worker error: $error');

          // If we receive multiple errors, consider falling back to timer
          // This would need to be implemented with an error counter
          break;

        case 'pong':
        // Handle health check response
          _logger.fine('Web Worker health check passed');
          break;

        case 'intervalUpdated':
          _logger.fine('Web Worker interval updated to ${data['interval']}ms');
          break;

        default:
          _logger.warning('Unknown message type from Web Worker: $type');
      }
    } catch (e, stackTrace) {
      _logger.severe('Error processing Web Worker message', e, stackTrace);
    }
  }

  /// Perform the background task with improved error handling
  void _performBackgroundTask() {
    _logger.fine('Performing web background task');

    try {
      // In a real implementation, this would:
      // 1. Check service worker registration status
      // 2. Sync data with server if needed
      // 3. Update application state
      // 4. Check for notifications that need to be displayed

      // For demo purposes, we're just logging
      final now = DateTime.now();
      _logger.fine('Background task executed at $now');

      // Check worker health periodically
      _checkWorkerHealth();
    } catch (e, stackTrace) {
      _logger.severe('Error in background task', e, stackTrace);
    }
  }

  /// Check worker health by sending a ping
  void _checkWorkerHealth() {
    if (_worker != null && _workerInitialized) {
      try {
        _worker!.postMessage(jsonEncode({'command': 'ping'}));
      } catch (e) {
        _logger.severe('Failed to send ping to worker, it may be unresponsive', e);

        // Consider restarting the worker if it's unresponsive
        _restartWorker();
      }
    }
  }

  /// Restart an unresponsive worker
  Future<void> _restartWorker() async {
    _logger.fine('Restarting unresponsive Web Worker');

    try {
      // Stop the current worker
      await stop();

      // Short delay
      await Future.delayed(Duration(milliseconds: 100));

      // Restart with a worker
      await _startWithWorker();
    } catch (e, stackTrace) {
      _logger.severe('Failed to restart Web Worker, falling back to timer', e, stackTrace);
      _startWithTimer();
    }
  }

  /// Update background task interval
  Future<bool> updateInterval(int intervalMs) async {
    _intervalMs = intervalMs;

    if (!_isRunning) {
      return true; // Will use new interval when started
    }

    if (_worker != null && _workerInitialized) {
      try {
        _worker!.postMessage(jsonEncode({
          'command': 'updateInterval',
          'interval': intervalMs
        }));
        return true;
      } catch (e, stackTrace) {
        _logger.severe('Failed to update Web Worker interval', e, stackTrace);
        return false;
      }
    } else if (_periodicTimer != null) {
      _periodicTimer!.cancel();
      _periodicTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
        _performBackgroundTask();
      });
      return true;
    }

    return false;
  }

  /// Check if the browser supports Web Workers
  bool _supportsWebWorkers() {
    try {
      return hasProperty(window, 'Worker');
    } catch (e) {
      return false;
    }
  }
}