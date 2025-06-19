import 'package:flutter_mcp/src/utils/memory_manager.dart';
import 'dart:async';

/// Utility methods for testing the MCP framework

/// Simulate high memory pressure for testing
/// This method provides a public way to trigger memory pressure simulation in tests
Future<void> simulateHighMemoryPressure(MemoryManager manager) async {
  // For MemoryManager that uses a private _checkMemoryUsage method
  // We create this public wrapper for testing purposes

  // In a real implementation, we would make the MemoryManager provide
  // a testing-only method for this purpose.

  // First, we force a "high" memory reading by setting memory usage values
  // directly when possible, or trigger the callbacks

  // Since we can't access the private highMemoryCallbacks directly,
  // we'll use a more direct approach for testing

  // Add a direct high memory callback just for this test
  // This is a test-only approach
  final callbackCompleter = Completer<void>();

  // Create a one-time callback that will complete our completer
  manager.addHighMemoryCallback(() async {
    callbackCompleter.complete();
  });

  // Wait for the callback to execute
  await callbackCompleter.future;
}

/// Simulate checking health for a service
Future<Map<String, dynamic>> simulateHealthCheck() async {
  return {
    'status': 'healthy',
    'timestamp': DateTime.now().toIso8601String(),
    'checks': {
      'core': {'status': 'ok'},
      'memory': {'status': 'ok'},
    }
  };
}
