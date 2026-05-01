# Plugins

Flutter MCP ships a typed plugin system that sits on top of the
manager runtime. A plugin is an object implementing one of six
interfaces; you register it with `FlutterMCP.instance.registerPlugin`
and the plugin registry exposes it through helper methods.

The `EnhancedPluginRegistry` (the default registry used by the
singleton) adds version validation, sandboxing hints, and dependency
resolution on top of the base registry.

## Plugin interfaces

All plugins extend `MCPPlugin`:

```dart
abstract class MCPPlugin {
  String get name;
  String get version;
  String get description;

  Future<void> initialize(Map<String, dynamic> config);
  Future<void> shutdown();
}
```

Six concrete subtypes:

| Interface | Purpose |
|---|---|
| `MCPToolPlugin` | Custom tool implementation: `execute(args)` + `getToolMetadata()` |
| `MCPResourcePlugin` | Resource provider: `getResource(uri, params)` + `getResourceMetadata()` |
| `MCPPromptPlugin` | Prompt template: `execute(args)` + `getPromptMetadata()` |
| `MCPBackgroundPlugin` | Long-running background task: `start()` / `stop()` / `isRunning` / `registerTaskHandler` |
| `MCPNotificationPlugin` | Custom notification stack: `showNotification(...)` / `hideNotification(id)` / `registerClickHandler` |
| `MCPTrayPlugin` | Custom tray adapter: `setIcon` / `setTooltip` / `setMenuItems` / `show` / `hide` / `isSupported` |

## Lifecycle

```
FlutterMCP.instance.registerPlugin(plugin, {config?})
   │
   ├── plugin.initialize(config)         // throws → registration aborts
   ├── registry stores plugin by (Type, name)
   └── ResourceManager.register(plugin.shutdown)

FlutterMCP.instance.unregisterPlugin(name)
   │
   └── plugin.shutdown()                  // errors are logged, never thrown
```

`registerPlugin` enforces:
- non-empty `plugin.name` (throws `MCPValidationException`)
- name uniqueness within the same plugin type
- `initialize` must complete; if it throws, the plugin is **not**
  registered and the exception is rethrown wrapped in
  `MCPPluginException`.

## Building a tool plugin

```dart
class CalculatorTool extends MCPToolPlugin {
  @override String get name        => 'calculator';
  @override String get version     => '1.0.0';
  @override String get description => 'Adds two numbers.';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // Read config if you need it.
  }

  @override
  Future<void> shutdown() async {
    // Release resources.
  }

  @override
  Map<String, dynamic> getToolMetadata() => {
    'name': name,
    'description': description,
    'inputSchema': {
      'type': 'object',
      'properties': {
        'a': {'type': 'number'},
        'b': {'type': 'number'},
      },
      'required': ['a', 'b'],
    },
  };

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> args) async {
    final a = (args['a'] as num).toDouble();
    final b = (args['b'] as num).toDouble();
    return {'result': a + b};
  }
}
```

Register and call:

```dart
await FlutterMCP.instance.registerPlugin(CalculatorTool());

final result = await FlutterMCP.instance.executeToolPlugin(
  'calculator',
  {'a': 2, 'b': 3},
);   // → {'result': 5}
```

`executeToolPlugin` wraps the call with a 30-second timeout (override
via the `timeout:` argument) and a circuit breaker; failures surface as
`MCPPluginException`.

## Resource plugin

```dart
class WikiResource extends MCPResourcePlugin {
  @override String get name        => 'wiki';
  @override String get version     => '1.0.0';
  @override String get description => 'Local wiki pages.';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> shutdown() async {}

  @override
  Map<String, dynamic> getResourceMetadata() => {
    'name': name,
    'description': description,
    'uri': 'wiki://',
    'mimeType': 'text/markdown',
  };

  @override
  Future<Map<String, dynamic>> getResource(
      String uri, Map<String, dynamic> params) async {
    final body = await _readWikiPage(uri);
    return {
      'mimeType': 'text/markdown',
      'content': body,
    };
  }
}
```

Use:

```dart
final page = await FlutterMCP.instance.getPluginResource(
  'wiki', 'wiki://home', {});
```

## Prompt plugin

`getPromptMetadata()` should return a spec-shaped prompt definition;
`execute(args)` returns `{description, messages}` where `messages` is a
list of `{role, content}` entries.

## Background / notification / tray plugins

These plug into the platform layer but stay in pure Dart. They are
useful when you want behaviour that's not in `PlatformServices` (for
example, an additional notification rail backed by a third-party SDK).
The registry methods `startBackgroundPlugin(name)` /
`stopBackgroundPlugin(name)` / `showNotification(name, ...)` /
`updateTrayIcon(name, path)` / `setTrayMenuItems(name, items)` route to
the named plugin.

## Inspecting and managing plugins

```dart
final status = FlutterMCP.instance.pluginRegistryStatus;
// → {'pluginCount': 3, 'plugins': ['calculator', 'wiki', 'cron-reminder']}

// Unregister
await FlutterMCP.instance.unregisterPlugin('calculator');
```

Direct registry access is also possible via
`FlutterMCP.instance.pluginRegistry` (returns
`EnhancedPluginRegistry`). The base `MCPPluginRegistry` shape is
described in `lib/src/plugins/plugin_system.dart`; the enhanced
registry adds:

- `PluginVersion` parsing + compatibility checks against
  `VersionConstraint`
- `PluginSandboxConfig` for resource-quota declarations
- `PluginUpdateSuggestion` reports when a registered plugin lags a
  declared minimum version

## Auto-loading from configuration

```dart
await FlutterMCP.instance.init(MCPConfig(
  appName: 'app',
  appVersion: '1.0.0',
  autoLoadPlugins: true,
  pluginConfigurations: [
    PluginConfig(
      plugin: CalculatorTool(),
      config: {'precision': 6},
      targets: ['default'],          // route into named MCPLlm instances
    ),
  ],
));
```

When `autoLoadPlugins` is true the registry calls `registerPlugin`
during `init` for every entry of `pluginConfigurations`.

## LLM-side plugins (`mcp_llm`)

`mcp_llm` 2.x ships its own plugin system for tool / resource / prompt
plugins that run **on the LLM client**. Flutter MCP exposes adapters
in `lib/src/plugins/plugin_system.dart`:

- `LlmToolPluginAdapter` wraps `mcp_llm.ToolPlugin` as `MCPToolPlugin`
- `LlmResourcePluginAdapter` wraps `mcp_llm.ResourcePlugin` as
  `MCPResourcePlugin`
- `LlmPromptPluginAdapter` wraps `mcp_llm.PromptPlugin` as
  `MCPPromptPlugin`

Use these when an `mcp_llm` plugin should also be reachable through the
flutter_mcp registry. The reverse direction (Flutter MCP plugin
exposed to the LLM) is handled by `_pluginIntegrator` inside
`MCPLlmManager` and triggered automatically when
`MCPConfig(registerMcpPluginsWithLlm: true)`.

## Errors

| Exception | When |
|---|---|
| `MCPValidationException` | Empty plugin name on register / unregister, or empty resource URI |
| `MCPPluginException` | Plugin lookup failed, plugin's own method threw, or `initialize` failed |
| `MCPException` | Plugin not found in registry (e.g. `executeToolPlugin('nope', ...)`) |
