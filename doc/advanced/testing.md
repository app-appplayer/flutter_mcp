# Testing Guide

Comprehensive guide for testing Flutter MCP applications.

## Test Setup

### Test Dependencies

```yaml
# pubspec.yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.0
  build_runner: ^2.3.0
  flutter_mcp_test: ^0.1.0
  integration_test:
    sdk: flutter
```

### Test Configuration

```dart
// test/test_config.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp_test/flutter_mcp_test.dart';

void setupTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Configure test environment
  MCPTestEnvironment.configure(
    mockServers: true,
    mockClients: true,
    stubResponses: true,
    enableLogging: true,
  );
  
  // Set test timeouts
  setUpAll(() {
    MCPTestConfig.defaultTimeout = Duration(seconds: 10);
    MCPTestConfig.connectionTimeout = Duration(seconds: 5);
  });
  
  // Clean up after tests
  tearDownAll(() {
    MCPTestEnvironment.cleanup();
  });
}
```

## Unit Testing

### Testing Core Components

```dart
// test/unit/server_manager_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class MockServer extends Mock implements MCPServer {}
class MockTransport extends Mock implements MCPTransport {}

void main() {
  group('ServerManager', () {
    late ServerManager serverManager;
    late MockTransport mockTransport;
    
    setUp(() {
      mockTransport = MockTransport();
      serverManager = ServerManager(transport: mockTransport);
    });
    
    test('creates server with correct config', () async {
      final config = ServerConfig(
        name: 'test-server',
        uri: 'ws://localhost:3000',
      );
      
      when(mockTransport.connect(any)).thenAnswer((_) async => MockServer());
      
      final server = await serverManager.createServer(config);
      
      expect(server, isA<MCPServer>());
      verify(mockTransport.connect(config.uri)).called(1);
    });
    
    test('handles connection failures', () async {
      final config = ServerConfig(
        name: 'test-server',
        uri: 'ws://localhost:3000',
      );
      
      when(mockTransport.connect(any))
          .thenThrow(ConnectionException('Failed to connect'));
      
      expect(
        () => serverManager.createServer(config),
        throwsA(isA<ConnectionException>()),
      );
    });
    
    test('caches server instances', () async {
      final config = ServerConfig(
        name: 'test-server',
        uri: 'ws://localhost:3000',
      );
      
      when(mockTransport.connect(any)).thenAnswer((_) async => MockServer());
      
      final server1 = await serverManager.createServer(config);
      final server2 = await serverManager.getServer('test-server');
      
      expect(server2, same(server1));
    });
  });
}
```

### Testing Plugins

```dart
// test/unit/plugin_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class TestPlugin extends MCPToolPlugin {
  bool initialized = false;
  
  @override
  String get name => 'test-plugin';
  
  @override
  List<Tool> get tools => [
    Tool(
      name: 'test-tool',
      description: 'Test tool',
      schema: {},
      handler: _handleTestTool,
    ),
  ];
  
  @override
  Future<void> onInitialize() async {
    initialized = true;
  }
  
  Future<dynamic> _handleTestTool(Map<String, dynamic> params) async {
    return {'result': 'success'};
  }
}

void main() {
  group('Plugin System', () {
    late PluginSystem pluginSystem;
    late TestPlugin testPlugin;
    
    setUp(() {
      pluginSystem = PluginSystem();
      testPlugin = TestPlugin();
    });
    
    test('registers plugin', () async {
      await pluginSystem.register(testPlugin);
      
      final registered = pluginSystem.getPlugin('test-plugin');
      expect(registered, same(testPlugin));
    });
    
    test('initializes plugin', () async {
      await pluginSystem.register(testPlugin);
      await pluginSystem.initialize();
      
      expect(testPlugin.initialized, isTrue);
    });
    
    test('handles tool execution', () async {
      await pluginSystem.register(testPlugin);
      await pluginSystem.initialize();
      
      final result = await pluginSystem.executeTool(
        'test-plugin',
        'test-tool',
        {},
      );
      
      expect(result, equals({'result': 'success'}));
    });
  });
}
```

### Mocking MCP Components

