# Flutter MCP Test Suite

Test suite for Flutter MCP 2.0. Covers the public API, the manager
runtime, transport scaffolding, and the platform integrations that ship
with the package.

## Layout

The suite is split between VM-only tests (which run with
`flutter test`) and browser tests (which run with
`flutter test --platform chrome`).

### Core surface
- `flutter_mcp_facade_test.dart` / `flutter_mcp_facade_extra_test.dart` —
  diagnostic getters and uninitialized-guard branches.
- `flutter_mcp_health_test.dart` — `getComponentHealth`,
  `getSystemHealth`, `connectClient`/`connectServer` error paths.
- `flutter_mcp_llm_details_test.dart` — `getLlmEnhancedDetails`,
  `getAllLlmDetails`, LLM lookup helpers.
- `flutter_mcp_transport_harness_test.dart` — drives `createClient` /
  `createServer` / `connectClient` / `callTool` / `chat` /
  `createLlmClient` / `createLlmServer` through a fake-transport harness.
- `phase2_surface_test.dart` — Phase 2 spec surface (sampling,
  elicitation, roots, completion, RFC 9728 OAuth Resource Server).

### Configuration & loaders
- `mcp_config_serialization_test.dart` — toJson roundtrips for every
  config class.
- `config_loader_extras_test.dart`, `config_parser_test.dart`,
  `config_task_execution_test.dart`, `config_integration_test.dart`,
  `app_config_test.dart`.
- `enhanced_background_config_test.dart`, `notification_models_test.dart`.

### Managers + LLM glue
- `llm_manager_test.dart`, `llm_info_test.dart`, `client_manager`-level
  paths covered through the harness above.
- `base_manager_test.dart`, `subscription_manager_test.dart` (+ extras),
  `subscription_manager_extra_test.dart`.

### Platform / native channel
- `flutter_mcp_method_channel_test.dart`,
  `flutter_mcp_platform_interface_test.dart`,
  `method_channel_event_test.dart`,
  `method_channel_typed_test.dart`,
  `typed_platform_channel_test.dart`,
  `platform_messages_test.dart`.
- `platform_factory_test.dart`, `platform_utils_test.dart`,
  `platform_services_test.dart`.
- `desktop_notification_test.dart`, `ios_notification_test.dart`,
  `android_notification_test.dart`,
  `desktop_background_test.dart`, `ios_background_test.dart`,
  `android_background_test.dart`, `macos_enhanced_tray_test.dart`,
  `enhanced_tray_manager_test.dart`, `tray_manager_test.dart`.

### Plugins / events / utilities
- `plugin_system_extras_test.dart`, `mcp_plugin_system_test.dart`,
  `enhanced_plugin_system_test.dart`, `plugin_config_test.dart`.
- `event_system_extras_test.dart`, `event_system_improved_test.dart`,
  `event_system_cleanup_test.dart`, `enhanced_event_system_test.dart`,
  `typed_event_system_test.dart`,
  `enhanced_typed_event_system_test.dart`,
  `typed_event_system_extra_test.dart`, `event_models_test.dart`.
- `memory_manager_test.dart`, `enhanced_resource_cleanup_test.dart`,
  `circuit_breaker_test.dart`, `circuit_breaker_thread_safety_test.dart`,
  `error_recovery_strategies_test.dart`, `error_handling_test.dart`,
  `exceptions_test.dart`, `exceptions_extras_test.dart`,
  `operation_wrapper_test.dart`, `lifecycle_manager_test.dart`,
  `object_pool_test.dart`, `logger_extensions_test.dart`,
  `noop_platform_services_test.dart`, `diagnostic_utils_test.dart`,
  `health_types_test.dart`, `mcp_job_test.dart`.

### Performance + security
- `enhanced_performance_monitor_test.dart`,
  `performance_monitoring_comprehensive_test.dart`,
  `simple_performance_test.dart`, `mcp_perfomance_test.dart`,
  `typed_metrics_test.dart`, `typed_metrics_extras_test.dart`.
- `security_comprehensive_test.dart`, `security_audit_extras_test.dart`,
  `oauth_manager_test.dart`, `encryption_manager_test.dart`,
  `security_test.dart`.

### Browser-only (`@TestOn('browser')`)
- `web_memory_monitor_web_test.dart`,
  `web_storage_web_test.dart`,
  `web_notification_web_test.dart`,
  `web_background_web_test.dart`.

## Running

### Run everything on the VM
```bash
flutter test
```

### Run with coverage
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Run the browser suite (web platform code paths)
```bash
flutter test --platform chrome \
  test/web_memory_monitor_web_test.dart \
  test/web_storage_web_test.dart \
  test/web_notification_web_test.dart \
  test/web_background_web_test.dart
```

### Run a specific suite
```bash
flutter test test/flutter_mcp_transport_harness_test.dart
flutter test test/phase2_surface_test.dart
```

### Integration test (example app, e2e on host)
```bash
cd example
flutter test integration_test/plugin_integration_test.dart -d macos
```

## Mock generation

A few suites use Mockito; regenerate the generated mocks with:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Notes

- `_mock_transport.dart` is shared infrastructure (a fake
  `ClientTransport` / `ServerTransport`) used by the transport harness.
  It is not a standalone test file.
- Browser tests are tagged `@TestOn('browser')` and skip on the VM run.
- The harness sets up the `FlutterMCP` singleton once per process; tests
  group around a single `setUpAll` / `tearDownAll` because the singleton
  cannot be re-initialised cleanly within one process.
