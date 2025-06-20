/// Run all tests for Flutter MCP
///
/// This file imports and runs all test suites to ensure
/// comprehensive coverage of all features.

import 'core_implementation_test.dart' as core_implementation;
import 'mcp_unit_test.dart' as unit;
import 'mcp_integration_test.dart' as integration;
import 'mcp_lifecycle_test.dart' as lifecycle;
import 'mcp_plugin_test.dart' as plugin;
import 'mcp_secure_storage_test.dart' as secure_storage;
import 'mcp_web_storage_test.dart' as web_storage;
import 'mcp_mock_test.dart' as mock;
import 'mcp_exception_test.dart' as exception;
import 'mcp_circuit_breaker_integration_test.dart' as circuit_breaker;
import 'mcp_concurrent_operations_test.dart' as concurrent;
import 'mcp_memory_leak_test.dart' as memory_leak;
import 'mcp_timeout_recovery_test.dart' as timeout;
import 'mcp_perfomance_test.dart' as performance;
import 'platform_integration_test.dart' as platform;
import 'platform_background_service_test.dart' as platform_background;
import 'platform_notification_service_test.dart' as platform_notification;
import 'platform_tray_service_test.dart' as platform_tray;
import 'security_test.dart' as security;
import 'transport_test.dart' as transport;
import 'native_channel_integration_test.dart' as native_channel;

void main() {
  // Run all test suites

  // Core implementation tests (direct testing of actual implementations)
  core_implementation.main();

  // Unit tests
  unit.main();

  // Integration tests
  integration.main();
  platform.main();

  // Platform-specific tests
  platform_background.main();
  platform_notification.main();
  platform_tray.main();
  native_channel.main();

  // Feature-specific tests
  lifecycle.main();
  plugin.main();
  secure_storage.main();
  web_storage.main();

  // Advanced tests
  circuit_breaker.main();
  concurrent.main();
  memory_leak.main();
  timeout.main();
  exception.main();

  // Performance tests
  performance.main();

  // Security tests
  security.main();

  // Transport tests
  transport.main();

  // Mock tests
  mock.main();
}
