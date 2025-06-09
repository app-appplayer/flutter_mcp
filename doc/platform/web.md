# Web Platform Guide

This guide covers web-specific implementation details and best practices for Flutter MCP.

## Requirements

- Modern web browser (Chrome 88+, Firefox 78+, Safari 14+, Edge 88+)
- HTTPS for production (required for many APIs)
- Service Worker support for background tasks

## Setup

### 1. Web Configuration

Update `web/index.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="MCP Web Application">
  
  <!-- iOS meta tags & icons -->
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="MCP">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  
  <!-- Favicon -->
  <link rel="icon" type="image/png" href="favicon.png"/>
  
  <title>MCP</title>
  <link rel="manifest" href="manifest.json">
  
  <!-- Service Worker Registration -->
  <script>
    if ('serviceWorker' in navigator) {
      window.addEventListener('flutter-first-frame', function () {
        navigator.serviceWorker.register('flutter_service_worker.js');
      });
    }
  </script>
</head>
<body>
  <script src="main.dart.js" type="application/javascript"></script>
</body>
</html>
```

### 2. Web Manifest

Update `web/manifest.json`:

```json
{
  "name": "MCP Application",
  "short_name": "MCP",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#0175C2",
  "theme_color": "#0175C2",
  "description": "Model Context Protocol Application",
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
    }
  ],
  "categories": ["productivity", "utilities"],
  "shortcuts": [
    {
      "name": "New Chat",
      "url": "/chat/new",
      "icons": [{"src": "icons/chat.png", "sizes": "96x96"}]
    }
  ]
}
```

### 3. CORS Configuration

Configure your server for CORS:

```dart
// Server-side CORS headers
response.headers.add('Access-Control-Allow-Origin', '*');
response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
```

## Features

### Service Workers

Implement background functionality using Service Workers:

```dart
// Register service worker
await mcp.serviceWorker.register(
  scope: '/',
  onMessage: (message) {
    print('Service Worker message: $message');
  },
);

// Send message to service worker
await mcp.serviceWorker.postMessage({
  'type': 'sync',
  'data': {'timestamp': DateTime.now().toIso8601String()},
});

// Background sync
await mcp.serviceWorker.registerBackgroundSync(
  tag: 'mcp-sync',
  minInterval: Duration(minutes: 15),
);
```

Service Worker implementation (`web/service_worker.js`):

```javascript
self.addEventListener('sync', (event) => {
  if (event.tag === 'mcp-sync') {
    event.waitUntil(performBackgroundSync());
  }
});

async function performBackgroundSync() {
  // Perform background sync tasks
  const response = await fetch('/api/sync', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({timestamp: Date.now()}),
  });
  return response.json();
}
```

### Local Storage

Web-specific storage options:

```dart
// IndexedDB for large data
await mcp.webStorage.indexedDB.open('mcp_db', version: 1);
await mcp.webStorage.indexedDB.put(
  objectStore: 'config',
  key: 'settings',
  value: {'theme': 'dark', 'language': 'en'},
);

// LocalStorage for small data
await mcp.webStorage.localStorage.setItem('user_token', 'abc123');
final token = await mcp.webStorage.localStorage.getItem('user_token');

// SessionStorage for temporary data
await mcp.webStorage.sessionStorage.setItem('temp_data', 'xyz');

// Web SQL (deprecated but sometimes useful)
final db = await mcp.webStorage.openDatabase('mcp.db', '1.0');
await db.execute('CREATE TABLE IF NOT EXISTS messages (id INTEGER, content TEXT)');
```

### Notifications

Web Notifications API:

```dart
// Request permission
final permission = await mcp.webNotifications.requestPermission();
if (permission == 'granted') {
  // Show notification
  await mcp.webNotifications.show(
    title: 'MCP Update',
    body: 'New message received',
    icon: '/icons/notification.png',
    badge: '/icons/badge.png',
    tag: 'mcp-notification',
    requireInteraction: true,
    actions: [
      NotificationAction(action: 'reply', title: 'Reply'),
      NotificationAction(action: 'dismiss', title: 'Dismiss'),
    ],
  );
}

// Handle notification clicks in service worker
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  if (event.action === 'reply') {
    event.waitUntil(clients.openWindow('/chat'));
  }
});
```

