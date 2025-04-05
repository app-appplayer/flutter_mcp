export 'src/config/mcp_config.dart';
export 'src/config/background_config.dart';
export 'src/config/notification_config.dart';
export 'src/config/tray_config.dart';
export 'src/config/job.dart';
export 'src/utils/exceptions.dart';

import 'dart:async';
import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';

import 'src/config/mcp_config.dart';
import 'src/core/client_manager.dart';
import 'src/core/server_manager.dart';
import 'src/core/llm_manager.dart';
import 'src/core/scheduler.dart';
import 'src/platform/platform_services.dart';
import 'src/utils/logger.dart';
import 'src/utils/exceptions.dart';

/// Flutter MCP - 통합 MCP 관리 시스템
/// 
/// MCP(Model Context Protocol) 관련 구성 요소(`mcp_client`, `mcp_server`, `mcp_llm`)를
/// 통합하고 Flutter 환경에서의 다양한 플랫폼 기능(백그라운드 실행, 알림, 트레이 등)을 추가하는 패키지
class FlutterMCP {
  // 싱글톤 인스턴스
  static final FlutterMCP _instance = FlutterMCP._();

  /// 싱글톤 인스턴스 접근자
  static FlutterMCP get instance => _instance;

  // Private 생성자
  FlutterMCP._();

  // MCP 핵심 매니저
  final MCPClientManager _clientManager = MCPClientManager();
  final MCPServerManager _serverManager = MCPServerManager();
  final MCPLlmManager _llmManager = MCPLlmManager();

  // 플랫폼 서비스
  final PlatformServices _platformServices = PlatformServices();

  // 작업 스케줄러
  final MCPScheduler _scheduler = MCPScheduler();

  // 플러그인 상태
  bool _initialized = false;
  MCPConfig? _config;

  // 통합 로거
  static final MCPLogger _logger = MCPLogger('flutter_mcp');

  /// 플러그인이 초기화되었는지 여부
  bool get initialized => _initialized;

  /// 플러그인 초기화
  /// 
  /// [config]에 지정된 설정에 따라 필요한 구성 요소를 초기화합니다.
  Future<void> init(MCPConfig config) async {
    if (_initialized) {
      _logger.warning('Flutter MCP가 이미 초기화되었습니다');
      return;
    }

    _config = config;

    // 초기화 로깅 설정
    if (config.loggingLevel != null) {
      MCPLogger.setDefaultLevel(config.loggingLevel!);
    }

    _logger.info('Flutter MCP 초기화 시작');

    // 플랫폼 서비스 초기화
    await _platformServices.initialize(config);

    // 매니저 초기화
    await _clientManager.initialize();
    await _serverManager.initialize();
    await _llmManager.initialize();

    // 스케줄러 초기화
    if (config.schedule != null && config.schedule!.isNotEmpty) {
      _scheduler.initialize();
      for (final job in config.schedule!) {
        _scheduler.addJob(job);
      }
      _scheduler.start();
    }

    // 자동 시작 설정
    if (config.autoStart) {
      _logger.info('자동 시작 설정에 따라 서비스 시작');
      await startServices();
    }

    _initialized = true;
    _logger.info('Flutter MCP 초기화 완료');
  }

  /// 서비스 시작
  Future<void> startServices() async {
    if (!_initialized) {
      throw MCPException('Flutter MCP가 초기화되지 않았습니다');
    }

    // 백그라운드 서비스 시작
    if (_config!.useBackgroundService) {
      await _platformServices.startBackgroundService();
    }

    // 알림 표시
    if (_config!.useNotification) {
      await _platformServices.showNotification(
        title: '${_config!.appName} 실행 중',
        body: 'MCP 서비스가 실행 중입니다',
      );
    }

    // 자동 시작 구성 요소 실행
    await _startConfiguredComponents();
  }

