# Web Applications Example

This example demonstrates building web applications with Flutter MCP, including Web Worker integration, Service Worker setup, and browser-specific features.

## Overview

This example shows how to:
- Integrate with Web Workers
- Set up Service Workers
- Use browser storage
- Handle web-specific security

## Web Worker Integration

### Basic Web Worker Setup

```dart
// lib/services/web_worker_service.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

class WebWorkerService {
  static html.Worker? _worker;
  static final _messageHandlers = <String, Function>{};
  static final _responseCompleters = <String, Completer>{};
  
  static Future<void> initialize() async {
    if (!kIsWeb) return;
    
    // Create worker from JavaScript file
    _worker = html.Worker('worker.js');
    
    // Listen to worker messages
    _worker!.onMessage.listen((html.MessageEvent event) {
      final data = event.data as Map<String, dynamic>;
      final messageId = data['id'] as String?;
      final type = data['type'] as String;
      
      if (messageId != null && _responseCompleters.containsKey(messageId)) {
        // Handle response to request
        final completer = _responseCompleters.remove(messageId)!;
        if (data['error'] != null) {
          completer.completeError(data['error']);
        } else {
          completer.complete(data['result']);
        }
      } else if (_messageHandlers.containsKey(type)) {
        // Handle worker-initiated message
        _messageHandlers[type]!(data);
      }
    });
    
    // Initialize worker with MCP config
    await _sendToWorker('init', {
      'config': FlutterMCP.config.toJson(),
    });
  }
  
  static Future<T> executeInWorker<T>(String method, Map<String, dynamic> params) async {
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final completer = Completer<T>();
    
    _responseCompleters[messageId] = completer;
    
    _worker!.postMessage({
      'id': messageId,
      'type': 'execute',
      'method': method,
      'params': params,
    });
    
    return completer.future;
  }
  
  static void registerHandler(String type, Function handler) {
    _messageHandlers[type] = handler;
  }
  
  static Future<dynamic> _sendToWorker(String type, Map<String, dynamic> data) async {
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final completer = Completer();
    
    _responseCompleters[messageId] = completer;
    
    _worker!.postMessage({
      'id': messageId,
      'type': type,
      ...data,
    });
    
    return completer.future;
  }
  
  static void dispose() {
    _worker?.terminate();
    _worker = null;
    _messageHandlers.clear();
    _responseCompleters.clear();
  }
}
```

### Worker JavaScript Implementation

```javascript
// web/worker.js
let mcpClient = null;
let config = null;

// Listen for messages from main thread
self.addEventListener('message', async (event) => {
  const { id, type, ...data } = event.data;
  
  try {
    let result;
    
    switch (type) {
      case 'init':
        result = await initializeMCP(data.config);
        break;
        
      case 'execute':
        result = await executeMCPMethod(data.method, data.params);
        break;
        
      case 'subscribe':
        result = await subscribeTopic(data.topic);
        break;
        
      default:
        throw new Error(`Unknown message type: ${type}`);
    }
    
    // Send response back to main thread
    self.postMessage({
      id,
      type: 'response',
      result,
    });
  } catch (error) {
    self.postMessage({
      id,
      type: 'error',
      error: error.toString(),
    });
  }
});

async function initializeMCP(configData) {
  config = configData;
  
  // Import MCP client library
  importScripts('/mcp-client.js');
  
  mcpClient = new MCPClient(config);
  await mcpClient.initialize();
  
  return { status: 'initialized' };
}

async function executeMCPMethod(method, params) {
  if (!mcpClient) {
    throw new Error('MCP client not initialized');
  }
  
  return await mcpClient.execute(method, params);
}

async function subscribeTopic(topic) {
  if (!mcpClient) {
    throw new Error('MCP client not initialized');
  }
  
  mcpClient.subscribe(topic, (data) => {
    // Send subscription data to main thread
    self.postMessage({
      type: 'subscription',
      topic,
      data,
    });
  });
  
  return { status: 'subscribed' };
}
```