### WebSocket Connections

Real-time communication:

```dart
// Connect to WebSocket server
final websocket = await mcp.webSocket.connect(
  url: 'wss://server.example.com/mcp',
  protocols: ['mcp-v1'],
);

// Send messages
websocket.send(json.encode({
  'type': 'message',
  'content': 'Hello, server!',
}));

// Receive messages
websocket.stream.listen((message) {
  final data = json.decode(message);
  print('Received: ${data['content']}');
});

// Handle connection state
websocket.onOpen(() => print('Connected'));
websocket.onClose(() => print('Disconnected'));
websocket.onError((error) => print('Error: $error'));
```

### File Handling

Web file APIs:

```dart
// File picker
final result = await mcp.webFiles.pickFiles(
  allowMultiple: false,
  type: FileType.custom,
  allowedExtensions: ['json', 'txt'],
);

if (result != null) {
  final file = result.files.first;
  final content = await file.readAsString();
  print('File content: $content');
}

// Drag and drop
mcp.webFiles.setupDropZone(
  elementId: 'drop-zone',
  onDrop: (files) async {
    for (final file in files) {
      print('Dropped: ${file.name}');
      final content = await file.readAsString();
      await processFile(content);
    }
  },
);

// File download
await mcp.webFiles.downloadFile(
  content: json.encode(data),
  filename: 'export.json',
  mimeType: 'application/json',
);
```

### Web Workers

Offload heavy computation:

```dart
// Create web worker
final worker = await mcp.webWorker.create('worker.js');

// Send task to worker
worker.postMessage({
  'task': 'processData',
  'data': largeDataSet,
});

// Receive results
worker.onMessage.listen((message) {
  final result = message.data;
  print('Worker result: $result');
});

// Terminate worker
worker.terminate();
```

Worker implementation (`web/worker.js`):

```javascript
self.addEventListener('message', (event) => {
  const {task, data} = event.data;
  
  if (task === 'processData') {
    const result = processLargeDataSet(data);
    self.postMessage({result});
  }
});
```

### Progressive Web App (PWA)

PWA features:

```dart
// Check if running as PWA
final isPWA = await mcp.webPWA.isInstalled();

// Prompt to install
if (!isPWA) {
  await mcp.webPWA.showInstallPrompt();
}

// Handle app install
mcp.webPWA.onBeforeInstallPrompt((event) {
  // Show custom install UI
  showInstallButton();
});

// Update notification
if (await mcp.webPWA.hasUpdate()) {
  showUpdateBanner();
  
  // Apply update
  await mcp.webPWA.applyUpdate();
  await mcp.webPWA.reload();
}
```

## Security

### Content Security Policy

Add to `web/index.html`:

```html
<meta http-equiv="Content-Security-Policy" 
      content="default-src 'self'; 
               script-src 'self' 'unsafe-inline' 'unsafe-eval'; 
               style-src 'self' 'unsafe-inline'; 
               img-src 'self' data: https:; 
               connect-src 'self' wss: https:;">
```

### HTTPS and Secure Contexts

```dart
// Check if secure context
if (!window.isSecureContext) {
  showWarning('This app requires HTTPS');
}

// Force HTTPS redirect
if (window.location.protocol !== 'https:') {
  window.location.protocol = 'https:';
}
```

### Web Crypto API

```dart
// Generate keys
final keyPair = await mcp.webCrypto.generateKey(
  algorithm: 'RSA-OAEP',
  extractable: true,
  keyUsages: ['encrypt', 'decrypt'],
);

// Encrypt data
final encrypted = await mcp.webCrypto.encrypt(
  algorithm: 'RSA-OAEP',
  key: keyPair.publicKey,
  data: utf8.encode('secret message'),
);

// Decrypt data
final decrypted = await mcp.webCrypto.decrypt(
  algorithm: 'RSA-OAEP',
  key: keyPair.privateKey,
  data: encrypted,
);
```

## Performance

### Code Splitting

```dart
// Lazy load features
if (userWantsAdvancedFeatures) {
  final advancedModule = await loadLibrary('package:mcp/advanced.dart');
  advancedModule.initialize();
}
```