  /// 설정에 따른 구성 요소 시작
  Future<void> _startConfiguredComponents() async {
    final config = _config!;

    // 자동 시작 서버
    if (config.autoStartServer != null && config.autoStartServer!.isNotEmpty) {
      for (final serverConfig in config.autoStartServer!) {
        final serverId = await createServer(
          name: serverConfig.name,
          version: serverConfig.version,
          capabilities: serverConfig.capabilities,
          useStdioTransport: serverConfig.useStdioTransport,
          ssePort: serverConfig.ssePort,
        );

        // 서버를 LLM과 통합 (필요한 경우)
        if (serverConfig.integrateLlm != null) {
          String llmId;

          if (serverConfig.integrateLlm!.existingLlmId != null) {
            llmId = serverConfig.integrateLlm!.existingLlmId!;
          } else {
            llmId = await createLlm(
              providerName: serverConfig.integrateLlm!.providerName!,
              config: serverConfig.integrateLlm!.config!,
            );
          }

          await integrateServerWithLlm(
            serverId: serverId,
            llmId: llmId,
          );
        }

        // 서버 시작
        connectServer(serverId);
      }
    }

    // 자동 시작 클라이언트
    if (config.autoStartClient != null && config.autoStartClient!.isNotEmpty) {
      for (final clientConfig in config.autoStartClient!) {
        final clientId = await createClient(
          name: clientConfig.name,
          version: clientConfig.version,
          capabilities: clientConfig.capabilities,
          transportCommand: clientConfig.transportCommand,
          transportArgs: clientConfig.transportArgs,
          serverUrl: clientConfig.serverUrl,
        );

        // 클라이언트를 LLM과 통합 (필요한 경우)
        if (clientConfig.integrateLlm != null) {
          String llmId;

          if (clientConfig.integrateLlm!.existingLlmId != null) {
            llmId = clientConfig.integrateLlm!.existingLlmId!;
          } else {
            llmId = await createLlm(
              providerName: clientConfig.integrateLlm!.providerName!,
              config: clientConfig.integrateLlm!.config!,
            );
          }

          await integrateClientWithLlm(
            clientId: clientId,
            llmId: llmId,
          );
        }

        // 클라이언트 연결
        await connectClient(clientId);
      }
    }
  }

  /// MCP 클라이언트 생성
  /// 
  /// [name]: 클라이언트 이름
  /// [version]: 클라이언트 버전
  /// [capabilities]: 클라이언트 기능
  /// [transportCommand]: stdio 트랜스포트 명령어
  /// [transportArgs]: stdio 트랜스포트 인수
  /// [serverUrl]: SSE 트랜스포트 URL
  /// 
  /// 생성된 클라이언트의 ID를 반환합니다.
  Future<String> createClient({
    required String name,
    required String version,
    ClientCapabilities? capabilities,
    String? transportCommand,
    List<String>? transportArgs,
    String? serverUrl,
  }) async {
    _verifyInitialized();

    _logger.info('MCP 클라이언트 생성: $name');

    // 클라이언트 생성
    final clientId = _clientManager.generateId();
    final client = McpClient.createClient(
      name: name,
      version: version,
      capabilities: capabilities ?? ClientCapabilities(),
    );

    // 트랜스포트 생성 (명령어 또는 URL에 따라)
    ClientTransport? transport;
    if (transportCommand != null) {
      transport = await McpClient.createStdioTransport(
        command: transportCommand,
        arguments: transportArgs ?? [],
      );
    } else if (serverUrl != null) {
      transport = await McpClient.createSseTransport(
        serverUrl: serverUrl,
      );
    }

    // 클라이언트 등록
    await _clientManager.registerClient(clientId, client, transport);

    return clientId;
  }

  /// MCP 서버 생성
  /// 
  /// [name]: 서버 이름
  /// [version]: 서버 버전
  /// [capabilities]: 서버 기능
  /// [useStdioTransport]: stdio 트랜스포트 사용 여부
  /// [ssePort]: SSE 트랜스포트 포트
  /// 
  /// 생성된 서버의 ID를 반환합니다.
  Future<String> createServer({
    required String name,
    required String version,
    ServerCapabilities? capabilities,
    bool useStdioTransport = true,
    int? ssePort,
  }) async {
    _verifyInitialized();

    _logger.info('MCP 서버 생성: $name');

    // 서버 생성
    final serverId = _serverManager.generateId();
    final server = McpServer.createServer(
      name: name,
      version: version,
      capabilities: capabilities ?? ServerCapabilities(),
    );

    // 트랜스포트 생성
    ServerTransport? transport;
    if (useStdioTransport) {
      transport = McpServer.createStdioTransport();
    } else if (ssePort != null) {
      transport = McpServer.createSseTransport(
        endpoint: '/sse',
        messagesEndpoint: '/messages',
        port: ssePort,
      );
    }

    // 서버 등록
    _serverManager.registerServer(serverId, server, transport);

    return serverId;
  }

