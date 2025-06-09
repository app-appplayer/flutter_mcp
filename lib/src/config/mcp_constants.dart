/// MCP 시스템 전체에서 사용되는 상수들을 정의합니다.
/// 
/// 이 클래스는 매직 넘버를 방지하고 일관된 설정 값을 제공합니다.
class MCPConstants {
  // Private constructor to prevent instantiation
  MCPConstants._();

  // === Object Pool 관련 상수 ===
  
  /// 기본 객체 풀 크기
  static const int defaultObjectPoolSize = 50;
  
  /// 기본 객체 풀 초기 크기
  static const int defaultObjectPoolInitialSize = 10;
  
  /// 객체 풀 최대 크기
  static const int maxObjectPoolSize = 200;

  // === 로깅 관련 상수 ===
  
  /// 최대 로그 파일 크기 (10MB)
  static const int maxLogFileSizeBytes = 10 * 1024 * 1024;
  
  /// 최대 로그 파일 개수
  static const int maxLogFiles = 5;
  
  /// 로그 정리 주기 (분)
  static const int logCleanupIntervalMinutes = 60;

  // === 성능 모니터링 관련 상수 ===
  
  /// 최근 작업 큐 최대 크기
  static const int maxRecentOperations = 100;
  
  /// 성능 메트릭 샘플링 간격 (초)
  static const int performanceMetricsSamplingSeconds = 30;
  
  /// 메모리 모니터링 간격 (초)
  static const int memoryMonitoringIntervalSeconds = 30;

  // === 네트워크 관련 상수 ===
  
  /// 기본 연결 타임아웃 (초)
  static const int defaultConnectionTimeoutSeconds = 30;
  
  /// 기본 요청 타임아웃 (초) 
  static const int defaultRequestTimeoutSeconds = 60;
  
  /// 최대 재시도 횟수
  static const int maxRetryAttempts = 3;
  
  /// 재시도 간격 (밀리초)
  static const int retryIntervalMilliseconds = 1000;

  // === 스케줄러 관련 상수 ===
  
  /// 스케줄러 체크 간격 (초)
  static const int schedulerCheckIntervalSeconds = 1;
  
  /// 최대 동시 실행 작업 수
  static const int maxConcurrentJobs = 10;
  
  /// 작업 실행 기록 최대 개수
  static const int maxJobExecutionHistory = 100;

  // === 메모리 관리 관련 상수 ===
  
  /// 고메모리 임계값 (MB)
  static const int highMemoryThresholdMB = 512;
  
  /// 메모리 정리 임계값 (MB)
  static const int memoryCleanupThresholdMB = 256;
  
  /// 메모리 모니터링 기록 최대 개수
  static const int maxMemoryReadings = 60;

  // === 캐시 관련 상수 ===
  
  /// 시맨틱 캐시 기본 크기
  static const int defaultSemanticCacheSize = 1000;
  
  /// 시맨틱 캐시 TTL (분)
  static const int semanticCacheTTLMinutes = 60;
  
  /// 유사도 임계값 (0.0 ~ 1.0)
  static const double semanticSimilarityThreshold = 0.8;

  // === 백그라운드 서비스 관련 상수 ===
  
  /// 기본 백그라운드 간격 (밀리초)
  static const int defaultBackgroundIntervalMs = 60000; // 1분
  
  /// iOS 최소 백그라운드 간격 (밀리초)
  static const int iosMinBackgroundIntervalMs = 900000; // 15분
  
  /// 최대 연속 에러 횟수
  static const int maxConsecutiveErrors = 5;

  // === 암호화 관련 상수 ===
  
  /// AES 키 크기 (비트)
  static const int aesKeySizeBits = 256;
  
  /// 솔트 크기 (바이트)
  static const int saltSizeBytes = 32;
  
  /// PBKDF2 반복 횟수
  static const int pbkdf2Iterations = 100000;

  // === 플러그인 관련 상수 ===
  
  /// 플러그인 로딩 타임아웃 (초)
  static const int pluginLoadTimeoutSeconds = 30;
  
  /// 플러그인 초기화 타임아웃 (초)
  static const int pluginInitTimeoutSeconds = 10;
  
  /// 최대 플러그인 개수
  static const int maxPluginCount = 100;

  // === Duration 상수들 ===
  
  /// 기본 연결 타임아웃
  static const Duration defaultConnectionTimeout = Duration(seconds: defaultConnectionTimeoutSeconds);
  
  /// 기본 요청 타임아웃
  static const Duration defaultRequestTimeout = Duration(seconds: defaultRequestTimeoutSeconds);
  
  /// 스케줄러 체크 간격
  static const Duration schedulerCheckInterval = Duration(seconds: schedulerCheckIntervalSeconds);
  
  /// 메모리 모니터링 간격
  static const Duration memoryMonitoringInterval = Duration(seconds: memoryMonitoringIntervalSeconds);
  
  /// 백그라운드 서비스 기본 간격
  static const Duration defaultBackgroundInterval = Duration(milliseconds: defaultBackgroundIntervalMs);
  
  /// iOS 최소 백그라운드 간격
  static const Duration iosMinBackgroundInterval = Duration(milliseconds: iosMinBackgroundIntervalMs);
  
  /// 로그 정리 주기
  static const Duration logCleanupInterval = Duration(minutes: logCleanupIntervalMinutes);
  
  /// 성능 메트릭 샘플링 간격
  static const Duration performanceMetricsSamplingInterval = Duration(seconds: performanceMetricsSamplingSeconds);

  // === 파일 경로 관련 상수 ===
  
  /// 로그 파일 확장자
  static const String logFileExtension = '.log';
  
  /// 설정 파일 확장자
  static const String configFileExtension = '.json';
  
  /// 백업 파일 확장자
  static const String backupFileExtension = '.bak';

  // === 이벤트 토픽 상수 ===
  
  /// MCP 초기화 완료 이벤트
  static const String eventMcpInitialized = 'mcp.initialized';
  
  /// MCP 종료 이벤트
  static const String eventMcpShutdown = 'mcp.shutdown';
  
  /// 고메모리 경고 이벤트
  static const String eventHighMemoryWarning = 'mcp.memory.high';
  
  /// Circuit Breaker 열림 이벤트
  static const String eventCircuitBreakerOpened = 'circuit_breaker.opened';
  
  /// Circuit Breaker 닫힘 이벤트
  static const String eventCircuitBreakerClosed = 'circuit_breaker.closed';

  // === 버전 정보 ===
  
  /// 현재 MCP 버전
  static const String mcpVersion = '1.0.0';
  
  /// 최소 지원 Flutter 버전
  static const String minFlutterVersion = '3.3.0';
  
  /// 최소 지원 Dart 버전
  static const String minDartVersion = '3.7.2';
}