### Caching Strategies

```dart
// Cache API responses
final cache = await caches.open('mcp-v1');
final response = await cache.match(request);

if (response == null) {
  // Fetch and cache
  final networkResponse = await fetch(request);
  await cache.put(request, networkResponse.clone());
  return networkResponse;
}

return response;
```

### Web Vitals

```dart
// Monitor performance
mcp.webPerformance.observe(
  metrics: ['FCP', 'LCP', 'FID', 'CLS'],
  onMetric: (metric) {
    print('${metric.name}: ${metric.value}');
    // Send to analytics
    analytics.track('web_vital', {
      'metric': metric.name,
      'value': metric.value,
    });
  },
);
```

## Deployment

### Build Optimization

```bash
# Build for production
flutter build web --release --web-renderer canvaskit

# Build with tree shaking
flutter build web --release --tree-shake-icons

# Build for specific renderer
flutter build web --release --web-renderer html
```

### Static Hosting

Deploy to various platforms:

```bash
# Firebase Hosting
firebase deploy --only hosting

# Netlify
netlify deploy --prod

# Vercel
vercel --prod

# GitHub Pages
flutter build web --release --base-href "/repo-name/"
```

### CDN Configuration

```nginx
# Nginx configuration
location / {
  add_header Cache-Control "public, max-age=3600";
  gzip on;
  gzip_types text/plain text/css text/javascript application/javascript;
}

location /assets/ {
  add_header Cache-Control "public, max-age=31536000, immutable";
}
```

## Browser Compatibility

### Feature Detection

```dart
// Check browser features
if (!mcp.webFeatures.hasWebSocket()) {
  showFallbackUI();
}

if (!mcp.webFeatures.hasServiceWorker()) {
  disableOfflineMode();
}

if (!mcp.webFeatures.hasIndexedDB()) {
  useLocalStorageFallback();
}
```

### Polyfills

```html
<!-- Add polyfills for older browsers -->
<script src="https://polyfill.io/v3/polyfill.min.js?features=es2015%2Ces2016%2Ces2017"></script>
```

## Debugging

### Browser DevTools

```dart
// Web-specific debugging
if (kIsWeb) {
  // Console logging
  window.console.log('Debug message');
  window.console.error('Error message');
  
  // Performance timing
  window.performance.mark('start');
  // ... operation ...
  window.performance.mark('end');
  window.performance.measure('operation', 'start', 'end');
  
  // Network monitoring
  final entries = window.performance.getEntriesByType('resource');
  entries.forEach((entry) {
    print('Resource: ${entry.name}, Duration: ${entry.duration}ms');
  });
}
```

### Remote Debugging

```dart
// Enable remote debugging
if (kDebugMode) {
  await mcp.webDebug.enableRemoteDebugging(
    port: 9229,
    bindAddress: '0.0.0.0',
  );
}
```

## Platform-Specific APIs

```dart
// Access web-specific features
if (kIsWeb) {
  // Browser information
  final userAgent = window.navigator.userAgent;
  final platform = window.navigator.platform;
  
  // Screen information
  final width = window.screen.width;
  final height = window.screen.height;
  final pixelRatio = window.devicePixelRatio;
  
  // Network information
  final connection = window.navigator.connection;
  if (connection != null) {
    print('Network type: ${connection.effectiveType}');
    print('Downlink: ${connection.downlink}');
  }
}
```

## Limitations

### Web Platform Constraints

1. **No Native Process Management**: Cannot spawn system processes
2. **Limited File System Access**: Only through user interaction
3. **Network Restrictions**: CORS and mixed content policies
4. **Background Execution**: Limited to Service Workers
5. **Storage Quotas**: Browser-imposed limits on storage

### Workarounds

```dart
// Fallback for unavailable features
Future<void> executeCommand(String command) async {
  if (kIsWeb) {
    // Use server-side API
    await http.post('/api/execute', body: {'command': command});
  } else {
    // Native process execution
    await Process.run(command, []);
  }
}
```

## Next Steps

- [Deployment Guide](../guides/deployment.md) - Web deployment strategies
- [Performance Guide](../advanced/performance.md) - Web optimization techniques
- [Security Guide](../advanced/security.md) - Web security best practices