## Service Worker Implementation

### Service Worker Registration

```dart
// lib/services/service_worker_service.dart
import 'dart:html' as html;
import 'dart:js_util' as js_util;

class ServiceWorkerService {
  static html.ServiceWorkerRegistration? _registration;
  static final _messageHandlers = <String, Function>{};
  
  static Future<void> register() async {
    if (!kIsWeb) return;
    
    try {
      _registration = await html.window.navigator.serviceWorker
          .register('/service-worker.js');
      
      print('Service Worker registered: ${_registration!.scope}');
      
      // Wait for service worker to be ready
      await html.window.navigator.serviceWorker.ready;
      
      // Listen for messages from service worker
      html.window.navigator.serviceWorker.addEventListener('message', (event) {
        final messageEvent = event as html.MessageEvent;
        final data = messageEvent.data as Map<String, dynamic>;
        final type = data['type'] as String;
        
        if (_messageHandlers.containsKey(type)) {
          _messageHandlers[type]!(data);
        }
      });
      
      // Setup periodic sync for background tasks
      await _setupPeriodicSync();
      
      // Setup push notifications
      await _setupPushNotifications();
    } catch (e) {
      print('Service Worker registration failed: $e');
    }
  }
  
  static Future<void> _setupPeriodicSync() async {
    final registration = _registration!;
    
    // Request periodic background sync
    final tags = ['sync-data', 'check-notifications'];
    
    for (final tag in tags) {
      try {
        await js_util.callMethod(
          registration,
          'periodicSync.register', 
          [tag, {'minInterval': 12 * 60 * 60 * 1000}], // 12 hours
        );
      } catch (e) {
        print('Periodic sync registration failed for $tag: $e');
      }
    }
  }
  
  static Future<void> _setupPushNotifications() async {
    // Request notification permission
    final permission = await html.Notification.requestPermission();
    
    if (permission != 'granted') {
      print('Notification permission denied');
      return;
    }
    
    // Subscribe to push notifications
    final subscription = await _registration!.pushManager.subscribe(
      js_util.jsify({
        'userVisibleOnly': true,
        'applicationServerKey': urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
      }),
    );
    
    // Send subscription to server
    await _sendSubscriptionToServer(subscription);
  }
  
  static Future<void> postMessage(Map<String, dynamic> message) async {
    if (_registration?.active == null) {
      throw Exception('Service worker not active');
    }
    
    _registration!.active!.postMessage(js_util.jsify(message));
  }
  
  static void registerHandler(String type, Function handler) {
    _messageHandlers[type] = handler;
  }
  
  static Future<void> _sendSubscriptionToServer(dynamic subscription) async {
    // Convert subscription to JSON and send to MCP server
    final subscriptionData = js_util.dartify(subscription) as Map<String, dynamic>;
    
    await FlutterMCP.server('push-server').execute('registerPushSubscription', {
      'subscription': subscriptionData,
      'userId': getCurrentUserId(),
    });
  }
}
```

### Service Worker JavaScript

