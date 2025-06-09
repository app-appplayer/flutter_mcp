# Error Codes Reference

Complete reference for Flutter MCP error codes and their solutions.

## Error Code Structure

Flutter MCP uses a structured error code system:

```
MCP-[CATEGORY]-[NUMBER]
```

- **Category**: Error category (e.g., CONN, AUTH, TOOL)
- **Number**: Specific error number within the category

## Connection Errors (CONN)

### MCP-CONN-001: Connection Timeout

**Description**: Failed to establish connection within the timeout period.

**Common Causes**:
- Server is not running
- Network connectivity issues
- Firewall blocking connection
- Incorrect server URL

**Solution**:
```dart
try {
  await mcp.initialize(config: McpConfig(
    servers: [
      ServerConfig(
        id: 'server',
        url: 'ws://localhost:8080',
        connectionTimeout: Duration(seconds: 30), // Increase timeout
      ),
    ],
  ));
} on MCPConnectionTimeoutException catch (e) {
  // Handle timeout
  print('Connection timeout: ${e.message}');
  // Retry with exponential backoff
  await retryWithBackoff(() => mcp.initialize(config: config));
}
```

### MCP-CONN-002: Connection Refused

**Description**: Server actively refused the connection.

**Common Causes**:
- Server not listening on specified port
- Wrong port number
- Server crashed

**Solution**:
```bash
# Check if server is running
lsof -i :8080

# Start server if needed
node mcp-server.js

# Verify port in Flutter app matches server
```

### MCP-CONN-003: DNS Resolution Failed

**Description**: Cannot resolve hostname.

**Common Causes**:
- Invalid hostname
- DNS server issues
- No internet connection

**Solution**:
```dart
// Use IP address instead of hostname for testing
final config = McpConfig(
  servers: [
    ServerConfig(
      id: 'server',
      url: 'ws://192.168.1.100:8080', // Use IP instead of hostname
    ),
  ],
);

// Or add DNS fallback
try {
  await InternetAddress.lookup('your-server.com');
} on SocketException {
  // Use fallback server
  config.servers.first.url = 'ws://fallback-server.com:8080';
}
```

### MCP-CONN-004: SSL/TLS Handshake Failed

**Description**: SSL/TLS negotiation failed.

**Common Causes**:
- Invalid certificate
- Certificate expired
- Self-signed certificate
- Protocol mismatch

**Solution**:
```dart
// For development with self-signed certificates
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true; // Development only!
  }
}

// For production with custom CA
final securityContext = SecurityContext(withTrustedRoots: true)
  ..setTrustedCertificates('path/to/ca-cert.pem');

final config = McpConfig(
  securityContext: securityContext,
  servers: [
    ServerConfig(
      id: 'server',
      url: 'wss://secure-server.com:8443',
    ),
  ],
);
```

### MCP-CONN-005: WebSocket Protocol Error

**Description**: WebSocket protocol violation.

**Common Causes**:
- Server not supporting WebSocket
- Protocol version mismatch
- Invalid WebSocket headers

**Solution**:
```dart
// Ensure correct WebSocket protocol
final config = McpConfig(
  servers: [
    ServerConfig(
      id: 'server',
      url: 'ws://localhost:8080', // Use ws:// for WebSocket
      headers: {
        'Sec-WebSocket-Protocol': 'mcp', // Specify protocol
      },
    ),
  ],
);

// Add WebSocket-specific error handling
mcp.client.onError.listen((error) {
  if (error is WebSocketException) {
    print('WebSocket error: ${error.message}');
    // Handle WebSocket-specific errors
  }
});
```

## Authentication Errors (AUTH)

### MCP-AUTH-001: Invalid Credentials

**Description**: Authentication failed due to invalid credentials.

**Common Causes**:
- Wrong username/password
- Expired API key
- Invalid token

**Solution**:
```dart
// Implement credential refresh
class AuthManager {
  Future<Credentials> refreshCredentials() async {
    // Get new token
    final response = await http.post(
      Uri.parse('https://auth.example.com/refresh'),
      body: {'refresh_token': currentRefreshToken},
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Credentials(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
    }
    
    throw MCPAuthException('Failed to refresh credentials');
  }
}

// Use in MCP configuration
final config = McpConfig(
  authProvider: AuthProvider(
    getCredentials: () async => await authManager.refreshCredentials(),
    onAuthError: (error) async {
      // Handle auth error
      await authManager.clearCredentials();
      await authManager.login();
    },
  ),
);
```

### MCP-AUTH-002: Permission Denied

**Description**: User lacks required permissions.

**Common Causes**:
- Insufficient user role
- Feature not available in plan
- Resource access denied

**Solution**:
```dart
// Check permissions before operations
class PermissionChecker {
  final Set<String> userPermissions;
  
  bool hasPermission(String permission) {
    return userPermissions.contains(permission);
  }
  
  Future<void> checkPermission(String permission) async {
    if (!hasPermission(permission)) {
      throw MCPPermissionException(
        'Permission denied: $permission',
        code: 'MCP-AUTH-002',
      );
    }
  }
}

// Wrap MCP calls with permission checks
try {
  await permissionChecker.checkPermission('tools.execute');
  await mcp.client.callTool(...);
} on MCPPermissionException catch (e) {
  // Show permission error to user
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Permission Denied'),
      content: Text('You need to upgrade your plan to use this feature.'),
    ),
  );
}
```

### MCP-AUTH-003: Token Expired

**Description**: Authentication token has expired.

**Common Causes**:
- Token TTL exceeded
- Clock skew between client and server
- Session timeout

