import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';
import '../managers/server_info.dart';
import '../utils/logger.dart';

/// MCP 서버 매니저
class MCPServerManager {
  /// 등록된 서버
  final Map<String, ServerInfo> _servers = {};

  /// 서버 카운터 (ID 생성용)
  int _counter = 0;

  /// 로거
  final MCPLogger _logger = MCPLogger('mcp.server_manager');

  /// 초기화
  Future<void> initialize() async {
    _logger.debug('서버 매니저 초기화');
  }

  /// 새 서버 ID 생성
  String generateId() {
    _counter++;
    return 'server_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// 서버 등록
  void registerServer(String id, Server server, ServerTransport? transport) {
    _logger.debug('서버 등록: $id');
    _servers[id] = ServerInfo(
      id: id,
      server: server,
      transport: transport,
    );
  }

  /// LLM 서버 설정
  void setLlmServer(String id, LlmServer llmServer) {
    _logger.debug('LLM 서버 설정: $id');
    final serverInfo = _servers[id];
    if (serverInfo != null) {
      serverInfo.llmServer = llmServer;
    }
  }

  /// 서버 정보 가져오기
  ServerInfo? getServerInfo(String id) {
    return _servers[id];
  }

  /// 서버 가져오기
  Server? getServer(String id) {
    return _servers[id]?.server;
  }

  /// 모든 서버 ID 가져오기
  List<String> getAllServerIds() {
    return _servers.keys.toList();
  }

  /// 서버 종료
  Future<void> closeServer(String id) async {
    _logger.debug('서버 종료: $id');
    final serverInfo = _servers[id];
    if (serverInfo != null) {
      serverInfo.server.disconnect();
      if (serverInfo.llmServer != null) {
        await serverInfo.llmServer!.close();
      }
      _servers.remove(id);
    }
  }

  /// 모든 서버 종료
  Future<void> closeAll() async {
    _logger.debug('모든 서버 종료');
    for (final id in _servers.keys.toList()) {
      await closeServer(id);
    }
  }

  /// 상태 정보 가져오기
  Map<String, dynamic> getStatus() {
    return {
      'total': _servers.length,
      'servers': _servers.map((key, value) => MapEntry(key, {
        'name': value.server.name,
        'version': value.server.version,
        'tools': value.server.getTools().length,
        'resources': value.server.getResources().length,
        'prompts': value.server.getPrompts().length,
        'hasLlmServer': value.llmServer != null,
      })),
    };
  }
}