# Flutter MCP API Reference

Complete API reference for the Flutter MCP plugin.

## Table of Contents

- [FlutterMCP (Main Class)](#fluttermcp-main-class)
- [Client Manager](#client-manager)
- [Server Manager](#server-manager)
- [LLM Manager](#llm-manager)
- [Configuration Classes](#configuration-classes)
- [Exception Classes](#exception-classes)
- [Plugin System](#plugin-system)

## FlutterMCP (Main Class)

The main entry point for all Flutter MCP functionality.

### Instance Access

```dart
static FlutterMCP get instance
```

Access the singleton instance of FlutterMCP.

### Initialization

```dart
Future<void> init(MCPConfig config)
```

Initialize Flutter MCP with the provided configuration.

**Parameters:**
- `config` - The main configuration object

**Example:**
```dart
await FlutterMCP.instance.init(
  MCPConfig(
    appName: 'My App',
    appVersion: '1.0.0',
    autoStart: false,
  ),
);
```

### Properties

```dart
bool get isInitialized
```
Check if Flutter MCP has been initialized.

```dart
MCPClientManager get clientManager
```
Access the client manager for MCP client operations.

```dart
MCPServerManager get serverManager
```
Access the server manager for MCP server operations.

```dart
MCPLlmManager get llmManager
```
Access the LLM manager for language model operations.

```dart
PlatformServices get backgroundService
```
Access platform-specific background services.

```dart
MCPScheduler get scheduler
```
Access the job scheduler.

```dart
EnhancedPluginRegistry get pluginRegistry
```
Access the plugin registry.

### Client Methods

```dart
Future<String> createClient({
  required String name,
  required String version,
  required String serverUrl,
  String? transportType,
  String? authToken,
  Duration? timeout,
  Map<String, String>? headers,
})
```

Create a new MCP client with simplified configuration.

**Returns:** Client ID string

```dart
Future<void> connectClient(String clientId)
```

Connect a client by its ID.

### Server Methods

```dart
Future<String> createServer({
  required String name,
  required String version,
  required String transportCommand,
  List<String>? transportArgs,
  Map<String, String>? env,
})
```

Create a new MCP server with simplified configuration.

**Returns:** Server ID string

### Status Methods

```dart
Map<String, dynamic> getStatus()
```

Get overall system status including all managers.

```dart
Map<String, dynamic> getClientDetails(String clientId)
```

Get detailed information about a specific client.

```dart
Map<String, dynamic> getServerDetails(String serverId)
```

Get detailed information about a specific server.

```dart
Map<String, dynamic> getLlmDetails(String llmId)
```

Get detailed information about a specific LLM.

```dart
Map<String, dynamic> getLlmEnhancedDetails(String llmId, {
  bool includeMetrics = false,
  bool includeCapabilities = false,
})
```

Get enhanced details about a specific LLM including metrics and capabilities.

```dart
Map<String, dynamic> getAllLlmDetails({bool includeCapabilities = false})
```

Get details for all registered LLMs.

### LLM Management Methods

```dart
Future<(String, String)> createLlmClient({
  required String llmId,
  String? name,
  String? version,
  Map<String, dynamic>? config,
})
```

Create an LLM client and return tuple of (llmId, llmClientId).

```dart
Future<(String, String)> createLlmServer({
  required String llmId,
  String? name,
  String? version,
  Map<String, dynamic>? config,
})
```

Create an LLM server and return tuple of (llmId, llmServerId).

```dart
Future<void> removeLlmClient(String llmId, String llmClientId)
```

Remove an LLM client from an LLM instance.

```dart
Future<void> removeLlmServer(String llmId, String llmServerId)
```

Remove an LLM server from an LLM instance.

```dart
Future<void> setDefaultLlmClientId(String llmClientId)
```

Set the default LLM client ID.

```dart
Future<void> setDefaultLlmServerId(String llmServerId)
```

Set the default LLM server ID.

### MCP-LLM Integration Methods

```dart
Future<void> addMcpClientToLlmClient({
  required String llmId,
  required String llmClientId,
  required String mcpClientId,
})
```

Add an MCP client to an LLM client.

```dart
Future<void> removeMcpClientFromLlmClient({
  required String llmId,
  required String llmClientId,
  required String mcpClientId,
})
```

Remove an MCP client from an LLM client.

```dart
Future<void> setDefaultMcpClientForLlmClient({
  required String llmId,
  required String llmClientId,
  required String mcpClientId,
})
```

Set the default MCP client for an LLM client.

```dart
Future<void> addMcpServerToLlmServer({
  required String llmId,
  required String llmServerId,
  required String mcpServerId,
})
```

Add an MCP server to an LLM server.

```dart
Future<void> removeMcpServerFromLlmServer({
  required String llmId,
  required String llmServerId,
  required String mcpServerId,
})
```

Remove an MCP server from an LLM server.

```dart
Future<void> setDefaultMcpServerForLlmServer({
  required String llmId,
  required String llmServerId,
  required String mcpServerId,
})
```

Set the default MCP server for an LLM server.

### Advanced Query Methods

```dart
Future<List<LLMResponse>> executeParallelQuery({
  required List<String> llmIds,
  required String prompt,
  QueryOptions? options,
  Duration? timeout,
})
```

Execute parallel queries across multiple LLMs.

```dart
Future<Map<String, LLMResponse>> fanOutQuery({
  required String prompt,
  List<String>? llmIds,
  QueryOptions? options,
  bool includeFailures = false,
})
```

Fan out a query to multiple LLMs and collect results.

```dart
Future<List<T>> processBatch<T>({
  required List<BatchItem> items,
  required Future<T> Function(BatchItem) processor,
  int maxConcurrency = 5,
  bool continueOnError = true,
})
```

Generic batch processing with load balancing.

### Security Methods

```dart
Future<AuthResult> authenticateUser({
  required String username,
  required String password,
  Map<String, dynamic>? metadata,
})
```

Authenticate a user and return authentication result.

```dart
Future<String> startUserSession({
  required String userId,
  required AuthToken token,
  Duration? sessionDuration,
})
```

Start an authenticated user session.

```dart
Future<void> endUserSession(String sessionId)
```

End a user session.

```dart
Future<bool> checkDataAccess({
  required String userId,
  required String resource,
  required String action,
})
```

Check if a user has access to perform an action on a resource.

```dart
Future<String> encryptData({
  required String data,
  String? keyId,
  EncryptionAlgorithm? algorithm,
})
```

Encrypt data using the specified key and algorithm.

```dart
Future<String> decryptData({
  required String encryptedData,
  String? keyId,
})
```

Decrypt encrypted data.

```dart
Future<String> generateEncryptionKey({
  EncryptionAlgorithm algorithm = EncryptionAlgorithm.aes256,
  int? keyLength,
})
```

Generate a new encryption key.

```dart
Future<RiskAssessment> getUserRiskAssessment(String userId)
```

Get risk assessment for a specific user.

```dart
Future<List<AuditEvent>> getUserAuditEvents({
  required String userId,
  DateTime? startDate,
  DateTime? endDate,
  int? limit,
})
```

Get audit events for a specific user.

```dart
Future<SecurityReport> generateSecurityReport({
  DateTime? startDate,
  DateTime? endDate,
  List<String>? includeCategories,
})
```

Generate a comprehensive security report.

```dart
Future<void> updateSecurityPolicy(SecurityPolicy policy)
```

Update the security policy.

### OAuth Methods

```dart
Future<void> initializeOAuth(OAuthConfig config)
```

Initialize OAuth configuration.

```dart
Future<OAuthToken> authenticateOAuth({
  required String provider,
  Map<String, String>? additionalParams,
})
```

Perform OAuth authentication for the specified provider.

```dart
bool isOAuthAuthenticated(String provider)
```

Check if authenticated with OAuth provider.

```dart
Future<void> revokeOAuthToken(String provider)
```

Revoke OAuth token for the specified provider.

```dart
Map<String, String> getOAuthHeaders(String provider)
```

Get OAuth headers for authenticated requests.

### Health & Monitoring Methods

```dart
Future<ComponentHealth> getComponentHealth(String componentId)
```

Get health status for a specific component.

```dart
Future<SystemHealth> getSystemHealth()
```

Get overall system health including all components.

```dart
Future<HealthCheckResult> checkHealth({
  List<String>? components,
  bool detailed = false,
})
```

Perform async health check on specified components.

```dart
Map<String, BatchStatistics> getBatchStatistics()
```

Get batch processing statistics.

```dart
Map<String, ResourceStatistics> getResourceStatistics()
```

Get resource usage statistics.

```dart
Future<List<ResourceLeak>> checkForResourceLeaks()
```

Check for potential resource leaks.

```dart
Map<String, dynamic> getResourceDetails(String resourceId)
```

Get detailed information about a specific resource.

### Document & RAG Support Methods

```dart
Future<String> addDocument({
  required String content,
  required Map<String, dynamic> metadata,
  String? collectionId,
})
```

Add a document to the retrieval system.

```dart
Future<List<Document>> retrieveRelevantDocuments({
  required String query,
  int limit = 10,
  double minSimilarity = 0.7,
  String? collectionId,
})
```

Retrieve documents relevant to the query.

```dart
Future<List<double>> generateEmbeddings(String text)
```

Generate embeddings for the given text.

```dart
Future<void> processDocumentsInChunks({
  required List<String> documents,
  required int chunkSize,
  required Future<void> Function(List<String>) processor,
})
```

Process documents in chunks for efficient handling.

### Session Management Methods

```dart
Future<String> createChatSession({
  required String llmId,
  Map<String, dynamic>? config,
})
```

Create a new chat session.

```dart
Future<String> createConversation({
  required String sessionId,
  String? title,
  Map<String, dynamic>? metadata,
})
```

Create a new conversation within a session.

### Plugin Management (Enhanced)

```dart
Future<void> registerPluginEnhanced({
  required MCPPlugin plugin,
  Version? version,
  List<PluginDependency>? dependencies,
})
```

Register a plugin with version and dependency information.

```dart
Map<String, PluginVersion> getAllPluginVersions()
```

Get version information for all registered plugins.

```dart
List<VersionConflict> checkPluginVersionConflicts()
```

Check for plugin version conflicts.

```dart
Future<void> updatePluginSandboxConfig({
  required String pluginId,
  required PluginSandboxConfig config,
})
```

Update sandbox configuration for a plugin.

```dart
Future<T> executePluginInSandbox<T>({
  required String pluginId,
  required Future<T> Function() operation,
})
```

Execute a plugin operation in an isolated sandbox.

```dart
PluginSystemReport getPluginSystemReport()
```

Get comprehensive plugin system report.

```dart
Future<void> registerLlmPluginWithSystem({
  required String pluginId,
  required LlmPlugin plugin,
})
```

Register an LLM-specific plugin.

```dart
Future<void> registerPluginsFromLlmClient({
  required String llmId,
  required String llmClientId,
})
```

Bulk register plugins from an LLM client.

```dart
Future<void> registerPluginsFromLlmServer({
  required String llmId,
  required String llmServerId,
})
```

Bulk register plugins from an LLM server.

```dart
Future<void> registerCoreLlmPlugins()
```

Register core LLM plugins (tools, resources, prompts).

```dart
LlmPlugin? convertMcpPluginToLlm(MCPPlugin plugin)
```

Convert an MCP plugin to LLM plugin format.

```dart
Map<String, PluginInfo> getAllPluginInfo()
```

Get detailed information for all plugins.

### Utility Methods

```dart
bool isFeatureSupported(String featureId)
```

Check if a specific feature is supported.

```dart
Future<void> startServices()
```

Start all configured services.

```dart
List<String> getAllMcpLlmInstanceIds()
```

Get all MCP LLM instance IDs.

```dart
Future<void> registerLlmProvider({
  required String providerId,
  required LlmProvider provider,
})
```

Register a custom LLM provider.

### Cleanup

```dart
Future<void> dispose()
```

Clean up all resources and shut down Flutter MCP.

## Client Manager

Manages MCP client connections.

### Methods

```dart
Future<String> createClient(MCPClientConfig config)
```

Create a new client with detailed configuration.

**Parameters:**
- `config` - MCPClientConfig object

**Returns:** Client ID string

```dart
Future<void> connectClient(String clientId)
```

Connect a client by ID.

```dart
Future<void> closeClient(String clientId)
```

Close and clean up a client connection.

```dart
Future<dynamic> callTool(String clientId, String name, Map<String, dynamic> arguments)
```

Call a tool on the connected server.

**Returns:** Tool execution result

```dart
Future<String> callPrompt(String clientId, String name, Map<String, dynamic> arguments)
```

Call a prompt on the connected server.

**Returns:** Prompt result string

```dart
Future<dynamic> getResource(String clientId, String uri)
```

Get a resource from the connected server.

```dart
ClientInfo? getClientInfo(String clientId)
```

Get information about a specific client.

```dart
List<ClientInfo> getAllClients()
```

Get information about all clients.

```dart
Stream<List<ClientInfo>> get clientStream
```

Stream of client status updates.

### Properties

```dart
Map<String, dynamic> getStatus()
```

Get client manager status information.

## Server Manager

Manages MCP server processes.

### Methods

```dart
Future<String> addServer(MCPServerConfig config)
```

Add a server configuration.

**Parameters:**
- `config` - MCPServerConfig object

**Returns:** Server ID string

```dart
Future<void> startServer(String serverId)
```

Start a server by ID.

```dart
Future<void> stopServer(String serverId)
```

Stop a server by ID.

```dart
Future<void> restartServer(String serverId)
```

Restart a server by ID.

```dart
Future<void> removeServer(String serverId)
```

Remove a server configuration.

```dart
ServerInfo? getServerInfo(String serverId)
```

Get information about a specific server.

```dart
List<ServerInfo> getAllServers()
```

Get information about all servers.

```dart
Stream<List<ServerInfo>> get serverStream
```

Stream of server status updates.

### Properties

```dart
Map<String, dynamic> getStatus()
```

Get server manager status information.

## LLM Manager

Manages language model integrations.

### Methods

```dart
Future<String> addLLM(LLMConfig config)
```

Add an LLM configuration.

**Parameters:**
- `config` - LLMConfig object

**Returns:** LLM ID string

```dart
Future<LLMResponse> query({
  required String llmId,
  required String prompt,
  QueryOptions? options,
})
```

Execute a query on an LLM.

**Parameters:**
- `llmId` - The LLM to query
- `prompt` - The prompt text
- `options` - Optional query parameters

**Returns:** LLMResponse object

```dart
Future<void> removeLLM(String llmId)
```

Remove an LLM configuration.

```dart
LlmInfo? getLlmInfo(String llmId)
```

Get information about a specific LLM.

```dart
List<LlmInfo> getAllLLMs()
```

Get information about all LLMs.

### Properties

```dart
Map<String, dynamic> getStatus()
```

Get LLM manager status information.

## Configuration Classes

### MCPConfig

Main configuration for Flutter MCP.

```dart
class MCPConfig {
  final String appName;
  final String appVersion;
  final bool autoStart;
  final bool useBackgroundService;
  final bool useNotification;
  final bool useTray;
  final bool secure;
  final BackgroundConfig? background;
  final NotificationConfig? notification;
  final TrayConfig? tray;
  final bool? enablePerformanceMonitoring;
  final int? highMemoryThresholdMB;
  final int? maxConnectionRetries;
  
  MCPConfig({
    required this.appName,
    required this.appVersion,
    this.autoStart = false,
    this.useBackgroundService = false,
    this.useNotification = false,
    this.useTray = false,
    this.secure = false,
    this.background,
    this.notification,
    this.tray,
    this.enablePerformanceMonitoring,
    this.highMemoryThresholdMB,
    this.maxConnectionRetries,
  });
}
```

### MCPClientConfig

Configuration for MCP clients.

```dart
class MCPClientConfig {
  final String name;
  final String version;
  final String transportType; // 'stdio', 'sse', 'streamablehttp'
  final String? transportCommand;
  final List<String>? transportArgs;
  final String? serverUrl;
  final String? authToken;
  final String? endpoint;
  final Duration? timeout;
  final Duration? sseReadTimeout;
  final Map<String, String>? headers;
  final ClientCapabilities? capabilities;
  
  MCPClientConfig({
    required this.name,
    required this.version,
    required this.transportType,
    this.transportCommand,
    this.transportArgs,
    this.serverUrl,
    this.authToken,
    this.endpoint,
    this.timeout,
    this.sseReadTimeout,
    this.headers,
    this.capabilities,
  });
}
```

### MCPServerConfig

Configuration for MCP servers.

```dart
class MCPServerConfig {
  final String name;
  final String version;
  final String transportType; // 'stdio', 'sse', 'streamablehttp'
  final String? transportCommand;
  final List<String>? transportArgs;
  final int? port;
  final String? endpoint;
  final Map<String, String>? env;
  final ServerCapabilities? capabilities;
  
  MCPServerConfig({
    required this.name,
    required this.version,
    required this.transportType,
    this.transportCommand,
    this.transportArgs,
    this.port,
    this.endpoint,
    this.env,
    this.capabilities,
  });
}
```

### LLMConfig

Configuration for language models.

```dart
class LLMConfig {
  final String? id;
  final String provider; // 'openai', 'anthropic', 'google', 'local'
  final String model;
  final String? apiKey;
  final String? baseUrl;
  final Map<String, dynamic>? defaultOptions;
  
  LLMConfig({
    this.id,
    required this.provider,
    required this.model,
    this.apiKey,
    this.baseUrl,
    this.defaultOptions,
  });
}
```

### BackgroundConfig

Configuration for background services.

```dart
class BackgroundConfig {
  final String notificationChannelId;
  final String notificationChannelName;
  final String notificationDescription;
  final int intervalMs;
  final bool keepAlive;
  final String? notificationIcon;
  final NotificationImportance importance;
  
  BackgroundConfig({
    required this.notificationChannelId,
    required this.notificationChannelName,
    required this.notificationDescription,
    this.intervalMs = 60000,
    this.keepAlive = false,
    this.notificationIcon,
    this.importance = NotificationImportance.low,
  });
}
```

### NotificationConfig

Configuration for notifications.

```dart
class NotificationConfig {
  final String channelId;
  final String channelName;
  final String channelDescription;
  final bool enableSound;
  final bool enableVibration;
  final NotificationPriority priority;
  
  NotificationConfig({
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
    this.enableSound = true,
    this.enableVibration = true,
    this.priority = NotificationPriority.normal,
  });
}
```

### TrayConfig

Configuration for system tray (desktop platforms).

```dart
class TrayConfig {
  final String iconPath;
  final String tooltip;
  final List<TrayMenuItem> menuItems;
  
  TrayConfig({
    required this.iconPath,
    required this.tooltip,
    this.menuItems = const [],
  });
}
```

## Exception Classes

### MCPException

Base exception class for all MCP errors.

```dart
class MCPException implements Exception {
  final String message;
  final String? code;
  final dynamic details;
  
  MCPException(this.message, {this.code, this.details});
}
```

### MCPConnectionException

Thrown when connection errors occur.

```dart
class MCPConnectionException extends MCPException {
  MCPConnectionException(String message, {String? code, dynamic details})
    : super(message, code: code, details: details);
}
```

### MCPAuthenticationException

Thrown when authentication fails.

```dart
class MCPAuthenticationException extends MCPException {
  MCPAuthenticationException(String message, {String? code, dynamic details})
    : super(message, code: code, details: details);
}
```

### MCPTimeoutException

Thrown when operations timeout.

```dart
class MCPTimeoutException extends MCPException {
  MCPTimeoutException(String message, {String? code, dynamic details})
    : super(message, code: code, details: details);
}
```

## Plugin System

### MCPPlugin

Base class for all plugins.

```dart
abstract class MCPPlugin {
  String get id;
  String get name;
  String get version;
  
  Future<void> initialize();
  Future<void> dispose();
}
```

### MCPToolPlugin

Plugin that provides tools to MCP servers.

```dart
abstract class MCPToolPlugin extends MCPPlugin {
  Map<String, ToolDefinition> get tools;
  
  Future<dynamic> executeTool(String name, Map<String, dynamic> arguments);
}
```

### MCPResourcePlugin

Plugin that manages resources.

```dart
abstract class MCPResourcePlugin extends MCPPlugin {
  Map<String, ResourceDefinition> get resources;
  
  Future<dynamic> getResource(String uri);
}
```

### MCPBackgroundPlugin

Plugin for background task execution.

```dart
abstract class MCPBackgroundPlugin extends MCPPlugin {
  Future<void> onBackgroundExecute();
}
```

### MCPNotificationPlugin

Plugin for custom notifications.

```dart
abstract class MCPNotificationPlugin extends MCPPlugin {
  Future<void> showNotification(NotificationData data);
}
```

### MCPPromptPlugin

Plugin that provides prompt templates.

```dart
abstract class MCPPromptPlugin extends MCPPlugin {
  Map<String, PromptDefinition> get prompts;
  
  Future<String> executePrompt(String name, Map<String, dynamic> arguments);
}
```

## Info Classes

### ClientInfo

Information about an MCP client.

```dart
class ClientInfo {
  final String id;
  final MCPClient client;
  final MCPClientConfig? config;
  final dynamic transport;
  final ClientStatus status;
  final DateTime createdAt;
  final DateTime? connectedAt;
}
```

### ServerInfo

Information about an MCP server.

```dart
class ServerInfo {
  final String id;
  final MCPServer server;
  final MCPServerConfig config;
  final dynamic transport;
  final ServerStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
}
```

### LlmInfo

Information about an LLM.

```dart
class LlmInfo {
  final String id;
  final MCPLlm mcpLlm;
  final LLMConfig config;
  final Map<String, dynamic> llmClients;
  final Map<String, dynamic> llmServers;
  final String? defaultLlmClientId;
  final String? defaultLlmServerId;
}
```

## Enums

### ClientStatus

```dart
enum ClientStatus {
  disconnected,
  connecting,
  connected,
  error,
}
```

### ServerStatus

```dart
enum ServerStatus {
  stopped,
  starting,
  running,
  stopping,
  error,
}
```

### NotificationPriority

```dart
enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}
```

### NotificationImportance

```dart
enum NotificationImportance {
  none,
  low,
  normal,
  high,
  max,
}
```

## Security Types

### AuthResult

Result of authentication operation.

```dart
class AuthResult {
  final bool success;
  final String? userId;
  final AuthToken? token;
  final String? message;
  final Map<String, dynamic>? metadata;
}
```

### AuthToken

Authentication token information.

```dart
class AuthToken {
  final String token;
  final String type;
  final DateTime? expiresAt;
  final List<String>? scopes;
}
```

### RiskAssessment

User risk assessment result.

```dart
class RiskAssessment {
  final String userId;
  final RiskLevel level;
  final double score;
  final List<RiskFactor> factors;
  final DateTime assessedAt;
}
```

### AuditEvent

Security audit event.

```dart
class AuditEvent {
  final String id;
  final String userId;
  final String action;
  final String resource;
  final DateTime timestamp;
  final bool success;
  final Map<String, dynamic>? metadata;
}
```

### SecurityReport

Comprehensive security report.

```dart
class SecurityReport {
  final DateTime startDate;
  final DateTime endDate;
  final Map<String, int> eventCounts;
  final List<SecurityIncident> incidents;
  final Map<String, dynamic> statistics;
}
```

### OAuthConfig

OAuth configuration.

```dart
class OAuthConfig {
  final String clientId;
  final String clientSecret;
  final String authorizeUrl;
  final String tokenUrl;
  final List<String> scopes;
  final String? redirectUri;
}
```

### OAuthToken

OAuth token information.

```dart
class OAuthToken {
  final String accessToken;
  final String? refreshToken;
  final String tokenType;
  final int? expiresIn;
  final List<String>? scopes;
}
```

## Health & Monitoring Types

### ComponentHealth

Health status for a component.

```dart
class ComponentHealth {
  final String componentId;
  final HealthStatus status;
  final String? message;
  final Map<String, dynamic>? details;
  final DateTime checkedAt;
}
```

### SystemHealth

Overall system health.

```dart
class SystemHealth {
  final HealthStatus overallStatus;
  final Map<String, ComponentHealth> components;
  final List<HealthIssue> issues;
  final DateTime timestamp;
}
```

### HealthCheckResult

Result of health check operation.

```dart
class HealthCheckResult {
  final bool healthy;
  final Map<String, HealthStatus> componentStatuses;
  final List<String> errors;
  final List<String> warnings;
}
```

### BatchStatistics

Statistics for batch processing.

```dart
class BatchStatistics {
  final int totalItems;
  final int processedItems;
  final int failedItems;
  final Duration totalDuration;
  final double averageItemDuration;
}
```

### ResourceStatistics

Resource usage statistics.

```dart
class ResourceStatistics {
  final String resourceType;
  final int totalAllocated;
  final int currentInUse;
  final int peakUsage;
  final Map<String, dynamic> metadata;
}
```

### ResourceLeak

Potential resource leak information.

```dart
class ResourceLeak {
  final String resourceId;
  final String resourceType;
  final DateTime allocatedAt;
  final String? stackTrace;
  final Map<String, dynamic>? context;
}
```

## Document & RAG Types

### Document

Document in retrieval system.

```dart
class Document {
  final String id;
  final String content;
  final Map<String, dynamic> metadata;
  final List<double>? embeddings;
  final double? relevanceScore;
}
```

## Plugin System (Enhanced) Types

### PluginVersion

Plugin version information.

```dart
class PluginVersion {
  final String pluginId;
  final Version version;
  final List<PluginDependency> dependencies;
  final DateTime registeredAt;
}
```

### PluginDependency

Plugin dependency specification.

```dart
class PluginDependency {
  final String pluginId;
  final VersionConstraint versionConstraint;
  final bool optional;
}
```

### VersionConflict

Version conflict information.

```dart
class VersionConflict {
  final String pluginId;
  final Version currentVersion;
  final Version requiredVersion;
  final String conflictingPluginId;
}
```

### PluginSandboxConfig

Sandbox configuration for plugin execution.

```dart
class PluginSandboxConfig {
  final bool enableNetworkAccess;
  final bool enableFileAccess;
  final List<String> allowedPaths;
  final Map<String, dynamic> environmentVariables;
  final Duration? executionTimeout;
}
```

### PluginSystemReport

Comprehensive plugin system report.

```dart
class PluginSystemReport {
  final int totalPlugins;
  final Map<String, PluginStatus> pluginStatuses;
  final List<VersionConflict> conflicts;
  final Map<String, dynamic> statistics;
}
```

### PluginInfo

Detailed plugin information.

```dart
class PluginInfo {
  final String id;
  final String name;
  final String version;
  final PluginStatus status;
  final Map<String, dynamic> capabilities;
  final Map<String, dynamic> metadata;
}
```

### LlmPlugin

LLM-specific plugin interface.

```dart
abstract class LlmPlugin {
  String get id;
  String get type;
  Map<String, dynamic> get capabilities;
  
  Future<dynamic> execute(String operation, Map<String, dynamic> params);
}
```

## Batch Processing Types

### BatchItem

Item for batch processing.

```dart
class BatchItem {
  final String id;
  final dynamic data;
  final Map<String, dynamic>? metadata;
}
```

## Enums (Additional)

### HealthStatus

```dart
enum HealthStatus {
  healthy,
  degraded,
  unhealthy,
  unknown,
}
```

### RiskLevel

```dart
enum RiskLevel {
  low,
  medium,
  high,
  critical,
}
```

### PluginStatus

```dart
enum PluginStatus {
  active,
  inactive,
  error,
  loading,
  unloaded,
}
```

### EncryptionAlgorithm

```dart
enum EncryptionAlgorithm {
  aes128,
  aes256,
  rsa2048,
  rsa4096,
}
```