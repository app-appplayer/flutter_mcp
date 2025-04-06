import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// Log level
enum LogLevel {
  trace,
  debug,
  info,
  warning,
  error,
  none,
}

/// Log format
enum LogFormat {
  text,
  json,
}

/// MCP logger
class MCPLogger {
  /// Logger name
  final String name;

  /// Log level
  LogLevel _level = LogLevel.info;

  /// Default log level
  static LogLevel _defaultLevel = LogLevel.info;

  /// Log file path
  static String? _logFilePath;

  /// Log directory path
  static String? _logDirPath;

  /// Whether to log to file
  static bool _logToFile = false;

  /// Whether to include timestamp
  static bool _includeTimestamp = true;

  /// Whether to use color
  static bool _useColor = true;

  /// Log file sink
  static IOSink? _logFileSink;

  /// Maximum log file size in bytes
  static int _maxLogFileSize = 10 * 1024 * 1024; // 10 MB default

  /// Maximum number of log files to keep
  static int _maxLogFiles = 5;

  /// Current log file size
  static int _currentLogFileSize = 0;

  /// Log format
  static LogFormat _logFormat = LogFormat.text;

  /// Logger instances map
  static final Map<String, MCPLogger> _loggers = {};

  IOSink _output = stderr;

  /// Set default log level
  static void setDefaultLevel(LogLevel level) {
    _defaultLevel = level;
    // Update existing loggers
    for (final logger in _loggers.values) {
      logger._level = level;
    }
  }

  /// Configure log file rotation
  static void configureLogRotation({
    required String directory,
    String prefix = 'mcp',
    int maxSizeBytes = 10 * 1024 * 1024, // 10 MB
    int maxFiles = 5,
    LogFormat format = LogFormat.text,
  }) async {
    _maxLogFileSize = maxSizeBytes;
    _maxLogFiles = maxFiles;
    _logFormat = format;
    _logDirPath = directory;

    // Create directory if it doesn't exist
    final dir = Directory(directory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Initialize log file
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    _logFilePath = path.join(directory, '${prefix}_$timestamp.log');

    // Enable file logging
    await enableFileLogging(true);

    // Check if we need to perform rotation
    await _checkAndRotateLogs();
  }

  /// Set log file
  static Future<void> setLogFile(String filePath) async {
    if (_logFileSink != null) {
      await _logFileSink!.close();
    }

    _logFilePath = filePath;
    _currentLogFileSize = 0;

    // Create directory if it doesn't exist
    final dir = Directory(path.dirname(filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    if (_logToFile) {
      final file = File(filePath);

      // Initialize current size
      if (await file.exists()) {
        _currentLogFileSize = await file.length();
      }

      _logFileSink = file.openWrite(mode: FileMode.append);
    }
  }

  /// Enable/disable file logging
  static Future<void> enableFileLogging(bool enable) async {
    _logToFile = enable;
    if (enable && _logFilePath != null) {
      final file = File(_logFilePath!);

      // Initialize current size
      if (await file.exists()) {
        _currentLogFileSize = await file.length();
      }

      _logFileSink = file.openWrite(mode: FileMode.append);
    } else if (!enable && _logFileSink != null) {
      await _logFileSink!.close();
      _logFileSink = null;
    }
  }

  /// Configure logger
  static void configure({
    LogLevel? level,
    bool? includeTimestamp,
    bool? useColor,
    String? logFilePath,
    bool? logToFile,
    LogFormat? logFormat,
  }) {
    if (level != null) {
      setDefaultLevel(level);
    }

    if (includeTimestamp != null) {
      _includeTimestamp = includeTimestamp;
    }

    if (useColor != null) {
      _useColor = useColor;
    }

    if (logFormat != null) {
      _logFormat = logFormat;
    }

    if (logFilePath != null) {
      setLogFile(logFilePath);
    }

    if (logToFile != null) {
      enableFileLogging(logToFile);
    }
  }

  /// Check and rotate logs if necessary
  static Future<void> _checkAndRotateLogs() async {
    if (!_logToFile || _logFilePath == null || _logDirPath == null) {
      return;
    }

    final currentFile = File(_logFilePath!);

    // Check if current log file size exceeds limit
    if (await currentFile.exists() && await currentFile.length() > _maxLogFileSize) {
      // Close current log file
      if (_logFileSink != null) {
        await _logFileSink!.close();
        _logFileSink = null;
      }

      // Create new log file
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final prefix = path.basenameWithoutExtension(_logFilePath!).split('_').first;
      final newLogFilePath = path.join(_logDirPath!, '${prefix}_$timestamp.log');

      // Set new log file
      await setLogFile(newLogFilePath);

      // Delete old log files if we have too many
      await _cleanOldLogFiles();
    }
  }

  /// Clean old log files to stay under the maximum number
  static Future<void> _cleanOldLogFiles() async {
    if (_logDirPath == null) return;

    final dir = Directory(_logDirPath!);
    if (!await dir.exists()) return;

    // Get all log files
    final prefix = path.basenameWithoutExtension(_logFilePath!).split('_').first;
    final logFiles = await dir.list()
        .where((entity) =>
    entity is File &&
        path.basename(entity.path).startsWith('${prefix}_') &&
        path.basename(entity.path).endsWith('.log'))
        .toList();

    // If we have too many log files, delete the oldest ones
    if (logFiles.length > _maxLogFiles) {
      // Sort files by last modified timestamp (oldest first)
      logFiles.sort((a, b) =>
          a.statSync().modified.compareTo(b.statSync().modified));

      // Delete oldest files to stay under the limit
      final filesToDelete = logFiles.length - _maxLogFiles;
      for (var i = 0; i < filesToDelete; i++) {
        if (logFiles[i] is File) {
          await (logFiles[i] as File).delete();
        }
      }
    }
  }

  /// Get a logger instance
  factory MCPLogger(String name) {
    if (_loggers.containsKey(name)) {
      return _loggers[name]!;
    }

    final logger = MCPLogger._internal(name);
    _loggers[name] = logger;
    return logger;
  }

  MCPLogger._internal(this.name) {
    _level = _defaultLevel;
  }

  /// Set log level
  void setLevel(LogLevel level) {
    _level = level;
  }

  /// Trace log
  void trace(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.trace, message, error, stackTrace);
  }

  /// Debug log
  void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.debug, message, error, stackTrace);
  }

