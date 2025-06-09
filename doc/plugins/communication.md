# Plugin Communication

Learn how Flutter MCP plugins communicate with each other and the core system.

## Communication Patterns

### 1. Event-Based Communication

The primary method for plugin communication is through the event bus.

```dart
// Define custom events
class DataProcessedEvent extends PluginEvent {
  final String dataId;
  final Map<String, dynamic> results;
  final String processorPlugin;
  
  DataProcessedEvent({
    required this.dataId,
    required this.results,
    required this.processorPlugin,
  }) : super(source: processorPlugin);
}

// Publish events
context.eventBus.publish(DataProcessedEvent(
  dataId: 'user_123',
  results: {'score': 95, 'category': 'premium'},
  processorPlugin: 'analytics_plugin',
));

// Subscribe to events
context.eventBus.on<DataProcessedEvent>().listen((event) {
  print('Data processed by ${event.processorPlugin}');
  print('Results: ${event.results}');
});
```

### 2. Direct Plugin Communication

Plugins can communicate directly through the registry.

```dart
class NotificationPlugin extends MCPPlugin {
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    // Get reference to another plugin
    final analyticsPlugin = context.registry
        .getPlugin<AnalyticsPlugin>('analytics');
    
    if (analyticsPlugin != null) {
      // Direct method call
      await analyticsPlugin.trackEvent('plugin_initialized', {
        'plugin': this.id,
      });
    }
  }
}
```

### 3. Request-Response Pattern

Implement request-response communication.

```dart
// Request event
class DataRequest extends PluginEvent {
  final String requestId;
  final String dataType;
  final Map<String, dynamic> parameters;
  
  DataRequest({
    required this.requestId,
    required this.dataType,
    required this.parameters,
  });
}

// Response event
class DataResponse extends PluginEvent {
  final String requestId;
  final dynamic data;
  final String? error;
  
  DataResponse({
    required this.requestId,
    this.data,
    this.error,
  });
}

// Request handler plugin
class DataProviderPlugin extends MCPPlugin {
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    // Listen for requests
    context.eventBus.on<DataRequest>().listen((request) async {
      try {
        final data = await _fetchData(
          request.dataType,
          request.parameters,
        );
        
        // Send response
        context.eventBus.publish(DataResponse(
          requestId: request.requestId,
          data: data,
        ));
      } catch (e) {
        // Send error response
        context.eventBus.publish(DataResponse(
          requestId: request.requestId,
          error: e.toString(),
        ));
      }
    });
  }
}

// Requesting plugin
class ConsumerPlugin extends MCPPlugin {
  Future<dynamic> requestData(
    String dataType,
    Map<String, dynamic> parameters,
  ) async {
    final requestId = Uuid().v4();
    
    // Send request
    context.eventBus.publish(DataRequest(
      requestId: requestId,
      dataType: dataType,
      parameters: parameters,
    ));
    
    // Wait for response
    final response = await context.eventBus
        .on<DataResponse>()
        .where((r) => r.requestId == requestId)
        .first
        .timeout(Duration(seconds: 10));
    
    if (response.error != null) {
      throw Exception(response.error);
    }
    
    return response.data;
  }
}
```

## Communication Bus

### Custom Communication Bus

Create a dedicated communication bus for plugins.

```dart
class PluginCommunicationBus {
  final _channels = <String, StreamController<PluginMessage>>{};
  
  // Create or get channel
  Stream<PluginMessage> channel(String name) {
    _channels.putIfAbsent(
      name,
      () => StreamController<PluginMessage>.broadcast(),
    );
    return _channels[name]!.stream;
  }
  
  // Send message to channel
  void send(String channel, PluginMessage message) {
    _channels[channel]?.add(message);
  }
  
  // Broadcast to all channels
  void broadcast(PluginMessage message) {
    for (final controller in _channels.values) {
      controller.add(message);
    }
  }
  
  // Close channel
  void closeChannel(String name) {
    _channels[name]?.close();
    _channels.remove(name);
  }
}

class PluginMessage {
  final String sender;
  final String? recipient;
  final String type;
  final dynamic payload;
  final DateTime timestamp;
  
  PluginMessage({
    required this.sender,
    this.recipient,
    required this.type,
    this.payload,
  }) : timestamp = DateTime.now();
}
```