**Solution**:
```dart
// Implement automatic token refresh
class TokenManager {
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  
  Future<String> getAccessToken() async {
    if (_isTokenExpired()) {
      await _refreshToken();
    }
    return _accessToken!;
  }
  
  bool _isTokenExpired() {
    if (_expiresAt == null) return true;
    // Refresh 5 minutes before expiry
    return DateTime.now().add(Duration(minutes: 5)).isAfter(_expiresAt!);
  }
  
  Future<void> _refreshToken() async {
    final response = await http.post(
      Uri.parse('https://auth.example.com/token'),
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken,
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _accessToken = data['access_token'];
      _refreshToken = data['refresh_token'];
      _expiresAt = DateTime.now().add(
        Duration(seconds: data['expires_in']),
      );
    } else {
      throw MCPAuthException('Token refresh failed');
    }
  }
}
```

### MCP-AUTH-004: Invalid Session

**Description**: Session is invalid or has been terminated.

**Common Causes**:
- Session expired
- Logged out from another device
- Server restart

**Solution**:
```dart
// Implement session validation
class SessionManager {
  static const String sessionKey = 'mcp_session';
  
  Future<bool> validateSession() async {
    final session = await _storage.read(key: sessionKey);
    if (session == null) return false;
    
    try {
      final response = await http.get(
        Uri.parse('https://api.example.com/session/validate'),
        headers: {'Authorization': 'Bearer $session'},
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  Future<void> createNewSession() async {
    // Re-authenticate user
    final credentials = await _authenticate();
    await _storage.write(key: sessionKey, value: credentials.sessionId);
  }
}

// Use in MCP lifecycle
mcp.client.onError.listen((error) async {
  if (error.code == 'MCP-AUTH-004') {
    final isValid = await sessionManager.validateSession();
    if (!isValid) {
      await sessionManager.createNewSession();
      // Retry the operation
    }
  }
});
```

## Tool Errors (TOOL)

### MCP-TOOL-001: Tool Not Found

**Description**: Requested tool does not exist on the server.

**Common Causes**:
- Typo in tool name
- Tool not registered on server
- Server version mismatch

**Solution**:
```dart
// List available tools first
Future<void> callToolSafely(String toolName, Map<String, dynamic> args) async {
  // Get available tools
  final tools = await mcp.client.listTools(serverId: 'server');
  
  // Check if tool exists
  final toolExists = tools.any((tool) => tool.name == toolName);
  
  if (!toolExists) {
    throw MCPToolNotFoundException(
      'Tool not found: $toolName',
      availableTools: tools.map((t) => t.name).toList(),
    );
  }
  
  // Call tool
  await mcp.client.callTool(
    serverId: 'server',
    name: toolName,
    arguments: args,
  );
}

// Handle tool not found
try {
  await callToolSafely('myTool', {'param': 'value'});
} on MCPToolNotFoundException catch (e) {
  print('Tool not found. Available tools: ${e.availableTools}');
  // Show tool selector to user
}
```

### MCP-TOOL-002: Invalid Tool Arguments

**Description**: Tool arguments do not match expected schema.

**Common Causes**:
- Missing required arguments
- Wrong argument types
- Extra unexpected arguments

**Solution**:
```dart
// Validate arguments before calling
class ToolArgumentValidator {
  final Map<String, ToolSchema> schemas;
  
  void validate(String toolName, Map<String, dynamic> arguments) {
    final schema = schemas[toolName];
    if (schema == null) return;
    
    // Check required arguments
    for (final required in schema.requiredArguments) {
      if (!arguments.containsKey(required)) {
        throw MCPInvalidArgumentException(
          'Missing required argument: $required',
          code: 'MCP-TOOL-002',
        );
      }
    }
    
    // Validate types
    arguments.forEach((key, value) {
      final expectedType = schema.argumentTypes[key];
      if (expectedType != null && value.runtimeType != expectedType) {
        throw MCPInvalidArgumentException(
          'Invalid type for $key: expected $expectedType, got ${value.runtimeType}',
          code: 'MCP-TOOL-002',
        );
      }
    });
  }
}

// Use validator
try {
  validator.validate('generateCode', arguments);
  await mcp.client.callTool(
    serverId: 'server',
    name: 'generateCode',
    arguments: arguments,
  );
} on MCPInvalidArgumentException catch (e) {
  // Show validation error
  print('Invalid arguments: ${e.message}');
}
```

### MCP-TOOL-003: Tool Execution Failed

**Description**: Tool execution failed on the server.

**Common Causes**:
- Server-side error
- Resource unavailable
- External service failure

**Solution**:
```dart
// Implement retry with fallback
class ToolExecutor {
  static const int maxRetries = 3;
  
  Future<ToolResult> executeWithRetry({
    required String toolName,
    required Map<String, dynamic> arguments,
    Duration retryDelay = const Duration(seconds: 1),
  }) async {
    MCPException? lastError;
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await mcp.client.callTool(
          serverId: 'server',
          name: toolName,
          arguments: arguments,
        );
      } on MCPToolExecutionException catch (e) {
        lastError = e;
        
        // Don't retry for certain errors
        if (e.message.contains('Invalid input')) {
          rethrow;
        }
        
        if (attempt < maxRetries - 1) {
          await Future.delayed(retryDelay * (attempt + 1));
        }
      }
    }
    
    throw lastError!;
  }
}

// Use with error handling
try {
  final result = await ToolExecutor().executeWithRetry(
    toolName: 'processData',
    arguments: {'data': largeDataset},
  );
} on MCPToolExecutionException catch (e) {
  if (e.message.contains('Out of memory')) {
    // Try with smaller chunks
    final chunks = splitDataset(largeDataset);
    for (final chunk in chunks) {
      await ToolExecutor().executeWithRetry(
        toolName: 'processData',
        arguments: {'data': chunk},
      );
    }
  }
}
```

### MCP-TOOL-004: Tool Timeout

**Description**: Tool execution exceeded timeout limit.

**Common Causes**:
- Long-running operation
- Server overloaded
- Network latency