```javascript
// web/service-worker.js
const CACHE_NAME = 'flutter-mcp-v1';
const urlsToCache = [
  '/',
  '/main.dart.js',
  '/flutter.js',
  '/manifest.json',
];

// Install event - cache resources
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(urlsToCache))
  );
});

// Activate event - clean old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((cacheName) => cacheName !== CACHE_NAME)
          .map((cacheName) => caches.delete(cacheName))
      );
    })
  );
});

// Fetch event - serve from cache or network
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request)
      .then((response) => {
        // Cache hit - return response
        if (response) {
          return response;
        }
        
        // Clone the request
        const fetchRequest = event.request.clone();
        
        return fetch(fetchRequest).then((response) => {
          // Check if valid response
          if (!response || response.status !== 200 || response.type !== 'basic') {
            return response;
          }
          
          // Clone the response
          const responseToCache = response.clone();
          
          caches.open(CACHE_NAME)
            .then((cache) => {
              cache.put(event.request, responseToCache);
            });
          
          return response;
        });
      })
  );
});

// Push event - handle push notifications
self.addEventListener('push', (event) => {
  let data = {};
  
  if (event.data) {
    data = event.data.json();
  }
  
  const options = {
    body: data.body || 'New notification',
    icon: data.icon || '/icons/icon-192.png',
    badge: data.badge || '/icons/icon-72.png',
    data: data,
  };
  
  event.waitUntil(
    self.registration.showNotification(data.title || 'Flutter MCP', options)
  );
});

// Notification click event
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  
  event.waitUntil(
    clients.openWindow(event.notification.data.url || '/')
  );
});

// Periodic sync event
self.addEventListener('periodicsync', (event) => {
  if (event.tag === 'sync-data') {
    event.waitUntil(syncData());
  } else if (event.tag === 'check-notifications') {
    event.waitUntil(checkNotifications());
  }
});

// Message event - communicate with main thread
self.addEventListener('message', (event) => {
  const { type, ...data } = event.data;
  
  switch (type) {
    case 'cache-update':
      updateCache(data.urls);
      break;
      
    case 'clear-cache':
      clearCache();
      break;
      
    default:
      console.log('Unknown message type:', type);
  }
});

// Helper functions
async function syncData() {
  // Sync local data with server
  const localData = await getLocalData();
  
  if (localData.length > 0) {
    await fetch('/api/sync', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(localData),
    });
    
    await clearLocalData();
  }
}

async function checkNotifications() {
  // Check for new notifications
  const response = await fetch('/api/notifications/check');
  const notifications = await response.json();
  
  for (const notification of notifications) {
    await self.registration.showNotification(notification.title, {
      body: notification.body,
      icon: notification.icon,
      data: notification.data,
    });
  }
}

async function updateCache(urls) {
  const cache = await caches.open(CACHE_NAME);
  await cache.addAll(urls);
}

async function clearCache() {
  await caches.delete(CACHE_NAME);
}
```

## Browser Storage Integration

### Local Storage Service

```dart
// lib/services/web_storage_service.dart
import 'dart:html' as html;
import 'dart:convert';

class WebStorageService {
  static const _prefix = 'flutter_mcp_';
  
  // Local Storage
  static void setLocal(String key, dynamic value) {
    final prefixedKey = '$_prefix$key';
    final jsonValue = jsonEncode(value);
    html.window.localStorage[prefixedKey] = jsonValue;
  }
  
  static T? getLocal<T>(String key) {
    final prefixedKey = '$_prefix$key';
    final jsonValue = html.window.localStorage[prefixedKey];
    
    if (jsonValue == null) return null;
    
    try {
      return jsonDecode(jsonValue) as T;
    } catch (e) {
      print('Error decoding local storage value: $e');
      return null;
    }
  }
  
  static void removeLocal(String key) {
    final prefixedKey = '$_prefix$key';
    html.window.localStorage.remove(prefixedKey);
  }
  
  static void clearLocal() {
    final keys = html.window.localStorage.keys
        .where((key) => key.startsWith(_prefix))
        .toList();
    
    for (final key in keys) {
      html.window.localStorage.remove(key);
    }
  }
  
  // Session Storage
  static void setSession(String key, dynamic value) {
    final prefixedKey = '$_prefix$key';
    final jsonValue = jsonEncode(value);
    html.window.sessionStorage[prefixedKey] = jsonValue;
  }
  
  static T? getSession<T>(String key) {
    final prefixedKey = '$_prefix$key';
    final jsonValue = html.window.sessionStorage[prefixedKey];
    
    if (jsonValue == null) return null;
    
    try {
      return jsonDecode(jsonValue) as T;
    } catch (e) {
      print('Error decoding session storage value: $e');
      return null;
    }
  }
  
  static void removeSession(String key) {
    final prefixedKey = '$_prefix$key';
    html.window.sessionStorage.remove(prefixedKey);
  }
  
  static void clearSession() {
    final keys = html.window.sessionStorage.keys
        .where((key) => key.startsWith(_prefix))
        .toList();
    
    for (final key in keys) {
      html.window.sessionStorage.remove(key);
    }
  }
  
  // Storage Events
  static Stream<StorageEvent> get storageEvents {
    return html.window.onStorage
        .where((event) => event.key?.startsWith(_prefix) ?? false)
        .map((event) => StorageEvent(
              key: event.key!.substring(_prefix.length),
              oldValue: event.oldValue != null
                  ? jsonDecode(event.oldValue!)
                  : null,
              newValue: event.newValue != null
                  ? jsonDecode(event.newValue!)
                  : null,
              url: event.url,
              storageArea: event.storageArea == html.window.localStorage
                  ? StorageArea.local
                  : StorageArea.session,
            ));
  }
}

class StorageEvent {
  final String key;
  final dynamic oldValue;
  final dynamic newValue;
  final String? url;
  final StorageArea storageArea;
  
  StorageEvent({
    required this.key,
    this.oldValue,
    this.newValue,
    this.url,
    required this.storageArea,
  });
}

enum StorageArea {
  local,
  session,
}
```

