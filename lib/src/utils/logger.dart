// Re-export logging package to follow MCP standard pattern
export 'package:logging/logging.dart';

import 'dart:io';
import 'package:logging/logging.dart';

/// Extension methods for backward compatibility with existing MCP patterns
extension LoggerExtensions on Logger {
  /// Debug log - maps to fine level
  void debug(String message) => fine(message);

  /// Error log - maps to severe level
  void error(String message) => severe(message);

  /// Warning log - maps to warning level
  void warn(String message) => warning(message);

  /// Trace log - maps to finest level
  void trace(String message) => finest(message);
}

/// Logger configuration utilities following MCP standard patterns
class FlutterMcpLogging {
  /// Configure the root logger with standard MCP settings
  static void configure({
    Level level = Level.INFO,
    bool enableDebugLogging = false,
  }) {
    // Set log level
    Logger.root.level = enableDebugLogging ? Level.FINE : level;

    // Configure standard MCP log output format
    Logger.root.onRecord.listen((record) {
      final timestamp = record.time.toIso8601String();
      final levelName = record.level.name;
      final loggerName = record.loggerName;
      final message = record.message;

      // Use stderr for logging output (standard practice for logs)
      stderr.writeln('[$timestamp] [$levelName] $loggerName: $message');

      // Write error details if available
      if (record.error != null) {
        stderr.writeln('  Error: ${record.error}');
      }

      // Write stack trace if available
      if (record.stackTrace != null) {
        stderr.writeln('  StackTrace: ${record.stackTrace}');
      }
    });
  }

  /// Create a logger with standard MCP naming convention
  /// Format: flutter_mcp.component_name
  static Logger createLogger(String componentName) {
    return Logger('flutter_mcp.$componentName');
  }
}

/// Type alias for backward compatibility
typedef MCPLogger = Logger;
