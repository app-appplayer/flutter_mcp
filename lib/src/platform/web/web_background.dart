import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import '../../config/background_config.dart';
import '../../utils/logger.dart';
import '../background/background_service.dart';
import '../../utils/exceptions.dart';

/// Web background service implementation using Web Workers
class WebBackgroundService implements BackgroundService {
  bool _isRunning = false;
  html.Worker? _worker;
  Timer? _periodicTimer;
  final MCPLogger _logger = MCPLogger('mcp.web_background');

  // Configuration
  int _intervalMs = 5000;
  bool _keepAlive = true;

  // Registered task handlers
  final List<Future<void> Function()> _taskHandlers = [];

  // Service worker registration
  html.ServiceWorkerRegistration? _serviceWorkerRegistration;

  // Task data
  Map<String, dynamic> _taskData = {};

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.debug('Initializing web background service');

    if (config != null) {
      _intervalMs = config.intervalMs;
      _keepAlive = config.keepAlive;
    }

    // Check if service workers are supported and try to register
    if (_supportsServiceWorkers()) {
      try {
        _serviceWorkerRegistration = await _registerServiceWorker();
        _logger.debug('Service worker registered successfully');
      } catch (e) {
        _logger.warning('Failed to register service worker: $e');
      }
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
    } catch (e, stackTrace) {
      _logger.error('Failed to start web background service', e, stackTrace);
      throw MCPException('Failed to start web background service', e, stackTrace);
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
        _worker!.postMessage({'command': 'stop'});

        // Wait for response with a timeout
        await Future.delayed(Duration(milliseconds: 500));

        _worker!.terminate();
        _worker = null;
      }

      if (_periodicTimer != null) {
        _periodicTimer!.cancel();
        _periodicTimer = null;
      }