**Solution**:
```dart
// Implement adaptive timeout
class AdaptiveTimeoutManager {
  final Map<String, Duration> _toolTimeouts = {};
  final Map<String, List<int>> _executionTimes = {};
  
  Duration getTimeout(String toolName) {
    // Use custom timeout if set
    if (_toolTimeouts.containsKey(toolName)) {
      return _toolTimeouts[toolName]!;
    }
    
    // Calculate based on historical data
    final times = _executionTimes[toolName];
    if (times != null && times.isNotEmpty) {
      final average = times.reduce((a, b) => a + b) / times.length;
      final buffer = average * 0.5; // 50% buffer
      return Duration(milliseconds: (average + buffer).round());
    }
    
    // Default timeout
    return Duration(seconds: 30);
  }
  
  void recordExecutionTime(String toolName, int milliseconds) {
    _executionTimes.putIfAbsent(toolName, () => []).add(milliseconds);
    
    // Keep only last 10 executions
    if (_executionTimes[toolName]!.length > 10) {
      _executionTimes[toolName]!.removeAt(0);
    }
  }
  
  Future<ToolResult> executeWithAdaptiveTimeout(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final timeout = getTimeout(toolName);
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await mcp.client.callTool(
        serverId: 'server',
        name: toolName,
        arguments: arguments,
      ).timeout(timeout);
      
      stopwatch.stop();
      recordExecutionTime(toolName, stopwatch.elapsedMilliseconds);
      
      return result;
    } on TimeoutException {
      throw MCPTimeoutException(
        'Tool execution timeout: $toolName (${timeout.inSeconds}s)',
        code: 'MCP-TOOL-004',
      );
    }
  }
}
```

## Resource Errors (RES)

### MCP-RES-001: Resource Not Found

**Description**: Requested resource does not exist.

**Common Causes**:
- Invalid resource URI
- Resource deleted
- Permission issue

**Solution**:
```dart
// Check resource existence before access
class ResourceManager {
  final Map<String, DateTime> _resourceCache = {};
  
  Future<bool> resourceExists(String uri) async {
    // Check cache first
    if (_resourceCache.containsKey(uri)) {
      final cacheTime = _resourceCache[uri]!;
      if (DateTime.now().difference(cacheTime) < Duration(minutes: 5)) {
        return true;
      }
    }
    
    try {
      final resources = await mcp.client.listResources(serverId: 'server');
      final exists = resources.any((r) => r.uri == uri);
      
      if (exists) {
        _resourceCache[uri] = DateTime.now();
      }
      
      return exists;
    } catch (e) {
      return false;
    }
  }
  
  Future<Resource> getResourceSafely(String uri) async {
    if (!await resourceExists(uri)) {
      throw MCPResourceNotFoundException(
        'Resource not found: $uri',
        code: 'MCP-RES-001',
      );
    }
    
    return await mcp.client.readResource(
      serverId: 'server',
      uri: uri,
    );
  }
}
```

### MCP-RES-002: Resource Access Denied

**Description**: Access to resource is denied.

**Common Causes**:
- Insufficient permissions
- Resource is private
- Authentication required

**Solution**:
```dart
// Handle resource permissions
class ResourcePermissionManager {
  final Map<String, Set<String>> _permissions = {};
  
  Future<void> checkAccess(String uri, String operation) async {
    final permissions = _permissions[uri] ?? {};
    
    if (!permissions.contains(operation)) {
      // Request permission
      final granted = await requestPermission(uri, operation);
      
      if (!granted) {
        throw MCPAccessDeniedException(
          'Access denied to resource: $uri',
          code: 'MCP-RES-002',
          requiredPermission: operation,
        );
      }
      
      _permissions.putIfAbsent(uri, () => {}).add(operation);
    }
  }
  
  Future<bool> requestPermission(String uri, String operation) async {
    try {
      final response = await mcp.client.callTool(
        serverId: 'server',
        name: 'requestPermission',
        arguments: {
          'resource': uri,
          'operation': operation,
        },
      );
      
      return response.content['granted'] == true;
    } catch (e) {
      return false;
    }
  }
}

// Use in resource access
try {
  await permissionManager.checkAccess(uri, 'read');
  final resource = await mcp.client.readResource(
    serverId: 'server',
    uri: uri,
  );
} on MCPAccessDeniedException catch (e) {
  print('Access denied: ${e.requiredPermission}');
  // Show permission request dialog
}
```

### MCP-RES-003: Resource Limit Exceeded

**Description**: Resource usage limit exceeded.

**Common Causes**:
- Rate limit reached
- Quota exhausted
- Storage full

**Solution**:
```dart
// Implement resource usage tracking
class ResourceUsageTracker {
  final Map<String, UsageStats> _usage = {};
  final Map<String, RateLimit> _limits = {};
  
  Future<void> checkLimit(String resource) async {
    final usage = _usage[resource] ?? UsageStats();
    final limit = _limits[resource] ?? await _fetchLimit(resource);
    
    if (usage.count >= limit.maxRequests) {
      final resetTime = usage.windowStart.add(limit.window);
      final waitTime = resetTime.difference(DateTime.now());
      
      throw MCPResourceLimitException(
        'Rate limit exceeded for $resource',
        code: 'MCP-RES-003',
        resetTime: resetTime,
        waitTime: waitTime,
      );
    }
    
    // Update usage
    usage.count++;
    usage.lastUsed = DateTime.now();
    _usage[resource] = usage;
  }
  
  Future<RateLimit> _fetchLimit(String resource) async {
    final response = await mcp.client.callTool(
      serverId: 'server',
      name: 'getResourceLimits',
      arguments: {'resource': resource},
    );
    
    final limit = RateLimit(
      maxRequests: response.content['maxRequests'],
      window: Duration(seconds: response.content['windowSeconds']),
    );
    
    _limits[resource] = limit;
    return limit;
  }
}

// Handle rate limiting
try {
  await usageTracker.checkLimit('api/data');
  final data = await mcp.client.readResource(
    serverId: 'server',
    uri: 'api/data',
  );
} on MCPResourceLimitException catch (e) {
  print('Rate limit exceeded. Reset in: ${e.waitTime}');
  
  // Implement backoff
  if (e.waitTime.inSeconds < 60) {
    await Future.delayed(e.waitTime);
    // Retry
  } else {
    // Show rate limit error to user
  }
}
```

