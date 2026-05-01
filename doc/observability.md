# Observability

What you have available for inspecting a running Flutter MCP instance:
logging, system status / health, performance metrics, security audit,
and resource leak tracking.

## Logging

Flutter MCP uses the standard Dart [`logging`](https://pub.dev/packages/logging)
package, namespaced under `flutter_mcp.<component>`.

```dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:logging/logging.dart';

// Configure once during app start.
FlutterMcpLogging.configure(
  level: Level.INFO,
  enableDebugLogging: false,   // true → root level becomes Level.FINE
);

// Optional: get a logger for your own component.
final log = FlutterMcpLogging.createLogger('demo_app');
//        Logger('flutter_mcp.demo_app')

log.info('starting up');
log.warning('low memory');
log.severe('failed to connect: $error');
```

`FlutterMcpLogging.configure` writes a single line to `stderr` per
record, formatted as
`[<timestamp>] [<level>] <loggerName>: <message>`. If a record carries
an `error` or `stackTrace`, those are appended on subsequent lines.

Convenience extensions on `Logger` (when `flutter_mcp.dart` is
imported): `debug` → `fine`, `warn` → `warning`, `error` → `severe`,
`trace` → `finest`.

To plug in your own sink (file, structured JSON, telemetry SDK), bypass
`configure` and listen to `Logger.root.onRecord` directly — the rest of
the package only emits records, it does not own the sink.

---

## System status — `getSystemStatus()`

```dart
final status = FlutterMCP.instance.getSystemStatus();
```

Returns a snapshot map. Top-level keys (always present after `init`):

| Key | Type | Notes |
|---|---|---|
| `initialized` | `bool` | `false` shape used before `init`; in that case only `platformName` / `platformFeatures` / `timestamp` are populated. |
| `clients`, `servers`, `llms` | `int` | Counts only. |
| `clientsStatus`, `serversStatus`, `llmsStatus` | `Map` | Per-manager `getStatus()` output. |
| `backgroundServiceRunning` | `bool` | From `PlatformServices`. |
| `schedulerRunning` | `bool` | From `MCPScheduler`. |
| `scheduler` | `Map` | `{running, jobCount, activeJobCount}`. |
| `pluginsCount` | `int` | Registered plugins. |
| `registeredResourcesCount` | `int` | Live entries in the resource manager. |
| `platformName`, `platformFeatures` | `String` / `Map<String, bool>` | From `PlatformUtils`. |
| `circuitBreakers` | `Map` | `{<name>: {state, failureCount}}`. |
| `cacheStats` | `Map` | LLM response semantic cache sizes + hit rates. |
| `diagnostics` | `Map` | `DiagnosticUtils.collectSystemDiagnostics(this)` — runtime info, init errors, etc. |

Optional / conditional keys:

| Key | When present |
|---|---|
| `memory` | `MCPConfig.highMemoryThresholdMB` was set. `{currentUsageMB, peakUsageMB, thresholdMB}` |
| `performanceMetrics` | `MCPConfig.enablePerformanceMonitoring == true`. Shape below. |

### `performanceMetrics` shape

`PerformanceMonitor.getMetricsSummary()`:

```
{
  'counters': { '<name>': <int>, ... },
  'timers':   { '<name>': {avg_ms, min_ms, max_ms, count, success_rate}, ... },
  'resources':{ '<name>': {current, avg, peak, capacity}, ... },
}
```

Resource sample names (recorded by `MemoryManager`):
- `memory.usageMB`

Timer sample names depend on what runs; the high-level Flutter MCP
methods record under `client.create`, `server.create`, and
`operation.<context>` where `<context>` is the value passed to
`EnhancedErrorHandler.handleError`. There is no fixed allow-list —
`timers.keys` enumerates whatever has been observed.

---

## Health

### Component health — one-off

```dart
final r = await FlutterMCP.instance.getComponentHealth('client_abc');
//   componentId follows '<kind>_<id>': 'client_<id>', 'server_<id>', 'llm_<id>'
// r.status: MCPHealthStatus.healthy | degraded | unhealthy
```

Recognised prefixes: `client_`, `server_`, `llm_`. Anything else
returns `unhealthy` with `'Unknown component: ...'`.

### Aggregate snapshot — `getSystemHealth()`

```dart
final h = await FlutterMCP.instance.getSystemHealth();
// {
//   'timestamp': ISO8601,
//   'overall':   'healthy' | 'degraded' | 'unhealthy',
//   'components': {
//     'client_<id>': {'status': '...', 'message': '...'},
//     'server_<id>': {...},
//     'llm_<id>':    {...},
//   },
// }
```

`overall` is `unhealthy` if any component is unhealthy, `degraded` if
any are degraded, otherwise `healthy`.

### Stream

```dart
final sub = FlutterMCP.instance.healthStream.listen((event) {
  // MCPHealthCheckResult — per-component live updates from HealthMonitor
});
```

---

## Performance metrics

Two layers:

1. **`PerformanceMonitor.instance`** — the lower-level singleton used
   internally. `recordResourceUsage`, `startTimer` / `stopTimer`,
   `incrementCounter`, `getMetricsSummary`. Surfaces through
   `getSystemStatus()['performanceMetrics']` when monitoring is enabled.

2. **`EnhancedPerformanceMonitor`** (available as
   `FlutterMCP.instance.enhancedPerformanceMonitor`, non-null only
   after `init`) — adds aggregation windows
   (`AggregationConfig`/`AggregationType`), thresholds
   (`ThresholdConfig`/`ThresholdLevel`), and trend analysis
   (`TrendInfo`/`TrendDirection`).

Enable monitoring on init:

```dart
await FlutterMCP.instance.init(MCPConfig(
  appName: 'app', appVersion: '1.0.0',
  enablePerformanceMonitoring: true,
  enableMetricsExport: false,             // optional file/web export
  metricsExportPath: '/path/metrics.json',
  highMemoryThresholdMB: 256,             // memory subsection in status
));
```

---

## Security audit

```dart
final audit = FlutterMCP.instance.securityAuditManager;   // null before init
audit?.checkAuthenticationAttempt('user-1', success: false);
audit?.checkDataAccess('user-1', 'documents', 'read');

// All audit events
final events = audit?.getAllAuditEvents(limit: 100);

// Per-user
final mine = audit?.getUserAuditEvents('user-1');

// Aggregated report
final report = audit?.generateSecurityReport();
// → {totalEvents, events24h, events7d, failedLogins24h,
//    suspiciousEvents24h, lockedOutUsers, activeSessions,
//    highRiskUsers, eventsByType, topRiskyUsers}
```

Configure thresholds + lockout policy through
`SecurityAuditManager.instance.initialize(policy: SecurityPolicy(...))`
or by passing a `SecurityPolicy` to `updatePolicy`.

Audit events also publish on the `EventSystem` topic
`security.event` (and `security.alert` for high-risk cases) so app code
can react in real time.

---

## Resource leak tracking

`EnhancedResourceCleanup.instance` keeps a registry of every Flutter
MCP-created resource (clients, servers, LLM adapters, plugins, scheduler
jobs, …). Three convenience methods on the facade:

```dart
final stats = FlutterMCP.instance.getResourceStatistics();
// {totalAllocations, currentlyAllocated, leakedCount, memoryEstimateMB, ...}

FlutterMCP.instance.checkForResourceLeaks();
// Runs the leak detector now (logs warnings; does not throw).

final details = FlutterMCP.instance.getResourceDetails();
// List<Map> — one entry per live resource: key, type, age, stack trace
```

Resources are auto-disposed by `shutdown()`, but explicit cleanup
helpers (`clientManager.closeClient(id)`,
`pluginRegistry.unregisterPlugin(name)`) deregister them on the way
out. Anything created outside the manager flow is your responsibility.

---

## Event system

`EventSystem.instance` (and `TypedEventSystem.instance`) provide
internal pub/sub. Topics emitted by Flutter MCP that you may want to
listen to:

| Topic | Payload | When |
|---|---|---|
| `mcp.shutdown` | `{timestamp}` | `FlutterMCP.shutdown()` reaches teardown |
| `client.connected` / `client.disconnected` | `{clientId, timestamp}` | Manager lifecycle |
| `server.started` / `server.stopped` | `{serverId, timestamp}` | Manager lifecycle |
| `circuit_breaker.opened` / `circuit_breaker.closed` | `{operation}` | When `llm.chat` etc. trip / recover |
| `oauth.open_browser` | `{llmId, url}` | App should launch the URL during OAuth flow |
| `oauth.authorization_requested` | `{llmId, state, authUrl}` | OAuth flow needs user attention |
| `security.event` | `SecurityEvent` | Every audit event |
| `security.alert` | `SecurityAlert` | High-risk events |
| `background.started` / `background.stopped` | platform-specific stats | Native background service callbacks |
| `background.task.completed` / `background.task.error` | `{platform, executionCount, ...}` | Background task lifecycle |

Subscribe:

```dart
EventSystem.instance.subscribeTopic('oauth.open_browser', (payload) {
  launchUrl(Uri.parse(payload['url'] as String));
});
```

---

## Diagnostics for support tickets

For one-shot snapshots that bundle everything:

```dart
final status   = FlutterMCP.instance.getSystemStatus();
final health   = await FlutterMCP.instance.getSystemHealth();
final leaks    = FlutterMCP.instance.getResourceStatistics();
final details  = FlutterMCP.instance.getResourceDetails();

print(jsonEncode({
  'status': status,
  'health': health,
  'leaks':  leaks,
  'resources': details,
}));
```

These four together capture configuration, live counts, per-component
health, and the resource-manager state — enough for most support
investigations without leaking app payload data.
