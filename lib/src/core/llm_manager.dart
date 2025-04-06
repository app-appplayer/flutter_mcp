import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_llm/mcp_llm.dart';
import '../managers/llm_info.dart';
import '../utils/logger.dart';

/// MCP LLM Manager
class MCPLlmManager {
  /// Registered LLMs
  final Map<String, LlmInfo> _llms = {};

  /// LLM counter (for ID generation)
  int _counter = 0;

  /// Logger
  final MCPLogger _logger = MCPLogger('mcp.llm_manager');

  /// Initialize
  Future<void> initialize() async {
    _logger.debug('LLM manager initialization');
  }

  /// Generate new LLM ID
  String generateId() {
    _counter++;
    return 'llm_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// Register LLM
  void registerLlm(String id, MCPLlm mcpLlm, LlmClient client) {
    _logger.debug('Registering LLM: $id');
    _llms[id] = LlmInfo(
      id: id,
      mcpLlm: mcpLlm,
      client: client,
    );
  }

  /// Add client to LLM
  Future<void> addClientToLlm(String llmId, Client client) async {
    _logger.debug('Adding client to LLM: $llmId, ${client.name}');
    final llmInfo = _llms[llmId];
    if (llmInfo != null) {
      // Since mcpLlm.addClient() doesn't exist, we'll just track the client
      // in our connected clients list
      llmInfo.connectedClientIds.add(client.name);

      // Your actual integration logic here
      // This might involve:
      // 1. Registering the client with tools from the LLM
      // 2. Setting up communication channels between the client and LLM
      // 3. Any other necessary integration steps

      _logger.info('Client ${client.name} connected to LLM $llmId');
    }
  }

  /// Get LLM info
  LlmInfo? getLlmInfo(String id) {
    return _llms[id];
  }

  /// Get LLM client
  LlmClient? getLlm(String id) {
    return _llms[id]?.client;
  }

  /// Get all LLM IDs
  List<String> getAllLlmIds() {
    return _llms.keys.toList();
  }

  /// Close LLM
  Future<void> closeLlm(String id) async {
    _logger.debug('Closing LLM: $id');
    final llmInfo = _llms[id];
    if (llmInfo != null) {
      await llmInfo.client.close();
      _llms.remove(id);
    }
  }

  /// Close all LLMs
  Future<void> closeAll() async {
    _logger.debug('Closing all LLMs');
    for (final id in _llms.keys.toList()) {
      await closeLlm(id);
    }
  }

  /// Get status information
  Map<String, dynamic> getStatus() {
    return {
      'total': _llms.length,
      'llms': _llms.map((key, value) => MapEntry(key, {
        'provider': value.client.runtimeType.toString(),
        'connectedClients': value.connectedClientIds.length,
      })),
    };
  }
}