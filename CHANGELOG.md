## 1.0.0 - 2025-03-26

### First Stable Release

Complete rewrite to support MCP v1.0.0 specification with modern API design.

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