### Using Communication Bus

```dart
class ChatPlugin extends MCPPlugin {
  late final PluginCommunicationBus _bus;
  
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    _bus = context.get<PluginCommunicationBus>();
    
    // Subscribe to chat channel
    _bus.channel('chat').listen(_handleChatMessage);
    
    // Subscribe to private messages
    _bus.channel('private_${this.id}').listen(_handlePrivateMessage);
  }
  
  void sendChatMessage(String message) {
    _bus.send('chat', PluginMessage(
      sender: this.id,
      type: 'chat_message',
      payload: message,
    ));
  }
  
  void sendPrivateMessage(String recipientId, String message) {
    _bus.send('private_$recipientId', PluginMessage(
      sender: this.id,
      recipient: recipientId,
      type: 'private_message',
      payload: message,
    ));
  }
}
```

## Service Discovery

### Plugin Discovery

Discover available plugins and their capabilities.

```dart
class PluginDiscovery {
  final PluginRegistry registry;
  
  PluginDiscovery(this.registry);
  
  // Find plugins by capability
  List<MCPPlugin> findByCapability(String capability) {
    return registry.getAllPlugins().where((plugin) {
      if (plugin is CapablePlugin) {
        return plugin.capabilities.contains(capability);
      }
      return false;
    }).toList();
  }
  
  // Find plugins by interface
  List<T> findByInterface<T extends MCPPlugin>() {
    return registry.getPluginsOfType<T>();
  }
  
  // Find plugins by metadata
  List<MCPPlugin> findByMetadata(
    bool Function(Map<String, dynamic>) predicate,
  ) {
    return registry.getAllPlugins().where((plugin) {
      return predicate(plugin.metadata);
    }).toList();
  }
}

// Plugin with capabilities
abstract class CapablePlugin extends MCPPlugin {
  List<String> get capabilities;
  Map<String, dynamic> get metadata => {};
}

// Example implementation
class DataPlugin extends CapablePlugin {
  @override
  List<String> get capabilities => [
    'data_processing',
    'data_storage',
    'data_export',
  ];
  
  @override
  Map<String, dynamic> get metadata => {
    'version': '2.0',
    'dataFormats': ['json', 'csv', 'xml'],
    'maxFileSize': 100 * 1024 * 1024, // 100MB
  };
}
```

### Service Registration

Register plugin services for discovery.

```dart
class ServiceRegistry {
  final Map<String, ServiceDescriptor> _services = {};
  
  // Register service
  void register(ServiceDescriptor service) {
    _services[service.id] = service;
    
    // Notify about new service
    _notifyServiceAdded(service);
  }
  
  // Unregister service
  void unregister(String serviceId) {
    final service = _services.remove(serviceId);
    if (service != null) {
      _notifyServiceRemoved(service);
    }
  }
  
  // Find services
  List<ServiceDescriptor> find({
    String? type,
    String? provider,
    Map<String, dynamic>? tags,
  }) {
    return _services.values.where((service) {
      if (type != null && service.type != type) return false;
      if (provider != null && service.provider != provider) return false;
      if (tags != null) {
        for (final entry in tags.entries) {
          if (service.tags[entry.key] != entry.value) return false;
        }
      }
      return true;
    }).toList();
  }
}

class ServiceDescriptor {
  final String id;
  final String type;
  final String provider;
  final String endpoint;
  final Map<String, dynamic> tags;
  final DateTime registeredAt;
  
  ServiceDescriptor({
    required this.id,
    required this.type,
    required this.provider,
    required this.endpoint,
    this.tags = const {},
  }) : registeredAt = DateTime.now();
}
```

## Message Routing

### Message Router

Route messages between plugins based on rules.

