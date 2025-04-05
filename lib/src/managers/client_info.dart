import 'package:mcp_client/mcp_client.dart';

/// 클라이언트 정보
class ClientInfo {
  /// 클라이언트 ID
  final String id;

  /// MCP 클라이언트
  final Client client;

  /// 클라이언트 트랜스포트
  final ClientTransport? transport;

  /// 연결 여부
  bool connected = false;

  ClientInfo({
    required this.id,
    required this.client,
    this.transport,
  });
}