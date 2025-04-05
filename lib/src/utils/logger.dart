import 'dart:io';

/// 로그 레벨
enum LogLevel {
  trace,
  debug,
  info,
  warning,
  error,
  none,
}

/// MCP 로거
class MCPLogger {
  /// 로거 이름
  final String name;

  /// 로그 레벨
  LogLevel _level = LogLevel.info;

  /// 기본 로그 레벨
  static LogLevel _defaultLevel = LogLevel.info;

  /// 로그 파일 경로
  static String? _logFilePath;

  /// 파일에 로그 기록 여부
  static bool _logToFile = false;

  /// 시간 포함 여부
  static bool _includeTimestamp = true;

  /// 색상 사용 여부
  static bool _useColor = true;

  /// 로그 파일 싱크
  static IOSink? _logFileSink;

  /// 로거 인스턴스 맵
  static final Map<String, MCPLogger> _loggers = {};

  /// 기본 로그 레벨 설정
  static void setDefaultLevel(LogLevel level) {
    _defaultLevel = level;
    // 기존 로거 업데이트
    for (final logger in _loggers.values) {
      logger._level = level;
    }
  }

  /// 로그 파일 설정
  static Future<void> setLogFile(String path) async {
    if (_logFileSink != null) {
      await _logFileSink!.close();
    }

    _logFilePath = path;
    if (_logToFile) {
      final file = File(path);
      _logFileSink = file.openWrite(mode: FileMode.append);
    }
  }

  /// 파일 로깅 활성화/비활성화
  static void enableFileLogging(bool enable) {
    _logToFile = enable;
    if (enable && _logFilePath != null) {
      final file = File(_logFilePath!);
      _logFileSink = file.openWrite(mode: FileMode.append);
    } else if (!enable && _logFileSink != null) {
      _logFileSink!.close();
      _logFileSink = null;
    }
  }

  /// 로거 설정
  static void configure({
    LogLevel? level,
    bool? includeTimestamp,
    bool? useColor,
    String? logFilePath,
    bool? logToFile,
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

    if (logFilePath != null) {
      setLogFile(logFilePath);
    }

    if (logToFile != null) {
      enableFileLogging(logToFile);
    }
  }

  /// 로거 인스턴스 가져오기
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

  /// 로그 레벨 설정
  void setLevel(LogLevel level) {
    _level = level;
  }

  /// 트레이스 로그
  void trace(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.trace, message, error, stackTrace);
  }

  /// 디버그 로그
  void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.debug, message, error, stackTrace);
  }

  /// 정보 로그
  void info(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.info, message, error, stackTrace);
  }

  /// 경고 로그
  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.warning, message, error, stackTrace);
  }

  /// 오류 로그
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, error, stackTrace);
  }

  /// 로그 기록
  void _log(LogLevel level, String message, [Object? error, StackTrace? stackTrace]) {
    if (level.index < _level.index) {
      return;
    }

    final timestamp = _includeTimestamp ? '[${DateTime.now().toIso8601String()}] ' : '';
    final loggerName = '[$name] ';
    final levelStr = _getLevelString(level);

    final fullMessage = '$timestamp$loggerName$levelStr $message';

    // 콘솔에 로그 출력
    print(fullMessage);

    // 에러가 있는 경우 출력
    if (error != null) {
      print('  Error: $error');
    }

    // 스택 트레이스가 있는 경우 출력
    if (stackTrace != null) {
      print('  StackTrace: $stackTrace');
    }

    // 파일에 로그 기록
    if (_logToFile && _logFileSink != null) {
      _logFileSink!.writeln(fullMessage);

      if (error != null) {
        _logFileSink!.writeln('  Error: $error');
      }

      if (stackTrace != null) {
        _logFileSink!.writeln('  StackTrace: $stackTrace');
      }
    }
  }

  /// 로그 레벨 문자열 가져오기
  String _getLevelString(LogLevel level) {
    if (!_useColor) {
      return '[${level.toString().split('.').last.toUpperCase()}]';
    }

    // 컬러 코드
    const String resetColor = '\x1B[0m';

    final String color;
    switch (level) {
      case LogLevel.trace:
        color = '\x1B[37m'; // 흰색
        break;
      case LogLevel.debug:
        color = '\x1B[36m'; // 청록색
        break;
      case LogLevel.info:
        color = '\x1B[32m'; // 녹색
        break;
      case LogLevel.warning:
        color = '\x1B[33m'; // 노란색
        break;
      case LogLevel.error:
        color = '\x1B[31m'; // 빨간색
        break;
      default:
        color = resetColor;
    }

    return '$color[${level.toString().split('.').last.toUpperCase()}]$resetColor';
  }
}