```dart
class MessageRouter {
  final List<RouteRule> _rules = [];
  final EventBus _eventBus;
  
  MessageRouter(this._eventBus);
  
  // Add routing rule
  void addRule(RouteRule rule) {
    _rules.add(rule);
  }
  
  // Route message
  void route(PluginMessage message) {
    for (final rule in _rules) {
      if (rule.matches(message)) {
        rule.handle(message, _eventBus);
        
        if (!rule.continueRouting) {
          break;
        }
      }
    }
  }
}

abstract class RouteRule {
  bool get continueRouting => true;
  
  bool matches(PluginMessage message);
  void handle(PluginMessage message, EventBus eventBus);
}

// Example routing rules
class TypeBasedRule extends RouteRule {
  final String messageType;
  final String targetChannel;
  
  TypeBasedRule(this.messageType, this.targetChannel);
  
  @override
  bool matches(PluginMessage message) {
    return message.type == messageType;
  }
  
  @override
  void handle(PluginMessage message, EventBus eventBus) {
    eventBus.publish(RoutedMessage(
      originalMessage: message,
      channel: targetChannel,
    ));
  }
}

class ContentBasedRule extends RouteRule {
  final bool Function(dynamic) contentMatcher;
  final void Function(PluginMessage, EventBus) handler;
  
  ContentBasedRule(this.contentMatcher, this.handler);
  
  @override
  bool matches(PluginMessage message) {
    return contentMatcher(message.payload);
  }
  
  @override
  void handle(PluginMessage message, EventBus eventBus) {
    handler(message, eventBus);
  }
}
```

## Pub-Sub Patterns

### Topic-Based Subscription

```dart
class TopicManager {
  final Map<String, Set<String>> _subscriptions = {};
  final Map<String, StreamController<TopicMessage>> _topics = {};
  
  // Subscribe to topic
  Stream<TopicMessage> subscribe(String pluginId, String topic) {
    _subscriptions.putIfAbsent(topic, () => {}).add(pluginId);
    _topics.putIfAbsent(
      topic,
      () => StreamController<TopicMessage>.broadcast(),
    );
    
    return _topics[topic]!.stream;
  }
  
  // Unsubscribe from topic
  void unsubscribe(String pluginId, String topic) {
    _subscriptions[topic]?.remove(pluginId);
    
    if (_subscriptions[topic]?.isEmpty ?? false) {
      _topics[topic]?.close();
      _topics.remove(topic);
      _subscriptions.remove(topic);
    }
  }
  
  // Publish to topic
  void publish(String topic, TopicMessage message) {
    _topics[topic]?.add(message);
  }
  
  // Get subscribers for topic
  Set<String> getSubscribers(String topic) {
    return Set.from(_subscriptions[topic] ?? {});
  }
}

class TopicMessage {
  final String topic;
  final String sender;
  final dynamic data;
  final Map<String, dynamic>? headers;
  final DateTime timestamp;
  
  TopicMessage({
    required this.topic,
    required this.sender,
    required this.data,
    this.headers,
  }) : timestamp = DateTime.now();
}
```

### Plugin Using Topics

```dart
class NewsPlugin extends MCPPlugin {
  late final TopicManager _topicManager;
  
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    _topicManager = context.get<TopicManager>();
    
    // Subscribe to topics
    _topicManager.subscribe(this.id, 'news.breaking')
        .listen(_handleBreakingNews);
    
    _topicManager.subscribe(this.id, 'news.sports')
        .listen(_handleSportsNews);
  }
  
  void publishBreakingNews(String headline, String content) {
    _topicManager.publish('news.breaking', TopicMessage(
      topic: 'news.breaking',
      sender: this.id,
      data: {
        'headline': headline,
        'content': content,
        'timestamp': DateTime.now(),
      },
    ));
  }
  
  void _handleBreakingNews(TopicMessage message) {
    final headline = message.data['headline'];
    print('Breaking: $headline');
  }
}
```

## RPC Communication

### Remote Procedure Calls

Implement RPC between plugins.