  /// Info log
  void info(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.info, message, error, stackTrace);
  }

  /// Warning log
  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.warning, message, error, stackTrace);
  }

  /// Error log
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, error, stackTrace);
  }

  /// Log record
  void _log(LogLevel level, String message, [Object? error, StackTrace? stackTrace]) async {
    if (level.index < _level.index) {
      return;
    }

    final now = DateTime.now();
    final timestamp = _includeTimestamp ? now.toIso8601String() : null;
    final levelStr = level.toString().split('.').last.toUpperCase();

    // Console output with optional color
    final consoleMessage = _buildConsoleMessage(timestamp, levelStr, message, error, stackTrace);
    _output.writeln(consoleMessage);

    // File logging with rotation check
    if (_logToFile && _logFileSink != null) {
      final fileContent = _logFormat == LogFormat.json
          ? _buildJsonLogEntry(timestamp, levelStr, message, error, stackTrace)
          : _buildTextLogEntry(timestamp, levelStr, message, error, stackTrace);

      _logFileSink!.writeln(fileContent);
      _currentLogFileSize += fileContent.length + 1; // +1 for newline

      // Check if we need to rotate logs
      if (_currentLogFileSize > _maxLogFileSize) {
        await _checkAndRotateLogs();
      }
    }
  }

  /// Build console message with optional coloring
  String _buildConsoleMessage(
      String? timestamp,
      String levelStr,
      String message,
      Object? error,
      StackTrace? stackTrace
      ) {
    final buffer = StringBuffer();

    // Add timestamp
    if (timestamp != null) {
      buffer.write('[$timestamp] ');
    }

    // Add logger name
    buffer.write('[$name] ');

    // Add level with optional coloring
    if (_useColor) {
      final color = _getLevelColor(levelStr);
      final resetColor = '\x1B[0m';
      buffer.write('$color[$levelStr]$resetColor ');
    } else {
      buffer.write('[$levelStr] ');
    }

    // Add message
    buffer.write(message);

    // Add error details
    if (error != null) {
      buffer.write('\n  Error: $error');
    }

    // Add stack trace
    if (stackTrace != null) {
      buffer.write('\n  StackTrace: $stackTrace');
    }

    return buffer.toString();
  }

  /// Build text log entry for file
  String _buildTextLogEntry(
      String? timestamp,
      String levelStr,
      String message,
      Object? error,
      StackTrace? stackTrace
      ) {
    final buffer = StringBuffer();

    // Add timestamp
    if (timestamp != null) {
      buffer.write('[$timestamp] ');
    }

    // Add logger name and level
    buffer.write('[$name] [$levelStr] ');

    // Add message
    buffer.write(message);

    // Add error details
    if (error != null) {
      buffer.write('\n  Error: $error');
    }

    // Add stack trace
    if (stackTrace != null) {
      buffer.write('\n  StackTrace: $stackTrace');
    }

    return buffer.toString();
  }

  /// Build JSON log entry
  String _buildJsonLogEntry(
      String? timestamp,
      String levelStr,
      String message,
      Object? error,
      StackTrace? stackTrace
      ) {
    final Map<String, dynamic> entry = {
      'logger': name,
      'level': levelStr,
      'message': message,
    };

    if (timestamp != null) {
      entry['timestamp'] = timestamp;
    }

    if (error != null) {
      entry['error'] = error.toString();
    }

    if (stackTrace != null) {
      entry['stackTrace'] = stackTrace.toString();
    }

    return json.encode(entry);
  }

  /// Get color code for log level
  String _getLevelColor(String level) {
    switch (level) {
      case 'TRACE':
        return '\x1B[37m'; // white
      case 'DEBUG':
        return '\x1B[36m'; // cyan
      case 'INFO':
        return '\x1B[32m'; // green
      case 'WARNING':
        return '\x1B[33m'; // yellow
      case 'ERROR':
        return '\x1B[31m'; // red
      default:
        return '\x1B[0m';  // reset
    }
  }

  /// Flush log buffer to file
  static Future<void> flush() async {
    if (_logFileSink != null) {
      await _logFileSink!.flush();
    }
  }

  /// Close all logging resources
  static Future<void> closeAll() async {
    if (_logFileSink != null) {
      await _logFileSink!.close();
      _logFileSink = null;
    }
  }

  /// Set log level for all loggers matching a pattern
  static void setLevelByPattern(String pattern, LogLevel level) {
    for (final entry in _loggers.entries) {
      if (entry.key.contains(pattern)) {
        entry.value.setLevel(level);
      }
    }
  }

  /// Set log level for all loggers
  static void setAllLevels(LogLevel level) {
    for (final logger in _loggers.values) {
      logger.setLevel(level);
    }
  }

  /// Get all logger names
  static List<String> getAllLoggerNames() {
    return _loggers.keys.toList();
  }
}