### MCP-RES-004: Resource Corrupted

**Description**: Resource data is corrupted or invalid.

**Common Causes**:
- Data corruption
- Incomplete write
- Format mismatch

**Solution**:
```dart
// Implement resource validation
class ResourceValidator {
  Future<bool> validateResource(Resource resource) async {
    try {
      // Check format
      if (resource.mimeType == 'application/json') {
        jsonDecode(resource.text);
      } else if (resource.mimeType == 'application/xml') {
        XmlDocument.parse(resource.text);
      }
      
      // Check integrity
      if (resource.metadata?['checksum'] != null) {
        final checksum = calculateChecksum(resource.contents);
        if (checksum != resource.metadata!['checksum']) {
          return false;
        }
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  Future<Resource> getValidatedResource(String uri) async {
    const maxRetries = 3;
    
    for (int i = 0; i < maxRetries; i++) {
      try {
        final resource = await mcp.client.readResource(
          serverId: 'server',
          uri: uri,
        );
        
        if (await validateResource(resource)) {
          return resource;
        }
        
        throw MCPResourceCorruptedException(
          'Resource validation failed: $uri',
          code: 'MCP-RES-004',
        );
      } on MCPResourceCorruptedException {
        if (i < maxRetries - 1) {
          // Wait before retry
          await Future.delayed(Duration(seconds: i + 1));
          
          // Try to repair resource
          await attemptResourceRepair(uri);
        } else {
          rethrow;
        }
      }
    }
    
    throw MCPResourceCorruptedException(
      'Failed to get valid resource after $maxRetries attempts',
      code: 'MCP-RES-004',
    );
  }
  
  Future<void> attemptResourceRepair(String uri) async {
    try {
      await mcp.client.callTool(
        serverId: 'server',
        name: 'repairResource',
        arguments: {'uri': uri},
      );
    } catch (e) {
      // Repair failed, will retry reading
    }
  }
}
```

## Transport Errors (TRANS)

### MCP-TRANS-001: Message Too Large

**Description**: Message size exceeds maximum allowed.

**Common Causes**:
- Large payload
- Binary data in message
- Accumulation of data

**Solution**:
```dart
// Implement message chunking
class MessageChunker {
  static const int maxChunkSize = 1024 * 1024; // 1MB
  
  List<MessageChunk> chunkMessage(dynamic message) {
    final json = jsonEncode(message);
    final bytes = utf8.encode(json);
    
    if (bytes.length <= maxChunkSize) {
      return [MessageChunk(
        id: generateId(),
        data: bytes,
        index: 0,
        total: 1,
      )];
    }
    
    final chunks = <MessageChunk>[];
    final chunkId = generateId();
    final totalChunks = (bytes.length / maxChunkSize).ceil();
    
    for (int i = 0; i < totalChunks; i++) {
      final start = i * maxChunkSize;
      final end = min((i + 1) * maxChunkSize, bytes.length);
      
      chunks.add(MessageChunk(
        id: chunkId,
        data: bytes.sublist(start, end),
        index: i,
        total: totalChunks,
      ));
    }
    
    return chunks;
  }
  
  Future<void> sendChunkedMessage(dynamic message) async {
    final chunks = chunkMessage(message);
    
    for (final chunk in chunks) {
      await mcp.client.sendRawMessage({
        'type': 'chunk',
        'id': chunk.id,
        'data': base64Encode(chunk.data),
        'index': chunk.index,
        'total': chunk.total,
      });
      
      // Small delay between chunks
      await Future.delayed(Duration(milliseconds: 10));
    }
  }
}

// Handle large messages
try {
  await mcp.client.callTool(
    serverId: 'server',
    name: 'processData',
    arguments: {'data': largeData},
  );
} on MCPMessageTooLargeException catch (e) {
  print('Message too large, chunking...');
  await MessageChunker().sendChunkedMessage({
    'tool': 'processData',
    'arguments': {'data': largeData},
  });
}
```

### MCP-TRANS-002: Invalid Message Format

**Description**: Message format is invalid or corrupted.

**Common Causes**:
- JSON parsing error
- Missing required fields
- Type mismatch

**Solution**:
```dart
// Implement message validation
class MessageValidator {
  static const Map<String, dynamic> messageSchema = {
    'type': String,
    'id': String,
    'timestamp': int,
    'payload': Map,
  };
  
  bool validateMessage(Map<String, dynamic> message) {
    try {
      // Check required fields
      for (final entry in messageSchema.entries) {
        if (!message.containsKey(entry.key)) {
          throw MCPInvalidMessageException(
            'Missing required field: ${entry.key}',
            code: 'MCP-TRANS-002',
          );
        }
        
        // Check types
        if (message[entry.key].runtimeType != entry.value) {
          throw MCPInvalidMessageException(
            'Invalid type for ${entry.key}: expected ${entry.value}, got ${message[entry.key].runtimeType}',
            code: 'MCP-TRANS-002',
          );
        }
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  Map<String, dynamic> sanitizeMessage(Map<String, dynamic> message) {
    final sanitized = <String, dynamic>{};
    
    // Copy valid fields
    messageSchema.forEach((key, type) {
      if (message.containsKey(key) && message[key].runtimeType == type) {
        sanitized[key] = message[key];
      } else {
        // Provide default value
        sanitized[key] = _getDefaultValue(type);
      }
    });
    
    return sanitized;
  }
  
  dynamic _getDefaultValue(Type type) {
    switch (type) {
      case String:
        return '';
      case int:
        return 0;
      case Map:
        return {};
      case List:
        return [];
      default:
        return null;
    }
  }
}

// Use message validation
mcp.client.onMessage.listen((message) {
  if (!MessageValidator().validateMessage(message)) {
    // Try to sanitize and process
    final sanitized = MessageValidator().sanitizeMessage(message);
    processMessage(sanitized);
  } else {
    processMessage(message);
  }
});
```

