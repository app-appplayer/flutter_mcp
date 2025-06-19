import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:universal_html/html.dart' as html;
import 'package:universal_html/js_util.dart';

import '../../utils/logger.dart';
import '../../utils/exceptions.dart';

/// Enhanced web platform manager that provides improved web-specific features
class EnhancedWebPlatform {
  final Logger _logger = Logger('flutter_mcp.enhanced_web_platform');

  // Platform capabilities
  bool _supportsNotifications = false;
  bool _supportsServiceWorkers = false;
  bool _supportsWebWorkers = false;
  bool _supportsWebPush = false;
  bool _supportsIndexedDB = false;
  bool _supportsWebAssembly = false;

  // Service worker registration
  html.ServiceWorkerRegistration? _serviceWorkerRegistration;

  // Visibility and lifecycle management
  final StreamController<String> _visibilityController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _lifecycleController =
      StreamController.broadcast();

  // Storage quota management
  int _storageQuota = 0;
  int _storageUsage = 0;

  static EnhancedWebPlatform? _instance;
  static EnhancedWebPlatform get instance =>
      _instance ??= EnhancedWebPlatform._internal();

  EnhancedWebPlatform._internal();

  /// Initialize the enhanced web platform
  Future<void> initialize() async {
    _logger.info('Initializing enhanced web platform');

    await _detectCapabilities();
    await _initializeServiceWorker();
    await _setupVisibilityHandling();
    await _setupLifecycleHandling();
    await _checkStorageQuota();

    _logger.info('Enhanced web platform initialized with capabilities: '
        'notifications=$_supportsNotifications, '
        'serviceWorkers=$_supportsServiceWorkers, '
        'webWorkers=$_supportsWebWorkers, '
        'webPush=$_supportsWebPush, '
        'indexedDB=$_supportsIndexedDB, '
        'webAssembly=$_supportsWebAssembly');
  }

  /// Detect browser capabilities
  Future<void> _detectCapabilities() async {
    try {
      // Check notification support
      _supportsNotifications = hasProperty(html.window, 'Notification');

      // Check service worker support
      _supportsServiceWorkers = hasProperty(html.window, 'navigator') &&
          hasProperty(getProperty(html.window, 'navigator'), 'serviceWorker');

      // Check web worker support
      _supportsWebWorkers = hasProperty(html.window, 'Worker');

      // Check web push support
      _supportsWebPush =
          _supportsServiceWorkers && hasProperty(html.window, 'PushManager');

      // Check IndexedDB support
      _supportsIndexedDB = hasProperty(html.window, 'indexedDB');

      // Check WebAssembly support
      _supportsWebAssembly = hasProperty(html.window, 'WebAssembly');
    } catch (e) {
      _logger.warning('Error detecting capabilities: $e');
    }
  }

  /// Initialize service worker for better background functionality
  Future<void> _initializeServiceWorker() async {
    if (!_supportsServiceWorkers) {
      _logger.info('Service workers not supported');
      return;
    }

    try {
      // Register service worker
      _serviceWorkerRegistration =
          await html.window.navigator.serviceWorker!.register(
        '/flutter_mcp_sw.js',
        {'scope': '/'},
      );

      _logger.info('Service worker registered successfully');

      // Listen for service worker messages
      html.window.navigator.serviceWorker!.onMessage
          .listen((html.MessageEvent event) {
        _handleServiceWorkerMessage(event.data);
      });

      // Check for updates
      await _serviceWorkerRegistration!.update();
    } catch (e) {
      _logger.warning('Failed to register service worker: $e');
    }
  }