  /// MCP LLM 생성
  /// 
  /// [providerName]: LLM 공급자 이름
  /// [config]: LLM 설정
  /// 
  /// 생성된 LLM의 ID를 반환합니다.
  Future<String> createLlm({
    required String providerName,
    required LlmConfiguration config,
  }) async {
    _verifyInitialized();

    _logger.info('MCP LLM 생성: $providerName');

    // LLM 인스턴스 가져오기
    final mcpLlm = MCPLlm.instance;

    // LLM 클라이언트 생성
    final llmClient = await mcpLlm.createClient(
      providerName: providerName,
      config: config,
    );

    // LLM ID 생성 및 등록
    final llmId = _llmManager.generateId();
    _llmManager.registerLlm(llmId, mcpLlm, llmClient);

    return llmId;
  }

  /// LLM 서버 통합
  /// 
  /// [serverId]: 서버 ID
  /// [llmId]: LLM ID
  Future<void> integrateServerWithLlm({
    required String serverId,
    required String llmId,
  }) async {
    _verifyInitialized();

    _logger.info('서버와 LLM 통합: $serverId + $llmId');

    final server = _serverManager.getServer(serverId);
    if (server == null) {
      throw MCPException('서버를 찾을 수 없음: $serverId');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM을 찾을 수 없음: $llmId');
    }

    // LLM 서버 생성
    final llmServer = LlmServer(
      llmProvider: llmInfo.client.getLlmProvider(),
      mcpServer: server,
    );

    // LLM 도구 등록
    await llmServer.registerLlmTools();

    // 서버 매니저에 LLM 서버 등록
    _serverManager.setLlmServer(serverId, llmServer);
  }

  /// LLM 클라이언트 통합
  /// 
  /// [clientId]: 클라이언트 ID
  /// [llmId]: LLM ID
  Future<void> integrateClientWithLlm({
    required String clientId,
    required String llmId,
  }) async {
    _verifyInitialized();

    _logger.info('클라이언트와 LLM 통합: $clientId + $llmId');

    final client = _clientManager.getClient(clientId);
    if (client == null) {
      throw MCPException('클라이언트를 찾을 수 없음: $clientId');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM을 찾을 수 없음: $llmId');
    }

    // LLM에 클라이언트 등록
    await _llmManager.addClientToLlm(llmId, client);
  }

  /// 클라이언트 연결
  /// 
  /// [clientId]: 클라이언트 ID
  Future<void> connectClient(String clientId) async {
    _verifyInitialized();

    _logger.info('클라이언트 연결: $clientId');

    final clientInfo = _clientManager.getClientInfo(clientId);
    if (clientInfo == null) {
      throw MCPException('클라이언트를 찾을 수 없음: $clientId');
    }

    if (clientInfo.transport == null) {
      throw MCPException('클라이언트에 트랜스포트가 구성되지 않음: $clientId');
    }

    await clientInfo.client.connect(clientInfo.transport!);
    clientInfo.connected = true;
  }

  /// 서버 연결
  /// 
  /// [serverId]: 서버 ID
  void connectServer(String serverId) {
    _verifyInitialized();

    _logger.info('서버 연결: $serverId');

    final serverInfo = _serverManager.getServerInfo(serverId);
    if (serverInfo == null) {
      throw MCPException('서버를 찾을 수 없음: $serverId');
    }

    if (serverInfo.transport == null) {
      throw MCPException('서버에 트랜스포트가 구성되지 않음: $serverId');
    }

    serverInfo.server.connect(serverInfo.transport!);
    serverInfo.running = true;
  }

