/// Run working tests for Flutter MCP
///
/// This file imports and runs tests that are known to work

import 'core_implementation_test.dart' as core_implementation;
import 'mcp_plugin_test.dart' as plugin;
import 'mcp_secure_storage_test.dart' as secure_storage;
import 'platform_integration_test.dart' as platform;
import 'security_test.dart' as security;
import 'transport_test.dart' as transport;

void main() {
  // Core implementation tests (direct testing of actual implementations)
  core_implementation.main();
  
  // Plugin tests
  plugin.main();
  
  // Secure storage tests
  secure_storage.main();
  
  // Platform integration tests
  platform.main();
  
  // Security tests
  security.main();
  
  // Transport tests
  transport.main();
}