// Test helper — fake ClientTransport / ServerTransport that intercepts
// outgoing JSON-RPC messages and feeds back canned responses. Lets us
// drive flutter_mcp.connectClient/createClient/callTool happy paths
// without a real subprocess or HTTP server.

import 'dart:async';
import 'dart:convert';

import 'package:mcp_client/mcp_client.dart' as mcp_c;
import 'package:mcp_server/mcp_server.dart' as mcp_s;

/// A fake [mcp_c.ClientTransport] that auto-responds to JSON-RPC
/// requests. Outgoing messages routed through [send] are inspected; any
/// `initialize` request is matched with a successful response so
/// [Client.connect] completes. Other methods can be wired by registering
/// handlers via [setHandler].
class FakeClientTransport implements mcp_c.ClientTransport {
  final _incoming = StreamController<dynamic>.broadcast();
  final _closeCompleter = Completer<void>();

  /// Captured outgoing messages.
  final List<dynamic> sent = [];

  /// Method-name → JSON-RPC `result` map. Defaults handle 'initialize'.
  final Map<String, Map<String, dynamic>> _handlers = {
    'initialize': {
      'protocolVersion': '2025-11-25',
      'serverInfo': {'name': 'fake-server', 'version': '1.0.0'},
      'capabilities': {
        'tools': {'listChanged': false},
        'resources': {'subscribe': false, 'listChanged': false},
        'prompts': {'listChanged': false},
      },
    },
    'tools/list': {
      'tools': [
        {
          'name': 'echo',
          'description': 'echoes input',
          'inputSchema': {'type': 'object', 'properties': {}},
        },
      ],
    },
    'tools/call': {
      'content': [
        {'type': 'text', 'text': 'tool result'},
      ],
      'isError': false,
    },
    'resources/list': {'resources': []},
    'resources/read': {
      'contents': [
        {'uri': 'file:///x', 'mimeType': 'text/plain', 'text': 'hello'},
      ],
    },
    'prompts/list': {'prompts': []},
  };

  void setHandler(String method, Map<String, dynamic> result) {
    _handlers[method] = result;
  }

  @override
  Stream<dynamic> get onMessage => _incoming.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  void send(dynamic message) {
    sent.add(message);
    final m = message is String ? jsonDecode(message) : message;
    if (m is! Map) return;
    final method = m['method'] as String?;
    final id = m['id'];
    if (method == null) return;
    if (id == null) return; // notification
    final result = _handlers[method];
    if (result != null) {
      // Schedule async to mimic real transport delivery semantics.
      scheduleMicrotask(() {
        _incoming.add({
          'jsonrpc': '2.0',
          'id': id,
          'result': result,
        });
      });
    } else {
      scheduleMicrotask(() {
        _incoming.add({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32601, 'message': 'method not found: $method'},
        });
      });
    }
  }

  @override
  void close() {
    if (!_closeCompleter.isCompleted) {
      _closeCompleter.complete();
    }
    _incoming.close();
  }
}

/// A fake [mcp_s.ServerTransport]. The MCP server connects to it and
/// then waits for client messages — for our coverage purposes we only
/// need [send]/[onMessage]/[onClose] to exist.
class FakeServerTransport implements mcp_s.ServerTransport {
  final _incoming = StreamController<dynamic>.broadcast();
  final _closeCompleter = Completer<void>();

  /// Captured outgoing messages.
  final List<dynamic> sent = [];

  @override
  Stream<dynamic> get onMessage => _incoming.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  void send(dynamic message) {
    sent.add(message);
  }

  @override
  void close() {
    if (!_closeCompleter.isCompleted) {
      _closeCompleter.complete();
    }
    _incoming.close();
  }
}
