## 0.1.0

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

## 0.0.2

* Bug fixes and improvements
    * Fixed issues with background service initialization
    * Improved error handling and logging
    * Enhanced performance monitoring features
    * Updated documentation for better clarity
  
## 0.0.1

* Initial release
    * Support for MCP client, server, and LLM integration
    * Platform features: background service, notifications, system tray
    * Secure storage integration
    * Lifecycle management
    * Scheduled tasks