```dart
// test/mocks/mcp_mocks.dart
import 'package:mockito/annotations.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

@GenerateMocks([
  MCPServer,
  MCPClient,
  ServerManager,
  ClientManager,
  LLMManager,
  BackgroundService,
])
void main() {}

// Usage in tests
import 'mcp_mocks.mocks.dart';

void main() {
  test('mocked server test', () async {
    final mockServer = MockMCPServer();
    
    when(mockServer.execute(any, any))
        .thenAnswer((_) async => {'result': 'mocked'});
    
    final result = await mockServer.execute('test', {});
    expect(result, equals({'result': 'mocked'}));
  });
}
```

## Integration Testing

### Testing Server Communication

```dart
// integration_test/server_communication_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Server Communication', () {
    late MCPServer testServer;
    
    setUpAll(() async {
      // Use test server instance
      testServer = await MCPTestServer.start(
        port: 3001,
        handlers: {
          'echo': (params) => params,
          'error': (params) => throw MCPException('Test error'),
        },
      );
    });
    
    tearDownAll(() async {
      await testServer.stop();
    });
    
    testWidgets('connects to server', (tester) async {
      final config = MCPConfig(
        servers: {
          'test': ServerConfig(
            uri: 'ws://localhost:3001',
          ),
        },
      );
      
      await FlutterMCP.initialize(config);
      final server = await FlutterMCP.connect('test');
      
      expect(server.isConnected, isTrue);
    });
    
    testWidgets('executes remote methods', (tester) async {
      final server = await FlutterMCP.connect('test');
      
      final result = await server.execute('echo', {'message': 'hello'});
      expect(result, equals({'message': 'hello'}));
    });
    
    testWidgets('handles server errors', (tester) async {
      final server = await FlutterMCP.connect('test');
      
      expect(
        () => server.execute('error', {}),
        throwsA(isA<MCPException>()),
      );
    });
  });
}
```

### Testing Background Services

```dart
// integration_test/background_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Background Service', () {
    late BackgroundService backgroundService;
    
    setUp(() async {
      backgroundService = await FlutterMCP.backgroundService;
    });
    
    testWidgets('schedules background job', (tester) async {
      final jobCompleter = Completer<bool>();
      
      await backgroundService.scheduleJob(
        id: 'test-job',
        callback: () async {
          jobCompleter.complete(true);
          return true;
        },
        interval: Duration(seconds: 1),
      );
      
      final result = await jobCompleter.future
          .timeout(Duration(seconds: 5));
      
      expect(result, isTrue);
      
      await backgroundService.cancelJob('test-job');
    });
    
    testWidgets('handles job failures', (tester) async {
      final errorCompleter = Completer<String>();
      
      await backgroundService.scheduleJob(
        id: 'failing-job',
        callback: () async {
          throw Exception('Job failed');
        },
        interval: Duration(seconds: 1),
        onError: (error) {
          errorCompleter.complete(error.toString());
        },
      );
      
      final error = await errorCompleter.future
          .timeout(Duration(seconds: 5));
      
      expect(error, contains('Job failed'));
      
      await backgroundService.cancelJob('failing-job');
    });
  });
}
```

## Widget Testing

### Testing MCP-Integrated Widgets

```dart
// test/widget/mcp_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class MCPDataWidget extends StatefulWidget {
  final String serverName;
  final String method;
  
  const MCPDataWidget({
    Key? key,
    required this.serverName,
    required this.method,
  }) : super(key: key);
  
  @override
  _MCPDataWidgetState createState() => _MCPDataWidgetState();
}

class _MCPDataWidgetState extends State<MCPDataWidget> {
  bool _loading = true;
  String? _data;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    try {
      final server = await FlutterMCP.connect(widget.serverName);
      final result = await server.execute(widget.method, {});
      
      setState(() {
        _data = result.toString();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return CircularProgressIndicator();
    }
    
    if (_error != null) {
      return Text('Error: $_error');
    }
    
    return Text('Data: $_data');
  }
}

void main() {
  group('MCPDataWidget', () {
    setUpAll(() {
      MCPTestEnvironment.mockServer('test-server', {
        'getData': {'value': 'test data'},
      });
    });
    
    testWidgets('shows loading state', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MCPDataWidget(
          serverName: 'test-server',
          method: 'getData',
        ),
      ));
      
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
    
    testWidgets('displays data', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MCPDataWidget(
          serverName: 'test-server',
          method: 'getData',
        ),
      ));
      
      await tester.pumpAndSettle();
      
      expect(find.text("Data: {value: test data}"), findsOneWidget);
    });
    
    testWidgets('handles errors', (tester) async {
      MCPTestEnvironment.mockServerError(
        'test-server',
        'getData',
        MCPException('Test error'),
      );
      
      await tester.pumpWidget(MaterialApp(
        home: MCPDataWidget(
          serverName: 'test-server',
          method: 'getData',
        ),
      ));
      
      await tester.pumpAndSettle();
      
      expect(find.textContaining('Error:'), findsOneWidget);
    });
  });
}
```

