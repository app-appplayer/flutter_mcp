# Flutter MCP Test Suite

Comprehensive test suite for Flutter MCP v1.0.0 covering all features and functionality.

## Test Structure

### Core Tests
- **flutter_mcp_v1_test.dart** - Main integration tests for v1.0.0 features
- **v1_features_test.dart** - Specific tests for new v1.0.0 features (batch processing, health monitoring, OAuth)
- **mcp_unit_test.dart** - Basic unit tests for core components

### Feature Tests
- **mcp_integration_test.dart** - Integration tests for MCP components
- **mcp_lifecycle_test.dart** - Lifecycle management tests
- **mcp_plugin_test.dart** - Plugin system tests
- **platform_integration_test.dart** - Platform-specific feature tests

### Storage Tests
- **mcp_secure_storage_test.dart** - Secure storage functionality tests
- **mcp_web_storage_test.dart** - Web storage implementation tests

### Reliability Tests
- **mcp_circuit_breaker_integration_test.dart** - Circuit breaker pattern tests
- **mcp_concurrent_operations_test.dart** - Concurrent operation handling tests
- **mcp_memory_leak_test.dart** - Memory leak detection tests
- **mcp_timeout_recovery_test.dart** - Timeout and recovery tests
- **mcp_exception_test.dart** - Exception handling tests

### Performance Tests
- **mcp_perfomance_test.dart** - Basic performance tests
- **mcp_performance_v1_test.dart** - v1.0.0 specific performance tests including:
  - Batch processing performance (40-60% improvement verification)
  - Health monitoring overhead
  - OAuth operations performance
  - Memory efficiency

### Security Tests
- **security_test.dart** - Security-focused tests including:
  - OAuth token security
  - Credential storage security
  - Input sanitization
  - Error message sanitization

### Mock Tests
- **mcp_mock_test.dart** - Mock object tests
- **test_utils.dart** - Shared test utilities

## Running Tests

### Run All Tests
```bash
flutter test test/all_tests.dart
```

### Run Specific Test Suite
```bash
# Run v1.0.0 feature tests
flutter test test/flutter_mcp_v1_test.dart

# Run security tests
flutter test test/security_test.dart

# Run performance tests
flutter test test/mcp_performance_v1_test.dart
```

### Run with Coverage
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Test Coverage

The test suite covers:

1. **v1.0.0 Features**
   - Factory-based creation patterns
   - Result<T, E> error handling
   - Batch processing with performance validation
   - Health monitoring and streaming
   - OAuth 2.1 authentication flow

2. **Core Functionality**
   - Client/Server creation and management
   - LLM integration
   - Plugin system
   - Event system

3. **Platform Features**
   - Background service execution
   - Notifications
   - System tray (desktop)
   - Secure storage
   - Lifecycle management

4. **Reliability**
   - Circuit breaker patterns
   - Memory management
   - Timeout handling
   - Error recovery
   - Concurrent operations

5. **Security**
   - OAuth token handling
   - Credential storage
   - Input validation
   - Error sanitization

6. **Performance**
   - Batch processing efficiency
   - Memory usage monitoring
   - Operation throughput
   - Health check overhead

## Writing New Tests

When adding new features, ensure to:

1. Add unit tests for individual components
2. Add integration tests for feature interactions
3. Add performance tests for any performance-critical code
4. Add security tests for any security-sensitive features
5. Update this README with new test descriptions

## Mock Generation

Some tests require mock generation using Mockito:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Continuous Integration

Tests are configured to run on:
- Every pull request
- Every commit to main branch
- Nightly for extended test suites

Performance benchmarks are tracked over time to detect regressions.