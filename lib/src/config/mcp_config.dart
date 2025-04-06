import 'package:mcp_client/mcp_client.dart' as client hide LogLevel;
import 'package:mcp_server/mcp_server.dart' as server hide LogLevel;
import 'package:mcp_llm/mcp_llm.dart'  hide LogLevel;

import 'background_config.dart';
import 'notification_config.dart';
import 'tray_config.dart';
import 'job.dart';
import '../utils/logger.dart';

/// MCP LLM 통합 설정
class MCPLlmIntegration {
  /// 기존 LLM ID (기존 LLM 사용 시)
  final String? existingLlmId;

  /// LLM 공급자 이름 (새 LLM 생성 시)
  final String? providerName;

  /// LLM 설정 (새 LLM 생성 시)
  final LlmConfiguration? config;

  MCPLlmIntegration({
    this.existingLlmId,
    this.providerName,
    this.config,
  }) : assert(existingLlmId != null || (providerName != null && config != null),
  'existingLlmId 또는 (providerName과 config) 중 하나는 제공되어야 합니다');

  /// Validate configuration
  void validate() {
    if (existingLlmId == null && (providerName == null || config == null)) {
      throw ArgumentError('Either existingLlmId or both providerName and config must be provided');
    }

    if (config != null) {
      // Validate API key
      if (config!.apiKey == null || config!.apiKey!.isEmpty || config!.apiKey == 'placeholder-key') {
        throw ArgumentError('API key is missing or invalid in LLM configuration');
      }

      // Validate model
      if (config!.model == null || config!.model!.isEmpty) {
        throw ArgumentError('Model name is required in LLM configuration');
      }
    }
  }

  /// Create a copy with modified values
  MCPLlmIntegration copyWith({
    String? existingLlmId,
    String? providerName,
    LlmConfiguration? config,
  }) {
    return MCPLlmIntegration(
      existingLlmId: existingLlmId ?? this.existingLlmId,
      providerName: providerName ?? this.providerName,
      config: config ?? this.config,
    );
  }
}

/// MCP 서버 자동 시작 설정
class MCPServerConfig {
  /// 서버 이름
  final String name;

  /// 서버 버전
  final String version;

  /// 서버 기능
  final server.ServerCapabilities? capabilities;

  /// stdio 트랜스포트 사용 여부
  final bool useStdioTransport;

  /// SSE 트랜스포트 포트
  final int? ssePort;

  /// SSE fallback ports
  final List<int>? fallbackPorts;

  /// SSE authentication token
  final String? authToken;

  /// LLM 통합 설정
  final MCPLlmIntegration? integrateLlm;

  MCPServerConfig({
    required this.name,
    required this.version,
    this.capabilities,
    this.useStdioTransport = true,
    this.ssePort,
    this.fallbackPorts,
    this.authToken,
    this.integrateLlm,
  }) {
    validate();
  }

  /// Validate configuration
  void validate() {
    if (name.isEmpty) {
      throw ArgumentError('Server name cannot be empty');
    }

    if (version.isEmpty) {
      throw ArgumentError('Server version cannot be empty');
    }

    if (!useStdioTransport && ssePort == null) {
      throw ArgumentError('SSE port must be provided when using SSE transport');
    }

    if (integrateLlm != null) {
      integrateLlm!.validate();
    }
  }

  /// Create a copy with modified values
  MCPServerConfig copyWith({
    String? name,
    String? version,
    server.ServerCapabilities? capabilities,
    bool? useStdioTransport,
    int? ssePort,
    List<int>? fallbackPorts,
    String? authToken,
    MCPLlmIntegration? integrateLlm,
  }) {
    return MCPServerConfig(
      name: name ?? this.name,
      version: version ?? this.version,
      capabilities: capabilities ?? this.capabilities,
      useStdioTransport: useStdioTransport ?? this.useStdioTransport,
      ssePort: ssePort ?? this.ssePort,
      fallbackPorts: fallbackPorts ?? this.fallbackPorts,
      authToken: authToken ?? this.authToken,
      integrateLlm: integrateLlm ?? this.integrateLlm,
    );
  }
}

/// MCP 클라이언트 자동 시작 설정
class MCPClientConfig {
  /// 클라이언트 이름
  final String name;

  /// 클라이언트 버전
  final String version;

  /// 클라이언트 기능
  final client.ClientCapabilities? capabilities;

  /// stdio 트랜스포트 명령어
  final String? transportCommand;

  /// stdio 트랜스포트 인수
  final List<String>? transportArgs;

  /// SSE 트랜스포트 URL
  final String? serverUrl;

  /// LLM 통합 설정
  final MCPLlmIntegration? integrateLlm;

  MCPClientConfig({
    required this.name,
    required this.version,
    this.capabilities,
    this.transportCommand,
    this.transportArgs,
    this.serverUrl,
    this.integrateLlm,
  }) {
    validate();
  }