### Testing State Management

```dart
// test/widget/state_management_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class MCPState extends ChangeNotifier {
  final ServerManager _serverManager;
  Map<String, dynamic>? _data;
  bool _loading = false;
  
  MCPState(this._serverManager);
  
  Map<String, dynamic>? get data => _data;
  bool get loading => _loading;
  
  Future<void> fetchData(String serverName, String method) async {
    _loading = true;
    notifyListeners();
    
    try {
      final server = await _serverManager.connect(serverName);
      _data = await server.execute(method, {});
    } catch (e) {
      _data = {'error': e.toString()};
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

void main() {
  group('MCPState', () {
    late MockServerManager mockServerManager;
    late MCPState mcpState;
    
    setUp(() {
      mockServerManager = MockServerManager();
      mcpState = MCPState(mockServerManager);
    });
    
    testWidgets('updates loading state', (tester) async {
      final mockServer = MockMCPServer();
      when(mockServerManager.connect(any))
          .thenAnswer((_) async => mockServer);
      when(mockServer.execute(any, any))
          .thenAnswer((_) async {
            await Future.delayed(Duration(milliseconds: 100));
            return {'result': 'data'};
          });
      
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: mcpState,
          child: MaterialApp(
            home: Consumer<MCPState>(
              builder: (context, state, _) {
                return Text(state.loading ? 'Loading' : 'Done');
              },
            ),
          ),
        ),
      );
      
      expect(find.text('Done'), findsOneWidget);
      
      final future = mcpState.fetchData('test', 'method');
      await tester.pump();
      
      expect(find.text('Loading'), findsOneWidget);
      
      await future;
      await tester.pump();
      
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
```

## Performance Testing

### Load Testing

```dart
// test/performance/load_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

void main() {
  group('Load Testing', () {
    test('handles concurrent connections', () async {
      final stopwatch = Stopwatch()..start();
      
      // Create multiple concurrent connections
      final futures = List.generate(100, (i) async {
        final server = await FlutterMCP.connect('test-server-$i');
        await server.execute('ping', {});
        await server.disconnect();
      });
      
      await Future.wait(futures);
      
      stopwatch.stop();
      
      print('100 connections completed in ${stopwatch.elapsed}');
      expect(stopwatch.elapsed.inSeconds, lessThan(10));
    });
    
    test('handles high-frequency requests', () async {
      final server = await FlutterMCP.connect('test-server');
      final stopwatch = Stopwatch()..start();
      
      // Send 1000 requests
      for (int i = 0; i < 1000; i++) {
        await server.execute('echo', {'index': i});
      }
      
      stopwatch.stop();
      
      final requestsPerSecond = 1000 / stopwatch.elapsed.inSeconds;
      print('Processed $requestsPerSecond requests/second');
      
      expect(requestsPerSecond, greaterThan(100));
    });
  });
}
```

### Memory Testing

