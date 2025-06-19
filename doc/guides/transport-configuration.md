# Transport Configuration Guide

Transport is the core communication mechanism in Model Context Protocol (MCP). This guide provides comprehensive information about configuring and using different transport types in Flutter MCP.

## Table of Contents

- [Overview](#overview)
- [Transport Types](#transport-types)
- [Server Configuration](#server-configuration)
- [Client Configuration](#client-configuration)
- [Connection Examples](#connection-examples)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

Flutter MCP supports three transport types for communication between MCP clients and servers:

1. **STDIO** - Standard Input/Output
2. **SSE** - Server-Sent Events
3. **StreamableHTTP** - HTTP with streaming capabilities

Each transport type has its own use cases and configuration requirements.

## Transport Types

### STDIO (Standard Input/Output)

STDIO transport uses standard input/output streams for communication. This is ideal for:
- Local process communication
- Subprocess execution
- Command-line tools
- Isolated environments

**Pros:**
- Simple and lightweight
- No network configuration required
- Secure (no network exposure)

**Cons:**
- Limited to local processes
- Not suitable for distributed systems

### SSE (Server-Sent Events)

SSE transport uses HTTP Server-Sent Events for real-time communication. This is ideal for:
- Web applications
- Real-time updates
- Browser-compatible communication
- Unidirectional streaming (server to client)

**Pros:**
- Native browser support
- Works through firewalls and proxies
- Automatic reconnection
- Simple HTTP-based protocol

**Cons:**
- Unidirectional (server to client only, uses separate endpoint for client to server)
- Limited by HTTP connection limits

### StreamableHTTP

StreamableHTTP combines traditional HTTP requests with streaming responses. This is ideal for:
- REST-like APIs
- Bidirectional communication
- High-throughput applications
- Modern web services

**Pros:**
- Bidirectional communication
- Supports both streaming and traditional request/response
- Flexible response modes (SSE or JSON)
- HTTP/2 support

**Cons:**
- More complex than SSE
- Requires proper session management

## Server Configuration

### STDIO Server

```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'STDIO Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'STDIO Server',
    version: '1.0.0',
    transportType: 'stdio',  // Required
  ),
);
```

**Configuration Options:**
- `transportType`: Must be `'stdio'`
- `authToken`: Optional authentication token

### SSE Server

```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'SSE Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'SSE Server',
    version: '1.0.0',
    transportType: 'sse',    // Required
    ssePort: 8080,           // Required
    
    // Optional configurations
    host: 'localhost',       // Default: 'localhost'
    endpoint: '/sse',        // Default: '/sse'
    messagesEndpoint: '/message',  // Default: '/message'
    fallbackPorts: [8081, 8082],   // Alternative ports if primary is busy
    authToken: 'your-secret-token',
    middleware: [],          // Custom shelf middleware
  ),
);
```

**Configuration Options:**
- `transportType`: Must be `'sse'`
- `ssePort`: Required. The port to listen on
- `host`: Server bind address (default: 'localhost')
- `endpoint`: SSE endpoint path (default: '/sse')
- `messagesEndpoint`: Message posting endpoint (default: '/message')
- `fallbackPorts`: List of alternative ports to try
- `authToken`: Optional bearer token for authentication
- `middleware`: List of custom shelf middleware

### StreamableHTTP Server

```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'StreamableHTTP Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'StreamableHTTP Server',
    version: '1.0.0',
    transportType: 'streamablehttp',  // Required
    streamableHttpPort: 8080,         // Required
    
    // Optional configurations
    host: 'localhost',                // Default: 'localhost'
    endpoint: '/mcp',                 // Default: '/mcp'
    messagesEndpoint: '/message',     // Default: '/message'
    fallbackPorts: [8081, 8082],
    authToken: 'your-secret-token',
    
    // StreamableHTTP specific options
    isJsonResponseEnabled: false,     // false = SSE mode, true = JSON mode
    jsonResponseMode: 'sync',         // 'sync' or 'async' (only for JSON mode)
    maxRequestSize: 4194304,          // Max request size in bytes (default: 4MB)
    requestTimeout: Duration(seconds: 30),
    
    // CORS configuration
    corsConfig: {
      'allowOrigin': '*',
      'allowMethods': 'POST, GET, OPTIONS, DELETE',
      'allowHeaders': 'Content-Type, Authorization, mcp-session-id',
      'maxAge': 86400,
    },
  ),
);
```

**Configuration Options:**
- `transportType`: Must be `'streamablehttp'`
- `streamableHttpPort`: Required. The port to listen on
- `host`: Server bind address (default: 'localhost')
- `endpoint`: HTTP endpoint path (default: '/mcp')
- `messagesEndpoint`: Message endpoint (default: '/message')
- `fallbackPorts`: List of alternative ports to try
- `authToken`: Optional bearer token for authentication
- `isJsonResponseEnabled`: Response mode (false = SSE streaming, true = JSON)
- `jsonResponseMode`: For JSON mode: 'sync' (immediate) or 'async' (polling)
- `maxRequestSize`: Maximum request body size in bytes
- `requestTimeout`: Request timeout duration
- `corsConfig`: CORS configuration map

## Client Configuration

### STDIO Client

```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'STDIO Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'STDIO Client',
    version: '1.0.0',
    transportType: 'stdio',        // Required
    transportCommand: 'python',    // Required
    transportArgs: [               // Optional
      'server.py',
      '--mode', 'mcp',
      '--port', '8080'
    ],
  ),
);
```

**Configuration Options:**
- `transportType`: Must be `'stdio'`
- `transportCommand`: Required. The command to execute
- `transportArgs`: Optional command arguments
- `authToken`: Optional authentication token

### SSE Client

```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'SSE Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'SSE Client',
    version: '1.0.0',
    transportType: 'sse',              // Required
    serverUrl: 'http://localhost:8080', // Required
    
    // Optional configurations
    endpoint: '/sse',                  // Will be appended to serverUrl
    authToken: 'your-secret-token',
    headers: {
      'X-Custom-Header': 'value',
      'User-Agent': 'MyApp/1.0',
    },
    timeout: Duration(seconds: 30),
    sseReadTimeout: Duration(minutes: 5),
  ),
);
```

**Configuration Options:**
- `transportType`: Must be `'sse'`
- `serverUrl`: Required. Base URL of the server
- `endpoint`: Optional endpoint path (appended to serverUrl)
- `authToken`: Optional bearer token for authentication
- `headers`: Additional HTTP headers
- `timeout`: Request timeout
- `sseReadTimeout`: SSE stream read timeout

### StreamableHTTP Client

```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'StreamableHTTP Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'StreamableHTTP Client',
    version: '1.0.0',
    transportType: 'streamablehttp',    // Required
    serverUrl: 'http://localhost:8080', // Required (base URL only)
    
    // Optional configurations
    endpoint: '/mcp',                   // Must match server endpoint
    authToken: 'your-secret-token',
    headers: {
      'X-Custom-Header': 'value',
    },
    timeout: Duration(seconds: 30),
    maxConcurrentRequests: 10,
    useHttp2: true,
    terminateOnClose: true,
  ),
);
```

**Configuration Options:**
- `transportType`: Must be `'streamablehttp'`
- `serverUrl`: Required. Base URL of the server (without endpoint)
- `endpoint`: Optional endpoint path (must match server configuration)
- `authToken`: Optional bearer token for authentication
- `headers`: Additional HTTP headers
- `timeout`: Request timeout
- `maxConcurrentRequests`: Maximum concurrent HTTP requests
- `useHttp2`: Enable HTTP/2 if available
- `terminateOnClose`: Send session termination on close

## Connection Examples

### Example 1: Local STDIO Connection

```dart
// Server side (subprocess)
final serverId = await FlutterMCP.instance.createServer(
  name: 'Local Tool Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'Local Tool Server',
    version: '1.0.0',
    transportType: 'stdio',
  ),
);

// Client side (parent process)
final clientId = await FlutterMCP.instance.createClient(
  name: 'Tool Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'Tool Client',
    version: '1.0.0',
    transportType: 'stdio',
    transportCommand: 'dart',
    transportArgs: ['run', 'bin/server.dart'],
  ),
);

await FlutterMCP.instance.connectClient(clientId);
```

### Example 2: Web-Compatible SSE Connection

```dart
// Server
final serverId = await FlutterMCP.instance.createServer(
  name: 'Web API Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'Web API Server',
    version: '1.0.0',
    transportType: 'sse',
    ssePort: 3000,
    corsConfig: {
      'allowOrigin': 'http://localhost:8080',
      'allowMethods': 'GET, POST, OPTIONS',
    },
  ),
);
await FlutterMCP.instance.connectServer(serverId);

// Client (can be web browser)
final clientId = await FlutterMCP.instance.createClient(
  name: 'Web Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'Web Client',
    version: '1.0.0',
    transportType: 'sse',
    serverUrl: 'http://localhost:3000',
  ),
);
await FlutterMCP.instance.connectClient(clientId);
```

### Example 3: High-Performance StreamableHTTP

```dart
// Server with authentication
final serverId = await FlutterMCP.instance.createServer(
  name: 'API Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'API Server',
    version: '1.0.0',
    transportType: 'streamablehttp',
    streamableHttpPort: 8443,
    endpoint: '/api/mcp',
    authToken: 'server-secret-key',
    isJsonResponseEnabled: false,  // Use SSE for streaming
    fallbackPorts: [8444, 8445],
  ),
);
await FlutterMCP.instance.connectServer(serverId);

// Client with authentication
final clientId = await FlutterMCP.instance.createClient(
  name: 'API Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'API Client',
    version: '1.0.0',
    transportType: 'streamablehttp',
    serverUrl: 'http://localhost:8443',
    endpoint: '/api/mcp',  // Must match server
    authToken: 'server-secret-key',
    maxConcurrentRequests: 20,
    useHttp2: true,
  ),
);
await FlutterMCP.instance.connectClient(clientId);
```

## Best Practices

### 1. Transport Selection

Choose the right transport for your use case:
- **STDIO**: For local tools, CLI applications, and subprocess communication
- **SSE**: For web browsers, real-time updates, and simple streaming
- **StreamableHTTP**: For production APIs, high-throughput applications, and complex interactions

### 2. Security

Always use authentication in production:
```dart
// Generate secure tokens
final authToken = generateSecureToken();

// Use HTTPS in production
serverUrl: 'https://api.example.com',

// Configure CORS properly
corsConfig: {
  'allowOrigin': 'https://app.example.com',  // Specific origin
  'allowMethods': 'POST, GET',  // Only required methods
  'allowHeaders': 'Content-Type, Authorization',
}
```

### 3. Error Handling

```dart
try {
  await FlutterMCP.instance.connectClient(clientId);
} on MCPTransportException catch (e) {
  // Handle transport-specific errors
  print('Transport error: ${e.message}');
} on MCPConnectionException catch (e) {
  // Handle connection errors
  print('Connection failed: ${e.message}');
} catch (e) {
  // Handle other errors
  print('Unexpected error: $e');
}
```

### 4. Port Management

Use fallback ports for server reliability:
```dart
config: MCPServerConfig(
  // ...
  streamableHttpPort: 8080,
  fallbackPorts: [8081, 8082, 8083],  // Try these if 8080 is busy
)
```

### 5. Connection Lifecycle

```dart
// 1. Create server
final serverId = await FlutterMCP.instance.createServer(...);

// 2. Start server
await FlutterMCP.instance.connectServer(serverId);

// 3. Create client
final clientId = await FlutterMCP.instance.createClient(...);

// 4. Connect client
await FlutterMCP.instance.connectClient(clientId);

// 5. Use the connection
// ... perform operations ...

// 6. Clean up
await FlutterMCP.instance.disconnectClient(clientId);
await FlutterMCP.instance.disconnectServer(serverId);
```

## Troubleshooting

### Common Issues

#### 1. "Transport Type Must Be Specified"

**Problem**: Getting error about missing transport type.

**Solution**: Explicitly specify transportType in your config:
```dart
config: MCPClientConfig(
  transportType: 'sse',  // Required!
  // ... other config
)
```

#### 2. "Session Terminated" Errors

**Problem**: StreamableHTTP client gets session terminated errors.

**Solution**: Ensure client and server endpoints match:
```dart
// Server
config: MCPServerConfig(
  transportType: 'streamablehttp',
  endpoint: '/mcp',  // Note the endpoint
  // ...
)

// Client
config: MCPClientConfig(
  transportType: 'streamablehttp',
  serverUrl: 'http://localhost:8080',  // Base URL only
  endpoint: '/mcp',  // Must match server!
  // ...
)
```

#### 3. Connection Refused

**Problem**: Client cannot connect to server.

**Solutions**:
1. Check if server is running: `await FlutterMCP.instance.connectServer(serverId)`
2. Verify port is not blocked by firewall
3. Ensure host is accessible (use '0.0.0.0' instead of 'localhost' for external access)
4. Check authentication tokens match

#### 4. CORS Errors (Web)

**Problem**: Web client gets CORS errors.

**Solution**: Configure CORS on server:
```dart
config: MCPServerConfig(
  corsConfig: {
    'allowOrigin': '*',  // Or specific origin
    'allowMethods': 'POST, GET, OPTIONS',
    'allowHeaders': 'Content-Type, Authorization',
  },
  // ...
)
```

### Debug Tips

1. Enable debug logging:
```dart
FlutterMcpLogging.configure(
  level: Level.FINE,
  enableDebugLogging: true,
);
```

2. Check transport status:
```dart
final status = FlutterMCP.instance.getSystemStatus();
print('Servers: ${status['servers']}');
print('Clients: ${status['clients']}');
```

3. Monitor connection events:
```dart
FlutterMCP.instance.connectionEvents.listen((event) {
  print('Connection event: ${event.type} for ${event.id}');
});
```

## See Also

- [Getting Started Guide](getting-started.md)
- [Architecture Overview](architecture.md)
- [Security Best Practices](../advanced/security.md)
- [Performance Tuning](../advanced/performance-tuning.md)