```dart
class PluginRPC {
  final Map<String, RPCHandler> _handlers = {};
  final EventBus _eventBus;
  
  PluginRPC(this._eventBus);
  
  // Register RPC handler
  void register(String method, RPCHandler handler) {
    _handlers[method] = handler;
  }
  
  // Call remote procedure
  Future<T> call<T>(
    String pluginId,
    String method,
    List<dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final requestId = Uuid().v4();
    
    // Send RPC request
    _eventBus.publish(RPCRequest(
      id: requestId,
      target: pluginId,
      method: method,
      params: params,
    ));
    
    // Wait for response
    final response = await _eventBus
        .on<RPCResponse>()
        .where((r) => r.id == requestId)
        .first
        .timeout(timeout);
    
    if (response.error != null) {
      throw RPCException(response.error!);
    }
    
    return response.result as T;
  }
  
  // Handle incoming RPC requests
  void handleRequest(RPCRequest request) async {
    final handler = _handlers[request.method];
    
    if (handler == null) {
      _sendError(request.id, 'Method not found: ${request.method}');
      return;
    }
    
    try {
      final result = await handler(request.params);
      _sendResponse(request.id, result);
    } catch (e) {
      _sendError(request.id, e.toString());
    }
  }
  
  void _sendResponse(String id, dynamic result) {
    _eventBus.publish(RPCResponse(
      id: id,
      result: result,
    ));
  }
  
  void _sendError(String id, String error) {
    _eventBus.publish(RPCResponse(
      id: id,
      error: error,
    ));
  }
}

typedef RPCHandler = Future<dynamic> Function(List<dynamic> params);

class RPCRequest extends PluginEvent {
  final String id;
  final String target;
  final String method;
  final List<dynamic> params;
  
  RPCRequest({
    required this.id,
    required this.target,
    required this.method,
    required this.params,
  });
}

class RPCResponse extends PluginEvent {
  final String id;
  final dynamic result;
  final String? error;
  
  RPCResponse({
    required this.id,
    this.result,
    this.error,
  });
}
```

### Using RPC

```dart
class CalculatorPlugin extends MCPPlugin {
  late final PluginRPC _rpc;
  
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    _rpc = PluginRPC(context.eventBus);
    
    // Register RPC methods
    _rpc.register('add', (params) async {
      final a = params[0] as num;
      final b = params[1] as num;
      return a + b;
    });
    
    _rpc.register('multiply', (params) async {
      final a = params[0] as num;
      final b = params[1] as num;
      return a * b;
    });
    
    // Listen for RPC requests
    context.eventBus.on<RPCRequest>()
        .where((r) => r.target == this.id)
        .listen(_rpc.handleRequest);
  }
}

class ConsumerPlugin extends MCPPlugin {
  late final PluginRPC _rpc;
  
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    _rpc = PluginRPC(context.eventBus);
  }
  
  Future<num> calculate() async {
    // Call remote calculator
    final sum = await _rpc.call<num>(
      'calculator',
      'add',
      [10, 20],
    );
    
    final product = await _rpc.call<num>(
      'calculator',
      'multiply',
      [sum, 2],
    );
    
    return product; // Returns 60
  }
}
```

## State Synchronization

### Shared State

Synchronize state between plugins.

```dart
class SharedState<T> {
  final String key;
  final _controller = StreamController<T>.broadcast();
  T? _value;
  
  SharedState(this.key, [T? initialValue]) : _value = initialValue;
  
  T? get value => _value;
  
  Stream<T> get changes => _controller.stream;
  
  void update(T newValue) {
    if (_value != newValue) {
      _value = newValue;
      _controller.add(newValue);
    }
  }
  
  void dispose() {
    _controller.close();
  }
}

class StateManager {
  final Map<String, SharedState> _states = {};
  
  SharedState<T> getState<T>(String key, [T? initialValue]) {
    return _states.putIfAbsent(
      key,
      () => SharedState<T>(key, initialValue),
    ) as SharedState<T>;
  }
  
  void removeState(String key) {
    _states[key]?.dispose();
    _states.remove(key);
  }
}

// Plugin using shared state
class ThemePlugin extends MCPPlugin {
  late final SharedState<ThemeMode> _themeState;
  
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    final stateManager = context.get<StateManager>();
    _themeState = stateManager.getState<ThemeMode>(
      'app_theme',
      ThemeMode.system,
    );
    
    // Listen for theme changes
    _themeState.changes.listen((theme) {
      print('Theme changed to: $theme');
      _applyTheme(theme);
    });
  }
  
  void setTheme(ThemeMode theme) {
    _themeState.update(theme);
  }
}
```

## Performance Considerations

### Message Batching

