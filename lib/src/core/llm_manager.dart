import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_llm/mcp_llm.dart';
import '../managers/llm_info.dart';
import '../utils/logger.dart';

/// MCP LLM 매니저
class MCPLlmManager {
  /// 등록된 LLM
  final Map<String, LlmInfo> _llms = {};

  /// LLM 카운터 (ID 생성용)
  int _counter = 0;

  /// 로거
  final MCPLogger _logger = MCPLogger('mcp.llm_manager');

  /// 초기화
  Future<void> initialize() async {
    _logger.debug('LLM 매니저 초기화');
  }

  /// 새 LLM ID 생성
  String generateId() {
    _counter++;
    return 'llm_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// LLM 등록
  void registerLlm(String id, MCPLlm mcpLlm, LlmClient client) {
    _logger.debug('LLM 등록: $id');
    _llms[id] = LlmInfo(
      id: id,
      mcpLlm: mcpLlm,
      client: client,
    );
  }

  /// LLM에 클라이언트 추가
  Future<void> addClientToLlm(String llmId, Client client) async {
    _logger.debug('LLM에 클라이언트 추가: $llmId, ${client.name}');
    final llmInfo = _llms[llmId];
    if (llmInfo != null) {
      await llmInfo.mcpLlm.addClient(client);
      llmInfo.connectedClientIds.add(client.name);
    }
  }

  /// LLM 정보 가져오기
  LlmInfo? getLlmInfo(String id) {
    return _llms[id];
  }

  /// LLM 클라이언트 가져오기
  LlmClient? getLlm(String id) {
    return _llms[id]?.client;
  }

  /// 모든 LLM ID 가져오기
  List<String> getAllLlmIds() {
    return _llms.keys.toList();
  }

  /// LLM 종료
  Future<void> closeLlm(String id) async {
    _logger.debug('LLM 종료: $id');
    final llmInfo = _llms[id];
    if (llmInfo != null) {
      await llmInfo.client.close();
      _llms.remove(id);
    }
  }

  /// 모든 LLM 종료
  Future<void> closeAll() async {
    _logger.debug('모든 LLM 종료');
    for (final id in _llms.keys.toList()) {
      await closeLlm(id);
    }
  }

  /// 상태 정보 가져오기
  Map<String, dynamic> getStatus() {
    return {
      'total': _llms.length,
      'llms': _llms.map((key, value) => MapEntry(key, {
        'provider': value.client.llmProvider.runtimeType.toString(),
        'connectedClients': value.connectedClientIds.length,
      })),
    };
  }
}