      _isRunning = false;
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to stop web background service', e, stackTrace);
      throw MCPException('Failed to stop web background service', e, stackTrace);
    }
  }

  /// Register a task handler to be executed by the background service
  void registerTaskHandler(Future<void> Function() handler) {
    _taskHandlers.add(handler);
    _logger.debug('Task handler registered, total handlers: ${_taskHandlers.length}');
  }

  /// Send data to the background task
  void sendData(Map<String, dynamic> data) {
    _taskData = {..._taskData, ...data};

    if (_worker != null) {
      _worker!.postMessage({
        'command': 'data',
        'data': _taskData
      });
    }

    _logger.debug('Data sent to background task: $data');
  }

  /// Start background service using a Web Worker
  void _startWithWorker() {
    _logger.debug('Starting web background service with Web Worker');

    // Create a blob URL with the worker script
    final String workerScript = '''
      let intervalId = null;
      let taskData = {};
      
      self.onmessage = function(e) {
        if (e.data.command === 'start') {
          const interval = e.data.interval || 5000;
          intervalId = setInterval(() => {
            self.postMessage({ type: 'task', data: taskData });
          }, interval);
          self.postMessage({ type: 'started' });
        } else if (e.data.command === 'stop') {
          if (intervalId) {
            clearInterval(intervalId);
            intervalId = null;
          }
          self.postMessage({ type: 'stopped' });
        } else if (e.data.command === 'data') {
          taskData = {...taskData, ...e.data.data};
          self.postMessage({ type: 'data_received', data: taskData });
        }
      };
      
      // Handle uncaught errors
      self.onerror = function(e) {
        self.postMessage({ 
          type: 'error', 
          message: e.message,
          filename: e.filename,
          lineno: e.lineno
        });
        return true;
      };
    ''';

    final blob = html.Blob([workerScript], 'application/javascript');
    final url = html.Url.createObjectUrlFromBlob(blob);

    // Create and start the worker
    _worker = html.Worker(url);
    _worker!.onMessage.listen(_handleWorkerMessage);
    _worker!.onError.listen(_handleWorkerError);

    // Start the worker
    _worker!.postMessage({
      'command': 'start',
      'interval': _intervalMs,
      'data': _taskData
    });
  }

  /// Start background service using a Timer (fallback)
  void _startWithTimer() {
    _logger.debug('Starting web background service with Timer (fallback)');

    // Start a periodic timer as a fallback for browsers without Web Worker support
    _periodicTimer = Timer.periodic(Duration(milliseconds: _intervalMs), (timer) {
      _performBackgroundTask(_taskData);
    });
  }

  /// Handle messages from the Web Worker
  void _handleWorkerMessage(html.MessageEvent event) {
    final data = event.data;

    if (data['type'] == 'task') {
      _performBackgroundTask(data['data'] ?? {});
    } else if (data['type'] == 'started') {
      _logger.debug('Web Worker started successfully');
    } else if (data['type'] == 'stopped') {
      _logger.debug('Web Worker stopped successfully');
    } else if (data['type'] == 'data_received') {
      _logger.debug('Worker received data: ${data['data']}');
    } else if (data['type'] == 'error') {
      _logger.error('Error in web worker: ${data['message']} at ${data['filename']}:${data['lineno']}');
    }
  }

  /// Handle errors from the Web Worker
  void _handleWorkerError(html.Event event) {
    if (event is html.ErrorEvent) {
      _logger.error('Web worker error: ${event.message}');
    } else {
      _logger.error('Web worker error: Unknown error type');
    }
  }

  /// Perform the background task
  Future<void> _performBackgroundTask(Map<String, dynamic> taskData) async {
    _logger.debug('Performing web background task with data: $taskData');

    try {
      // Try to keep the service worker alive
      if (_keepAlive && _serviceWorkerRegistration != null) {
        await _pingServiceWorker();
      }

      // Execute all registered task handlers
      if (_taskHandlers.isNotEmpty) {
        for (final handler in _taskHandlers) {
          try {
            await handler();
          } catch (e, stackTrace) {
            _logger.error('Error executing task handler', e, stackTrace);
          }
        }
      } else {
        _logger.debug('No task handlers registered');
      }
    } catch (e, stackTrace) {
      _logger.error('Error in background task execution', e, stackTrace);
    }
  }

  /// Register a service worker for additional background capabilities
  Future<html.ServiceWorkerRegistration?> _registerServiceWorker() async {
    if (!_supportsServiceWorkers()) {
      return null;
    }

    try {
      // Simple service worker script for keeping alive and caching
      final String swScript = '''
        self.addEventListener('install', function(event) {
          self.skipWaiting();
        });
        
        self.addEventListener('activate', function(event) {
          event.waitUntil(self.clients.claim());
        });
        
        self.addEventListener('fetch', function(event) {
          // Intercept fetch requests if needed
        });
        
        self.addEventListener('message', function(event) {
          if (event.data && event.data.type === 'ping') {
            event.source.postMessage({type: 'pong'});
          }
        });
      ''';

      final blob = html.Blob([swScript], 'application/javascript');
      final swUrl = html.Url.createObjectUrlFromBlob(blob);

      return await html.window.navigator.serviceWorker!.register(swUrl);
    } catch (e) {
      _logger.error('Failed to register service worker', e);
      return null;
    }
  }

  /// Keep the service worker alive with pings
  Future<void> _pingServiceWorker() async {
    if (_serviceWorkerRegistration?.active != null) {
      try {
        final controller = _serviceWorkerRegistration!.active;
        controller!.postMessage({'type': 'ping'});
      } catch (e) {
        _logger.error('Failed to ping service worker', e);
      }
    }
  }

  /// Check if the browser supports Web Workers
  bool _supportsWebWorkers() {
    try {
      return html.Worker.supported;
    } catch (e) {
      return false;
    }
  }

  /// Check if the browser supports Service Workers
  bool _supportsServiceWorkers() {
    try {
      return html.window.navigator.serviceWorker != null;
    } catch (e) {
      return false;
    }
  }

  /// Check if the browser supports Background Sync API
  bool _supportsBackgroundSync() {
    try {
      return js.context.hasProperty('SyncManager');
    } catch (e) {
      return false;
    }
  }

  /// Register for background sync (where supported)
  Future<bool> registerBackgroundSync(String tag) async {
    if (!_supportsServiceWorkers() || !_supportsBackgroundSync()) {
      return false;
    }

    try {
      final registration = await html.window.navigator.serviceWorker!.ready;
      await js.JsObject.fromBrowserObject(registration)
          .callMethod('sync', [tag]);
      return true;
    } catch (e) {
      _logger.error('Failed to register background sync', e);
      return false;
    }
  }
}