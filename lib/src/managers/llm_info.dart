import 'package:mcp_llm/mcp_llm.dart';

/// LLM 정보
class LlmInfo {
  /// LLM ID
  final String id;

  /// MCP LLM
  final MCPLlm mcpLlm;

  /// LLM 클라이언트
  final LlmClient client;

  /// 연결된 클라이언트 ID
  final List<String> connectedClientIds = [];

  LlmInfo({
    required this.id,
    required this.mcpLlm,
    required this.client,
  });
}