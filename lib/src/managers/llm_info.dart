import 'package:mcp_llm/mcp_llm.dart';

/// LLM information
class LlmInfo {
  /// LLM ID
  final String id;

  /// MCP LLM
  final MCPLlm mcpLlm;

  /// LLM client
  final LlmClient client;

  /// Connected client IDs
  final List<String> connectedClientIds = [];

  LlmInfo({
    required this.id,
    required this.mcpLlm,
    required this.client,
  });
}
