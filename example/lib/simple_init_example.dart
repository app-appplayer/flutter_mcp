import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

/// Flutter MCP 최소 초기화 예제
/// 
/// Platform 기능 없이 순수하게 MCP 기능만 사용하는 예제입니다.
/// "Flutter MCP is not initialized" 오류 해결용
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 최소 설정으로 초기화 - Platform 기능 모두 비활성화
  try {
    await FlutterMCP.instance.init(
      MCPConfig(
        appName: 'Simple MCP Example',
        appVersion: '1.0.0',
        autoStart: false,
        // Platform 기능 모두 비활성화
        useBackgroundService: false,
        useNotification: false,
        useTray: false,
        secure: false,
        // 성능 모니터링도 비활성화
        enablePerformanceMonitoring: false,
      ),
    );
    print('✅ Flutter MCP initialized successfully');
  } catch (e) {
    print('❌ Failed to initialize Flutter MCP: $e');
    // 초기화 실패 시 앱을 실행하지 않음
    return;
  }

  runApp(const SimpleApp());
}

class SimpleApp extends StatelessWidget {
  const SimpleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Flutter MCP',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SimpleExample(),
    );
  }
}

class SimpleExample extends StatefulWidget {
  const SimpleExample({Key? key}) : super(key: key);

  @override
  State<SimpleExample> createState() => _SimpleExampleState();
}

class _SimpleExampleState extends State<SimpleExample> {
  String? _clientId;
  String _status = 'Ready';
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _checkInitialization();
  }

  void _checkInitialization() {
    setState(() {
      _isInitialized = FlutterMCP.instance.isInitialized;
      _status = _isInitialized ? '✅ MCP Initialized' : '❌ MCP Not Initialized';
    });
  }

  Future<void> _testConnection() async {
    if (!_isInitialized) {
      setState(() => _status = '❌ MCP not initialized!');
      return;
    }

    setState(() => _status = '🔄 Testing connection...');

    try {
      // 가장 간단한 방법으로 클라이언트 생성
      _clientId = await FlutterMCP.instance.createClient(
        name: 'Test Client',
        version: '1.0.0',
        serverUrl: 'http://localhost:8080/sse',
      );

      setState(() => _status = '✅ Client created: $_clientId');
      
      // 연결 시도
      await FlutterMCP.instance.connectClient(_clientId!);
      setState(() => _status = '✅ Connected successfully!');
      
    } catch (e) {
      setState(() => _status = '❌ Error: $e');
    }
  }

  Future<void> _disconnect() async {
    if (_clientId == null) return;

    try {
      await FlutterMCP.instance.clientManager.closeClient(_clientId!);
      setState(() {
        _clientId = null;
        _status = '✅ Disconnected';
      });
    } catch (e) {
      setState(() => _status = '❌ Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Flutter MCP Test'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 초기화 상태
              Card(
                color: _isInitialized ? Colors.green[100] : Colors.red[100],
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(
                        _isInitialized ? Icons.check_circle : Icons.error,
                        size: 48,
                        color: _isInitialized ? Colors.green : Colors.red,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Flutter MCP: ${_isInitialized ? "Initialized" : "Not Initialized"}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // 상태 표시
              Text(
                _status,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              
              // 버튼들
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _isInitialized && _clientId == null ? _testConnection : null,
                    child: const Text('Test Connection'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _clientId != null ? _disconnect : null,
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              
              // 도움말
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '문제 해결:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('1. MCP가 초기화되지 않았다면:'),
                      Text('   - Platform 기능 비활성화 (이 예제처럼)'),
                      Text('   - 권한 문제 확인'),
                      SizedBox(height: 8),
                      Text('2. 연결이 실패한다면:'),
                      Text('   - 서버가 실행 중인지 확인'),
                      Text('   - URL과 포트 확인'),
                      Text('   - transportType 명시 (config 사용 시)'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}