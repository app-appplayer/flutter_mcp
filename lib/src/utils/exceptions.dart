/// MCP 예외
class MCPException implements Exception {
  /// 오류 메시지
  final String message;

  /// 내부 오류
  final dynamic innerError;

  MCPException(this.message, [this.innerError]);

  @override
  String toString() {
    if (innerError != null) {
      return 'MCPException: $message (Inner error: $innerError)';
    }
    return 'MCPException: $message';
  }
}

/// 초기화 오류
class MCPInitializationException extends MCPException {
  MCPInitializationException(String message, [dynamic innerError])
      : super('Initialization error: $message', innerError);
}

/// 플랫폼 지원 오류
class MCPPlatformNotSupportedException extends MCPException {
  MCPPlatformNotSupportedException(String feature)
      : super('Platform does not support the feature: $feature');
}

/// 설정 오류
class MCPConfigurationException extends MCPException {
  final Object? cause;
  final StackTrace? stackTrace;

  MCPConfigurationException(String message, [this.cause, this.stackTrace])
      : super('Configuration error: $message');
}