# Best Practices

Follow these best practices to get the most out of Flutter MCP.

## General Guidelines

### 1. Resource Management

```dart
// Always dispose of resources properly
@override
void dispose() {
  client?.disconnect();
  mcp.dispose();
  super.dispose();
}
```

### 2. Error Handling

```dart
try {
  await client.connect();
} catch (e) {
  if (e is MCPConnectionException) {
    // Handle connection errors
  } else if (e is MCPTimeoutException) {
    // Handle timeout
  } else {
    // Handle other errors
  }
}
```

### 3. Configuration Management

```dart
// Use environment-specific configurations
final config = await MCPConfig.fromFile(
  kDebugMode 
    ? 'assets/config.debug.json' 
    : 'assets/config.production.json'
);
```

## Performance Optimization

### 1. Connection Pooling

```dart
// Reuse client connections
class ClientPool {
  final Map<String, MCPClient> _clients = {};
  
  MCPClient getClient(String serverId) {
    return _clients.putIfAbsent(
      serverId, 
      () => createClient(serverId)
    );
  }
}
```

### 2. Caching

```dart
// Enable semantic caching for LLM responses
await mcp.llmManager.enableCache(
  maxSize: 100, // MB
  ttl: Duration(hours: 24),
);
```

### 3. Batch Operations

```dart
// Batch multiple operations
final futures = ids.map((id) => client.send(
  method: 'process',
  params: {'id': id},
));
await Future.wait(futures);
```

## Security

### 1. API Key Management

```dart
// Never hardcode API keys
final apiKey = await SecureStorage.read('openai_api_key');

// Use environment variables
final apiKey = Platform.environment['OPENAI_API_KEY'];
```

### 2. Secure Communication

```dart
// Use secure transports
final transport = SecureWebSocketTransport(
  url: 'wss://server.example.com',
  certificatePinning: true,
);
```

### 3. Data Validation

```dart
// Always validate input data
void processData(Map<String, dynamic> data) {
  if (!data.containsKey('required_field')) {
    throw ArgumentError('Missing required field');
  }
  // Process data
}
```

## Error Recovery

### 1. Circuit Breaker Pattern

```dart
final breaker = CircuitBreaker(
  failureThreshold: 5,
  recoveryTimeout: Duration(minutes: 1),
);

await breaker.execute(() => client.connect());
```

### 2. Retry Logic

```dart
await ErrorRecovery.withRetry(
  () => client.send(request),
  maxRetries: 3,
  backoff: ExponentialBackoff(),
);
```

### 3. Graceful Degradation

```dart
try {
  response = await llm.query(prompt);
} catch (e) {
  // Fall back to cached response
  response = await cache.get(prompt);
}
```

## Testing

### 1. Unit Testing

```dart
test('Client connects successfully', () async {
  final mock = MockServerTransport();
  final client = MCPClient(transport: mock);
  
  when(mock.connect()).thenAnswer((_) async => true);
  
  await client.connect();
  expect(client.isConnected, true);
});
```

### 2. Integration Testing

```dart
testWidgets('Chat interface works', (tester) async {
  await tester.pumpWidget(MyApp());
  
  // Enter message
  await tester.enterText(find.byType(TextField), 'Hello');
  await tester.tap(find.byIcon(Icons.send));
  
  // Verify response
  await tester.pumpAndSettle();
  expect(find.text('Response'), findsOneWidget);
});
```

### 3. Performance Testing

```dart
// Monitor performance in production
PerformanceMonitor.instance.startTimer('operation');
// ... operation ...
PerformanceMonitor.instance.stopTimer('operation');
```

## Architecture Patterns

### 1. Separation of Concerns

```dart
// Separate UI from business logic
class ChatViewModel extends ChangeNotifier {
  final MCPClient _client;
  
  ChatViewModel(this._client);
  
  Future<void> sendMessage(String message) async {
    // Business logic here
    notifyListeners();
  }
}
```

### 2. Dependency Injection

```dart
// Use DI for better testability
void main() {
  DependencyInjection.register<MCPClient>(
    MockClient(), // or RealClient()
  );
  
  runApp(MyApp());
}
```

### 3. Event-Driven Architecture

```dart
// Use events for loose coupling
EventSystem.instance.on<MessageReceived>()
  .listen((event) {
    // Handle message
  });
```

## Platform Considerations

### 1. Background Execution

```dart
// Handle platform differences
if (Platform.isIOS) {
  // iOS has 30s execution limit
  await timeoutTask(Duration(seconds: 25));
} else {
  // Android/Desktop can run longer
  await longRunningTask();
}
```

### 2. Memory Management

```dart
// Monitor memory usage
MemoryManager.instance.onHighMemory(() {
  // Clear caches
  cache.clear();
  // Reduce pool sizes
  objectPool.resize(10);
});
```

### 3. UI Responsiveness

```dart
// Use isolates for heavy computation
final result = await Isolate.run(() {
  return heavyComputation(data);
});
```

## Monitoring and Logging

### 1. Structured Logging

```dart
MCPLogger.instance.info('Operation completed', {
  'duration': stopwatch.elapsed,
  'userId': userId,
  'operation': 'send_message',
});
```

### 2. Metrics Collection

```dart
// Track key metrics
PerformanceMonitor.instance.incrementCounter('messages.sent');
PerformanceMonitor.instance.recordGauge('memory.usage', usage);
```

### 3. Error Tracking

```dart
// Report errors with context
try {
  await operation();
} catch (e, stack) {
  ErrorReporter.report(e, stack, {
    'user': currentUser,
    'action': 'operation',
  });
}
```

## Next Steps

- [Performance Tuning](../advanced/performance-tuning.md)
- [Security Guide](../advanced/security.md)
- [Testing Guide](../advanced/testing.md)