  /// Validate configuration
  void validate() {
    if (name.isEmpty) {
      throw ArgumentError('Client name cannot be empty');
    }

    if (version.isEmpty) {
      throw ArgumentError('Client version cannot be empty');
    }

    if (transportCommand == null && serverUrl == null) {
      throw ArgumentError('Either transportCommand or serverUrl must be provided');
    }

    if (integrateLlm != null) {
      integrateLlm!.validate();
    }
  }

  /// Create a copy with modified values
  MCPClientConfig copyWith({
    String? name,
    String? version,
    client.ClientCapabilities? capabilities,
    String? transportCommand,
    List<String>? transportArgs,
    String? serverUrl,
    MCPLlmIntegration? integrateLlm,
  }) {
    return MCPClientConfig(
      name: name ?? this.name,
      version: version ?? this.version,
      capabilities: capabilities ?? this.capabilities,
      transportCommand: transportCommand ?? this.transportCommand,
      transportArgs: transportArgs ?? this.transportArgs,
      serverUrl: serverUrl ?? this.serverUrl,
      integrateLlm: integrateLlm ?? this.integrateLlm,
    );
  }
}

/// MCP 메인 설정 클래스
class MCPConfig {
  /// 앱 이름
  final String appName;

  /// 앱 버전
  final String appVersion;

  /// 백그라운드 서비스 사용 여부
  final bool useBackgroundService;

  /// 알림 사용 여부
  final bool useNotification;

  /// 트레이 사용 여부
  final bool useTray;

  /// 보안 저장소 사용 여부
  final bool secure;

  /// 라이프사이클 관리 여부
  final bool lifecycleManaged;

  /// 자동 시작 여부
  final bool autoStart;

  /// 로깅 레벨
  final LogLevel? loggingLevel;

  /// 성능 모니터링 사용 여부
  final bool? enablePerformanceMonitoring;

  /// 성능 메트릭 내보내기 사용 여부
  final bool? enableMetricsExport;

  /// 성능 메트릭 내보내기 경로
  final String? metricsExportPath;

  /// 플러그인 자동 로드 여부
  final bool? autoLoadPlugins;

  /// 플러그인 설정
  final Map<String, Map<String, dynamic>>? pluginConfigurations;

  /// 높은 메모리 사용량 임계값 (MB)
  final int? highMemoryThresholdMB;

  /// 낮은 배터리 경고 임계값 (%)
  final int? lowBatteryWarningThreshold;

  /// 연결 재시도 제한
  final int? maxConnectionRetries;

  /// LLM 요청 제한 시간 (밀리초)
  final int? llmRequestTimeoutMs;

  /// 백그라운드 설정
  final BackgroundConfig? background;

  /// 알림 설정
  final NotificationConfig? notification;

  /// 트레이 설정
  final TrayConfig? tray;

  /// 스케줄 작업
  final List<MCPJob>? schedule;

  /// 자동 시작 서버 설정
  final List<MCPServerConfig>? autoStartServer;

  /// 자동 시작 클라이언트 설정
  final List<MCPClientConfig>? autoStartClient;

  MCPConfig({
    required this.appName,
    required this.appVersion,
    this.useBackgroundService = true,
    this.useNotification = true,
    this.useTray = true,
    this.secure = true,
    this.lifecycleManaged = true,
    this.autoStart = true,
    this.loggingLevel,
    this.enablePerformanceMonitoring = false,
    this.enableMetricsExport = false,
    this.metricsExportPath,
    this.autoLoadPlugins = true,
    this.pluginConfigurations,
    this.highMemoryThresholdMB = 1024,  // 1GB
    this.lowBatteryWarningThreshold = 20,  // 20%
    this.maxConnectionRetries = 3,
    this.llmRequestTimeoutMs = 60000,  // 60 seconds
    this.background,
    this.notification,
    this.tray,
    this.schedule,
    this.autoStartServer,
    this.autoStartClient,
  }) {
    validate();
  }

  /// Validate the configuration
  void validate() {
    if (appName.isEmpty) {
      throw ArgumentError('App name cannot be empty');
    }

    if (appVersion.isEmpty) {
      throw ArgumentError('App version cannot be empty');
    }

    if (enableMetricsExport == true && metricsExportPath == null) {
      throw ArgumentError('Metrics export path must be provided when metrics export is enabled');
    }

    if (autoStartServer != null) {
      for (final config in autoStartServer!) {
        config.validate();
      }
    }

    if (autoStartClient != null) {
      for (final config in autoStartClient!) {
        config.validate();
      }
    }

    if (highMemoryThresholdMB != null && highMemoryThresholdMB! <= 0) {
      throw ArgumentError('High memory threshold must be positive');
    }

    if (lowBatteryWarningThreshold != null &&
        (lowBatteryWarningThreshold! < 0 || lowBatteryWarningThreshold! > 100)) {
      throw ArgumentError('Low battery warning threshold must be between 0 and 100');
    }

    if (maxConnectionRetries != null && maxConnectionRetries! < 0) {
      throw ArgumentError('Max connection retries must be non-negative');
    }

    if (llmRequestTimeoutMs != null && llmRequestTimeoutMs! <= 0) {
      throw ArgumentError('LLM request timeout must be positive');
    }
  }