### MCP-TRANS-003: Protocol Version Mismatch

**Description**: Client and server protocol versions don't match.

**Common Causes**:
- Client/server version mismatch
- Outdated SDK
- Incompatible protocol changes

**Solution**:
```dart
// Implement protocol negotiation
class ProtocolNegotiator {
  static const String currentVersion = '2.0';
  static const List<String> supportedVersions = ['2.0', '1.9', '1.8'];
  
  Future<String> negotiate(String serverVersion) async {
    // Exact match
    if (serverVersion == currentVersion) {
      return currentVersion;
    }
    
    // Check if server version is supported
    if (supportedVersions.contains(serverVersion)) {
      return serverVersion;
    }
    
    // Check if we support server's version
    final serverSupported = await getServerSupportedVersions();
    
    for (final version in supportedVersions) {
      if (serverSupported.contains(version)) {
        return version;
      }
    }
    
    throw MCPProtocolMismatchException(
      'No compatible protocol version found',
      code: 'MCP-TRANS-003',
      clientVersion: currentVersion,
      serverVersion: serverVersion,
    );
  }
  
  Future<List<String>> getServerSupportedVersions() async {
    final response = await http.get(
      Uri.parse('${server.url}/protocol/versions'),
    );
    
    return List<String>.from(jsonDecode(response.body));
  }
}

// Use in connection initialization
try {
  final serverInfo = await mcp.client.getServerInfo();
  final negotiatedVersion = await ProtocolNegotiator().negotiate(
    serverInfo.protocolVersion,
  );
  
  // Configure client with negotiated version
  mcp.client.configureProtocol(negotiatedVersion);
} on MCPProtocolMismatchException catch (e) {
  print('Protocol mismatch: ${e.clientVersion} vs ${e.serverVersion}');
  // Show upgrade prompt to user
}
```

### MCP-TRANS-004: Stream Interrupted

**Description**: Streaming data transfer was interrupted.

**Common Causes**:
- Network interruption
- Client disconnect
- Server error during streaming

**Solution**:
```dart
// Implement resumable streaming
class ResumableStream {
  final String streamId;
  int bytesReceived = 0;
  final List<Uint8List> chunks = [];
  
  ResumableStream(this.streamId);
  
  Future<void> startOrResume() async {
    try {
      final stream = await mcp.client.streamData(
        serverId: 'server',
        streamId: streamId,
        offset: bytesReceived,
      );
      
      await for (final chunk in stream) {
        chunks.add(chunk);
        bytesReceived += chunk.length;
        
        // Save progress periodically
        if (chunks.length % 10 == 0) {
          await saveProgress();
        }
      }
      
      // Stream completed
      await processCompleteData();
    } on MCPStreamInterruptedException catch (e) {
      print('Stream interrupted at byte $bytesReceived');
      
      // Wait and resume
      await Future.delayed(Duration(seconds: 5));
      await startOrResume();
    }
  }
  
  Future<void> saveProgress() async {
    final progress = StreamProgress(
      streamId: streamId,
      bytesReceived: bytesReceived,
      lastChunkIndex: chunks.length - 1,
    );
    
    await storage.save('stream_$streamId', progress.toJson());
  }
  
  Future<void> processCompleteData() async {
    final completeData = chunks.fold<List<int>>(
      [],
      (previous, chunk) => previous..addAll(chunk),
    );
    
    // Process complete data
    await processData(Uint8List.fromList(completeData));
    
    // Clean up saved progress
    await storage.delete('stream_$streamId');
  }
}

// Use resumable streaming
final stream = ResumableStream('data-export-123');

try {
  await stream.startOrResume();
} catch (e) {
  print('Stream failed: $e');
  // Show error to user
}
```

## System Errors (SYS)

### MCP-SYS-001: Out of Memory

**Description**: Application ran out of memory.

**Common Causes**:
- Memory leak
- Large data processing
- Too many concurrent operations

**Solution**:
```dart
// Implement memory management
class MemoryManager {
  static const int memoryLimit = 500 * 1024 * 1024; // 500MB
  int currentUsage = 0;
  final List<WeakReference<Object>> trackedObjects = [];
  
  Future<bool> canAllocate(int bytes) async {
    final available = await getAvailableMemory();
    return (currentUsage + bytes) < available * 0.8; // 80% threshold
  }
  
  Future<T> allocateManaged<T>(
    int estimatedSize,
    Future<T> Function() operation,
  ) async {
    if (!await canAllocate(estimatedSize)) {
      // Try to free memory
      await freeMemory();
      
      if (!await canAllocate(estimatedSize)) {
        throw MCPOutOfMemoryException(
          'Insufficient memory for operation',
          code: 'MCP-SYS-001',
          required: estimatedSize,
          available: await getAvailableMemory() - currentUsage,
        );
      }
    }
    
    currentUsage += estimatedSize;
    
    try {
      final result = await operation();
      
      if (result is Object) {
        trackedObjects.add(WeakReference(result));
      }
      
      return result;
    } finally {
      currentUsage -= estimatedSize;
    }
  }
  
  Future<void> freeMemory() async {
    // Remove dead references
    trackedObjects.removeWhere((ref) => ref.target == null);
    
    // Force garbage collection if supported
    if (Platform.isAndroid || Platform.isIOS) {
      await SystemChannels.platform.invokeMethod('gc');
    }
    
    // Clear caches
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
  
  Future<int> getAvailableMemory() async {
    if (Platform.isAndroid) {
      final info = await SystemChannels.platform.invokeMethod('getMemoryInfo');
      return info['availMem'];
    } else if (Platform.isIOS) {
      return ProcessInfo.processInfo.physicalMemory;
    }
    return memoryLimit;
  }
}

// Use managed allocation
try {
  final result = await MemoryManager().allocateManaged(
    50 * 1024 * 1024, // 50MB
    () async {
      return await processLargeData(data);
    },
  );
} on MCPOutOfMemoryException catch (e) {
  print('Out of memory: required ${e.required}, available ${e.available}');
  
  // Process in smaller chunks
  final chunks = splitDataIntoChunks(data, 10 * 1024 * 1024); // 10MB chunks
  for (final chunk in chunks) {
    await processLargeData(chunk);
  }
}
```

