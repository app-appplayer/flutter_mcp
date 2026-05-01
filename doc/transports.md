# Transports

`transportType` is **required** on every `MCPClientConfig` /
`MCPServerConfig`. There is no auto-inference. Three values are
supported:

| `transportType` | Direction | Backed by |
|---|---|---|
| `stdio` | local subprocess | `mcp_client` `StdioClientTransport` / `mcp_server` `StdioServerTransport` |
| `sse` | HTTP, server-sent events | `mcp_client` `SseClientTransport` / `mcp_server` SSE transport |
| `streamablehttp` | HTTP, JSON-RPC + optional SSE stream | `mcp_client` `StreamableHttpClientTransport` / `mcp_server` Streamable HTTP transport (default for new deployments) |

Spec note: the JSON-RPC batch frame was removed in `2025-06-18`. None of
the three transports above ship batched messages; if you targeted
batching pre-2.0, fan out with `Future.wait` instead.

---

## Client side

### Stdio client

Spawns a subprocess and speaks JSON-RPC over its stdin/stdout.

```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'my-tool-bridge',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'my-tool-bridge',
    version: '1.0.0',
    transportType: 'stdio',
    transportCommand: '/usr/bin/python3',
    transportArgs: ['server.py', '--mode', 'mcp'],
  ),
);
await FlutterMCP.instance.connectClient(clientId);
```

Notes:
- `transportCommand` is required; missing throws `MCPValidationException`.
- The process inherits the current working directory unless you specify
  one in your launch wrapper. Spawn errors (binary missing) surface as
  `MCPOperationFailedException` wrapping a `ProcessException`.

### SSE client

Long-lived HTTP connection. The client `GET`s the server's SSE endpoint
to receive events; outbound JSON-RPC requests `POST` to a matched
messages endpoint.

```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'sse-client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'sse-client',
    version: '1.0.0',
    transportType: 'sse',
    serverUrl: 'http://localhost:8080',
    endpoint: '/sse',                     // appended to serverUrl
    authToken: 'bearer-token',            // → Authorization: Bearer ...
    headers: {'X-Tenant': 'acme'},
    timeout: const Duration(seconds: 30),
    sseReadTimeout: const Duration(minutes: 5),
  ),
);
```

`endpoint` is appended to `serverUrl` to form the SSE URL the client
opens; if you omit it the bare `serverUrl` is used.

### Streamable HTTP client

Modern HTTP transport — JSON-RPC over POST, optional response stream.
This is the recommended transport for new server deployments.

```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'http-client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'http-client',
    version: '1.0.0',
    transportType: 'streamablehttp',
    serverUrl: 'http://localhost:8080',   // base URL only
    endpoint: '/mcp',                     // joined to serverUrl
    authToken: 'bearer-token',
    headers: {'X-Trace-Id': 'abc123'},
    timeout: const Duration(seconds: 30),
    maxConcurrentRequests: 10,
    useHttp2: true,
    terminateOnClose: true,
  ),
);
```

Once the protocol is negotiated to `2025-06-18` or later, the underlying
`mcp_client` adds the spec `MCP-Protocol-Version: <version>` header to
every subsequent request.

---

## Server side

### Stdio server

```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'stdio-server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'stdio-server',
    version: '1.0.0',
    transportType: 'stdio',
  ),
);
FlutterMCP.instance.connectServer(serverId);
```

Reads from `stdin` and writes to `stdout`. Use this when the server is
a child process spawned by an external host (Claude Desktop, IDE
plugin, etc.).

### SSE server

```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'sse-server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'sse-server',
    version: '1.0.0',
    transportType: 'sse',
    ssePort: 8080,
    host: 'localhost',                 // default 'localhost'
    endpoint: '/sse',                  // default '/sse'
    messagesEndpoint: '/message',      // default '/message'
    fallbackPorts: [8081, 8082],       // try in order if 8080 is taken
    authToken: 'bearer-token',         // optional bearer-token gate
  ),
);
FlutterMCP.instance.connectServer(serverId);
```

`ssePort` is required for SSE. The server binds the SSE endpoint on
`host:ssePort/endpoint` and accepts JSON-RPC posts on
`host:ssePort/messagesEndpoint`. If `ssePort` is busy, the server walks
through `fallbackPorts` before throwing.

### Streamable HTTP server

```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'http-server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'http-server',
    version: '1.0.0',
    transportType: 'streamablehttp',
    streamableHttpPort: 8080,
    host: 'localhost',
    endpoint: '/mcp',                  // default '/mcp'
    fallbackPorts: [8081, 8082],
    authToken: 'bearer-token',
    isJsonResponseEnabled: false,      // false (default) = SSE responses; true = single JSON
    jsonResponseMode: 'sync',          // 'sync' | 'async' (only when JSON mode is on)
    maxRequestSize: 4 * 1024 * 1024,   // bytes
    requestTimeout: const Duration(seconds: 30),
    corsConfig: {                      // optional CORS
      'allowOrigin': '*',
      'allowMethods': 'POST, GET, OPTIONS',
      'allowHeaders': 'Content-Type, Authorization',
    },
    middleware: [/* shelf.Middleware list */],
    protectedResource: const MCPProtectedResourceConfig(
      resource: 'https://api.example.com/mcp',
      authorizationServers: ['https://auth.example.com'],
      scopesSupported: ['mcp:read', 'mcp:tools'],
      bearerMethodsSupported: ['header'],
    ),
  ),
);
FlutterMCP.instance.connectServer(serverId);
```

Either `streamableHttpPort` or the legacy `ssePort` must be set —
omitting both throws `MCPValidationException`.

`protectedResource` makes the server publish RFC 9728 OAuth metadata at
`/.well-known/oauth-protected-resource`; see `doc/spec-features.md`.

---

## Choosing a transport

| You're building... | Use |
|---|---|
| A subprocess "server.py" started by an IDE / desktop host | **stdio** |
| A long-running HTTP service in production today | **streamablehttp** |
| Code that must interop with pre-2025-06-18 SSE servers | **sse** |
| Browser-resident server | **streamablehttp** with `isJsonResponseEnabled: false` |
| Browser-resident client | **streamablehttp** (web build) |

The two HTTP transports are not interchangeable: a client opened with
`streamablehttp` cannot talk to a server speaking SSE (they expose
different endpoints and framing). Match the transport on both ends.

---

## Common pitfalls

- **`transportType must be specified`** — passing `MCPClientConfig` /
  `MCPServerConfig` without `transportType` throws at construction.
- **`serverUrl is required for sse / streamablehttp transport`** —
  HTTP transports need a base URL on the client.
- **`transportCommand is required for stdio transport`** — stdio
  clients need a command to spawn.
- **`ssePort is required for sse transport`** — SSE servers need a
  port; no auto-pick.
- **`http://127.0.0.1:0` in tests** — port 0 means "ephemeral OS-picked
  port" for `dart:io` HttpServer, but on the client side it's a 400
  from `EventSource`. Use a real port and a fake server.
- **Auth header collisions** — if you set `authToken` *and* a manual
  `Authorization` entry in `headers`, the explicit `authToken` wins
  (it's appended last).
- **`endpoint` joining** — for SSE/streamablehttp, `endpoint` is
  concatenated to `serverUrl` literally. Don't double-slash:
  `serverUrl: 'http://x/' + endpoint: '/api'` becomes `http://x//api`.
