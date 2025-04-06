import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

import '../../config/background_config.dart';
import '../../utils/logger.dart';
import 'background_service.dart';

/// Web background service implementation using Web Workers
class WebBackgroundService implements BackgroundService {
  bool _isRunning = false;
  web.Worker? _worker;
  Timer? _periodicTimer;
  final MCPLogger _logger = MCPLogger('mcp.web_background');

  // Configuration
  int _intervalMs = 5000;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.debug('Initializing web background service');

    if (config != null) {
      _intervalMs = config.intervalMs;
    }

    // Check if Web Workers are supported
    if (!_supportsWebWorkers()) {
      _logger.warning('Web Workers are not supported in this browser, using fallback Timer');
    }
  }

  @override
  Future<bool> start() async {
    _logger.debug('Starting web background service');

    if (_isRunning) {
      _logger.debug('Web background service is already running');
      return true;
    }

    try {
      if (_supportsWebWorkers()) {
        _startWithWorker();
      } else {
        _startWithTimer();
      }

      _isRunning = true;
      return true;
    } catch (e) {
      _logger.error('Failed to start web background service', e);
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    _logger.debug('Stopping web background service');

    if (!_isRunning) {
      _logger.debug('Web background service is not running');
      return true;
    }

    try {
      if (_worker != null) {
        _worker!.terminate();
        _worker = null;
      }

      if (_periodicTimer != null) {
        _periodicTimer!.cancel();
        _periodicTimer = null;
      }

      _isRunning = false;
      return true;
    } catch (e) {
      _logger.error('Failed to stop web background service', e);
      return false;
    }
  }

  /// Start background service using a Web Worker
  void _startWithWorker() {
    _logger.debug('Starting web background service with Web Worker');

    // Create a blob URL with the worker script
    final workerScript = '''
      let intervalId = null;
      
      self.onmessage = function(e) {
        if (e.data.command === 'start') {
          const interval = e.data.interval || 5000;
          intervalId = setInterval(() => {
            self.postMessage({ type: 'task' });
          }, interval);
          self.postMessage({ type: 'started' });
        } else if (e.data.command === 'stop') {
          if (intervalId) {
            clearInterval(intervalId);
            intervalId = null;
          }
          self.postMessage({ type: 'stopped' });
        }
      };
    ''';

    final blob = web.Blob(
        [workerScript.toJS].toJS as JSArray<web.BlobPart>,
        web.BlobPropertyBag(type: 'application/javascript')
    );

    final url = web.URL.createObjectURL(blob);

    // Create and start the worker
    _worker = web.Worker(url.toString().toJS);

    // Use addEventListener instead of onMessage
    _worker!.addEventListener('message', ((event) {
      final messageEvent = event as web.MessageEvent;
      final data = messageEvent.data.dartify();
      _handleWorkerMessage(data);
    }).toJS);

    // Start the worker
    _worker!.postMessage(
        {
          'command': 'start',
          'interval': _intervalMs
        }.jsify()
    );
  }

  /// Start background service using a Timer (fallback)
  void _startWithTimer() {
    _logger.debug('Starting web background service with Timer (fallback)');

    // Start a periodic timer as a fallback for browsers without Web Worker support
    _periodicTimer = Timer.periodic(Duration(milliseconds: _intervalMs), (timer) {
      _performBackgroundTask();
    });
  }

  /// Handle messages from the Web Worker
  void _handleWorkerMessage(dynamic data) {
    if (data['type'] == 'task') {
      _performBackgroundTask();
    } else if (data['type'] == 'started') {
      _logger.debug('Web Worker started successfully');
    } else if (data['type'] == 'stopped') {
      _logger.debug('Web Worker stopped successfully');
    }
  }

  /// Perform the background task
  void _performBackgroundTask() {
    _logger.debug('Performing web background task');

    // In a real implementation, this would:
    // 1. Check service worker registration status
    // 2. Sync data with server if needed
    // 3. Update application state
    // 4. Check for notifications that need to be displayed

    // Note: Web background capabilities are limited compared to native platforms
  }

  /// Check if the browser supports Web Workers
  bool _supportsWebWorkers() {
    try {
      return web.window.hasProperty('Worker'.toJS).toDart;
    } catch (e) {
      return false;
    }
  }}