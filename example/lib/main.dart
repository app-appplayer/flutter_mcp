import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // MCP 초기화
  await FlutterMCP.instance.init(
    MCPConfig(
      appName: 'MCP Demo App',
      appVersion: '1.0.0',
      useBackgroundService: true,
      useNotification: true,
      useTray: true,
      loggingLevel: LogLevel.debug,
      autoStart: true,
      // 자동 시작 서버
      autoStartServer: [
        MCPServerConfig(
          name: 'Sample MCP Server',
          version: '1.0.0',
          capabilities: ServerCapabilities(
            tools: true,
            resources: true,
            prompts: true,
          ),
          useStdioTransport: true,
          // LLM 통합
          integrateLlm: MCPLlmIntegration(
            providerName: 'echo',
            config: LlmConfiguration(
              apiKey: 'test_api_key',
              model: 'echo',
            ),
          ),
        ),
      ],
      // 자동 시작 클라이언트
      autoStartClient: [
        MCPClientConfig(
          name: 'Sample MCP Client',
          version: '1.0.0',
          capabilities: ClientCapabilities(
            sampling: true,
            roots: true,
          ),
          // 연결할 LLM (서버에서 생성한 동일한 LLM 사용)
          integrateLlm: MCPLlmIntegration(
            existingLlmId: 'llm_1',  // 나중에 가져올 수 있음
          ),
        ),
      ],
      // 스케줄링 작업
      schedule: [
        MCPJob.every(
          Duration(minutes: 1),
          task: () {
            print('1분마다 실행되는 작업');
          },
        ),
      ],
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MCP Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter MCP Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _statusText = '';
  final TextEditingController _messageController = TextEditingController();
  final List<String> _chatMessages = [];

  @override
  void initState() {
    super.initState();
    _updateStatus();
  }

  Future<void> _updateStatus() async {
    final status = FlutterMCP.instance.getSystemStatus();

    setState(() {
      _statusText = '''
        초기화: ${status['initialized']}
        클라이언트: ${status['clients']}
        서버: ${status['servers']}
        LLM: ${status['llms']}
        백그라운드 서비스: ${status['backgroundServiceRunning']}
        스케줄러: ${status['schedulerRunning']}
      ''';
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _chatMessages.add('사용자: $message');
    });

    try {
      // 모든 LLM ID 가져오기
      final llmIds = FlutterMCP.instance.allLlmIds;
      if (llmIds.isNotEmpty) {
        // 첫 번째 LLM 사용
        final response = await FlutterMCP.instance.chat(
          llmIds.first,
          message,
          enableTools: true,
        );

        setState(() {
          _chatMessages.add('AI: ${response.text}');
          _messageController.clear();
        });
      } else {
        setState(() {
          _chatMessages.add('오류: 사용 가능한 LLM이 없습니다');
        });
      }
    } catch (e) {
      setState(() {
        _chatMessages.add('오류: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _updateStatus,
          ),
        ],
      ),
      body: Column(
        children: [
          // 상태 표시
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.grey[200],
            width: double.infinity,
            child: Text(
              _statusText,
              style: const TextStyle(fontFamily: 'Monospace'),
            ),
          ),

          // 채팅 영역
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _chatMessages.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(_chatMessages[index]),
                );
              },
            ),
          ),

          // 메시지 입력 영역
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: '메시지를 입력하세요',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                ElevatedButton(
                  onPressed: _sendMessage,
                  child: const Text('전송'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}