```dart
class MessageBatcher {
  final Duration batchInterval;
  final int maxBatchSize;
  final void Function(List<PluginMessage>) onBatch;
  
  final List<PluginMessage> _batch = [];
  Timer? _timer;
  
  MessageBatcher({
    required this.batchInterval,
    required this.maxBatchSize,
    required this.onBatch,
  });
  
  void add(PluginMessage message) {
    _batch.add(message);
    
    if (_batch.length >= maxBatchSize) {
      _flush();
    } else {
      _timer ??= Timer(batchInterval, _flush);
    }
  }
  
  void _flush() {
    if (_batch.isEmpty) return;
    
    onBatch(List.from(_batch));
    _batch.clear();
    _timer?.cancel();
    _timer = null;
  }
  
  void dispose() {
    _flush();
    _timer?.cancel();
  }
}
```

### Message Filtering

```dart
class MessageFilter {
  final List<FilterRule> _rules = [];
  
  void addRule(FilterRule rule) {
    _rules.add(rule);
  }
  
  bool shouldProcess(PluginMessage message) {
    for (final rule in _rules) {
      if (!rule.allows(message)) {
        return false;
      }
    }
    return true;
  }
}

abstract class FilterRule {
  bool allows(PluginMessage message);
}

class SenderFilter extends FilterRule {
  final Set<String> allowedSenders;
  
  SenderFilter(this.allowedSenders);
  
  @override
  bool allows(PluginMessage message) {
    return allowedSenders.contains(message.sender);
  }
}

class RateLimitFilter extends FilterRule {
  final int maxPerMinute;
  final Map<String, List<DateTime>> _timestamps = {};
  
  RateLimitFilter(this.maxPerMinute);
  
  @override
  bool allows(PluginMessage message) {
    final now = DateTime.now();
    final key = message.sender;
    
    _timestamps.putIfAbsent(key, () => []);
    _timestamps[key]!.removeWhere(
      (time) => now.difference(time).inMinutes > 1,
    );
    
    if (_timestamps[key]!.length >= maxPerMinute) {
      return false;
    }
    
    _timestamps[key]!.add(now);
    return true;
  }
}
```

## Best Practices

### 1. Define Clear Contracts

```dart
// Define clear event interfaces
abstract class DataEvent extends PluginEvent {
  String get dataId;
  DateTime get timestamp;
}

class DataCreatedEvent extends DataEvent {
  @override
  final String dataId;
  final Map<String, dynamic> data;
  @override
  final DateTime timestamp;
  
  DataCreatedEvent({
    required this.dataId,
    required this.data,
  }) : timestamp = DateTime.now();
}

class DataUpdatedEvent extends DataEvent {
  @override
  final String dataId;
  final Map<String, dynamic> changes;
  @override
  final DateTime timestamp;
  
  DataUpdatedEvent({
    required this.dataId,
    required this.changes,
  }) : timestamp = DateTime.now();
}
```

### 2. Handle Communication Failures

```dart
class ResilientCommunicator {
  final EventBus _eventBus;
  final Duration timeout;
  final int maxRetries;
  
  ResilientCommunicator(
    this._eventBus, {
    this.timeout = const Duration(seconds: 5),
    this.maxRetries = 3,
  });
  
  Future<T> sendAndWait<T extends PluginEvent>(
    PluginEvent request,
    bool Function(PluginEvent) responseMatcher,
  ) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        _eventBus.publish(request);
        
        final response = await _eventBus
            .on<PluginEvent>()
            .where(responseMatcher)
            .first
            .timeout(timeout);
        
        return response as T;
      } on TimeoutException {
        if (i == maxRetries - 1) rethrow;
        
        // Wait before retry
        await Future.delayed(
          Duration(seconds: math.pow(2, i).toInt()),
        );
      }
    }
    
    throw Exception('Max retries exceeded');
  }
}
```

### 3. Avoid Circular Dependencies

```dart
// Use dependency injection to avoid circular dependencies
class PluginA extends MCPPlugin {
  late final PluginB _pluginB;
  
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    // Get plugin B after both are initialized
    context.registry.pluginStream
        .where((event) => event.plugin.id == 'plugin_b')
        .listen((event) {
          _pluginB = event.plugin as PluginB;
        });
  }
}
```

### 4. Document Communication Interfaces

