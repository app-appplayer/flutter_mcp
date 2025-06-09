import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/memory_manager.dart';
import 'package:flutter_mcp/src/utils/resource_manager.dart';
import 'package:flutter_mcp/src/utils/event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';
import 'package:flutter_mcp/src/events/typed_event_system.dart';
import 'dart:io';
import 'dart:async';

void main() {
  group('메모리 관리 분석 테스트', () {
    test('실제 ProcessInfo 메모리 추적', () async {
      print('=== ProcessInfo 메모리 추적 테스트 ===');
      
      // 초기 메모리 상태
      final initialMemory = ProcessInfo.currentRss;
      print('초기 메모리 사용량: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 메모리 집약적 작업 수행
      var largeList = <List<int>>[];
      for (int i = 0; i < 10; i++) {
        // 각각 1MB 정도의 데이터 생성
        largeList.add(List.filled(250000, i)); // 250k integers ≈ 1MB
      }
      
      final afterAllocationMemory = ProcessInfo.currentRss;
      final memoryIncrease = afterAllocationMemory - initialMemory;
      print('메모리 할당 후: ${(afterAllocationMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      print('메모리 증가량: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 메모리가 실제로 증가했는지 확인
      expect(memoryIncrease, greaterThan(5 * 1024 * 1024)); // 최소 5MB 증가
      
      // 메모리 해제
      largeList = []; // 빈 리스트로 교체
      
      // GC 힌트 (완전한 보장은 없지만 대부분의 경우 작동)
      for (int i = 0; i < 3; i++) {
        var tempList = List.filled(100000, 0);
        tempList = []; // 빈 리스트로 교체
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      final afterCleanupMemory = ProcessInfo.currentRss;
      final memoryReclaimed = afterAllocationMemory - afterCleanupMemory;
      print('정리 후 메모리: ${(afterCleanupMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      print('회수된 메모리: ${(memoryReclaimed / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // GC는 즉시 실행되지 않을 수 있으므로 메모리가 완전히 회수되지 않을 수 있음
      // 하지만 극단적으로 증가하지는 않아야 함
      expect(afterCleanupMemory, lessThan(afterAllocationMemory + 50 * 1024 * 1024)); // 50MB 추가 증가까지는 허용
    });

    test('MemoryManager 단독 기능 테스트', () async {
      print('=== MemoryManager 단독 기능 테스트 ===');
      
      final memoryManager = MemoryManager.instance;
      bool highMemoryCallbackCalled = false;
      
      // 고메모리 콜백 등록
      memoryManager.addHighMemoryCallback(() async {
        highMemoryCallbackCalled = true;
        print('고메모리 콜백 호출됨!');
      });
      
      // 매우 낮은 임계점으로 테스트 (현재 메모리보다 낮게)
      final currentMemoryMB = (ProcessInfo.currentRss / 1024 / 1024).round();
      final lowThreshold = (currentMemoryMB * 0.5).round(); // 현재의 50%
      
      print('현재 메모리: ${currentMemoryMB}MB, 테스트 임계점: ${lowThreshold}MB');
      
      // 메모리 모니터링 시작
      memoryManager.initialize(
        startMonitoring: true,
        monitoringInterval: Duration(milliseconds: 100),
        highMemoryThresholdMB: lowThreshold,
      );
      
      // 모니터링이 실행될 시간 제공
      await Future.delayed(Duration(milliseconds: 500));
      
      // 메모리 모니터링 중지
      memoryManager.stopMemoryMonitoring();
      memoryManager.clearHighMemoryCallbacks();
      
      print('고메모리 콜백 호출됨: $highMemoryCallbackCalled');
      
      // 낮은 임계점이므로 콜백이 호출되어야 함
      expect(highMemoryCallbackCalled, isTrue);
    });

    test('ResourceManager 의존성 관리', () async {
      print('=== ResourceManager 의존성 관리 테스트 ===');
      
      final resourceManager = ResourceManager.instance;
      final disposedOrder = <String>[];
      final disposeCompleters = <String, Completer<void>>{};
      
      // 의존성 체인 생성: A <- B <- C (C는 B에, B는 A에 의존)
      
      // A 리소스 (최하위 의존성)
      disposeCompleters['A'] = Completer<void>();
      resourceManager.register<String>(
        'A',
        'resourceA',
        (resource) async {
          await Future.delayed(Duration(milliseconds: 50)); // 정리 시간 시뮬레이션
          disposedOrder.add('A');
          disposeCompleters['A']!.complete();
          print('리소스 A 정리됨');
        },
        priority: ResourceManager.highPriority,
      );
      
      // B 리소스 (A에 의존)
      disposeCompleters['B'] = Completer<void>();
      resourceManager.register<String>(
        'B',
        'resourceB',
        (resource) async {
          await Future.delayed(Duration(milliseconds: 30));
          disposedOrder.add('B');
          disposeCompleters['B']!.complete();
          print('리소스 B 정리됨');
        },
        dependencies: ['A'],
        priority: ResourceManager.mediumPriority,
      );
      
      // C 리소스 (B에 의존)
      disposeCompleters['C'] = Completer<void>();
      resourceManager.register<String>(
        'C',
        'resourceC',
        (resource) async {
          await Future.delayed(Duration(milliseconds: 20));
          disposedOrder.add('C');
          disposeCompleters['C']!.complete();
          print('리소스 C 정리됨');
        },
        dependencies: ['B'],
        priority: ResourceManager.lowPriority,
      );
      
      // A를 정리하려고 시도 (의존성 때문에 C, B가 먼저 정리되어야 함)
      final disposeFuture = resourceManager.dispose('A');
      
      // 모든 정리 완료까지 대기
      await Future.wait([
        disposeCompleters['A']!.future,
        disposeCompleters['B']!.future,
        disposeCompleters['C']!.future,
      ]);
      
      await disposeFuture;
      
      print('정리 순서: $disposedOrder');
      
      // 의존성 순서대로 정리되었는지 확인 (C -> B -> A)
      expect(disposedOrder.length, equals(3));
      expect(disposedOrder[0], equals('C')); // C가 먼저
      expect(disposedOrder[1], equals('B')); // B가 다음
      expect(disposedOrder[2], equals('A')); // A가 마지막
    });

    test('메모리 청크 처리 효율성', () async {
      print('=== 메모리 청크 처리 효율성 테스트 ===');
      
      final initialMemory = ProcessInfo.currentRss;
      print('초기 메모리: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 큰 데이터셋 생성
      final largeDataSet = List.generate(1000, (index) => 'item_$index' * 100); // 각 항목은 약 500바이트
      
      // 일반적인 처리 (모든 데이터를 한번에)
      final normalResults = <String>[];
      for (final item in largeDataSet) {
        normalResults.add(item.toUpperCase());
      }
      
      final afterNormalMemory = ProcessInfo.currentRss;
      print('일반 처리 후 메모리: ${(afterNormalMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      normalResults.clear(); // 메모리 해제
      
      // 청크별 처리
      final chunkResults = await MemoryManager.processInChunks<String, String>(
        items: largeDataSet,
        processItem: (item) async {
          return item.toUpperCase();
        },
        chunkSize: 50, // 50개씩 처리
        pauseBetweenChunks: Duration(milliseconds: 5),
      );
      
      final afterChunkMemory = ProcessInfo.currentRss;
      print('청크 처리 후 메모리: ${(afterChunkMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 결과 검증
      expect(chunkResults.length, equals(largeDataSet.length));
      expect(chunkResults.first, equals(largeDataSet.first.toUpperCase()));
      
      // 청크 처리가 메모리 효율적인지 확인 (큰 차이는 없을 수 있지만 안정적이어야 함)
      final normalMemoryIncrease = afterNormalMemory - initialMemory;
      final chunkMemoryIncrease = afterChunkMemory - initialMemory;
      
      print('일반 처리 메모리 증가: ${(normalMemoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');
      print('청크 처리 메모리 증가: ${(chunkMemoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 청크 처리가 제어된 메모리 사용량을 보여야 함
      expect(chunkMemoryIncrease, lessThan(100 * 1024 * 1024)); // 100MB 미만 증가
    });

    test('병렬 처리 동시성 제어', () async {
      print('=== 병렬 처리 동시성 제어 테스트 ===');
      
      final concurrentTracker = <int>[];
      int maxConcurrent = 0;
      int currentConcurrent = 0;
      
      final results = await MemoryManager.processInParallelChunks<int, int>(
        items: List.generate(20, (i) => i),
        processItem: (item) async {
          currentConcurrent++;
          if (currentConcurrent > maxConcurrent) {
            maxConcurrent = currentConcurrent;
          }
          concurrentTracker.add(currentConcurrent);
          
          // 작업 시뮬레이션
          await Future.delayed(Duration(milliseconds: 50));
          
          currentConcurrent--;
          return item * 2;
        },
        maxConcurrent: 3, // 최대 3개 동시 실행
        chunkSize: 5,
      );
      
      print('최대 동시 실행 수: $maxConcurrent');
      print('동시성 추적: ${concurrentTracker.take(10).toList()}...'); // 처음 10개만 출력
      
      // 결과 검증
      expect(results.length, equals(20));
      expect(results[5], equals(10)); // 5 * 2 = 10
      
      // 동시성 제한이 지켜졌는지 확인
      expect(maxConcurrent, lessThanOrEqualTo(3));
      expect(maxConcurrent, greaterThan(0));
    });

    test('EventSystem 메모리 이벤트 전파 (타입 안전)', () async {
      print('=== EventSystem 타입 안전 메모리 이벤트 테스트 ===');
      
      // 테스트 전 캐시 정리
      TypedEventSystem.instance.clearCache();
      
      final eventSystem = EventSystem.instance;
      final receivedTypedEvents = <MemoryEvent>[];
      final receivedLegacyEvents = <Map<String, dynamic>>[];
      
      // 타입 안전 메모리 이벤트 구독
      final typedToken = eventSystem.subscribeTyped<MemoryEvent>((event) {
        receivedTypedEvents.add(event);
        print('타입 안전 메모리 이벤트 수신: ${event.currentMB}MB');
      });
      
      // 기존 방식 메모리 이벤트 구독 (하위 호환성)
      final legacyToken = eventSystem.subscribe<Map<String, dynamic>>('memory.high', (data) {
        receivedLegacyEvents.add(data);
        print('기존 방식 메모리 이벤트 수신: ${data['currentMB']}MB');
      });
      
      // 타입 안전 이벤트 발행
      final memoryEvent = MemoryEvent(
        currentMB: 150,
        thresholdMB: 100,
        peakMB: 180,
      );
      
      eventSystem.publishTyped<MemoryEvent>(memoryEvent);
      
      // 이벤트 처리 시간 제공
      await Future.delayed(Duration(milliseconds: 100));
      
      // 타입 안전 이벤트 확인
      expect(receivedTypedEvents.length, equals(1));
      expect(receivedTypedEvents.first.currentMB, equals(150));
      expect(receivedTypedEvents.first.thresholdMB, equals(100));
      expect(receivedTypedEvents.first.peakMB, equals(180));
      expect(receivedTypedEvents.first.eventType, equals('memory.high'));
      
      // 하위 호환성 확인
      expect(receivedLegacyEvents.length, equals(1));
      expect(receivedLegacyEvents.first['currentMB'], equals(150));
      expect(receivedLegacyEvents.first['thresholdMB'], equals(100));
      
      // 구독 해제 (TypedEventSystem의 unsubscribe는 Future를 반환)
      await TypedEventSystem.instance.unsubscribe(typedToken);
      eventSystem.unsubscribe(legacyToken);
      
      print('타입 안전 이벤트 시스템 정상 작동 확인됨');
    });
  });
}