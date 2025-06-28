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