```dart
/// Weather data provider plugin
/// 
/// Publishes:
/// - WeatherUpdateEvent: When weather data is updated
/// - WeatherAlertEvent: When severe weather is detected
/// 
/// Listens to:
/// - LocationChangeEvent: Updates weather for new location
/// - RefreshRequestEvent: Forces weather data refresh
/// 
/// RPC Methods:
/// - getCurrentWeather(): Returns current weather data
/// - getForecast(days): Returns weather forecast
class WeatherPlugin extends MCPPlugin {
  // Implementation
}
```

## Testing Communication

### Mock Event Bus

```dart
class MockEventBus implements EventBus {
  final _streams = <Type, StreamController>{};
  final _publishedEvents = <PluginEvent>[];
  
  @override
  void publish<T extends PluginEvent>(T event) {
    _publishedEvents.add(event);
    _streams[T]?.add(event);
  }
  
  @override
  Stream<T> on<T extends PluginEvent>() {
    _streams.putIfAbsent(
      T,
      () => StreamController<T>.broadcast(),
    );
    return _streams[T]!.stream as Stream<T>;
  }
  
  List<T> getPublishedEvents<T extends PluginEvent>() {
    return _publishedEvents.whereType<T>().toList();
  }
  
  void reset() {
    _publishedEvents.clear();
    for (final controller in _streams.values) {
      controller.close();
    }
    _streams.clear();
  }
}
```

### Testing Plugin Communication

```dart
test('plugin communication', () async {
  final mockEventBus = MockEventBus();
  final context = MockPluginContext(eventBus: mockEventBus);
  
  final senderPlugin = SenderPlugin();
  final receiverPlugin = ReceiverPlugin();
  
  // Initialize plugins
  await senderPlugin.initialize(context);
  await receiverPlugin.initialize(context);
  
  // Test event publishing
  senderPlugin.sendMessage('Hello');
  
  // Verify event was published
  final events = mockEventBus.getPublishedEvents<MessageEvent>();
  expect(events, hasLength(1));
  expect(events.first.message, equals('Hello'));
  
  // Test event reception
  var receivedMessage = '';
  mockEventBus.on<MessageEvent>().listen((event) {
    receivedMessage = event.message;
  });
  
  mockEventBus.publish(MessageEvent('World'));
  
  await Future.delayed(Duration.zero);
  expect(receivedMessage, equals('World'));
});
```

## Examples

### Chat System

```dart
// Chat message event
class ChatMessageEvent extends PluginEvent {
  final String roomId;
  final String userId;
  final String message;
  final DateTime timestamp;
  
  ChatMessageEvent({
    required this.roomId,
    required this.userId,
    required this.message,
  }) : timestamp = DateTime.now();
}

// Chat plugin
class ChatPlugin extends MCPPlugin {
  final Map<String, List<ChatMessageEvent>> _rooms = {};
  
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    // Listen for chat messages
    context.eventBus.on<ChatMessageEvent>().listen((event) {
      _rooms.putIfAbsent(event.roomId, () => []).add(event);
      
      // Notify UI about new message
      context.eventBus.publish(ChatUpdateEvent(
        roomId: event.roomId,
        messages: _rooms[event.roomId]!,
      ));
    });
  }
  
  void sendMessage(String roomId, String userId, String message) {
    context.eventBus.publish(ChatMessageEvent(
      roomId: roomId,
      userId: userId,
      message: message,
    ));
  }
  
  List<ChatMessageEvent> getMessages(String roomId) {
    return _rooms[roomId] ?? [];
  }
}

// Notification plugin
class NotificationPlugin extends MCPPlugin {
  @override
  Future<void> initialize(PluginContext context) async {
    super.initialize(context);
    
    // Listen for chat messages and show notifications
    context.eventBus.on<ChatMessageEvent>().listen((event) {
      _showNotification(
        title: 'New message in ${event.roomId}',
        body: event.message,
      );
    });
  }
}
```

## Next Steps

- [Plugin Examples](examples.md) - More examples
- [Development Guide](development.md) - Creating plugins
- [Lifecycle Guide](lifecycle.md) - Plugin lifecycle
- [API Reference](../api/plugin-system.md) - Plugin API