  /// Set up page visibility handling
  Future<void> _setupVisibilityHandling() async {
    try {
      html.document.onVisibilityChange.listen((_) {
        final isVisible = !html.document.hidden!;
        _visibilityController.add(isVisible ? 'visible' : 'hidden');

        _lifecycleController.add({
          'type': 'visibilitychange',
          'visible': isVisible,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      });

      // Handle page focus/blur
      html.window.onFocus.listen((_) {
        _lifecycleController.add({
          'type': 'focus',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      });

      html.window.onBlur.listen((_) {
        _lifecycleController.add({
          'type': 'blur',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      });

      // Handle beforeunload
      html.window.onBeforeUnload.listen((html.Event event) {
        _lifecycleController.add({
          'type': 'beforeunload',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      });
    } catch (e) {
      _logger.warning('Failed to setup visibility handling: $e');
    }
  }

  /// Set up page lifecycle event handling
  Future<void> _setupLifecycleHandling() async {
    try {
      // Handle page freeze/resume (Page Lifecycle API)
      if (hasProperty(html.document, 'onfreeze')) {
        callMethod(html.document, 'addEventListener', [
          'freeze',
          (event) {
            _lifecycleController.add({
              'type': 'freeze',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
          }
        ]);
      }

      if (hasProperty(html.document, 'onresume')) {
        callMethod(html.document, 'addEventListener', [
          'resume',
          (event) {
            _lifecycleController.add({
              'type': 'resume',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
          }
        ]);
      }

      // Handle connection changes
      if (hasProperty(html.window.navigator, 'connection')) {
        final connection = getProperty(html.window.navigator, 'connection');
        if (connection != null) {
          callMethod(connection, 'addEventListener', [
            'change',
            (event) {
              _lifecycleController.add({
                'type': 'connectionchange',
                'online': html.window.navigator.onLine,
                'effectiveType': getProperty(connection, 'effectiveType'),
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              });
            }
          ]);
        }
      }
    } catch (e) {
      _logger.warning('Failed to setup lifecycle handling: $e');
    }
  }

  /// Check storage quota and usage
  Future<void> _checkStorageQuota() async {
    try {
      if (hasProperty(html.window.navigator, 'storage') &&
          hasProperty(
              getProperty(html.window.navigator, 'storage'), 'estimate')) {
        final storage = getProperty(html.window.navigator, 'storage');
        final estimate =
            await promiseToFuture(callMethod(storage, 'estimate', []));

        _storageQuota = (estimate['quota'] as num?)?.toInt() ?? 0;
        _storageUsage = (estimate['usage'] as num?)?.toInt() ?? 0;

        _logger.info('Storage quota: ${_formatBytes(_storageQuota)}, '
            'usage: ${_formatBytes(_storageUsage)}');
      }
    } catch (e) {
      _logger.warning('Failed to check storage quota: $e');
    }
  }

  /// Handle service worker messages
  void _handleServiceWorkerMessage(dynamic data) {
    try {
      if (data is Map<String, dynamic>) {
        final type = data['type'] as String?;

        switch (type) {
          case 'notification-click':
            _handleNotificationClick(data);
            break;
          case 'background-sync':
            _handleBackgroundSync(data);
            break;
          case 'push':
            _handlePushMessage(data);
            break;
          default:
            _logger.fine('Unknown service worker message type: $type');
        }
      }
    } catch (e) {
      _logger.warning('Error handling service worker message: $e');
    }
  }

  /// Handle notification click from service worker
  void _handleNotificationClick(Map<String, dynamic> data) {
    _logger.fine('Notification clicked via service worker: ${data['id']}');

    // Focus the window
    try {
      callMethod(html.window, 'focus', []);
    } catch (e) {
      _logger.warning('Failed to focus window: $e');
    }

    // Emit notification click event
    _lifecycleController.add({
      'type': 'notification-click',
      'notificationId': data['id'],
      'data': data['data'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Handle background sync from service worker
  void _handleBackgroundSync(Map<String, dynamic> data) {
    _logger.fine('Background sync triggered: ${data['tag']}');

    _lifecycleController.add({
      'type': 'background-sync',
      'tag': data['tag'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Handle push message from service worker
  void _handlePushMessage(Map<String, dynamic> data) {
    _logger.fine('Push message received: ${data['title']}');

    _lifecycleController.add({
      'type': 'push-message',
      'title': data['title'],
      'body': data['body'],
      'data': data['data'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Request persistent notification permission with enhanced features
  Future<bool> requestEnhancedNotificationPermission() async {
    if (!_supportsNotifications) {
      throw MCPPlatformNotSupportedException('Notifications');
    }

    try {
      final permission = await html.Notification.requestPermission();
      return permission == 'granted';
    } catch (e) {
      _logger.warning('Failed to request notification permission: $e');
      return false;
    }
  }

  /// Show persistent notification via service worker
  Future<void> showPersistentNotification({
    required String title,
    required String body,
    String? icon,
    String? badge,
    String id = 'mcp_notification',
    Map<String, dynamic>? data,
    List<Map<String, String>>? actions,
    bool requireInteraction = false,
    bool silent = false,
  }) async {
    if (!_supportsServiceWorkers || _serviceWorkerRegistration == null) {
      throw MCPPlatformNotSupportedException('Persistent Notifications');
    }

    try {
      final options = <String, dynamic>{
        'body': body,
        'tag': id,
        'requireInteraction': requireInteraction,
        'silent': silent,
        'data': {'id': id, ...?data},
      };

      if (icon != null) options['icon'] = icon;
      if (badge != null) options['badge'] = badge;
      if (actions != null && actions.isNotEmpty) {
        options['actions'] = actions;
      }

      await promiseToFuture(callMethod(
        _serviceWorkerRegistration!,
        'showNotification',
        [title, options],
      ));

      _logger.fine('Persistent notification shown: $title');
    } catch (e) {
      _logger.severe('Failed to show persistent notification: $e');
      throw MCPException('Failed to show persistent notification: $e');
    }
  }

  /// Register for web push notifications
  Future<String?> subscribeToWebPush({String? vapidPublicKey}) async {
    if (!_supportsWebPush || _serviceWorkerRegistration == null) {
      throw MCPPlatformNotSupportedException('Web Push');
    }

    try {
      final pushManager =
          getProperty(_serviceWorkerRegistration!, 'pushManager');

      final options = <String, dynamic>{
        'userVisibleOnly': true,
      };

      if (vapidPublicKey != null) {
        // Convert VAPID key to Uint8Array
        final keyData = _urlBase64ToUint8Array(vapidPublicKey);
        options['applicationServerKey'] = keyData;
      }

      final subscription = await promiseToFuture(
          callMethod(pushManager, 'subscribe', [options]));

      // Convert subscription to JSON string
      final subscriptionJson = callMethod(subscription, 'toJSON', []);
      return jsonEncode(subscriptionJson);
    } catch (e) {
      _logger.warning('Failed to subscribe to web push: $e');
      return null;
    }
  }

  /// Convert VAPID key from URL-safe base64 to Uint8Array
  Uint8List _urlBase64ToUint8Array(String base64String) {
    const padding = '=';
    final normalizedBase64 =
        (base64String + padding * (4 - base64String.length % 4))
            .replaceAll('-', '+')
            .replaceAll('_', '/');

    return base64Decode(normalizedBase64);
  }

  /// Request persistent storage to prevent data eviction
  Future<bool> requestPersistentStorage() async {
    try {
      if (hasProperty(html.window.navigator, 'storage') &&
          hasProperty(
              getProperty(html.window.navigator, 'storage'), 'persist')) {
        final storage = getProperty(html.window.navigator, 'storage');
        final persistent =
            await promiseToFuture(callMethod(storage, 'persist', []));

        _logger.info('Persistent storage ${persistent ? 'granted' : 'denied'}');
        return persistent as bool;
      }
      return false;
    } catch (e) {
      _logger.warning('Failed to request persistent storage: $e');
      return false;
    }
  }

  /// Get detailed browser information
  Map<String, dynamic> getBrowserInfo() {
    final nav = html.window.navigator;
    return {
      'userAgent': nav.userAgent,
      'platform': nav.platform,
      'language': nav.language,
      'languages': nav.languages,
      'cookieEnabled': nav.cookieEnabled,
      'onLine': nav.onLine,
      'hardwareConcurrency': nav.hardwareConcurrency,
      'maxTouchPoints': getProperty(nav, 'maxTouchPoints') ?? 0,
      'vendor': nav.vendor,
      'vendorSub': nav.vendorSub,
      'product': nav.product,
      'productSub': nav.productSub,
      'appName': nav.appName,
      'appVersion': nav.appVersion,
      'appCodeName': nav.appCodeName,
      'capabilities': {
        'notifications': _supportsNotifications,
        'serviceWorkers': _supportsServiceWorkers,
        'webWorkers': _supportsWebWorkers,
        'webPush': _supportsWebPush,
        'indexedDB': _supportsIndexedDB,
        'webAssembly': _supportsWebAssembly,
      },
      'storage': {
        'quota': _storageQuota,
        'usage': _storageUsage,
        'quotaFormatted': _formatBytes(_storageQuota),
        'usageFormatted': _formatBytes(_storageUsage),
      },
    };
  }

  /// Format bytes in human readable format
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    final size = bytes / math.pow(1024, i);

    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  /// Get platform capabilities
  Map<String, bool> get capabilities => {
        'notifications': _supportsNotifications,
        'serviceWorkers': _supportsServiceWorkers,
        'webWorkers': _supportsWebWorkers,
        'webPush': _supportsWebPush,
        'indexedDB': _supportsIndexedDB,
        'webAssembly': _supportsWebAssembly,
      };

  /// Get storage information
  Map<String, dynamic> get storageInfo => {
        'quota': _storageQuota,
        'usage': _storageUsage,
        'available': _storageQuota - _storageUsage,
        'quotaFormatted': _formatBytes(_storageQuota),
        'usageFormatted': _formatBytes(_storageUsage),
        'availableFormatted': _formatBytes(_storageQuota - _storageUsage),
      };

  /// Stream of visibility changes
  Stream<String> get onVisibilityChange => _visibilityController.stream;

  /// Stream of lifecycle events
  Stream<Map<String, dynamic>> get onLifecycleEvent =>
      _lifecycleController.stream;

  /// Check if page is currently visible
  bool get isVisible => !html.document.hidden!;

  /// Check if service worker is available
  bool get hasServiceWorker => _serviceWorkerRegistration != null;

  /// Dispose resources
  void dispose() {
    _visibilityController.close();
    _lifecycleController.close();
  }
}
