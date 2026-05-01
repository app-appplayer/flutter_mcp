# Architecture

Flutter MCP wraps `mcp_client`, `mcp_server`, and `mcp_llm` 2.x in a
singleton-fronted, manager-based runtime and adds native platform
integration. This page describes how the pieces fit together so you can
reason about responsibilities and lifetimes when integrating the package.

## High-level layout

```
┌──────────────────────────────────────────────────────────────┐
│                    FlutterMCP.instance                       │  Public facade
└──────────────────────────────────────────────────────────────┘
        │                │                │                │
        ▼                ▼                ▼                ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│MCPClientMgr  │ │MCPServerMgr  │ │ MCPLlmMgr    │ │PlatformSvcs  │  Manager layer
│  + Client    │ │  + Server    │ │  + LlmClient │ │  (BG/Notif/  │
│  + Transport │ │  + Transport │ │  + LlmServer │ │   Tray/SecStg│
└──────────────┘ └──────────────┘ └──────────────┘ │   Lifecycle) │
        │                │                │       └──────────────┘
        ▼                ▼                ▼               │
┌──────────────┐ ┌──────────────┐ ┌──────────────┐        ▼
│  mcp_client  │ │  mcp_server  │ │   mcp_llm    │ FlutterMcpPlatform
│     2.x      │ │     2.x      │ │     2.x      │ (method channel)
└──────────────┘ └──────────────┘ └──────────────┘
```

Cross-cutting components hang off the same singleton:

- **`MCPScheduler`** — interval / one-shot / conditional jobs.
- **`EnhancedPluginRegistry`** — typed plugin registration (tool /
  resource / prompt / background / notification / tray plugins).
- **`HealthMonitor`** — component-level health + a `healthStream`.
- **`MCPOAuthManager`** — OAuth 2.1 credential cache (per-LLM).
- **`SecurityAuditManager`** + **`EncryptionManager`** — audit log
  and symmetric crypto for app-level secrets.
- **`EventSystem`** — typed and topic-based pub/sub for internal events.
- **`ResourceManager`** + **`EnhancedResourceCleanup`** — leak-detecting
  cleanup registry (everything created through `FlutterMCP` registers a
  disposer here).

All of the above are reachable through getters on `FlutterMCP.instance`
(e.g. `instance.scheduler`, `instance.platformServices`).

## Source layout

```
lib/
├── flutter_mcp.dart               // Public facade
├── flutter_mcp_method_channel.dart
├── flutter_mcp_platform_interface.dart
├── flutter_mcp_web.dart
└── src/
    ├── core/                      // Manager classes
    │   ├── client_manager.dart
    │   ├── server_manager.dart
    │   ├── llm_manager.dart
    │   ├── scheduler.dart
    │   └── base_manager.dart
    ├── managers/                  // Per-resource info records
    │   ├── client_info.dart
    │   ├── server_info.dart
    │   └── llm_info.dart
    ├── platform/                  // Native integration
    │   ├── platform_services.dart
    │   ├── platform_factory.dart
    │   ├── lifecycle_manager.dart
    │   ├── background/            //   Android / iOS / desktop / web
    │   ├── notification/          //   Android / iOS / desktop / web
    │   ├── storage/               //   Secure storage + web fallback
    │   └── tray/                  //   macOS / Windows / Linux
    ├── plugins/
    │   ├── plugin_system.dart
    │   └── enhanced_plugin_system.dart
    ├── security/
    │   ├── oauth_manager.dart
    │   ├── credential_manager.dart
    │   ├── security_audit.dart
    │   └── encryption_manager.dart
    ├── events/                    // Typed + topic event bus
    ├── config/                    // MCPConfig + ConfigLoader
    ├── monitoring/                // HealthMonitor
    ├── performance/               // EnhancedPerformanceMonitor
    ├── metrics/                   // Typed metric value classes
    ├── models/                    // Platform-channel message classes
    ├── types/                     // Health-check result types
    └── utils/                     // Exceptions, logger, memory, …
```

## Lifecycle