```dart
// test/performance/memory_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

void main() {
  group('Memory Testing', () {
    test('cleans up resources', () async {
      final initialMemory = await _getMemoryUsage();
      
      // Create and destroy many connections
      for (int i = 0; i < 100; i++) {
        final server = await FlutterMCP.connect('test-server');
        await server.execute('echo', {'data': 'x' * 1000});
        await server.disconnect();
      }
      
      // Force garbage collection
      await Future.delayed(Duration(seconds: 1));
      
      final finalMemory = await _getMemoryUsage();
      final increase = finalMemory - initialMemory;
      
      print('Memory increase: ${increase ~/ 1024}KB');
      expect(increase, lessThan(10 * 1024 * 1024)); // Less than 10MB
    });
    
    test('handles large payloads', () async {
      final server = await FlutterMCP.connect('test-server');
      
      // Test with 1MB payload
      final largeData = 'x' * 1024 * 1024;
      final result = await server.execute('echo', {'data': largeData});
      
      expect(result['data'], equals(largeData));
    });
  });
  
  Future<int> _getMemoryUsage() async {
    // Platform-specific memory measurement
    // This is a simplified example
    return ProcessInfo.currentRss;
  }
}
```

## Test Utilities

### Test Helpers

```dart
// test/utils/test_helpers.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class MCPTestHelpers {
  static Future<MCPServer> createMockServer({
    required String name,
    Map<String, dynamic Function(Map<String, dynamic>)>? handlers,
  }) async {
    final server = MockMCPServer();
    
    // Setup default handlers
    handlers?.forEach((method, handler) {
      when(server.execute(method, any)).thenAnswer((invocation) async {
        final params = invocation.positionalArguments[1] as Map<String, dynamic>;
        return handler(params);
      });
    });
    
    // Setup connection behavior
    when(server.isConnected).thenReturn(true);
    when(server.name).thenReturn(name);
    
    return server;
  }
  
  static Future<void> withMockedMCP(
    Future<void> Function() testBody, {
    Map<String, MCPServer>? servers,
  }) async {
    // Save original state
    final originalState = FlutterMCP.instance;
    
    try {
      // Setup mocked environment
      MCPTestEnvironment.setup(servers: servers);
      
      // Run test
      await testBody();
    } finally {
      // Restore original state
      MCPTestEnvironment.restore(originalState);
    }
  }
  
  static void expectMCPException(
    dynamic actual,
    MCPErrorCode code, {
    String? messageContains,
  }) {
    expect(actual, isA<MCPException>());
    final exception = actual as MCPException;
    expect(exception.code, equals(code.code));
    if (messageContains != null) {
      expect(exception.message, contains(messageContains));
    }
  }
}
```

### Custom Matchers

```dart
// test/utils/matchers.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class IsMCPException extends Matcher {
  final MCPErrorCode? code;
  final String? messagePattern;
  
  IsMCPException({this.code, this.messagePattern});
  
  @override
  bool matches(item, Map matchState) {
    if (item is! MCPException) return false;
    
    if (code != null && item.code != code!.code) return false;
    
    if (messagePattern != null && 
        !RegExp(messagePattern!).hasMatch(item.message)) return false;
    
    return true;
  }
  
  @override
  Description describe(Description description) {
    description.add('MCPException');
    if (code != null) {
      description.add(' with code ${code!.code}');
    }
    if (messagePattern != null) {
      description.add(' with message matching "$messagePattern"');
    }
    return description;
  }
}

// Usage
Matcher isMCPException({MCPErrorCode? code, String? messagePattern}) {
  return IsMCPException(code: code, messagePattern: messagePattern);
}

// Example usage in tests
void main() {
  test('custom matcher example', () {
    expect(
      () => throw MCPException(
        message: 'Connection failed',
        code: MCPErrorCode.connectionFailed.code,
      ),
      throwsA(isMCPException(
        code: MCPErrorCode.connectionFailed,
        messagePattern: 'Connection.*',
      )),
    );
  });
}
```

## Test Data Fixtures

### Mock Data Generation

```dart
// test/fixtures/test_data.dart
class TestData {
  static Map<String, dynamic> serverConfig({
    String? name,
    String? uri,
    Map<String, dynamic>? auth,
  }) {
    return {
      'name': name ?? 'test-server',
      'uri': uri ?? 'ws://localhost:3000',
      'auth': auth ?? {'type': 'none'},
    };
  }
  
  static Map<String, dynamic> clientRequest({
    String? method,
    Map<String, dynamic>? params,
    String? id,
  }) {
    return {
      'jsonrpc': '2.0',
      'method': method ?? 'test-method',
      'params': params ?? {},
      'id': id ?? DateTime.now().millisecondsSinceEpoch.toString(),
    };
  }
  
  static Map<String, dynamic> serverResponse({
    dynamic result,
    String? id,
    Map<String, dynamic>? error,
  }) {
    final response = {
      'jsonrpc': '2.0',
      'id': id ?? '12345',
    };
    
    if (error != null) {
      response['error'] = error;
    } else {
      response['result'] = result ?? {'status': 'ok'};
    }
    
    return response;
  }
  
  static List<Map<String, dynamic>> batchRequest(int count) {
    return List.generate(count, (i) => clientRequest(
      method: 'method-$i',
      params: {'index': i},
      id: 'batch-$i',
    ));
  }
}
```

