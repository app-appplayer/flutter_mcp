import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

/// Flutter MCP HTTP 연결 예제
/// 
/// 이 예제는 HTTP URL을 통해 MCP 서버에 연결하는 올바른 방법을 보여줍니다.
/// Flutter MCP 1.0.4 버전 기준입니다.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Flutter MCP 초기화 (필수!)
  try {
    await FlutterMCP.instance.init(
      MCPConfig(
        appName: 'HTTP Connection Example',
        appVersion: '1.0.0',
        autoStart: false,
        useBackgroundService: false,
        useNotification: false,
        useTray: false,
      ),
    );
    print('✅ Flutter MCP initialized successfully');
  } catch (e) {
    print('❌ Failed to initialize Flutter MCP: $e');
    return;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MCP HTTP Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HttpConnectionExample(),
    );
  }
}

class HttpConnectionExample extends StatefulWidget {
  const HttpConnectionExample({Key? key}) : super(key: key);

  @override
  State<HttpConnectionExample> createState() => _HttpConnectionExampleState();
}

class _HttpConnectionExampleState extends State<HttpConnectionExample> {
  String? _clientId;
  String _status = 'Not connected';
  final TextEditingController _urlController = TextEditingController(
    text: 'http://localhost:8080/sse',
  );

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// 방법 1: config 없이 직접 serverUrl 전달 (권장)
  Future<void> _connectDirectly() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _status = '❌ URL is empty');
      return;
    }

    setState(() => _status = '🔄 Connecting...');

    try {
      // 직접 파라미터로 전달 - config 없이
      _clientId = await FlutterMCP.instance.createClient(
        name: 'HTTP Client (Direct)',
        version: '1.0.0',
        serverUrl: url,
      );

      // 연결
      await FlutterMCP.instance.connectClient(_clientId!);
      
      setState(() => _status = '✅ Connected successfully via direct parameters');
    } catch (e) {
      setState(() => _status = '❌ Error: $e');
    }
  }

  /// 방법 2: MCPClientConfig 사용 (transportType 필수!)
  Future<void> _connectWithConfig() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _status = '❌ URL is empty');
      return;
    }

    setState(() => _status = '🔄 Connecting with config...');

    try {
      // URL에서 transport type 결정
      String transportType;
      if (url.contains('/sse')) {
        transportType = 'sse';
      } else if (url.contains('/mcp')) {
        transportType = 'streamablehttp';
      } else {
        // 기본값
        transportType = 'sse';
      }

      // Config 생성 - transportType 반드시 명시!
      final config = MCPClientConfig(
        name: 'HTTP Client (Config)',
        version: '1.0.0',
        transportType: transportType,  // 필수!
        serverUrl: url,
      );

      _clientId = await FlutterMCP.instance.createClient(
        name: config.name,
        version: config.version,
        config: config,
      );

      // 연결
      await FlutterMCP.instance.connectClient(_clientId!);
      
      setState(() => _status = '✅ Connected successfully via config (transport: $transportType)');
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
        _status = 'Disconnected';
      });
    } catch (e) {
      setState(() => _status = '❌ Disconnect error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter MCP HTTP Connection'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상태 표시
            Card(
              color: _clientId != null ? Colors.green[50] : Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Status: $_status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_clientId != null) ...[
                      const SizedBox(height: 8),
                      Text('Client ID: $_clientId'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // URL 입력
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://localhost:8080/sse',
                border: OutlineInputBorder(),
                helperText: 'SSE: /sse endpoint, StreamableHTTP: /mcp endpoint',
              ),
            ),
            const SizedBox(height: 20),

            // 연결 방법 설명
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📌 중요: transportType 명시',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• 방법 1: config 없이 serverUrl만 전달 (권장)'),
                    Text('• 방법 2: MCPClientConfig 사용 시 transportType 필수'),
                    SizedBox(height: 8),
                    Text('Transport Types:'),
                    Text('  - sse: Server-Sent Events'),
                    Text('  - streamablehttp: Streamable HTTP'),
                    Text('  - stdio: Standard I/O (로컬 프로세스용)'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 버튼들
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _clientId == null ? _connectDirectly : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    child: const Text('Connect (Direct)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _clientId == null ? _connectWithConfig : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('Connect (Config)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _clientId != null ? _disconnect : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}