  /// Create a copy of this configuration with modified values
  MCPConfig copyWith({
    String? appName,
    String? appVersion,
    bool? useBackgroundService,
    bool? useNotification,
    bool? useTray,
    bool? secure,
    bool? lifecycleManaged,
    bool? autoStart,
    LogLevel? loggingLevel,
    bool? enablePerformanceMonitoring,
    bool? enableMetricsExport,
    String? metricsExportPath,
    bool? autoLoadPlugins,
    Map<String, Map<String, dynamic>>? pluginConfigurations,
    int? highMemoryThresholdMB,
    int? lowBatteryWarningThreshold,
    int? maxConnectionRetries,
    int? llmRequestTimeoutMs,
    BackgroundConfig? background,
    NotificationConfig? notification,
    TrayConfig? tray,
    List<MCPJob>? schedule,
    List<MCPServerConfig>? autoStartServer,
    List<MCPClientConfig>? autoStartClient,
  }) {
    return MCPConfig(
      appName: appName ?? this.appName,
      appVersion: appVersion ?? this.appVersion,
      useBackgroundService: useBackgroundService ?? this.useBackgroundService,
      useNotification: useNotification ?? this.useNotification,
      useTray: useTray ?? this.useTray,
      secure: secure ?? this.secure,
      lifecycleManaged: lifecycleManaged ?? this.lifecycleManaged,
      autoStart: autoStart ?? this.autoStart,
      loggingLevel: loggingLevel ?? this.loggingLevel,
      enablePerformanceMonitoring: enablePerformanceMonitoring ?? this.enablePerformanceMonitoring,
      enableMetricsExport: enableMetricsExport ?? this.enableMetricsExport,
      metricsExportPath: metricsExportPath ?? this.metricsExportPath,
      autoLoadPlugins: autoLoadPlugins ?? this.autoLoadPlugins,
      pluginConfigurations: pluginConfigurations ?? this.pluginConfigurations,
      highMemoryThresholdMB: highMemoryThresholdMB ?? this.highMemoryThresholdMB,
      lowBatteryWarningThreshold: lowBatteryWarningThreshold ?? this.lowBatteryWarningThreshold,
      maxConnectionRetries: maxConnectionRetries ?? this.maxConnectionRetries,
      llmRequestTimeoutMs: llmRequestTimeoutMs ?? this.llmRequestTimeoutMs,
      background: background ?? this.background,
      notification: notification ?? this.notification,
      tray: tray ?? this.tray,
      schedule: schedule ?? this.schedule,
      autoStartServer: autoStartServer ?? this.autoStartServer,
      autoStartClient: autoStartClient ?? this.autoStartClient,
    );
  }

  /// Create a configuration for development environments
  factory MCPConfig.development({
    required String appName,
    required String appVersion,
  }) {
    return MCPConfig(
      appName: appName,
      appVersion: appVersion,
      loggingLevel: LogLevel.debug,
      enablePerformanceMonitoring: true,
      background: BackgroundConfig.defaultConfig(),
    );
  }

  /// Create a configuration for production environments
  factory MCPConfig.production({
    required String appName,
    required String appVersion,
  }) {
    return MCPConfig(
      appName: appName,
      appVersion: appVersion,
      loggingLevel: LogLevel.info,
      enablePerformanceMonitoring: false,
      background: BackgroundConfig(
        notificationChannelId: 'production_${appName.toLowerCase()}_channel',
        notificationChannelName: '$appName Service',
        notificationDescription: '$appName Background Service',
        autoStartOnBoot: true,
        intervalMs: 30000, // 30 seconds for production
        keepAlive: true,
      ),
    );
  }

  /// Convert configuration to a map for storage/debugging
  Map<String, dynamic> toMap() {
    return {
      'appName': appName,
      'appVersion': appVersion,
      'useBackgroundService': useBackgroundService,
      'useNotification': useNotification,
      'useTray': useTray,
      'secure': secure,
      'lifecycleManaged': lifecycleManaged,
      'autoStart': autoStart,
      'loggingLevel': loggingLevel?.toString().split('.').last,
      'enablePerformanceMonitoring': enablePerformanceMonitoring,
      'enableMetricsExport': enableMetricsExport,
      'metricsExportPath': metricsExportPath,
      'autoLoadPlugins': autoLoadPlugins,
      'highMemoryThresholdMB': highMemoryThresholdMB,
      'lowBatteryWarningThreshold': lowBatteryWarningThreshold,
      'maxConnectionRetries': maxConnectionRetries,
      'llmRequestTimeoutMs': llmRequestTimeoutMs,
      'background': background != null ? {
        'notificationChannelId': background!.notificationChannelId,
        'autoStartOnBoot': background!.autoStartOnBoot,
        'intervalMs': background!.intervalMs,
        'keepAlive': background!.keepAlive,
      } : null,
      'autoStartServerCount': autoStartServer?.length,
      'autoStartClientCount': autoStartClient?.length,
    };
  }
}