/// Defines constants used throughout the MCP system.
///
/// This class prevents magic numbers and provides consistent configuration values.
class MCPConstants {
  // Private constructor to prevent instantiation
  MCPConstants._();

  // === Object Pool Related Constants ===

  /// Default object pool size
  static const int defaultObjectPoolSize = 50;

  /// Default object pool initial size
  static const int defaultObjectPoolInitialSize = 10;

  /// Maximum object pool size
  static const int maxObjectPoolSize = 200;

  // === Logging Related Constants ===

  /// Maximum log file size (10MB)
  static const int maxLogFileSizeBytes = 10 * 1024 * 1024;

  /// Maximum number of log files
  static const int maxLogFiles = 5;

  /// Log cleanup interval (minutes)
  static const int logCleanupIntervalMinutes = 60;

  // === Performance Monitoring Related Constants ===

  /// Maximum size of recent operations queue
  static const int maxRecentOperations = 100;

  /// Performance metrics sampling interval (seconds)
  static const int performanceMetricsSamplingSeconds = 30;

  /// Memory monitoring interval (seconds)
  static const int memoryMonitoringIntervalSeconds = 30;

  // === Network Related Constants ===

  /// Default connection timeout (seconds)
  static const int defaultConnectionTimeoutSeconds = 30;

  /// Default request timeout (seconds)
  static const int defaultRequestTimeoutSeconds = 60;

  /// Maximum retry attempts
  static const int maxRetryAttempts = 3;

  /// Retry interval (milliseconds)
  static const int retryIntervalMilliseconds = 1000;

  // === Scheduler Related Constants ===

  /// Scheduler check interval (seconds)
  static const int schedulerCheckIntervalSeconds = 1;

  /// Maximum concurrent jobs
  static const int maxConcurrentJobs = 10;

  /// Maximum job execution history count
  static const int maxJobExecutionHistory = 100;

  // === Memory Management Related Constants ===

  /// High memory threshold (MB)
  static const int highMemoryThresholdMB = 512;

  /// Memory cleanup threshold (MB)
  static const int memoryCleanupThresholdMB = 256;

  /// Maximum memory monitoring record count
  static const int maxMemoryReadings = 60;

  // === Cache Related Constants ===

  /// Default semantic cache size
  static const int defaultSemanticCacheSize = 1000;

  /// Semantic cache TTL (minutes)
  static const int semanticCacheTTLMinutes = 60;

  /// Similarity threshold (0.0 ~ 1.0)
  static const double semanticSimilarityThreshold = 0.8;

  // === Background Service Related Constants ===

  /// Default background interval (milliseconds)
  static const int defaultBackgroundIntervalMs = 60000; // 1 minute

  /// iOS minimum background interval (milliseconds)
  static const int iosMinBackgroundIntervalMs = 900000; // 15 minutes

  /// Maximum consecutive error count
  static const int maxConsecutiveErrors = 5;

  // === Encryption Related Constants ===

  /// AES key size (bits)
  static const int aesKeySizeBits = 256;

  /// Salt size (bytes)
  static const int saltSizeBytes = 32;

  /// PBKDF2 iteration count
  static const int pbkdf2Iterations = 100000;

  // === Plugin Related Constants ===

  /// Plugin loading timeout (seconds)
  static const int pluginLoadTimeoutSeconds = 30;

  /// Plugin initialization timeout (seconds)
  static const int pluginInitTimeoutSeconds = 10;

  /// Maximum plugin count
  static const int maxPluginCount = 100;

  // === Duration Constants ===

  /// Default connection timeout
  static const Duration defaultConnectionTimeout =
      Duration(seconds: defaultConnectionTimeoutSeconds);

  /// Default request timeout
  static const Duration defaultRequestTimeout =
      Duration(seconds: defaultRequestTimeoutSeconds);

  /// Scheduler check interval
  static const Duration schedulerCheckInterval =
      Duration(seconds: schedulerCheckIntervalSeconds);

  /// Memory monitoring interval
  static const Duration memoryMonitoringInterval =
      Duration(seconds: memoryMonitoringIntervalSeconds);

  /// Default background service interval
  static const Duration defaultBackgroundInterval =
      Duration(milliseconds: defaultBackgroundIntervalMs);

  /// iOS minimum background interval
  static const Duration iosMinBackgroundInterval =
      Duration(milliseconds: iosMinBackgroundIntervalMs);

  /// Log cleanup interval
  static const Duration logCleanupInterval =
      Duration(minutes: logCleanupIntervalMinutes);

  /// Performance metrics sampling interval
  static const Duration performanceMetricsSamplingInterval =
      Duration(seconds: performanceMetricsSamplingSeconds);

  // === File Path Related Constants ===

  /// Log file extension
  static const String logFileExtension = '.log';

  /// Configuration file extension
  static const String configFileExtension = '.json';

  /// Backup file extension
  static const String backupFileExtension = '.bak';

  // === Event Topic Constants ===

  /// MCP initialization complete event
  static const String eventMcpInitialized = 'mcp.initialized';

  /// MCP shutdown event
  static const String eventMcpShutdown = 'mcp.shutdown';

  /// High memory warning event
  static const String eventHighMemoryWarning = 'mcp.memory.high';

  /// Circuit breaker opened event
  static const String eventCircuitBreakerOpened = 'circuit_breaker.opened';

  /// Circuit breaker closed event
  static const String eventCircuitBreakerClosed = 'circuit_breaker.closed';

  // === Version Information ===

  /// Current MCP version
  static const String mcpVersion = '1.0.0';

  /// Minimum supported Flutter version
  static const String minFlutterVersion = '3.3.0';

  /// Minimum supported Dart version
  static const String minDartVersion = '3.7.2';
}