### IndexedDB Integration

```dart
// lib/services/indexed_db_service.dart
import 'dart:html' as html;
import 'dart:indexed_db' as idb;
import 'dart:async';

class IndexedDBService {
  static const String _dbName = 'FlutterMCPDB';
  static const int _dbVersion = 1;
  static idb.Database? _database;
  
  static const String _serverDataStore = 'serverData';
  static const String _cacheStore = 'cache';
  static const String _userDataStore = 'userData';
  
  static Future<void> initialize() async {
    if (_database != null) return;
    
    _database = await html.window.indexedDB!.open(
      _dbName,
      version: _dbVersion,
      onUpgradeNeeded: (idb.VersionChangeEvent event) {
        final db = event.target.result as idb.Database;
        
        // Create object stores
        if (!db.objectStoreNames!.contains(_serverDataStore)) {
          db.createObjectStore(
            _serverDataStore,
            keyPath: 'id',
            autoIncrement: true,
          );
        }
        
        if (!db.objectStoreNames!.contains(_cacheStore)) {
          final cacheStore = db.createObjectStore(
            _cacheStore,
            keyPath: 'key',
          );
          
          // Create index for expiration
          cacheStore.createIndex('expiration', 'expiration');
        }
        
        if (!db.objectStoreNames!.contains(_userDataStore)) {
          db.createObjectStore(
            _userDataStore,
            keyPath: 'id',
          );
        }
      },
    );
  }
  
  // Server Data Store
  static Future<void> saveServerData(String server, Map<String, dynamic> data) async {
    final transaction = _database!.transaction([_serverDataStore], 'readwrite');
    final store = transaction.objectStore(_serverDataStore);
    
    await store.put({
      'server': server,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  static Future<List<Map<String, dynamic>>> getServerData(String server) async {
    final transaction = _database!.transaction([_serverDataStore], 'readonly');
    final store = transaction.objectStore(_serverDataStore);
    
    final results = <Map<String, dynamic>>[];
    
    await for (final cursor in store.openCursor()) {
      final data = cursor.value as Map<String, dynamic>;
      if (data['server'] == server) {
        results.add(data);
      }
      cursor.next();
    }
    
    return results;
  }
  
  // Cache Store
  static Future<void> cacheData(String key, dynamic value, Duration ttl) async {
    final transaction = _database!.transaction([_cacheStore], 'readwrite');
    final store = transaction.objectStore(_cacheStore);
    
    await store.put({
      'key': key,
      'value': value,
      'expiration': DateTime.now().add(ttl).toIso8601String(),
    });
  }
  
  static Future<T?> getCachedData<T>(String key) async {
    final transaction = _database!.transaction([_cacheStore], 'readonly');
    final store = transaction.objectStore(_cacheStore);
    
    final data = await store.getObject(key) as Map<String, dynamic>?;
    
    if (data == null) return null;
    
    final expiration = DateTime.parse(data['expiration'] as String);
    if (expiration.isBefore(DateTime.now())) {
      // Cache expired, delete it
      await deleteCachedData(key);
      return null;
    }
    
    return data['value'] as T?;
  }
  
  static Future<void> deleteCachedData(String key) async {
    final transaction = _database!.transaction([_cacheStore], 'readwrite');
    final store = transaction.objectStore(_cacheStore);
    
    await store.delete(key);
  }
  
  static Future<void> cleanExpiredCache() async {
    final transaction = _database!.transaction([_cacheStore], 'readwrite');
    final store = transaction.objectStore(_cacheStore);
    final index = store.index('expiration');
    
    final now = DateTime.now().toIso8601String();
    final range = idb.KeyRange.upperBound(now);
    
    await for (final cursor in index.openCursor(range: range)) {
      await cursor.delete();
      cursor.next();
    }
  }
  
  // User Data Store
  static Future<void> saveUserData(String id, Map<String, dynamic> data) async {
    final transaction = _database!.transaction([_userDataStore], 'readwrite');
    final store = transaction.objectStore(_userDataStore);
    
    await store.put({
      'id': id,
      ...data,
      'lastModified': DateTime.now().toIso8601String(),
    });
  }
  
  static Future<Map<String, dynamic>?> getUserData(String id) async {
    final transaction = _database!.transaction([_userDataStore], 'readonly');
    final store = transaction.objectStore(_userDataStore);
    
    return await store.getObject(id) as Map<String, dynamic>?;
  }
  
  static Future<void> deleteUserData(String id) async {
    final transaction = _database!.transaction([_userDataStore], 'readwrite');
    final store = transaction.objectStore(_userDataStore);
    
    await store.delete(id);
  }
  
  static Future<void> close() async {
    _database?.close();
    _database = null;
  }
}
```

