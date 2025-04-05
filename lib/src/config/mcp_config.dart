import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';

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
}

/// MCP 서버 자동 시작 설정
class MCPServerConfig {
  /// 서버 이름
  final String name;

  /// 서버 버전
  final String version;

  /// 서버 기능
  final ServerCapabilities? capabilities;

  /// stdio 트랜스포트 사용 여부
  final bool useStdioTransport;

  /// SSE 트랜스포트 포트
  final int? ssePort;

  /// LLM 통합 설정
  final MCPLlmIntegration? integrateLlm;

  MCPServerConfig({
    required this.name,
    required this.version,
    this.capabilities,
    this.useStdioTransport = true,
    this.ssePort,
    this.integrateLlm,
  });
}

/// MCP 클라이언트 자동 시작 설정
class MCPClientConfig {
  /// 클라이언트 이름
  final String name;

  /// 클라이언트 버전
  final String version;

  /// 클라이언트 기능
  final ClientCapabilities? capabilities;

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
  });
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
    this.background,
    this.notification,
    this.tray,
    this.schedule,
    this.autoStartServer,
    this.autoStartClient,
  });
}