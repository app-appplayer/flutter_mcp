# Spec Features

Phase-2 MCP capabilities surfaced by Flutter MCP. Each section explains
the spec method, the direction, and the Flutter MCP entry point.

| Method | Direction | Added in | Entry point |
|---|---|---|---|
| `sampling/createMessage` | server → client | `2025-03-26` (auto-bridge), tools in `2025-11-25` | `requestClientSampling` (server side); `MCPClientConfig.autoBridgeSampling` (client side) |
| `roots/list` | server → client | `2024-11-05` | `MCPClientConfig.initialRoots` / `addClientRoot`; server side: `requestClientRoots` |
| `elicitation/create` | server → client | `2025-06-18` | `setElicitationHandler` / `MCPClientConfig.elicitationHandler`; server side: `requestClientElicitation` |
| `completion/complete` | client → server | `2024-11-05`, context field added in `2025-06-18` | `addServerCompletion` / `removeServerCompletion` |
| OAuth Resource Server (RFC 9728) | HTTP discovery | `2025-06-18` | `MCPServerConfig.protectedResource` |
| Structured tool output | tool result | `2025-06-18` | `Tool.outputSchema` + `CallToolResult.structuredContent`, `ResourceLinkContent` |

---

## Sampling — `sampling/createMessage`

The server asks the connected client to fulfil a prompt with the user's
own LLM seat. Useful for tool handlers that want to ride on the host's
configured model without packaging their own.

### Auto-bridge to the host LLM (default)

`MCPClientConfig.autoBridgeSampling` defaults to `true`. When `true`
(and `capabilities` is not explicitly supplied), the client advertises
`sampling: true` on initialize, and Flutter MCP wires an
`onSamplingRequest` handler that delegates to the **default LLM client**
registered through `MCPLlmManager`.

```dart
// 1. Register an LLM client first.
final (_, llmClientId) = await FlutterMCP.instance.createLlmClient(
  providerName: 'openai',
  config: LlmConfiguration(apiKey: '...', model: 'gpt-4o'),
);
FlutterMCP.instance.setDefaultLlmClientId(llmClientId);

// 2. Create a sampling-capable client (default — autoBridgeSampling: true).
final clientId = await FlutterMCP.instance.createClient(
  name: 'my-client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'my-client',
    version: '1.0.0',
    transportType: 'streamablehttp',
    serverUrl: 'http://localhost:8080',
  ),
);
```

If a request arrives and there is no default LLM client, Flutter MCP
throws `MCPException('Cannot fulfil sampling/createMessage: no default
LLM client. ...')` so the failure is visible to the server.

The bridge currently flattens the spec `messages` array (each
`{role, content: {type: "text", text}}` entry) plus the optional
`systemPrompt` into a single prompt string and calls the LLM client.
Tool-calling sampling fields added in `2025-11-25` (`tools`,
`toolChoice`) are not yet propagated — register a custom handler to
participate in those flows.

### Custom client-side handler

Bypass the bridge by reaching to the underlying `Client`:

```dart
final mcpClient = FlutterMCP.instance.clientManager.getClient(clientId)!;
mcpClient.onSamplingRequestMap((params) async {
  // params: spec CreateMessageRequest.params
  return {
    'role': 'assistant',
    'content': {'type': 'text', 'text': 'custom answer'},
    'model': 'custom-model',
    'stopReason': 'endTurn',
  };
});
```

To opt out entirely set `autoBridgeSampling: false`, or pass an explicit
`ClientCapabilities()` value without the `sampling` flag.

### Server-side request

Inside a tool handler:

```dart
final result = await FlutterMCP.instance.requestClientSampling(
  serverId: serverId,
  sessionId: sessionId,
  params: {
    'messages': [
      {'role': 'user', 'content': {'type': 'text', 'text': 'summarise X'}},
    ],
    'systemPrompt': 'You are a concise summariser.',
    'maxTokens': 200,
    'temperature': 0.2,
  },
  timeout: const Duration(seconds: 60),
);
final text = result['content']['text'] as String;
```

If the connected client never advertised the `sampling` capability the
call fails with `methodNotFound`.

---

## Roots — `roots/list`

The server asks the client which filesystem (or URI) roots it should
treat as in-scope for this session. Flutter MCP keeps a per-client list
of `Root`s and answers `roots/list` from it automatically.

### Configure roots up front

```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'my-client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'my-client',
    version: '1.0.0',
    transportType: 'streamablehttp',
    serverUrl: 'http://localhost:8080',
    initialRoots: const [
      Root(uri: 'file:///workspace/project', name: 'project'),
    ],
  ),
);
```

Adding `initialRoots` (or a `listRootsHandler`) implies the `roots`
capability when `capabilities` is not explicitly supplied; the client
advertises `roots: true` on initialize and emits
`notifications/roots/list_changed` whenever you mutate the list.

### Mutate at runtime

```dart
FlutterMCP.instance.addClientRoot(
  clientId, Root(uri: 'file:///tmp', name: 'tmp'));
FlutterMCP.instance.removeClientRoot(clientId, 'file:///tmp');

final current = FlutterMCP.instance.getClientRoots(clientId);
```

### Custom handler

Override the locally-stored list with a dynamic computation by
supplying `MCPClientConfig.listRootsHandler`:

```dart
config: MCPClientConfig(
  /* ... */,
  listRootsHandler: () async => _resolveRootsForCurrentUser(),
),
```