## Web Security Implementation

### Content Security Policy

```html
<!-- web/index.html -->
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="Flutter MCP Web Application">
  
  <!-- CSP Header -->
  <meta http-equiv="Content-Security-Policy" content="
    default-src 'self';
    script-src 'self' 'unsafe-inline' 'unsafe-eval';
    style-src 'self' 'unsafe-inline';
    img-src 'self' data: https:;
    font-src 'self';
    connect-src 'self' wss://localhost:* ws://localhost:* https://api.example.com;
    worker-src 'self' blob:;
    frame-src 'none';
    object-src 'none';
    base-uri 'self';
    form-action 'self';
    frame-ancestors 'none';
    upgrade-insecure-requests;
  ">
  
  <!-- PWA Meta Tags -->
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="Flutter MCP">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  
  <title>Flutter MCP</title>
  <link rel="manifest" href="manifest.json">
  <link rel="stylesheet" type="text/css" href="splash/style.css">
  
  <!-- Favicon -->
  <link rel="icon" type="image/png" href="favicon.png"/>
</head>
<body>
  <!-- Loading splash screen -->
  <div id="splash">
    <div class="splash-content">
      <img src="splash/img/splash.png" alt="Flutter MCP">
      <div class="loading-bar">
        <div class="loading-progress"></div>
      </div>
    </div>
  </div>
  
  <script>
    // Register service worker
    if ('serviceWorker' in navigator) {
      window.addEventListener('flutter-first-frame', function () {
        navigator.serviceWorker.register('service-worker.js');
      });
    }
  </script>
  
  <!-- Load Flutter app -->
  <script src="main.dart.js" type="application/javascript"></script>
</body>
</html>
```

### CORS Configuration

