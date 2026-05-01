# Migrating from 1.x to 2.0

Flutter MCP 2.0 aligns with the `mcp_client` / `mcp_server` / `mcp_llm`
2.0 release wave. It adds support for protocol revisions `2025-06-18`
and `2025-11-25` (in addition to `2024-11-05` and `2025-03-26`); the
session ends up on the highest version both peers understand.

This page lists every breaking change. The mechanical migration
checklist is at the bottom.

---

## 1. JSON-RPC batching surface removed

`processBatch`, `batchChat`, `getBatchStatistics`,
`EnhancedBatchManager`, `BatchConfig`, and `BatchRequestPriority` are
gone. Spec `2025-06-18` dropped the JSON-RPC batch frame, so
`mcp_llm` 2.0 no longer ships a `BatchRequestManager`.

```dart
// 1.x
final results = await FlutterMCP.instance.processBatch<String>(
  llmId: llmId,
  requests: [() async => '...', () async => '...'],
);

// 2.0 — fan out yourself
final results = await Future.wait([
  someFuture1(),
  someFuture2(),
]);
```

For LLM-level concurrency, use `mcp_llm`'s `ParallelExecutor` or
`MultiLlm` directly.

---

## 2. Sampling direction reversed

In 1.x the `Client` exposed a (broken) `createMessage(...)` request.
The spec defines `sampling/createMessage` as **server-initiated** — the
server asks the client to fulfil a prompt with the host LLM. In 2.0:

- **Client side** — register a handler with
  `Client.onSamplingRequest(...)`. Flutter MCP wires this automatically
  to the host LLM when `MCPClientConfig.autoBridgeSampling` is `true`
  (default). Set `false` to opt out, or pass an explicit
  `ClientCapabilities` without `sampling` to suppress the capability
  altogether.
- **Server side** — initiate sampling via
  `Server.requestClientSampling(sessionId, params)`, surfaced on
  `FlutterMCP` as
  `requestClientSampling({serverId, sessionId, params, timeout})`.

See `doc/spec-features.md` for the full sampling / elicitation / roots
flow.

---

## 3. Roots direction reversed

Same shape change: `Client.listRoots()` is gone; the server requests
roots from the client.

```dart
// 1.x — client-initiated (broken)
final roots = await mcpClient.listRoots();

// 2.0 — configure on the client
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
FlutterMCP.instance.addClientRoot(
  clientId, Root(uri: 'file:///tmp', name: 'tmp'));

// 2.0 — server reads roots via requestClientRoots
final roots = await FlutterMCP.instance.requestClientRoots(
  serverId: serverId,
  sessionId: sessionId,
);
```

---

## 4. Cancellation is a notification

`client.cancelOperation(opId)` (which sent a non-spec `cancel` request)
is removed. Use `Client.notifyCancelled(requestId, reason: '...')` from
the underlying `mcp_client` directly — it fires the spec
`notifications/cancelled` notification.

---

## 5. Logging method name corrected

`setLoggingLevel` now sends spec method `logging/setLevel`
(camelCase). The previous `logging/set_level` is gone — any custom
server handlers that listened on that name will not receive requests.

---

## 6. `client.healthCheck()` removed

The non-spec `health/check` JSON-RPC method has been removed from both
client and server. Expose health via your transport (e.g. an HTTP
`/health` endpoint) or use Flutter MCP's local `HealthMonitor` /
`getSystemHealth()` (see `doc/observability.md`).

---

## 7. JSON-RPC `auth/*` removed; OAuth Resource Server (RFC 9728)

The non-spec `auth/authorize` / `auth/token` / `auth/refresh` /
`auth/revoke` JSON-RPC methods are removed. Spec `2025-06-18` defines
the MCP server as an OAuth 2.0 Resource Server (RFC 9728); discovery is
served at `/.well-known/oauth-protected-resource`. Configure via
`MCPServerConfig.protectedResource`:

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
    ),
  ),
);
```

Token issuance and refresh remain the client app's responsibility.

---

## 8. List-changed notifications use spec names

`tools/listChanged` → `notifications/tools/list_changed`; same for
resources and prompts. Existing client code that listened on the legacy
names will not see updates.

The typed helpers `Client.onToolListChanged` /
`onResourceListChanged` / `onPromptListChanged` already resolve to the
new names — most callers won't be affected.

---

## 9. New capabilities you may want to advertise

- **Elicitation** (`2025-06-18+`) — server requests user input from the
  client.

  ```dart
  FlutterMCP.instance.setElicitationHandler((params) async {
    final form = await showElicitationForm(params);
    return form.cancelled
        ? {'action': 'cancel'}
        : {'action': 'accept', 'content': form.values};
  });
  ```

- **Completion** (`completion/complete`) — argument autocompletion for
  prompts and resource templates:

  ```dart
  FlutterMCP.instance.addServerCompletion(
    serverId: serverId,
    refType: 'prompt',
    refKey: 'analyze',
    handler: (ref, argument, context) async => {
      'values': suggestionsFor(argument['value'] as String),
    },
  );
  ```

- **Structured tool output** (`2025-06-18+`) — set
  `Tool.outputSchema` and return `CallToolResult.structuredContent`
  alongside (or instead of) text content.

---

## Mechanical migration checklist

1. Bump `flutter_mcp` to `^2.0.0` in `pubspec.yaml` (transitively
   brings `mcp_*` 2.x).
2. Remove all references to `processBatch`, `batchChat`, and
   `getBatchStatistics`.
3. Remove any client-side calls to `createMessage` / `listRoots` /
   `cancelOperation` / `healthCheck`.
4. Replace `auth/*` JSON-RPC client code with HTTP Bearer + RFC 9728
   discovery (token lifecycle is owned by your auth client / OAuth
   library).
5. If you handle list-changed notifications manually, switch the
   subscription names to the
   `notifications/{tools,resources,prompts}/list_changed` forms.
6. (Optional) Opt into elicitation / structured tool output / completion
   surface where useful.

## See also

- `doc/spec-features.md` — full Phase 2 capability surface
- `doc/transports.md` — transport configuration
- [`mcp_client` 2.0 changelog](https://pub.dev/packages/mcp_client/changelog)
- [`mcp_server` 2.0 changelog](https://pub.dev/packages/mcp_server/changelog)
- [`mcp_llm` 2.0 changelog](https://pub.dev/packages/mcp_llm/changelog)