### MCP-SYS-002: Disk Space Full

**Description**: Insufficient disk space for operation.

**Common Causes**:
- Large file downloads
- Cache overflow
- Log files accumulation

**Solution**:
```dart
// Implement disk space management
class DiskSpaceManager {
  static const int minFreeSpace = 100 * 1024 * 1024; // 100MB
  
  Future<bool> hasEnoughSpace(int requiredBytes) async {
    final freeSpace = await getFreeDiskSpace();
    return freeSpace > (requiredBytes + minFreeSpace);
  }
  
  Future<int> getFreeDiskSpace() async {
    if (Platform.isAndroid) {
      final stat = await FileStat.stat('/data');
      return stat.blockSize * stat.availableBlocks;
    } else if (Platform.isIOS) {
      final home = await getApplicationDocumentsDirectory();
      final stat = await FileStat.stat(home.path);
      return stat.blockSize * stat.availableBlocks;
    } else {
      final temp = Directory.systemTemp;
      final stat = await FileStat.stat(temp.path);
      return stat.blockSize * stat.availableBlocks;
    }
  }
  
  Future<void> freeSpace(int requiredBytes) async {
    // Clean cache
    await cleanCache();
    
    // Delete old log files
    await deleteOldLogs();
    
    // Remove temporary files
    await cleanTempFiles();
    
    // Check if enough space freed
    if (!await hasEnoughSpace(requiredBytes)) {
      throw MCPDiskSpaceException(
        'Insufficient disk space',
        code: 'MCP-SYS-002',
        required: requiredBytes,
        available: await getFreeDiskSpace(),
      );
    }
  }
  
  Future<void> cleanCache() async {
    final cacheDir = await getTemporaryDirectory();
    final cacheFiles = cacheDir.listSync();
    
    // Delete files older than 7 days
    final cutoff = DateTime.now().subtract(Duration(days: 7));
    
    for (final file in cacheFiles) {
      if (file is File) {
        final stat = await file.stat();
        if (stat.modified.isBefore(cutoff)) {
          await file.delete();
        }
      }
    }
  }
  
  Future<void> deleteOldLogs() async {
    final logDir = Directory('${(await getApplicationDocumentsDirectory()).path}/logs');
    if (!await logDir.exists()) return;
    
    final logs = logDir.listSync();
    logs.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    
    // Keep only last 10 log files
    if (logs.length > 10) {
      for (int i = 0; i < logs.length - 10; i++) {
        await logs[i].delete();
      }
    }
  }
}

// Use disk space management
try {
  final fileSize = 50 * 1024 * 1024; // 50MB
  
  if (!await DiskSpaceManager().hasEnoughSpace(fileSize)) {
    await DiskSpaceManager().freeSpace(fileSize);
  }
  
  await downloadFile(url, fileSize);
} on MCPDiskSpaceException catch (e) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Storage Full'),
      content: Text('Need ${e.required ~/ 1024 ~/ 1024}MB, '
                   'only ${e.available ~/ 1024 ~/ 1024}MB available.'),
      actions: [
        TextButton(
          onPressed: () => openStorageSettings(),
          child: Text('Manage Storage'),
        ),
      ],
    ),
  );
}
```

### MCP-SYS-003: Process Crashed

**Description**: Background process crashed unexpectedly.

**Common Causes**:
- Unhandled exception
- Memory corruption
- System resource exhaustion

**Solution**:
```dart
// Implement crash recovery
class CrashRecoveryManager {
  static const String crashKey = 'last_crash';
  static const int maxCrashCount = 3;
  
  Future<void> handleCrash(dynamic error, StackTrace stackTrace) async {
    // Save crash info
    final crashInfo = CrashInfo(
      error: error.toString(),
      stackTrace: stackTrace.toString(),
      timestamp: DateTime.now(),
      version: packageInfo.version,
      platform: Platform.operatingSystem,
    );
    
    await saveCrashInfo(crashInfo);
    
    // Check crash frequency
    final recentCrashes = await getRecentCrashes();
    
    if (recentCrashes.length >= maxCrashCount) {
      // Too many crashes, enter safe mode
      await enterSafeMode();
    } else {
      // Attempt recovery
      await attemptRecovery();
    }
  }
  
  Future<void> saveCrashInfo(CrashInfo info) async {
    final crashes = await getRecentCrashes();
    crashes.add(info);
    
    // Keep only last 10 crashes
    if (crashes.length > 10) {
      crashes.removeRange(0, crashes.length - 10);
    }
    
    await storage.save(crashKey, crashes.map((c) => c.toJson()).toList());
  }
  
  Future<List<CrashInfo>> getRecentCrashes() async {
    final data = await storage.load(crashKey);
    if (data == null) return [];
    
    return (data as List)
        .map((json) => CrashInfo.fromJson(json))
        .toList();
  }
  
  Future<void> attemptRecovery() async {
    // Clear temporary data
    await clearTempData();
    
    // Reset to default configuration
    await resetConfiguration();
    
    // Restart services
    await restartServices();
  }
  
  Future<void> enterSafeMode() async {
    await storage.save('safe_mode', true);
    
    // Start with minimal configuration
    final safeConfig = McpConfig(
      servers: [
        ServerConfig(
          id: 'default',
          url: 'ws://localhost:8080',
          reconnectDelay: Duration(seconds: 10),
          maxReconnectAttempts: 1,
        ),
      ],
      debugOptions: DebugOptions(
        logLevel: LogLevel.verbose,
        saveLogsToFile: true,
      ),
    );
    
    await mcp.initialize(config: safeConfig);
  }
  
  Future<void> reportCrash(CrashInfo info) async {
    if (!await shouldReportCrash()) return;
    
    try {
      await http.post(
        Uri.parse('https://crashes.example.com/report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'app_version': info.version,
          'platform': info.platform,
          'error': info.error,
          'stack_trace': info.stackTrace,
          'timestamp': info.timestamp.toIso8601String(),
        }),
      );
    } catch (e) {
      // Fail silently
    }
  }
  
  Future<bool> shouldReportCrash() async {
    // Check user preference
    return await preferences.getBool('crash_reporting') ?? false;
  }
}

// Set up crash handling
void main() {
  FlutterError.onError = (details) async {
    await CrashRecoveryManager().handleCrash(
      details.exception,
      details.stack ?? StackTrace.empty,
    );
  };
  
  runZonedGuarded(() {
    runApp(MyApp());
  }, (error, stack) async {
    await CrashRecoveryManager().handleCrash(error, stack);
  });
}
```