```dart
// lib/services/web_cors_service.dart
import 'dart:html' as html;
import 'package:http/http.dart' as http;

class WebCorsService {
  static final _client = http.Client();
  
  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  
  static Future<http.Response> get(
    String url, {
    Map<String, String>? headers,
    bool withCredentials = false,
  }) async {
    return _makeRequest(
      'GET',
      url,
      headers: headers,
      withCredentials: withCredentials,
    );
  }
  
  static Future<http.Response> post(
    String url, {
    Map<String, String>? headers,
    dynamic body,
    bool withCredentials = false,
  }) async {
    return _makeRequest(
      'POST',
      url,
      headers: headers,
      body: body,
      withCredentials: withCredentials,
    );
  }
  
  static Future<http.Response> _makeRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    dynamic body,
    bool withCredentials = false,
  }) async {
    final request = html.HttpRequest();
    
    request.open(method, url);
    
    // Set headers
    final allHeaders = {...defaultHeaders, ...?headers};
    allHeaders.forEach((key, value) {
      request.setRequestHeader(key, value);
    });
    
    // Set credentials mode
    if (withCredentials) {
      request.withCredentials = true;
    }
    
    // Handle preflight
    request.onLoadStart.listen((_) {
      print('Request started: $method $url');
    });
    
    request.onError.listen((html.ProgressEvent event) {
      print('Request error: ${event.type}');
    });
    
    // Send request
    final completer = Completer<http.Response>();
    
    request.onLoad.listen((_) {
      final response = http.Response(
        request.responseText ?? '',
        request.status ?? 0,
        headers: _parseHeaders(request.getAllResponseHeaders()),
      );
      
      completer.complete(response);
    });
    
    if (body != null) {
      request.send(jsonEncode(body));
    } else {
      request.send();
    }
    
    return completer.future;
  }
  
  static Map<String, String> _parseHeaders(String? headers) {
    if (headers == null) return {};
    
    final result = <String, String>{};
    final lines = headers.split('\n');
    
    for (final line in lines) {
      if (line.isEmpty) continue;
      
      final colonIndex = line.indexOf(':');
      if (colonIndex == -1) continue;
      
      final key = line.substring(0, colonIndex).trim();
      final value = line.substring(colonIndex + 1).trim();
      
      result[key] = value;
    }
    
    return result;
  }
}
```

## Web Application Example

### Main Application

```dart
// lib/main_web.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'services/web_worker_service.dart';
import 'services/service_worker_service.dart';
import 'services/indexed_db_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize web services
  await ServiceWorkerService.register();
  await IndexedDBService.initialize();
  await WebWorkerService.initialize();
  
  // Initialize MCP with web-specific config
  await FlutterMCP.initialize(MCPConfig(
    servers: {
      'web-server': ServerConfig(
        uri: 'wss://api.example.com/mcp',
        transport: WebSocketTransport(),
      ),
    },
    storage: WebStorageProvider(),
    background: WebBackgroundProvider(),
  ));
  
  runApp(WebApp());
}

class WebApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MCP Web',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: WebHomeScreen(),
    );
  }
}
```

### Web Home Screen

