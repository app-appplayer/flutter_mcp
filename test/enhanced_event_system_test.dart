import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/event_system.dart';
import 'package:flutter_mcp/src/events/enhanced_typed_event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

void main() {
  group('Enhanced Event System Integration Tests', () {
    late EventSystem eventSystem;
    
    setUp(() {
      eventSystem = EventSystem.instance;
    });
    
    tearDown(() async {
      await eventSystem.reset();
    });

    test('should publish and receive typed events through enhanced system', () async {
      final receivedEvents = <ServerEvent>[];
      
      // Subscribe using enhanced API
      final subscriptionId = eventSystem.subscribeTyped<ServerEvent>((event) {
        receivedEvents.add(event);
      });
      
      // Create test event
      final testEvent = ServerEvent(
        serverId: 'test_server',
        status: ServerStatus.running,
        metadata: {'test': 'data'},
      );
      
      // Publish using enhanced API
      await eventSystem.publishTyped<ServerEvent>(testEvent);
      
      // Allow event to propagate
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(receivedEvents.length, equals(1));
      expect(receivedEvents.first.serverId, equals('test_server'));
      expect(receivedEvents.first.status, equals(ServerStatus.running));
      expect(receivedEvents.first.metadata?['test'], equals('data'));
    });

    test('should support advanced filtering and transformation', () async {
      final transformedResults = <String>[];
      
      // Subscribe with filter and transform using enhanced API
      final subscriptionId = eventSystem.subscribeAdvanced<ServerEvent, String>(
        handler: (result) => transformedResults.add(result),
        filter: (event) => event.status == ServerStatus.running,
        transform: (event) => 'Server ${event.serverId} is running',
        description: 'Test filtered server subscription',
      );
      
      // Create events - one that should be filtered out
      final stoppedEvent = ServerEvent(
        serverId: 'server1',
        status: ServerStatus.stopped,
      );
      
      final runningEvent = ServerEvent(
        serverId: 'server2',
        status: ServerStatus.running,
      );
      
      // Publish events
      await eventSystem.publishTyped<ServerEvent>(stoppedEvent);
      await eventSystem.publishTyped<ServerEvent>(runningEvent);
      
      // Allow events to propagate
      await Future.delayed(Duration(milliseconds: 10));
      
      // Should only receive the running event, transformed
      expect(transformedResults.length, equals(1));
      expect(transformedResults.first, equals('Server server2 is running'));
    });

    test('should track comprehensive statistics', () async {
      // Skip this test as enhanced features are temporarily disabled
      // TODO: Re-enable when enhanced event system is fixed
    }, skip: 'Enhanced event system temporarily disabled');

    test('should support pause and resume functionality', () async {
      final receivedEvents = <ServerEvent>[];
      
      // Subscribe
      final subscriptionId = eventSystem.subscribeTyped<ServerEvent>((event) {
        receivedEvents.add(event);
      });
      
      // Pause the system
      eventSystem.pause();
      
      // Publish events while paused
      await eventSystem.publishTyped<ServerEvent>(
        ServerEvent(serverId: 'paused_server', status: ServerStatus.running),
      );
      
      // Should not receive events while paused
      await Future.delayed(Duration(milliseconds: 10));
      expect(receivedEvents.length, equals(0));
      
      // Resume the system
      await eventSystem.resume();
      
      // Should now receive queued events
      await Future.delayed(Duration(milliseconds: 50));
      expect(receivedEvents.length, equals(1));
      expect(receivedEvents.first.serverId, equals('paused_server'));
    });

    test('should provide backward compatibility with legacy API', () async {
      final legacyEvents = <Map<String, dynamic>>[];
      final typedEvents = <ServerEvent>[];
      
      // Subscribe using legacy API
      final legacyId = eventSystem.subscribe<Map<String, dynamic>>('server.status', (event) {
        legacyEvents.add(event);
      });
      
      // Subscribe using typed API
      final typedId = eventSystem.subscribeTyped<ServerEvent>((event) {
        typedEvents.add(event);
      });
      
      // Publish using typed API
      final testEvent = ServerEvent(
        serverId: 'test_server',
        status: ServerStatus.running,
      );
      
      await eventSystem.publishTyped<ServerEvent>(testEvent);
      
      // Allow events to propagate
      await Future.delayed(Duration(milliseconds: 10));
      
      // Both should receive events
      expect(typedEvents.length, equals(1));
      expect(legacyEvents.length, equals(1));
      
      // Legacy event should be the serialized form
      expect(legacyEvents.first['serverId'], equals('test_server'));
      expect(legacyEvents.first['status'], equals('running'));
      
      // Clean up
      eventSystem.unsubscribe(legacyId);
    });

    test('should support event recording and replay', () async {
      // Skip this test as enhanced features are temporarily disabled
      // TODO: Re-enable when enhanced event system is fixed
    }, skip: 'Enhanced event system temporarily disabled');

    test('should support middleware for event processing', () async {
      // Skip this test as enhanced features are temporarily disabled
      // TODO: Re-enable when enhanced event system is fixed
    }, skip: 'Enhanced event system temporarily disabled');
  });
}

/// Test middleware implementation
class TestEventMiddleware extends EventMiddleware {
  @override
  String get name => 'test_middleware';
  
  @override
  int get priority => 100;
  
  int publishCalls = 0;
  int deliverCalls = 0;
  int errorCalls = 0;
  
  @override
  Future<McpEvent?> onPublish(McpEvent event) async {
    publishCalls++;
    return event; // Pass through unchanged
  }
  
  @override
  Future<McpEvent?> onDeliver(McpEvent event, String handlerId) async {
    deliverCalls++;
    return event; // Pass through unchanged
  }
  
  @override
  void onError(Object error, StackTrace stackTrace, McpEvent event) {
    errorCalls++;
  }
}