### MCP-SYS-004: Permission Denied

**Description**: System permission denied for requested operation.

**Common Causes**:
- Missing permissions in manifest
- User denied permission
- Platform restrictions

**Solution**:
```dart
// Implement permission handling
class PermissionManager {
  static const Map<String, List<Permission>> operationPermissions = {
    'camera': [Permission.camera],
    'location': [Permission.location, Permission.locationAlways],
    'storage': [Permission.storage],
    'microphone': [Permission.microphone],
    'contacts': [Permission.contacts],
    'bluetooth': [Permission.bluetooth, Permission.bluetoothScan],
  };
  
  Future<bool> checkPermission(String operation) async {
    final permissions = operationPermissions[operation];
    if (permissions == null) return true;
    
    for (final permission in permissions) {
      final status = await permission.status;
      if (!status.isGranted) {
        return false;
      }
    }
    
    return true;
  }
  
  Future<PermissionResult> requestPermission(String operation) async {
    final permissions = operationPermissions[operation];
    if (permissions == null) {
      return PermissionResult(granted: true);
    }
    
    final statuses = <Permission, PermissionStatus>{};
    
    for (final permission in permissions) {
      final status = await permission.request();
      statuses[permission] = status;
    }
    
    final allGranted = statuses.values.every((s) => s.isGranted);
    final permanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
    
    return PermissionResult(
      granted: allGranted,
      permanentlyDenied: permanentlyDenied,
      statuses: statuses,
    );
  }
  
  Future<void> handlePermissionError(
    String operation,
    BuildContext context,
  ) async {
    final result = await requestPermission(operation);
    
    if (result.granted) {
      // Permission granted, retry operation
      return;
    }
    
    if (result.permanentlyDenied) {
      // Show dialog to open settings
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Permission Required'),
          content: Text('Please enable $operation permission in settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
              child: Text('Open Settings'),
            ),
          ],
        ),
      );
    } else {
      // Permission denied
      throw MCPPermissionDeniedException(
        'Permission denied for $operation',
        code: 'MCP-SYS-004',
        operation: operation,
      );
    }
  }
}

// Use permission manager
try {
  if (!await PermissionManager().checkPermission('camera')) {
    await PermissionManager().handlePermissionError('camera', context);
  }
  
  await capturePhoto();
} on MCPPermissionDeniedException catch (e) {
  print('Permission denied: ${e.operation}');
  // Handle permission denial
}
```

## Error Recovery Strategies

### Automatic Retry

```dart
class ErrorRecovery {
  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffMultiplier = 2.0,
    bool Function(dynamic)? retryWhen,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;
    
    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        
        // Check if we should retry this error
        if (retryWhen != null && !retryWhen(e)) {
          rethrow;
        }
        
        // Check specific error codes
        if (e is MCPException) {
          if (!_isRetryableError(e.code)) {
            rethrow;
          }
        }
        
        if (attempt >= maxRetries) {
          rethrow;
        }
        
        await Future.delayed(delay);
        delay = delay * backoffMultiplier;
      }
    }
    
    throw StateError('Should not reach here');
  }
  
  static bool _isRetryableError(String code) {
    const retryableErrors = [
      'MCP-CONN-001', // Connection timeout
      'MCP-CONN-002', // Connection refused
      'MCP-TOOL-003', // Tool execution failed
      'MCP-TOOL-004', // Tool timeout
      'MCP-TRANS-004', // Stream interrupted
    ];
    
    return retryableErrors.contains(code);
  }
}
```

### Fallback Mechanisms

```dart
class FallbackHandler {
  final List<McpConfig> fallbackConfigs;
  int currentConfigIndex = 0;
  
  FallbackHandler(this.fallbackConfigs);
  
  Future<T> executeWithFallback<T>(
    Future<T> Function(McpConfig) operation,
  ) async {
    while (currentConfigIndex < fallbackConfigs.length) {
      final config = fallbackConfigs[currentConfigIndex];
      
      try {
        return await operation(config);
      } catch (e) {
        print('Failed with config $currentConfigIndex: $e');
        currentConfigIndex++;
        
        if (currentConfigIndex >= fallbackConfigs.length) {
          throw MCPAllFallbacksFailedException(
            'All fallback configurations failed',
            lastError: e,
          );
        }
      }
    }
    
    throw StateError('Should not reach here');
  }
}

// Use fallbacks
final fallbackHandler = FallbackHandler([
  McpConfig(servers: [ServerConfig(id: 'primary', url: 'ws://primary.example.com')]),
  McpConfig(servers: [ServerConfig(id: 'secondary', url: 'ws://secondary.example.com')]),
  McpConfig(servers: [ServerConfig(id: 'fallback', url: 'ws://fallback.example.com')]),
]);

try {
  final result = await fallbackHandler.executeWithFallback((config) async {
    final mcp = FlutterMCP();
    await mcp.initialize(config: config);
    return await mcp.client.callTool(...);
  });
} on MCPAllFallbacksFailedException catch (e) {
  // All fallbacks failed
  showErrorDialog('Service unavailable');
}
```

