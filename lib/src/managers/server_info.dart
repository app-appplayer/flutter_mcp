import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';

/// 서버 정보
class ServerInfo {
  /// 서버 ID
  final String id;

  /// MCP 서버
  final Server server;

  /// 서버 트랜스포트
  final ServerTransport? transport;

  /// LLM 서버
  LlmServer? llmServer;

  /// 실행 여부
  bool running = false;

  ServerInfo({
    required this.id,
    required this.server,
    this.transport,
  });
}