### Test Scenarios

```dart
// test/fixtures/scenarios.dart
class TestScenarios {
  static Future<void> connectionFailure(MCPServer server) async {
    // Simulate connection failure
    await server.disconnect();
    
    try {
      await server.execute('test', {});
      throw TestFailure('Should have thrown ConnectionException');
    } on ConnectionException {
      // Expected
    }
  }
  
  static Future<void> authenticationFlow(MCPServer server) async {
    // Test authentication
    final authResult = await server.authenticate({
      'username': 'test-user',
      'password': 'test-pass',
    });
    
    expect(authResult['token'], isNotNull);
    
    // Test authenticated request
    final result = await server.execute('protected-method', {
      'token': authResult['token'],
    });
    
    expect(result['status'], equals('authorized'));
  }
  
  static Future<void> errorRecovery(MCPServer server) async {
    // Simulate temporary error
    int attempts = 0;
    
    final result = await RetryHandler.withRetry(
      operation: () async {
        attempts++;
        if (attempts < 3) {
          throw MCPException('Temporary error');
        }
        return await server.execute('test', {});
      },
      maxAttempts: 3,
    );
    
    expect(attempts, equals(3));
    expect(result, isNotNull);
  }
}
```

## CI/CD Integration

### GitHub Actions Configuration

```yaml
# .github/workflows/test.yml
name: Test

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        flutter-version: ['3.3.x', '3.7.x', 'stable']
    
    steps:
    - uses: actions/checkout@v3
    
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: ${{ matrix.flutter-version }}
    
    - name: Install dependencies
      run: flutter pub get
    
    - name: Run tests
      run: flutter test --coverage
    
    - name: Upload coverage
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage/lcov.info
    
    - name: Run integration tests
      run: flutter test integration_test
```

### Test Coverage

```dart
// test/coverage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:coverage/coverage.dart';

void main() {
  test('check coverage', () async {
    final coverage = await collect(
      Uri.parse('http://localhost:8181'),
      true,
      false,
      false,
      {},
    );
    
    final report = await HitMap.parseJson(coverage);
    final formatter = LcovFormatter();
    final lcov = await formatter.format(report);
    
    // Check coverage thresholds
    final coveragePercent = _calculateCoverage(lcov);
    expect(coveragePercent, greaterThan(80.0));
  });
  
  double _calculateCoverage(String lcov) {
    // Parse LCOV and calculate coverage percentage
    // Implementation details omitted
    return 85.0;
  }
}
```

## Best Practices

### Test Organization

1. **Structure**: Organize tests by feature
2. **Naming**: Use descriptive test names
3. **Independence**: Tests should not depend on each other
4. **Isolation**: Mock external dependencies
5. **Coverage**: Aim for 80%+ code coverage
6. **Speed**: Keep tests fast
7. **Determinism**: Avoid flaky tests
8. **Documentation**: Document test scenarios

### Test Patterns

```dart
// Good test structure
void main() {
  group('Feature Name', () {
    late MockDependency mockDependency;
    late FeatureUnderTest feature;
    
    setUp(() {
      mockDependency = MockDependency();
      feature = FeatureUnderTest(mockDependency);
    });
    
    tearDown(() {
      // Cleanup
    });
    
    group('specific functionality', () {
      test('should do expected behavior', () {
        // Arrange
        when(mockDependency.someMethod()).thenReturn('value');
        
        // Act
        final result = feature.doSomething();
        
        // Assert
        expect(result, equals('expected'));
        verify(mockDependency.someMethod()).called(1);
      });
    });
  });
}
```