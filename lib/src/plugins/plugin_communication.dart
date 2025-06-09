import 'dart:async';
import '../utils/logger.dart';
import 'plugin_system.dart';

/// Plugin communication bus for inter-plugin messaging
class PluginCommunicationBus {
  static final PluginCommunicationBus _instance = PluginCommunicationBus._internal();
  
  /// Get singleton instance
  static PluginCommunicationBus get instance => _instance;
  
  PluginCommunicationBus._internal();
  
  final Logger _logger = Logger('flutter_mcp.plugin_communication');
  
  // Message channels
  final Map<String, StreamController<PluginMessage>> _channels = {};
  
  // Plugin subscriptions
  final Map<String, Set<String>> _subscriptions = {};
  
  // Message history for debugging
  final List<PluginMessage> _messageHistory = [];
  final int _maxHistorySize = 100;
  
  /// Subscribe to a channel
  Stream<PluginMessage> subscribe(String channel, String pluginId) {
    _logger.fine('Plugin $pluginId subscribing to channel: $channel');
    
    // Create channel if it doesn't exist
    if (!_channels.containsKey(channel)) {
      _channels[channel] = StreamController<PluginMessage>.broadcast();
    }
    
    // Track subscription
    _subscriptions.putIfAbsent(channel, () => {}).add(pluginId);
    
    return _channels[channel]!.stream;
  }
  
  /// Unsubscribe from a channel
  void unsubscribe(String channel, String pluginId) {
    _logger.fine('Plugin $pluginId unsubscribing from channel: $channel');
    
    final subscribers = _subscriptions[channel];
    if (subscribers != null) {
      subscribers.remove(pluginId);
      
      // Clean up empty channels
      if (subscribers.isEmpty) {
        _subscriptions.remove(channel);
        _channels[channel]?.close();
        _channels.remove(channel);
      }
    }
  }
  
  /// Send a message to a channel
  void send(String channel, PluginMessage message) {
    _logger.fine('Sending message on channel $channel from ${message.senderId}');
    
    // Add to history
    _messageHistory.add(message);
    if (_messageHistory.length > _maxHistorySize) {
      _messageHistory.removeAt(0);
    }
    
    // Create channel if it doesn't exist
    if (!_channels.containsKey(channel)) {
      _channels[channel] = StreamController<PluginMessage>.broadcast();
    }
    
    // Send message
    _channels[channel]!.add(message);
  }
  
  /// Send a request and wait for response
  Future<PluginMessage> request(
    String channel,
    PluginMessage request, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final responseCompleter = Completer<PluginMessage>();
    StreamSubscription<PluginMessage>? subscription;
    Timer? timeoutTimer;
    
    try {
      // Listen for response
      subscription = subscribe(channel, request.senderId).listen((message) {
        if (message.correlationId == request.id && message.type == PluginMessageType.response) {
          responseCompleter.complete(message);
        }
      });
      
      // Set timeout
      timeoutTimer = Timer(timeout, () {
        if (!responseCompleter.isCompleted) {
          responseCompleter.completeError(
            TimeoutException('Request timeout on channel $channel', timeout),
          );
        }
      });
      
      // Send request
      send(channel, request);
      
      // Wait for response
      return await responseCompleter.future;
      
    } finally {
      subscription?.cancel();
      timeoutTimer?.cancel();
    }
  }
  
  /// Get message history
  List<PluginMessage> getMessageHistory({String? channel}) {
    if (channel == null) {
      return List.from(_messageHistory);
    }
    
    return _messageHistory.where((m) => m.channel == channel).toList();
  }
  
  /// Clear message history
  void clearMessageHistory() {
    _messageHistory.clear();
  }
  
  /// Get active channels
  List<String> getActiveChannels() {
    return _channels.keys.toList();
  }
  
  /// Get channel subscribers
  Set<String> getChannelSubscribers(String channel) {
    return Set.from(_subscriptions[channel] ?? {});
  }
  
  /// Close all channels
  void dispose() {
    for (final controller in _channels.values) {
      controller.close();
    }
    _channels.clear();
    _subscriptions.clear();
    _messageHistory.clear();
  }
}

/// Plugin message
class PluginMessage {
  final String id;
  final String senderId;
  final String channel;
  final PluginMessageType type;
  final Map<String, dynamic> data;
  final String? correlationId;
  final DateTime timestamp;
  
  PluginMessage({
    String? id,
    required this.senderId,
    required this.channel,
    required this.type,
    required this.data,
    this.correlationId,
    DateTime? timestamp,
  }) : 
    id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
    timestamp = timestamp ?? DateTime.now();
  
  /// Create a response message
  PluginMessage createResponse(Map<String, dynamic> responseData) {
    return PluginMessage(
      senderId: senderId,
      channel: channel,
      type: PluginMessageType.response,
      data: responseData,
      correlationId: id,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'channel': channel,
    'type': type.toString(),
    'data': data,
    'correlationId': correlationId,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Plugin message type
enum PluginMessageType {
  request,
  response,
  notification,
  broadcast,
}

/// Enhanced plugin with communication capabilities
abstract class CommunicatingPlugin extends MCPPlugin {
  late String _pluginId;
  final Map<String, StreamSubscription<PluginMessage>> _subscriptions = {};
  
  /// Get plugin ID for communication
  String get pluginId => _pluginId;
  
  /// Get communication bus
  PluginCommunicationBus get communicationBus => PluginCommunicationBus.instance;
  
  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _pluginId = '$name-${DateTime.now().millisecondsSinceEpoch}';
    await onInitialize(config);
  }
  
  @override
  Future<void> shutdown() async {
    // Unsubscribe from all channels
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    
    await onShutdown();
  }
  
  /// Subscribe to a channel
  void subscribeToChannel(String channel, void Function(PluginMessage) handler) {
    final subscription = communicationBus.subscribe(channel, pluginId).listen(handler);
    _subscriptions[channel] = subscription;
  }
  
  /// Unsubscribe from a channel
  void unsubscribeFromChannel(String channel) {
    final subscription = _subscriptions.remove(channel);
    subscription?.cancel();
    communicationBus.unsubscribe(channel, pluginId);
  }
  
  /// Send a message
  void sendMessage(String channel, Map<String, dynamic> data, {PluginMessageType type = PluginMessageType.notification}) {
    final message = PluginMessage(
      senderId: pluginId,
      channel: channel,
      type: type,
      data: data,
    );
    
    communicationBus.send(channel, message);
  }
  
  /// Send a request and wait for response
  Future<PluginMessage> sendRequest(String channel, Map<String, dynamic> data, {Duration? timeout}) async {
    final request = PluginMessage(
      senderId: pluginId,
      channel: channel,
      type: PluginMessageType.request,
      data: data,
    );
    
    return await communicationBus.request(channel, request, timeout: timeout ?? Duration(seconds: 5));
  }
  
  /// Override these in subclasses
  Future<void> onInitialize(Map<String, dynamic> config);
  Future<void> onShutdown();
}