  /// 클라이언트로 도구 호출
  /// 
  /// [clientId]: 클라이언트 ID
  /// [toolName]: 도구 이름
  /// [arguments]: 도구 인수
  Future<CallToolResult> callTool(
      String clientId,
      String toolName,
      Map<String, dynamic> arguments,
      ) async {
    _verifyInitialized();

    final clientInfo = _clientManager.getClientInfo(clientId);
    if (clientInfo == null) {
      throw MCPException('클라이언트를 찾을 수 없음: $clientId');
    }

    return await clientInfo.client.callTool(toolName, arguments);
  }

  /// LLM으로 채팅
  /// 
  /// [llmId]: LLM ID
  /// [message]: 메시지 내용
  /// [enableTools]: 도구 사용 가능 여부
  /// [parameters]: 추가 매개변수
  Future<LlmResponse> chat(
      String llmId,
      String message, {
        bool enableTools = false,
        Map<String, dynamic>? parameters,
      }) async {
    _verifyInitialized();

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM을 찾을 수 없음: $llmId');
    }

    return await llmInfo.client.chat(
      message,
      enableTools: enableTools,
      parameters: parameters,
    );
  }

  /// 작업 스케줄링 추가
  /// 
  /// [job]: 추가할 작업
  /// 
  /// 생성된 작업의 ID를 반환합니다.
  String addScheduledJob(MCPJob job) {
    _verifyInitialized();

    final jobId = _scheduler.addJob(job);
    return jobId;
  }

  /// 작업 스케줄링 제거
  /// 
  /// [jobId]: 제거할 작업 ID
  void removeScheduledJob(String jobId) {
    _verifyInitialized();

    _scheduler.removeJob(jobId);
  }

  /// 보안 저장소에 저장
  /// 
  /// [key]: 저장할 키
  /// [value]: 저장할 값
  Future<void> secureStore(String key, String value) async {
    _verifyInitialized();

    await _platformServices.secureStore(key, value);
  }

  /// 보안 저장소에서 읽기
  /// 
  /// [key]: 읽을 키
  Future<String?> secureRead(String key) async {
    _verifyInitialized();

    return await _platformServices.secureRead(key);
  }

  /// 모든 서비스 종료
  Future<void> shutdown() async {
    if (!_initialized) return;

    _logger.info('Flutter MCP 종료 시작');

    // 스케줄러 종료
    _scheduler.stop();

    // 매니저 종료
    await Future.wait([
      _clientManager.closeAll(),
      _serverManager.closeAll(),
      _llmManager.closeAll(),
    ]);

    // 플랫폼 서비스 종료
    await _platformServices.shutdown();

    _initialized = false;
    _logger.info('Flutter MCP 종료 완료');
  }

  /// ID 접근 메서드들
  List<String> get allClientIds => _clientManager.getAllClientIds();
  List<String> get allServerIds => _serverManager.getAllServerIds();
  List<String> get allLlmIds => _llmManager.getAllLlmIds();

  /// 객체 접근 메서드들
  Client? getClient(String clientId) => _clientManager.getClient(clientId);
  Server? getServer(String serverId) => _serverManager.getServer(serverId);
  LlmClient? getLlm(String llmId) => _llmManager.getLlm(llmId);

  /// 상태 조회
  Map<String, dynamic> getSystemStatus() {
    return {
      'initialized': _initialized,
      'clients': _clientManager.getAllClientIds().length,
      'servers': _serverManager.getAllServerIds().length,
      'llms': _llmManager.getAllLlmIds().length,
      'backgroundServiceRunning': _platformServices.isBackgroundServiceRunning,
      'schedulerRunning': _scheduler.isRunning,
      'clientsStatus': _clientManager.getStatus(),
      'serversStatus': _serverManager.getStatus(),
      'llmsStatus': _llmManager.getStatus(),
    };
  }

  // 초기화 확인 헬퍼 메서드
  void _verifyInitialized() {
    if (!_initialized) {
      throw MCPException('Flutter MCP가 초기화되지 않았습니다');
    }
  }
}