```
init(MCPConfig)
   │
   ├── _initializeManagers
   │     ├── _platformServices.initialize(config)
   │     ├── _clientManager.initialize()
   │     ├── _serverManager.initialize()
   │     ├── _llmManager.initialize()
   │     ├── _scheduler.initialize()
   │     ├── _pluginRegistry.initialize()
   │     ├── _healthMonitor.start()
   │     ├── (optional) _oauthManager / _encryptionManager / _securityAuditManager
   │
   ├── _initializePluginRegistry(config.pluginConfigurations)
   │
   └── (if config.autoStart) startServices() → _startConfiguredComponents
                                ├── auto-start LLM clients / servers
                                └── auto-start MCP clients / servers
```

`shutdown()` walks the lifecycle in reverse: cleanup callbacks run from
the resource manager first, the plugin registry shuts down, then each
manager closes its registered objects, then `PlatformServices.shutdown()`
unwinds the native side.

## Identity model

Everything created through Flutter MCP is referenced by an opaque ID
string (e.g. `client_169...123`). The IDs are returned from the
factory methods on `FlutterMCP.instance` and consumed by every other
method that operates on that resource:

```dart
final serverId   = await FlutterMCP.instance.createServer(...);
final clientId   = await FlutterMCP.instance.createClient(...);
final (llmId, llmClientId) = await FlutterMCP.instance.createLlmClient(...);

// Later
await FlutterMCP.instance.connectClient(clientId);
await FlutterMCP.instance.callTool(clientId, 'echo', {'msg': 'hi'});
await FlutterMCP.instance.chat(llmId, 'hello', llmClientId: llmClientId);
```

Inside the managers each ID maps to an info record
(`ClientInfo`, `ServerInfo`, `LlmInfo`) holding the live MCP object plus
metadata (transport, default flags, association maps).

## Multiple `MCPLlm` instances

`MCPLlmManager` can host more than one `mcp_llm.MCPLlm` registry behind
`createMcpLlmInstance(instanceId)`. This is useful when you want
isolated provider sets — e.g. one set for end-user prompts, another for
internal background jobs:

```dart
FlutterMCP.instance.createMcpLlmInstance('user');
FlutterMCP.instance.createMcpLlmInstance('background');

FlutterMCP.instance.registerLlmProvider(
  'openai', OpenAiProviderFactory(), mcpLlmInstanceId: 'user');
FlutterMCP.instance.registerLlmProvider(
  'claude', ClaudeProviderFactory(), mcpLlmInstanceId: 'background');
```

`createLlmClient(providerName: ..., mcpLlmInstanceId: ...)` then routes
to the chosen registry.

## Spec capability mapping

| Spec method | Direction | Flutter MCP entry point |
|---|---|---|
| `initialize` | client → server | Wired automatically by `Client.connect` |
| `tools/call` | client → server | `callTool(clientId, name, args)` |
| `tools/list`, `resources/list`, `prompts/list` | client → server | Available on the underlying `Client` |
| `sampling/createMessage` (`2025-03-26+`) | server → client | Auto-bridged to host LLM (`autoBridgeSampling: true`); server side calls `requestClientSampling` |
| `roots/list` (`2024-11-05+`) | server → client | `MCPClientConfig.initialRoots`, `addClientRoot`, `removeClientRoot`; server side calls `requestClientRoots` |
| `elicitation/create` (`2025-06-18+`) | server → client | `setElicitationHandler` or `MCPClientConfig.elicitationHandler`; server side calls `requestClientElicitation` |
| `completion/complete` | client → server | `addServerCompletion(serverId, refType, refKey, handler)` |
| `notifications/{tools,resources,prompts}/list_changed` | server → client | Forwarded by the underlying `Client` |
| OAuth Resource Server (RFC 9728) | HTTP discovery | `MCPServerConfig.protectedResource` publishes `/.well-known/oauth-protected-resource` |
| `MCP-Protocol-Version` HTTP header (`2025-06-18+`) | HTTP transports | Sent automatically by `mcp_client` once protocol is negotiated |

See `doc/spec-features.md` for the full Phase 2 surface.

## Where to look next

- **Wiring the platform side** → `doc/platform-services.md`
- **Transport-by-transport setup** → `doc/transports.md`
- **Sampling / elicitation / roots / completion / OAuth Resource Server**
  → `doc/spec-features.md`
- **Plugins (tool / resource / prompt / background / notification / tray)**
  → `doc/plugins.md`
- **Logging, health, metrics, audit** → `doc/observability.md`
- **Upgrading from 1.x** → `doc/migration-2.0.md`
