import 'package:flutter_mcp/flutter_mcp.dart';

void main() async {
  // Initialize Flutter MCP
  final mcp = FlutterMCP.instance;
  await mcp.init(MCPConfig(
    appName: 'Transport Demo',
    appVersion: '1.0.0',
  ));

  print('Flutter MCP Transport Demo');
  print('==========================');

  // Demonstrate all three transport types for servers
  print('\n1. Creating servers with different transport types:');

  // STDIO Server
  final stdioServerId = await mcp.createServer(
    name: 'STDIO Server',
    version: '1.0.0',
    config: MCPServerConfig(
      name: 'STDIO Server',
      version: '1.0.0',
      transportType: 'stdio',
    ),
  );
  print('✓ STDIO Server created: $stdioServerId');

  // SSE Server
  final sseServerId = await mcp.createServer(
    name: 'SSE Server',
    version: '1.0.0',
    config: MCPServerConfig(
      name: 'SSE Server',
      version: '1.0.0',
      transportType: 'sse',
      ssePort: 8080,
      fallbackPorts: [8081, 8082],
    ),
  );
  print('✓ SSE Server created: $sseServerId');

  // Streamable HTTP Server
  final httpServerId = await mcp.createServer(
    name: 'HTTP Server',
    version: '1.0.0',
    config: MCPServerConfig(
      name: 'HTTP Server',
      version: '1.0.0',
      transportType: 'streamablehttp',
      streamableHttpPort: 8083,
      fallbackPorts: [8084, 8085],
    ),
  );
  print('✓ Streamable HTTP Server created: $httpServerId');

  // Demonstrate all three transport types for clients
  print('\n2. Creating clients with different transport types:');

  // STDIO Client
  final stdioClientId = await mcp.createClient(
    name: 'STDIO Client',
    version: '1.0.0',
    config: MCPClientConfig(
      name: 'STDIO Client',
      version: '1.0.0',
      transportType: 'stdio',
      transportCommand: 'echo',
      transportArgs: ['Hello from STDIO'],
    ),
  );
  print('✓ STDIO Client created: $stdioClientId');

  // SSE Client
  final sseClientId = await mcp.createClient(
    name: 'SSE Client',
    version: '1.0.0',
    config: MCPClientConfig(
      name: 'SSE Client',
      version: '1.0.0',
      transportType: 'sse',
      serverUrl: 'http://localhost:8080',
    ),
  );
  print('✓ SSE Client created: $sseClientId');

  // Streamable HTTP Client
  final httpClientId = await mcp.createClient(
    name: 'HTTP Client',
    version: '1.0.0',
    config: MCPClientConfig(
      name: 'HTTP Client',
      version: '1.0.0',
      transportType: 'streamablehttp',
      serverUrl: 'http://localhost:8083',
    ),
  );
  print('✓ Streamable HTTP Client created: $httpClientId');

  print('\n3. Transport type support summary:');
  print('   • STDIO: ✓ Supported (standard input/output)');
  print('   • SSE: ✓ Supported (Server-Sent Events)');
  print('   • StreamableHTTP: ✓ Supported (HTTP with streaming)');

  print('\n4. Configuration options:');
  print('   • Port configuration with fallback support');
  print('   • Authentication token support');
  print('   • Transport type auto-detection');
  print('   • Backward compatibility maintained');

  // Cleanup
  await mcp.shutdown();
  print('\n✓ Demo completed successfully!');
}