```dart
// lib/screens/web_home_screen.dart
import 'package:flutter/material.dart';
import 'dart:html' as html;

class WebHomeScreen extends StatefulWidget {
  @override
  _WebHomeScreenState createState() => _WebHomeScreenState();
}

class _WebHomeScreenState extends State<WebHomeScreen> {
  bool _isOnline = true;
  bool _hasWorkerSupport = false;
  String _browserInfo = '';
  
  @override
  void initState() {
    super.initState();
    _checkWebFeatures();
    _listenToConnectivity();
  }
  
  void _checkWebFeatures() {
    setState(() {
      _hasWorkerSupport = html.Worker != null;
      _browserInfo = html.window.navigator.userAgent;
    });
  }
  
  void _listenToConnectivity() {
    html.window.onOnline.listen((_) {
      setState(() => _isOnline = true);
    });
    
    html.window.onOffline.listen((_) {
      setState(() => _isOnline = false);
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flutter MCP Web'),
        actions: [
          IconButton(
            icon: Icon(_isOnline ? Icons.wifi : Icons.wifi_off),
            onPressed: () => _showConnectivityDialog(),
          ),
          IconButton(
            icon: Icon(Icons.notifications),
            onPressed: () => _requestNotificationPermission(),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildFeatureCard(
            'Web Workers',
            _hasWorkerSupport ? 'Supported' : 'Not Supported',
            _hasWorkerSupport ? Icons.check_circle : Icons.cancel,
            _hasWorkerSupport ? Colors.green : Colors.red,
          ),
          _buildFeatureCard(
            'Service Worker',
            'Registered',
            Icons.cloud_done,
            Colors.blue,
          ),
          _buildFeatureCard(
            'Browser Info',
            _browserInfo,
            Icons.web,
            Colors.orange,
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _testWebWorker(),
            child: Text('Test Web Worker'),
          ),
          SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _testServiceWorker(),
            child: Text('Test Service Worker'),
          ),
          SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _testIndexedDB(),
            child: Text('Test IndexedDB'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFeatureCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }
  
  void _showConnectivityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connectivity Status'),
        content: Text(_isOnline ? 'You are online' : 'You are offline'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _requestNotificationPermission() async {
    final permission = await html.Notification.requestPermission();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Notification permission: $permission'),
      ),
    );
  }
  
  Future<void> _testWebWorker() async {
    try {
      final result = await WebWorkerService.executeInWorker(
        'testMethod',
        {'input': 'test'},
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Worker result: $result'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Worker error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _testServiceWorker() async {
    try {
      await ServiceWorkerService.postMessage({
        'type': 'test',
        'data': 'Hello Service Worker',
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message sent to Service Worker'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Service Worker error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _testIndexedDB() async {
    try {
      await IndexedDBService.cacheData(
        'test-key',
        {'value': 'test data'},
        Duration(minutes: 5),
      );
      
      final data = await IndexedDBService.getCachedData('test-key');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('IndexedDB data: $data'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('IndexedDB error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

## Progressive Web App (PWA)

### Manifest Configuration

```json
// web/manifest.json
{
  "name": "Flutter MCP Web Application",
  "short_name": "Flutter MCP",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#0175C2",
  "theme_color": "#0175C2",
  "description": "A Flutter MCP web application",
  "orientation": "portrait-primary",
  "prefer_related_applications": false,
  "icons": [
    {
      "src": "icons/Icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "icons/Icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    },
    {
      "src": "icons/Icon-maskable-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    },
    {
      "src": "icons/Icon-maskable-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    }
  ],
  "screenshots": [
    {
      "src": "screenshots/screenshot1.png",
      "type": "image/png",
      "sizes": "540x720"
    },
    {
      "src": "screenshots/screenshot2.png",
      "type": "image/png",
      "sizes": "540x720"
    }
  ],
  "shortcuts": [
    {
      "name": "Dashboard",
      "short_name": "Dashboard",
      "description": "View dashboard",
      "url": "/dashboard",
      "icons": [
        {
          "src": "icons/dashboard.png",
          "sizes": "192x192"
        }
      ]
    }
  ]
}
```

### Offline Support

```dart
// lib/services/offline_service.dart
import 'dart:html' as html;

class OfflineService {
  static final _offlineQueue = <OfflineRequest>[];
  static bool _isOnline = html.window.navigator.onLine;
  
  static void initialize() {
    // Listen to connectivity changes
    html.window.onOnline.listen((_) {
      _isOnline = true;
      _processOfflineQueue();
    });
    
    html.window.onOffline.listen((_) {
      _isOnline = false;
    });
  }
  
  static Future<T> executeWithOfflineSupport<T>({
    required Future<T> Function() onlineOperation,
    required T Function() offlineOperation,
    required OfflineRequest request,
  }) async {
    if (_isOnline) {
      try {
        return await onlineOperation();
      } catch (e) {
        if (_isNetworkError(e)) {
          _isOnline = false;
          _queueRequest(request);
          return offlineOperation();
        }
        rethrow;
      }
    } else {
      _queueRequest(request);
      return offlineOperation();
    }
  }
  
  static void _queueRequest(OfflineRequest request) {
    _offlineQueue.add(request);
    WebStorageService.setLocal('offline_queue', _offlineQueue);
  }
  
  static Future<void> _processOfflineQueue() async {
    final queue = [..._offlineQueue];
    _offlineQueue.clear();
    
    for (final request in queue) {
      try {
        await request.execute();
      } catch (e) {
        // Re-queue failed requests
        _queueRequest(request);
      }
    }
    
    WebStorageService.setLocal('offline_queue', _offlineQueue);
  }
  
  static bool _isNetworkError(dynamic error) {
    return error.toString().contains('NetworkError') ||
           error.toString().contains('Failed to fetch');
  }
}

class OfflineRequest {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final Future<void> Function() execute;
  
  OfflineRequest({
    required this.id,
    required this.type,
    required this.data,
    required this.execute,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'data': data,
  };
  
  factory OfflineRequest.fromJson(Map<String, dynamic> json) {
    // Reconstruct execute function based on type
    return OfflineRequest(
      id: json['id'],
      type: json['type'],
      data: json['data'],
      execute: () => _executeFromType(json['type'], json['data']),
    );
  }
  
  static Future<void> _executeFromType(String type, Map<String, dynamic> data) async {
    switch (type) {
      case 'sync_data':
        await FlutterMCP.server('main').execute('syncData', data);
        break;
      case 'update_profile':
        await FlutterMCP.server('main').execute('updateProfile', data);
        break;
      default:
        throw Exception('Unknown offline request type: $type');
    }
  }
}
```

## Testing Web Features

```dart
// test/web_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('Web Services', () {
    test('web worker executes methods', () async {
      final mockWorker = MockWebWorker();
      
      when(mockWorker.postMessage(any))
          .thenAnswer((_) => Future.value({'result': 'success'}));
      
      final result = await WebWorkerService.executeInWorker(
        'testMethod',
        {'param': 'value'},
      );
      
      expect(result['result'], equals('success'));
    });
    
    test('service worker handles messages', () async {
      final mockServiceWorker = MockServiceWorker();
      
      await ServiceWorkerService.postMessage({
        'type': 'test',
        'data': 'test data',
      });
      
      verify(mockServiceWorker.postMessage(any)).called(1);
    });
    
    test('indexed db stores data', () async {
      await IndexedDBService.cacheData(
        'test-key',
        {'value': 'test'},
        Duration(minutes: 5),
      );
      
      final data = await IndexedDBService.getCachedData('test-key');
      expect(data['value'], equals('test'));
    });
  });
}
```

## Best Practices

### Performance Optimization

```dart
// Use web workers for heavy computations
await WebWorkerService.executeInWorker('heavyComputation', largeData);

// Implement code splitting
import 'package:flutter/material.dart' deferred as material;

// Use lazy loading for images
Image.network(
  imageUrl,
  loadingBuilder: (context, child, loadingProgress) {
    if (loadingProgress == null) return child;
    return CircularProgressIndicator();
  },
);
```

### Security Considerations

```dart
// Sanitize user input
final sanitized = html.window.document.createDocumentFragment()
  ..setInnerHtml(userInput, validator: html.NodeValidatorBuilder()
    ..allowTextElements());

// Use HTTPS in production
if (kReleaseMode) {
  assert(Uri.base.scheme == 'https');
}
```

### Responsive Design

```dart
// Adapt UI for different screen sizes
if (MediaQuery.of(context).size.width > 600) {
  // Desktop layout
} else {
  // Mobile layout
}
```

## Next Steps

- Explore [Android Integration](./android-integration.md)
- Learn about [iOS Integration](./ios-integration.md)
- Try [Desktop Applications](./desktop-applications.md)