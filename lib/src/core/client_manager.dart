import 'package:mcp_client/mcp_client.dart';
import '../managers/client_info.dart';
import '../utils/logger.dart';

/// MCP 클라이언트 매니저
class MCPClientManager {
  /// 등록된 클라이언트
  final Map<String, ClientInfo> _clients = {};

  /// 클라이언트 카운터 (ID 생성용)
  int _counter = 0;

  /// 로거
  final MCPLogger _logger = MCPLogger('mcp.client_manager');

  /// 초기화
  Future<void> initialize() async {
    _logger.debug('클라이언트 매니저 초기화');
  }

  /// 새 클라이언트 ID 생성
  String generateId() {
    _counter++;
    return 'client_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// 클라이언트 등록
  void registerClient(String id, Client client, ClientTransport? transport) {
    _logger.debug('클라이언트 등록: $id');
    _clients[id] = ClientInfo(
      id: id,
      client: client,
      transport: transport,
    );
  }

  /// 클라이언트 정보 가져오기
  ClientInfo? getClientInfo(String id) {
    return _clients[id];
  }

  /// 클라이언트 가져오기
  Client? getClient(String id) {
    return _clients[id]?.client;
  }

  /// 모든 클라이언트 ID 가져오기
  List<String> getAllClientIds() {
    return _clients.keys.toList();
  }

  /// 클라이언트 종료
  Future<void> closeClient(String id) async {
    _logger.debug('클라이언트 종료: $id');
    final clientInfo = _clients[id];
    if (clientInfo != null) {
      clientInfo.client.disconnect();
      _clients.remove(id);
    }
  }

  /// 모든 클라이언트 종료
  Future<void> closeAll() async {
    _logger.debug('모든 클라이언트 종료');
    for (final id in _clients.keys.toList()) {
      await closeClient(id);
    }
  }

  /// 상태 정보 가져오기
  Map<String, dynamic> getStatus() {
    return {
      'total': _clients.length,
      'clients': _clients.map((key, value) => MapEntry(key, {
        'connected': value.client.isConnected,
        'name': value.client.name,
        'version': value.client.version,
      })),
    };
  }
}