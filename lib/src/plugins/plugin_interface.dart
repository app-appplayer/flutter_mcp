import '../../flutter_mcp.dart';

/// Base plugin interface
abstract class MCPPlugin {
  /// Plugin name
  String get name;

  /// Plugin version
  String get version;

  /// Plugin description
  String get description;

  /// Initialize the plugin
  Future<void> initialize(Map<String, dynamic> config);

  /// Shutdown the plugin
  Future<void> shutdown();
}

/// MCP Tool plugin interface
abstract class MCPToolPlugin extends MCPPlugin {
  /// Execute the tool with arguments
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments);

  /// Get tool metadata including input schema
  Map<String, dynamic> getToolMetadata();

  /// Register tool with an MCP server
  Future<void> registerWithServer(Server server);
}

/// MCP Resource plugin interface
abstract class MCPResourcePlugin extends MCPPlugin {
  /// Get resource content
  Future<Map<String, dynamic>> getResource(String resourceUri, Map<String, dynamic> params);

  /// Get resource metadata
  Map<String, dynamic> getResourceMetadata();

  /// Register resource with an MCP server
  Future<void> registerWithServer(Server server);
}

/// MCP Background plugin interface
abstract class MCPBackgroundPlugin extends MCPPlugin {
  /// Start the background task
  Future<bool> start();

  /// Stop the background task
  Future<bool> stop();

  /// Check if the background task is running
  bool get isRunning;

  /// Register a background task handler
  void registerTaskHandler(Future<void> Function() handler);
}

/// MCP Notification plugin interface
abstract class MCPNotificationPlugin extends MCPPlugin {
  /// Show a notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? id,
    String? icon,
    Map<String, dynamic>? additionalData,
  });

  /// Hide a notification
  Future<void> hideNotification(String id);

  /// Register a notification click handler
  void registerClickHandler(Function(String id, Map<String, dynamic>? data) handler);
}

/// MCP Client plugin interface
abstract class MCPClientPlugin extends MCPPlugin {
  /// Initialize with a client
  Future<void> initializeWithClient(Client client);

  /// Handle connection state changes
  void handleConnectionStateChange(bool connected);

  /// Get client extensions
  Map<String, dynamic> getClientExtensions();
}

/// MCP Server plugin interface
abstract class MCPServerPlugin extends MCPPlugin {
  /// Initialize with a server
  Future<void> initializeWithServer(Server server);

  /// Handle connection state changes
  void handleConnectionStateChange(bool connected);

  /// Get server extensions
  Map<String, dynamic> getServerExtensions();
}
