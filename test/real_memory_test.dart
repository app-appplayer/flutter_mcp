import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/utils/memory_manager.dart';
import 'package:flutter_mcp/src/utils/resource_manager.dart';
import 'package:flutter_mcp/src/utils/event_system.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('실제 메모리 관리 테스트', () {
    late FlutterMCP mcp;
    
    setUp(() async {
      // Set up method channel mock handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_mcp'),
        (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'initialize':
              return null;
            case 'startBackgroundService':
              return true;
            case 'stopBackgroundService':
              return true;
            case 'showNotification':
              return null;
            case 'cancelAllNotifications':
              return null;
            case 'shutdown':
              return null;
            case 'getPlatformVersion':
              return 'Test Platform 1.0';
            default:
              return null;
          }
        },
      );
      
      mcp = FlutterMCP.instance;
      if (!mcp.isInitialized) {
        await mcp.init(MCPConfig(
          appName: 'Memory Test',
          appVersion: '1.0.0',
          highMemoryThresholdMB: 200, // 200MB 임계점 설정
        ));
      }
    });

    tearDown(() async {
      try {
        await mcp.shutdown();
      } catch (_) {
        // Ignore shutdown errors in tests
      }
    });

    tearDownAll(() {
      // Clear method channel mock
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_mcp'),
        null,
      );
    });

    test('실제 메모리 사용량 측정', () async {
      print('=== 실제 메모리 사용량 측정 테스트 ===');
      
      // 초기 메모리 상태 확인
      final initialMemory = ProcessInfo.currentRss;
      print('초기 메모리 사용량: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 여러 서버와 클라이언트 생성 (메모리 사용량 증가)
      final serverIds = <String>[];
      final clientIds = <String>[];
      
      for (int i = 0; i < 5; i++) {
        // 서버 생성
        final serverId = await mcp.createServer(
          name: 'Test Server $i',
          version: '1.0.0',
          config: MCPServerConfig(
            name: 'Test Server $i',
            version: '1.0.0',
            transportType: 'stdio',
          ),
        );
        serverIds.add(serverId);
        
        // 클라이언트 생성
        final clientId = await mcp.createClient(
          name: 'Test Client $i',
          version: '1.0.0',
          config: MCPClientConfig(
            name: 'Test Client $i',
            version: '1.0.0',
            transportType: 'stdio',
            transportCommand: 'echo',
          ),
        );
        clientIds.add(clientId);
      }
      
      // 메모리 사용량 증가 확인
      final afterCreationMemory = ProcessInfo.currentRss;
      final memoryIncrease = afterCreationMemory - initialMemory;
      print('서버/클라이언트 생성 후 메모리: ${(afterCreationMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      print('메모리 증가량: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');
      
      expect(memoryIncrease, greaterThan(0)); // 메모리가 증가해야 함
      
      // 리소스 정리
      await mcp.shutdown();
      
      // 짧은 지연 후 메모리 확인 (GC 시간 제공)
      await Future.delayed(Duration(milliseconds: 500));
      
      final afterCleanupMemory = ProcessInfo.currentRss;
      final memoryReclaimed = afterCreationMemory - afterCleanupMemory;
      print('정리 후 메모리: ${(afterCleanupMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      print('회수된 메모리: ${(memoryReclaimed / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 메모리가 어느정도 회수되었는지 확인 (완전히 같지는 않을 수 있음)
      expect(afterCleanupMemory, lessThan(afterCreationMemory));
    });

    test('메모리 임계점 감지 테스트', () async {
      print('=== 메모리 임계점 감지 테스트 ===');
      
      bool highMemoryCallbackCalled = false;
      String? memoryEventData;
      
      // 고메모리 콜백 등록
      MemoryManager.instance.addHighMemoryCallback(() async {
        highMemoryCallbackCalled = true;
        print('고메모리 콜백이 호출되었습니다!');
      });
      
      // 메모리 이벤트 리스너 등록
      EventSystem.instance.subscribe('memory.high', (data) {
        memoryEventData = data.toString();
        print('메모리 이벤트 수신: $memoryEventData');
      });
      
      // 메모리 모니터링 시작 (더 빠른 간격으로)
      MemoryManager.instance.initialize(
        startMonitoring: true,
        monitoringInterval: Duration(milliseconds: 100),
        highMemoryThresholdMB: 50, // 매우 낮은 임계점 설정 (테스트용)
      );
      
      // 메모리 모니터링이 실행될 때까지 대기
      await Future.delayed(Duration(milliseconds: 500));
      
      // 메모리 모니터링 중지
      MemoryManager.instance.stopMemoryMonitoring();
      
      print('고메모리 콜백 호출됨: $highMemoryCallbackCalled');
      print('메모리 이벤트 데이터: $memoryEventData');
      
      // 낮은 임계점이므로 콜백이 호출되어야 함
      expect(highMemoryCallbackCalled, isTrue);
      expect(memoryEventData, isNotNull);
    });

    test('리소스 의존성 관리 테스트', () async {
      print('=== 리소스 의존성 관리 테스트 ===');
      
      final resourceManager = ResourceManager.instance;
      final disposedOrder = <String>[];
      
      // 의존성이 있는 리소스들 등록
      resourceManager.register<String>(
        'dependency1',
        'resource1',
        (resource) async {
          disposedOrder.add('dependency1');
          print('dependency1 정리됨');
        },
        priority: ResourceManager.highPriority,
      );
      
      resourceManager.register<String>(
        'dependency2', 
        'resource2',
        (resource) async {
          disposedOrder.add('dependency2');
          print('dependency2 정리됨');
        },
        dependencies: ['dependency1'],
        priority: ResourceManager.mediumPriority,
      );
      
      resourceManager.register<String>(
        'main_resource',
        'main',
        (resource) async {
          disposedOrder.add('main_resource');
          print('main_resource 정리됨');
        },
        dependencies: ['dependency1', 'dependency2'],
        priority: ResourceManager.lowPriority,
      );
      
      // 메인 리소스 정리 (의존성이 먼저 정리되어야 함)
      await resourceManager.dispose('dependency1');
      
      print('정리 순서: $disposedOrder');
      
      // 의존성 때문에 main_resource와 dependency2가 먼저 정리되었는지 확인
      expect(disposedOrder.contains('main_resource'), isTrue);
      expect(disposedOrder.contains('dependency2'), isTrue);
      expect(disposedOrder.last, equals('dependency1')); // dependency1이 마지막에 정리
    });

    test('메모리 청크 처리 테스트', () async {
      print('=== 메모리 청크 처리 테스트 ===');
      
      // 큰 데이터 생성
      final largeDataSet = List.generate(1000, (index) => 'data_item_$index');
      
      final initialMemory = ProcessInfo.currentRss;
      print('청크 처리 전 메모리: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 청크별로 처리 (메모리 효율적)
      final results = await MemoryManager.processInChunks<String, String>(
        items: largeDataSet,
        processItem: (item) async {
          // 약간의 처리 시간과 메모리 사용
          await Future.delayed(Duration(milliseconds: 1));
          return item.toUpperCase();
        },
        chunkSize: 50, // 50개씩 처리
        pauseBetweenChunks: Duration(milliseconds: 10), // 청크 간 일시정지
      );
      
      final afterProcessingMemory = ProcessInfo.currentRss;
      print('청크 처리 후 메모리: ${(afterProcessingMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      expect(results.length, equals(largeDataSet.length));
      expect(results.first, equals('DATA_ITEM_0'));
      
      // 메모리 사용량이 제어되었는지 확인 (큰 증가가 없어야 함)
      final memoryIncrease = afterProcessingMemory - initialMemory;
      print('메모리 증가량: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 청크 처리로 인해 메모리 증가가 제한적이어야 함
      expect(memoryIncrease, lessThan(50 * 1024 * 1024)); // 50MB 미만으로 증가
    });

    test('병렬 청크 처리와 동시성 제어 테스트', () async {
      print('=== 병렬 청크 처리와 동시성 제어 테스트 ===');
      
      final dataSet = List.generate(100, (index) => index);
      
      final initialMemory = ProcessInfo.currentRss;
      print('병렬 처리 전 메모리: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 제한된 동시성으로 병렬 처리
      final results = await MemoryManager.processInParallelChunks<int, int>(
        items: dataSet,
        processItem: (item) async {
          // CPU 집약적 작업 시뮬레이션
          await Future.delayed(Duration(milliseconds: 10));
          return item * item;
        },
        maxConcurrent: 3, // 최대 3개 동시 실행
        chunkSize: 10,
        pauseBetweenChunks: Duration(milliseconds: 5),
      );
      
      final afterProcessingMemory = ProcessInfo.currentRss;
      print('병렬 처리 후 메모리: ${(afterProcessingMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      expect(results.length, equals(dataSet.length));
      expect(results[5], equals(25)); // 5^2 = 25
      
      // 동시성 제어로 메모리 사용량이 제한되었는지 확인
      final memoryIncrease = afterProcessingMemory - initialMemory;
      print('메모리 증가량: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');
      
      expect(memoryIncrease, lessThan(30 * 1024 * 1024)); // 30MB 미만 증가
    });
  });
}