### Server-side request

```dart
final roots = await FlutterMCP.instance.requestClientRoots(
  serverId: serverId,
  sessionId: sessionId,
  timeout: const Duration(seconds: 30),
);
// roots: List<server.Root>
```

---

## Elicitation — `elicitation/create` (`2025-06-18+`)

The server asks the connected client to elicit input from the user
(typically a small form). The handler returns one of three actions:

- `{action: 'accept', content: { ...filled fields... }}`
- `{action: 'decline'}`
- `{action: 'cancel'}`

### Global handler

```dart
FlutterMCP.instance.setElicitationHandler((params) async {
  final message = params['message'] as String;
  final schema = params['requestedSchema'] as Map<String, dynamic>;

  final result = await showElicitationDialog(message: message, schema: schema);
  if (result.cancelled) return {'action': 'cancel'};
  if (result.declined) return {'action': 'decline'};
  return {'action': 'accept', 'content': result.values};
});
```

The global handler applies to clients **created after** the call. To
update an already-connected client, replace the handler on the
underlying `Client` directly.

### Per-client handler

```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'my-client',
  version: '1.0.0',
  config: MCPClientConfig(
    /* ... */,
    elicitationHandler: (params) async => {
      'action': 'accept',
      'content': {'confirm': true},
    },
  ),
);
```

If neither a per-client nor a global handler is configured, Flutter MCP
returns `{action: 'decline'}` so the server falls back gracefully.

### Server-side request

```dart
final answer = await FlutterMCP.instance.requestClientElicitation(
  serverId: serverId,
  sessionId: sessionId,
  params: {
    'message': 'Confirm overwrite?',
    'requestedSchema': {
      'type': 'object',
      'properties': {'confirm': {'type': 'boolean'}},
      'required': ['confirm'],
    },
  },
  timeout: const Duration(minutes: 2),
);
```

---

## Completion — `completion/complete`

Client → server argument autocompletion. The server publishes
completion handlers for prompt arguments or resource-template arguments;
the client requests suggestions when the user is filling in a form.

```dart
FlutterMCP.instance.addServerCompletion(
  serverId: serverId,
  refType: 'prompt',           // 'prompt' or 'resource'
  refKey: 'analyze',           // prompt name or resource template URI
  handler: (ref, argument, context) async {
    // ref: {'type': 'ref/prompt', 'name': 'analyze'}
    // argument: {'name': 'topic', 'value': 'p'}
    // context: {'arguments': { ...previously resolved args... }}  (2025-06-18+)
    final partial = (argument['value'] as String?) ?? '';
    return {
      'values': topicsStartingWith(partial),
      'total': null,
      'hasMore': false,
    };
  },
);

// Wildcard handler — runs when no exact-key handler matches.
FlutterMCP.instance.addServerCompletion(
  serverId: serverId,
  refType: 'prompt',
  refKey: '*',
  handler: ...,
);

// Remove later
FlutterMCP.instance.removeServerCompletion(
  serverId: serverId, refType: 'prompt', refKey: 'analyze');
```

The `context.arguments` map (added in `2025-06-18`) contains
already-filled arguments, useful for chained completions like
"city" → "neighbourhood".

---

## OAuth Resource Server (RFC 9728)

`2025-06-18` deprecated the JSON-RPC `auth/*` flow. MCP servers are
now OAuth 2.0 Resource Servers, advertising metadata at
`/.well-known/oauth-protected-resource`. Configure on the server:

```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'my-server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'my-server',
    version: '1.0.0',
    transportType: 'streamablehttp',
    streamableHttpPort: 8080,
    protectedResource: const MCPProtectedResourceConfig(
      resource: 'https://api.example.com/mcp',
      authorizationServers: ['https://auth.example.com'],
      scopesSupported: ['mcp:read', 'mcp:tools'],
      bearerMethodsSupported: ['header'],
      resourceDocumentation: 'https://docs.example.com/mcp',
    ),
  ),
);
```

The server publishes the metadata document automatically. Token
issuance and refresh remain the client app's responsibility — Flutter
MCP does not embed an OAuth client. Add the obtained access token to
your `MCPClientConfig`:

```dart
MCPClientConfig(
  /* ... */,
  authToken: accessToken,    // → Authorization: Bearer <accessToken>
)
```

---

## Structured tool output (`2025-06-18+`)

Servers can declare a JSON Schema for their tool's structured result
and return that result alongside (or instead of) plain text:

```dart
// On the server
serverInstance.addTool(Tool(
  name: 'lookup',
  description: 'Resolve a SKU to canonical metadata.',
  inputSchema: { ... },
  outputSchema: {
    'type': 'object',
    'properties': {
      'sku': {'type': 'string'},
      'price_cents': {'type': 'integer'},
    },
    'required': ['sku', 'price_cents'],
  },
), (args) async {
  return CallToolResult(
    content: const [TextContent(text: 'Resolved successfully')],
    structuredContent: {
      'sku': 'WIDGET-1',
      'price_cents': 4200,
    },
  );
});
```

`ResourceLinkContent` is the new content type for "here's the resource,
read it yourself" responses — see the `mcp_server` 2.0 changelog.

---

## See also

- `doc/transports.md` — wiring up a session to actually use these methods
- `doc/observability.md` — capturing spec-method telemetry
- `doc/migration-2.0.md` — what changed from 1.x
