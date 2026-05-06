## [2.0.2] - 2026-05-06 - Web JS interop modernization + dead code removal

Restores pub.dev platform support — pana 2.0.1 reported 0/6 platforms (80 errors) because two web modules referenced the deprecated `dart:js_util` `hasProperty` / `callMethod` shape, and two unreachable lib files dragged in 70+ more violations of the same pattern.

### Fixed
- `WebBackgroundService._supportsWebWorkers` — replaces `hasProperty(window, 'Worker')` with a direct probe (`Worker('data:application/javascript,')` then `terminate()`); the constructor throws on the `universal_html` server stub, so the existing try/catch already returns `false` correctly off-web.
- `WebNotificationManager._isSupported` — replaces `hasProperty(window, 'Notification')` with a static-getter probe (`Notification.permission`).
- `WebNotificationManager._handleNotificationTap` — replaces `callMethod(window, 'focus', [])` with `window.focus()` (universal_html's `Window` already exposes the typed method).
- `package:universal_html/js_util.dart` import dropped from both web modules.

### Removed
- `lib/src/platform/web/enhanced_web_platform.dart` and `lib/src/platform/web/web_platform_improvements.dart` (plus the latter's test). Neither was reachable from the package barrel or any other lib entry, but pana still scanned them and counted their `hasProperty` / `callMethod` / `getProperty` call sites toward the platform-support score. Removing them collapses the analyser report to zero errors without losing any reachable behaviour — the active `WebBackgroundService` / `WebNotificationManager` / `WebMemoryMonitor` cover the same ground.

### Changed
- `pointycastle` constraint bumped from `^3.9.1` to `^4.0.0` so the package resolves against the current stable; encryption tests pass against the new line.
- `pubspec.yaml` `description` shortened to fit pub.dev's 180-character recommendation.

## [2.0.1] - 2026-05-04 - Pin mcp_llm 2.1.0 (prompt caching + cache fixes)

- Bumps `mcp_llm` to `^2.1.0` so consumers receive the prompt-caching fixes (empty text-block guard, 4-breakpoint cap, Gemini cachedContent ↔ systemInstruction conflict strip) baked into mcp_llm 2.1.0.

## [2.0.0] - 2026-05-01 - MCP spec compliance + 2025-11-25 alignment

Big-Bang upgrade aligning Flutter MCP with the `mcp_client` / `mcp_server`
/ `mcp_llm` 2.0 release wave. Adds support for protocol revisions
`2025-06-18` and `2025-11-25` (in addition to the previously supported
`2024-11-05` and `2025-03-26`); negotiation is automatic per session.

### Breaking
- **JSON-RPC batching surface removed.** `processBatch`, `batchChat`,
  `getBatchStatistics`, `EnhancedBatchManager`, `BatchConfig`,
  `BatchRequestPriority`, and the corresponding API doc entries are
  gone. JSON-RPC batching was dropped from the spec in 2025-06-18 and
  `mcp_llm` 2.0 no longer ships a `BatchRequestManager`. Iterate with
  `Future.wait`, or use `mcp_llm`'s `ParallelExecutor` / `MultiLlm`.
- **Sampling direction reversed.** `Client.createMessage(...)` (a 1.x
  bug — sampling is server-initiated per spec) is removed upstream.
  Servers initiate via `Server.requestClientSampling`, surfaced here as
  `FlutterMCP.requestClientSampling`. Clients fulfil via
  `Client.onSamplingRequest`; Flutter MCP wires this automatically to
  the host LLM when `MCPClientConfig.autoBridgeSampling` is true
  (default).
- **Roots direction reversed.** `Client.listRoots()` is removed. Servers
  call `requestClientRoots`; clients configure roots via
  `MCPClientConfig.initialRoots` and the new `addClientRoot` /
  `removeClientRoot` proxies.
- **Cancellation is a notification.** `cancelOperation` (non-spec
  request) is replaced by spec `notifications/cancelled` on the
  underlying client.
- **`client.healthCheck()` removed.** The non-spec `health/check`
  JSON-RPC method is gone. Use the `HealthMonitor` for in-process
  monitoring or expose `/health` at the transport layer.
- **JSON-RPC `auth/*` removed.** Replaced by RFC 9728 OAuth Protected
  Resource Metadata at `/.well-known/oauth-protected-resource`.
  Configure via `MCPServerConfig.protectedResource`
  (new `MCPProtectedResourceConfig` value class).
- **List-changed notifications** use the spec names
  (`notifications/{tools,resources,prompts}/list_changed`).

### Added
- `MCPClientConfig.initialRoots`, `autoBridgeSampling`,
  `elicitationHandler`, `listRootsHandler`.
- `MCPServerConfig.protectedResource` and `MCPProtectedResourceConfig`.
- `FlutterMCP.setElicitationHandler(handler)` — global fallback handler
  for `elicitation/create` requests.
- `FlutterMCP.addClientRoot` / `removeClientRoot` / `getClientRoots`.
- `FlutterMCP.requestClientSampling` / `requestClientRoots` /
  `requestClientElicitation` — server-initiated request proxies for use
  inside tool handlers.
- `FlutterMCP.addServerCompletion` / `removeServerCompletion` —
  `completion/complete` handler registration; the 2025-06-18 `context`
  field (previously-resolved arguments) is forwarded to the handler.
- Re-exports: `Root` (from `mcp_client`), `CompletionHandler` (from
  `mcp_server`).

### Spec features now reachable
- Spec metadata fields on `Tool` / `Resource` / `Prompt` /
  `ResourceTemplate`: `title`, `icons`, `_meta`, `outputSchema`.
- `CallToolResult.structuredContent` — typed tool output (2025-06-18+).
- `ResourceLinkContent` — `resource_link` content type.
- `AudioContent` (2025-03-26+).
- `MCP-Protocol-Version` HTTP header negotiation (handled by the
  underlying transports).

### Documentation
- New: `docs/advanced/sampling.md`, `docs/advanced/elicitation.md`,
  `docs/advanced/structured-tool-output.md`.
- Rewritten: `docs/troubleshooting/migration.md` (1.x → 2.0 section),
  `docs/security/oauth-integration.md` (RFC 9728 server-side block).
- Removed: `docs/advanced/batch-processing.md` (obsolete — wire
  protocol gone).
- Stripped literal `1.0.0` version examples from README and docs.

---

## [1.0.6] - 2026-04-28

### Changed
- README cleanup — removed "MCP Family" section, installation block, and donation links.

---

## 1.0.5

### Bug Fixes

* **Linux Compatibility**
    * Fixed appindicator library detection for modern Linux distributions
    * Added fallback support for both ayatana-appindicator3 and legacy appindicator3

## 1.0.4

### Improvements

* **Dependency Updates**
    * Updated to use latest versions of mcp_client (1.0.1), mcp_server (1.0.2), and mcp_llm (1.0.2)
    * All underlying MCP packages now achieve 100% MCP 2025-03-26 standard compliance
    * Improved compatibility with Python MCP SDK for cross-language interoperability

* **MCP Standard Compliance**
    * Enhanced validation test coverage for all MCP features
    * Fixed Content type handling in client verification code
    * Improved advanced MCP feature testing including OAuth, dynamic tools, and resource subscriptions
    * All transports (STDIO, SSE, StreamableHTTP) now pass 100% of validation tests

* **Type Safety**
    * Fixed type conversion issues with Content objects
    * Added safe text extraction methods for better compatibility
    * Improved null safety throughout the codebase

## 1.0.3

### Bug Fixes

* **Authentication**
    * Fixed compatibility with mcp_server StreamableHTTP Bearer token validation
    * Resolved auth token handling issues for StreamableHTTP transport
    * Fixed Swift compiler warnings in macOS implementation

* **Code Quality**
    * Fixed unused variable warnings in Swift codebase
    * Improved type safety for notification manager implementations
    * Enhanced error handling for authentication failures

## 1.0.2

### Bug Fixes

* **Transport Configuration**
    * Fixed transport configuration options not being passed to underlying mcp_server/mcp_client packages
    * Fixed StreamableHTTP session termination issues
    * Fixed constructor syntax error in MCPClientConfig
    * Added missing shelf dependency
    * Made transportType explicitly required to prevent configuration errors

* **Documentation**
    * Added Transport Configuration documentation to clarify proper usage

## 1.0.1 

### Bug Fixes and Security Improvements

* **Security Enhancements**
    * Replaced XOR encryption with HMAC-SHA256 based stream cipher
    * Added encryption timeout and error handling
    * Improved key generation and management

* **Platform Compatibility Fixes**
    * Android: Migrated from deprecated FlutterMain to FlutterLoader
    * macOS: Replaced deprecated NSUserNotification with UserNotifications framework (10.14+)
    * Added legacy support for older macOS versions

* **Event System Improvements**
    * Fixed hanging issues in EnhancedTypedEventSystem
    * Added timeout protection for middleware processing
    * Improved async event handling to prevent deadlocks
    * Restored full functionality of type-safe event system
    * **Event System Cleanup**
        * Removed dependency on EnhancedTypedEventSystem in core EventSystem
        * Made EventSystem fully self-contained without external dependencies
        * Integrated typed event support directly into EventSystem
        * Preserved all improvements (single lock, memory leak prevention, statistics)
        * Simplified API by removing temporary workarounds

* **Code Quality**
    * Fixed null safety issues in Android background service
    * Improved error handling across all platforms
    * Enhanced logging and diagnostics

---

## 1.0.0 - 2025-03-26

### First Stable Release

Complete rewrite to support MCP 2025-03-26 specification with modern API design.

### Breaking Changes

* **Complete API Redesign**
    * Migrated to factory-based creation patterns for all MCP components
    * Introduced configuration objects (McpClientConfig, McpServerConfig)
    * Implemented Result<T, E> pattern for better error handling
    * Removed all deprecated methods and legacy APIs

* **New Factory Methods**
    * `McpClient.createClient()` replaces direct Client constructor
    * `McpServer.createServer()` replaces direct Server constructor
    * Transport creation now uses factory methods with Result types

* **Enhanced Features**
    * OAuth 2.1 authentication support
    * Batch processing with 40-60% performance improvement
    * Health monitoring and capability management
    * Circuit breaker pattern for resilience
    * Real-time performance monitoring

### Features

* **Core MCP Integration**
    * Full MCP Client v1.0.0 support
    * Full MCP Server v1.0.0 support
    * Full MCP LLM v1.0.0 support with all 2025-03-26 features
    * Seamless multi-client and multi-server management

* **Platform Services**
    * Cross-platform background execution
    * Native notifications on all platforms
    * System tray support for desktop
    * Secure credential storage
    * Advanced job scheduling

* **Developer Experience**
    * Comprehensive plugin system
    * Dynamic plugin loading
    * Event-driven architecture
    * Advanced diagnostics and logging
    * Memory and performance optimization

### Platform Support

* Android (API 21+)
* iOS (12.0+)
* macOS (10.15+)
* Windows (10+)
* Linux
* Web (partial support)

---

## Previous Releases

### 0.1.0

* API Improvements and Breaking Changes
    * Renamed methods to be more descriptive and consistent
        * `createLlm` split into `createLlmServer` and `createLlmClient` for better clarity
        * `integrateServerWithLlm` changed to `addMcpServerToLlmServer`
        * `integrateClientWithLlm` changed to `addMcpClientToLlmClient`
    * Updated return types for better type safety
        * `createLlmServer` now returns `(String llmId, String llmServerId)` tuple
        * `createLlmClient` now returns `(String llmId, String llmClientId)` tuple
    * Parameter changes for consistency and clarity
        * Removed `useCache` parameter from `chat` method
    * Enhanced documentation with clearer examples
    * Added explicit dependency information in README.md

* Enhanced Testing Features
    * Improved memory leak detection and testing
    * Enhanced circuit breaker tests for better fault tolerance
    * Timeout recovery testing improvements
    * Added robust lifecycle management tests
    * Fixed timing-dependent tests for greater reliability

* Performance Improvements
    * Optimized memory usage during LLM operations
    * Enhanced error recovery mechanisms
    * Improved concurrent operations handling
    * Better resource management across platforms

### 0.0.2

* Bug fixes and improvements
    * Fixed issues with background service initialization
    * Improved error handling and logging
    * Enhanced performance monitoring features
    * Updated documentation for better clarity
  
### 0.0.1

* Initial release
    * Support for MCP client, server, and LLM integration
    * Platform features: background service, notifications, system tray
    * Secure storage integration
    * Lifecycle management
    * Scheduled tasks