### Error Aggregation

```dart
class ErrorAggregator {
  final Map<String, ErrorStats> _errorStats = {};
  final Duration aggregationWindow;
  
  ErrorAggregator({
    this.aggregationWindow = const Duration(minutes: 5),
  });
  
  void recordError(MCPException error) {
    final stats = _errorStats.putIfAbsent(
      error.code,
      () => ErrorStats(code: error.code),
    );
    
    stats.occurrences.add(ErrorOccurrence(
      timestamp: DateTime.now(),
      message: error.message,
      stackTrace: error.stackTrace,
    ));
    
    // Clean old occurrences
    final cutoff = DateTime.now().subtract(aggregationWindow);
    stats.occurrences.removeWhere((o) => o.timestamp.isBefore(cutoff));
  }
  
  List<ErrorSummary> getSummary() {
    return _errorStats.values.map((stats) {
      final recentOccurrences = stats.occurrences
          .where((o) => o.timestamp.isAfter(
              DateTime.now().subtract(aggregationWindow)))
          .toList();
      
      return ErrorSummary(
        code: stats.code,
        count: recentOccurrences.length,
        rate: recentOccurrences.length / aggregationWindow.inMinutes,
        firstOccurrence: recentOccurrences.first.timestamp,
        lastOccurrence: recentOccurrences.last.timestamp,
      );
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }
  
  void checkErrorPatterns() {
    final summary = getSummary();
    
    // Check for error spikes
    for (final error in summary) {
      if (error.rate > 10) { // More than 10 errors per minute
        // Trigger alert
        notifyErrorSpike(error);
      }
    }
    
    // Check for cascading failures
    final totalErrors = summary.fold(0, (sum, e) => sum + e.count);
    if (totalErrors > 50) { // More than 50 errors in 5 minutes
      // Enter degraded mode
      enterDegradedMode();
    }
  }
}
```

## Best Practices

### 1. Error Context

Always provide context with errors:

```dart
class ContextualError extends MCPException {
  final Map<String, dynamic> context;
  
  ContextualError({
    required String message,
    required String code,
    this.context = const {},
  }) : super(message: message, code: code);
  
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln(super.toString());
    
    if (context.isNotEmpty) {
      buffer.writeln('Context:');
      context.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
    }
    
    return buffer.toString();
  }
}

// Use contextual errors
throw ContextualError(
  message: 'Failed to process data',
  code: 'MCP-TOOL-003',
  context: {
    'tool': 'dataProcessor',
    'input_size': data.length,
    'timestamp': DateTime.now().toIso8601String(),
    'server': serverId,
  },
);
```

### 2. Error Boundaries

Implement error boundaries to prevent cascading failures:

```dart
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, StackTrace? stack)? errorBuilder;
  final Function(Object error, StackTrace? stack)? onError;
  
  const ErrorBoundary({
    Key? key,
    required this.child,
    this.errorBuilder,
    this.onError,
  }) : super(key: key);
  
  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;
  
  @override
  void initState() {
    super.initState();
    
    FlutterError.onError = (details) {
      setState(() {
        _error = details.exception;
        _stackTrace = details.stack;
      });
      
      widget.onError?.call(details.exception, details.stack);
    };
  }
  
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(_error!, _stackTrace) ??
             ErrorWidget(_error!);
    }
    
    return widget.child;
  }
}

// Use error boundaries
ErrorBoundary(
  child: MyRiskyWidget(),
  errorBuilder: (error, stack) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error, size: 48, color: Colors.red),
          Text('Something went wrong'),
          TextButton(
            onPressed: () => setState(() {
              _error = null;
              _stackTrace = null;
            }),
            child: Text('Retry'),
          ),
        ],
      ),
    );
  },
  onError: (error, stack) {
    // Log error
    MCPLogger().logError('Widget error', error: error, stackTrace: stack);
  },
)
```

### 3. User-Friendly Messages

Convert technical errors to user-friendly messages:

```dart
class ErrorMessageMapper {
  static const Map<String, String> errorMessages = {
    'MCP-CONN-001': 'Unable to connect to the server. Please check your internet connection.',
    'MCP-CONN-002': 'The server is not responding. Please try again later.',
    'MCP-AUTH-001': 'Invalid login credentials. Please check your username and password.',
    'MCP-AUTH-003': 'Your session has expired. Please log in again.',
    'MCP-TOOL-004': 'The operation is taking longer than expected. Please try again.',
    'MCP-RES-003': 'You have reached your usage limit. Please upgrade your plan.',
    'MCP-SYS-001': 'The app is running low on memory. Please close other apps.',
    'MCP-SYS-002': 'Not enough storage space. Please free up some space.',
  };
  
  static String getUserMessage(MCPException error) {
    // Check for specific error code
    if (errorMessages.containsKey(error.code)) {
      return errorMessages[error.code]!;
    }
    
    // Fallback to category-based messages
    final category = error.code.split('-')[1];
    switch (category) {
      case 'CONN':
        return 'Connection issue. Please check your network.';
      case 'AUTH':
        return 'Authentication problem. Please log in again.';
      case 'TOOL':
        return 'Operation failed. Please try again.';
      case 'RES':
        return 'Resource unavailable. Please contact support.';
      case 'SYS':
        return 'System error. Please restart the app.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
  
  static Widget buildErrorWidget(MCPException error) {
    final userMessage = getUserMessage(error);
    
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            SizedBox(height: 16),
            Text(
              userMessage,
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (FlutterMCP.debugMode) ...[
              SizedBox(height: 8),
              Text(
                'Error code: ${error.code}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

## See Also

- [Common Issues](/doc/troubleshooting/common-issues.md)
- [Debug Mode](/doc/troubleshooting/debug-mode.md)
- [Performance Tuning](/doc/troubleshooting/performance.md)
- [Testing Guide](/doc/advanced/testing.md)