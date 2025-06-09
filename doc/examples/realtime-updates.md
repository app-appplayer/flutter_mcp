# Real-time Updates Example

This example demonstrates implementing real-time data synchronization using Flutter MCP's WebSocket capabilities.

## Overview

This example shows how to:
- Subscribe to real-time events
- Handle streaming data
- Implement pub/sub patterns
- Manage WebSocket connections

## WebSocket Event Subscription

### Basic Event Subscription

```dart
// lib/services/realtime_service.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:async';

class RealtimeService {
  final String serverName;
  final _eventController = StreamController<RealtimeEvent>.broadcast();
  final _subscriptions = <String, StreamSubscription>{};
  
  MCPServer? _server;
  
  RealtimeService({required this.serverName});
  
  Stream<RealtimeEvent> get events => _eventController.stream;
  
  Future<void> connect() async {
    _server = await FlutterMCP.connect(serverName);
    
    // Subscribe to server events
    _server!.eventStream.listen((event) {
      _handleServerEvent(event);
    });
  }
  
  Future<void> subscribe(String channel) async {
    if (_server == null) {
      throw MCPException('Not connected to server');
    }
    
    // Subscribe to specific channel
    final subscription = await _server!.subscribe(channel);
    
    _subscriptions[channel] = subscription.listen((data) {
      _eventController.add(RealtimeEvent(
        channel: channel,
        data: data,
        timestamp: DateTime.now(),
      ));
    });
  }
  
  Future<void> unsubscribe(String channel) async {
    final subscription = _subscriptions[channel];
    if (subscription != null) {
      await subscription.cancel();
      _subscriptions.remove(channel);
    }
    
    if (_server != null) {
      await _server!.unsubscribe(channel);
    }
  }
  
  void _handleServerEvent(MCPEvent event) {
    switch (event.type) {
      case MCPEventType.connected:
        _resubscribeAll();
        break;
      case MCPEventType.disconnected:
        _handleDisconnection();
        break;
      case MCPEventType.error:
        _handleError(event.error);
        break;
      default:
        break;
    }
  }
  
  Future<void> _resubscribeAll() async {
    // Resubscribe to all channels after reconnection
    for (final channel in _subscriptions.keys) {
      await subscribe(channel);
    }
  }
  
  void _handleDisconnection() {
    _eventController.add(RealtimeEvent.system(
      'Connection lost',
      SystemEventType.disconnected,
    ));
  }
  
  void _handleError(dynamic error) {
    _eventController.add(RealtimeEvent.system(
      'Error: $error',
      SystemEventType.error,
    ));
  }
  
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _eventController.close();
  }
}

class RealtimeEvent {
  final String channel;
  final dynamic data;
  final DateTime timestamp;
  final SystemEventType? systemEventType;
  
  RealtimeEvent({
    required this.channel,
    required this.data,
    required this.timestamp,
    this.systemEventType,
  });
  
  factory RealtimeEvent.system(String message, SystemEventType type) {
    return RealtimeEvent(
      channel: 'system',
      data: message,
      timestamp: DateTime.now(),
      systemEventType: type,
    );
  }
  
  bool get isSystemEvent => systemEventType != null;
}

enum SystemEventType {
  connected,
  disconnected,
  error,
  info,
}
```

### Live Data Stream Implementation

```dart
// lib/models/live_data_stream.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:async';

class LiveDataStream<T> {
  final String channel;
  final T Function(Map<String, dynamic>) parser;
  final Duration? reconnectDelay;
  
  final _dataController = StreamController<T>.broadcast();
  final _connectionController = StreamController<ConnectionStatus>.broadcast();
  
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _isDisposed = false;
  
  LiveDataStream({
    required this.channel,
    required this.parser,
    this.reconnectDelay = const Duration(seconds: 5),
  });
  
  Stream<T> get dataStream => _dataController.stream;
  Stream<ConnectionStatus> get connectionStream => _connectionController.stream;
  
  Future<void> start(MCPServer server) async {
    try {
      _connectionController.add(ConnectionStatus.connecting);
      
      _subscription = await server.subscribe(channel);
      
      _subscription!.listen(
        (data) {
          try {
            final parsed = parser(data as Map<String, dynamic>);
            _dataController.add(parsed);
          } catch (e) {
            _dataController.addError(e);
          }
        },
        onError: (error) {
          _connectionController.add(ConnectionStatus.error);
          _dataController.addError(error);
          _scheduleReconnect(server);
        },
        onDone: () {
          _connectionController.add(ConnectionStatus.disconnected);
          _scheduleReconnect(server);
        },
      );
      
      _connectionController.add(ConnectionStatus.connected);
    } catch (e) {
      _connectionController.add(ConnectionStatus.error);
      _dataController.addError(e);
      _scheduleReconnect(server);
    }
  }
  
  void _scheduleReconnect(MCPServer server) {
    if (_isDisposed || reconnectDelay == null) return;
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay!, () {
      if (!_isDisposed) {
        start(server);
      }
    });
  }
  
  Future<void> stop() async {
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    _connectionController.add(ConnectionStatus.disconnected);
  }
  
  void dispose() {
    _isDisposed = true;
    stop();
    _dataController.close();
    _connectionController.close();
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}
```

## Pub/Sub Pattern Implementation

### Topic-Based Messaging

```dart
// lib/services/pubsub_service.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:async';

class PubSubService {
  final MCPServer server;
  final _topicSubscriptions = <String, Set<StreamController>>{};
  final _activeSubscriptions = <String, StreamSubscription>{};
  
  PubSubService({required this.server});
  
  Stream<T> subscribe<T>(String topic, T Function(Map<String, dynamic>) parser) {
    final controller = StreamController<T>.broadcast();
    
    // Add to topic subscriptions
    _topicSubscriptions.putIfAbsent(topic, () => {}).add(controller);
    
    // Subscribe to server if first subscriber
    if (_topicSubscriptions[topic]!.length == 1) {
      _subscribeToServer(topic);
    }
    
    // Clean up on cancel
    controller.onCancel = () {
      _topicSubscriptions[topic]?.remove(controller);
      
      // Unsubscribe from server if no more subscribers
      if (_topicSubscriptions[topic]?.isEmpty ?? true) {
        _unsubscribeFromServer(topic);
      }
    };
    
    return controller.stream.transform(
      StreamTransformer<dynamic, T>.fromHandlers(
        handleData: (data, sink) {
          try {
            final parsed = parser(data as Map<String, dynamic>);
            sink.add(parsed);
          } catch (e) {
            sink.addError(e);
          }
        },
      ),
    );
  }
  
  Future<void> publish(String topic, Map<String, dynamic> data) async {
    await server.execute('publish', {
      'topic': topic,
      'data': data,
    });
  }
  
  Future<void> _subscribeToServer(String topic) async {
    try {
      final subscription = await server.subscribe(topic);
      
      _activeSubscriptions[topic] = subscription.listen((data) {
        // Broadcast to all subscribers
        final controllers = _topicSubscriptions[topic] ?? {};
        for (final controller in controllers) {
          controller.add(data);
        }
      });
    } catch (e) {
      // Notify all subscribers of error
      final controllers = _topicSubscriptions[topic] ?? {};
      for (final controller in controllers) {
        controller.addError(e);
      }
    }
  }
  
  Future<void> _unsubscribeFromServer(String topic) async {
    final subscription = _activeSubscriptions[topic];
    if (subscription != null) {
      await subscription.cancel();
      _activeSubscriptions.remove(topic);
    }
    
    await server.unsubscribe(topic);
  }
  
  void dispose() {
    // Cancel all subscriptions
    for (final subscription in _activeSubscriptions.values) {
      subscription.cancel();
    }
    _activeSubscriptions.clear();
    
    // Close all controllers
    for (final controllers in _topicSubscriptions.values) {
      for (final controller in controllers) {
        controller.close();
      }
    }
    _topicSubscriptions.clear();
  }
}
```

### Message Broadcasting

```dart
// lib/services/broadcast_service.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class BroadcastService {
  final MCPServer server;
  final _rooms = <String, Set<String>>{};
  
  BroadcastService({required this.server});
  
  Future<void> joinRoom(String roomId, String userId) async {
    _rooms.putIfAbsent(roomId, () => {}).add(userId);
    
    await server.execute('joinRoom', {
      'roomId': roomId,
      'userId': userId,
    });
  }
  
  Future<void> leaveRoom(String roomId, String userId) async {
    _rooms[roomId]?.remove(userId);
    
    if (_rooms[roomId]?.isEmpty ?? true) {
      _rooms.remove(roomId);
    }
    
    await server.execute('leaveRoom', {
      'roomId': roomId,
      'userId': userId,
    });
  }
  
  Future<void> broadcast(String roomId, Message message) async {
    await server.execute('broadcast', {
      'roomId': roomId,
      'message': message.toJson(),
    });
  }
  
  Stream<Message> getRoomMessages(String roomId) {
    return server.subscribe('room:$roomId').map((data) {
      return Message.fromJson(data as Map<String, dynamic>);
    });
  }
  
  Stream<UserEvent> getRoomUserEvents(String roomId) {
    return server.subscribe('room:$roomId:users').map((data) {
      return UserEvent.fromJson(data as Map<String, dynamic>);
    });
  }
}

class Message {
  final String id;
  final String userId;
  final String content;
  final DateTime timestamp;
  final MessageType type;
  
  Message({
    required this.id,
    required this.userId,
    required this.content,
    required this.timestamp,
    required this.type,
  });
  
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      userId: json['userId'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
    };
  }
}

enum MessageType {
  text,
  image,
  file,
  system,
}

class UserEvent {
  final String userId;
  final UserEventType type;
  final DateTime timestamp;
  
  UserEvent({
    required this.userId,
    required this.type,
    required this.timestamp,
  });
  
  factory UserEvent.fromJson(Map<String, dynamic> json) {
    return UserEvent(
      userId: json['userId'],
      type: UserEventType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

enum UserEventType {
  joined,
  left,
  typing,
  idle,
}
```

## Real-time UI Example

### Live Chat Implementation

```dart
// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/broadcast_service.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String userId;
  
  const ChatScreen({
    Key? key,
    required this.roomId,
    required this.userId,
  }) : super(key: key);
  
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <Message>[];
  final _typingUsers = <String>{};
  
  late BroadcastService _broadcastService;
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<UserEvent>? _userEventSubscription;
  Timer? _typingTimer;
  
  @override
  void initState() {
    super.initState();
    _initializeChat();
  }
  
  Future<void> _initializeChat() async {
    _broadcastService = context.read<BroadcastService>();
    
    // Join room
    await _broadcastService.joinRoom(widget.roomId, widget.userId);
    
    // Subscribe to messages
    _messageSubscription = _broadcastService
        .getRoomMessages(widget.roomId)
        .listen((message) {
      setState(() {
        _messages.add(message);
      });
      _scrollToBottom();
    });
    
    // Subscribe to user events
    _userEventSubscription = _broadcastService
        .getRoomUserEvents(widget.roomId)
        .listen((event) {
      _handleUserEvent(event);
    });
  }
  
  void _handleUserEvent(UserEvent event) {
    setState(() {
      switch (event.type) {
        case UserEventType.typing:
          _typingUsers.add(event.userId);
          break;
        case UserEventType.idle:
          _typingUsers.remove(event.userId);
          break;
        case UserEventType.joined:
          _messages.add(Message(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            userId: 'system',
            content: '${event.userId} joined the room',
            timestamp: event.timestamp,
            type: MessageType.system,
          ));
          break;
        case UserEventType.left:
          _typingUsers.remove(event.userId);
          _messages.add(Message(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            userId: 'system',
            content: '${event.userId} left the room',
            timestamp: event.timestamp,
            type: MessageType.system,
          ));
          break;
      }
    });
  }
  
  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    
    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: widget.userId,
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.text,
    );
    
    _broadcastService.broadcast(widget.roomId, message);
    _messageController.clear();
    _sendTypingEvent(false);
  }
  
  void _onTextChanged(String text) {
    _typingTimer?.cancel();
    
    if (text.isNotEmpty) {
      _sendTypingEvent(true);
      
      _typingTimer = Timer(Duration(seconds: 2), () {
        _sendTypingEvent(false);
      });
    } else {
      _sendTypingEvent(false);
    }
  }
  
  void _sendTypingEvent(bool isTyping) {
    final event = UserEvent(
      userId: widget.userId,
      type: isTyping ? UserEventType.typing : UserEventType.idle,
      timestamp: DateTime.now(),
    );
    
    // Send typing event to server
    _broadcastService.server.execute('userEvent', {
      'roomId': widget.roomId,
      'event': event.toJson(),
    });
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room: ${widget.roomId}'),
        actions: [
          IconButton(
            icon: Icon(Icons.info),
            onPressed: () => _showRoomInfo(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          if (_typingUsers.isNotEmpty)
            _buildTypingIndicator(),
          _buildMessageInput(),
        ],
      ),
    );
  }
  
  Widget _buildMessageBubble(Message message) {
    final isMe = message.userId == widget.userId;
    final isSystem = message.type == MessageType.system;
    
    if (isSystem) {
      return Center(
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 8),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                message.userId,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isMe ? Colors.white70 : Colors.black54,
                ),
              ),
            Text(
              message.content,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
              ),
            ),
            SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTypingIndicator() {
    final typingUsersList = _typingUsers.toList();
    String text;
    
    if (typingUsersList.length == 1) {
      text = '${typingUsersList[0]} is typing...';
    } else if (typingUsersList.length == 2) {
      text = '${typingUsersList[0]} and ${typingUsersList[1]} are typing...';
    } else {
      text = '${typingUsersList.length} people are typing...';
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 10,
            child: _buildTypingDots(),
          ),
          SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTypingDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(3, (index) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 600),
          builder: (context, value, child) {
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey[400]!.withOpacity(value),
                shape: BoxShape.circle,
              ),
            );
          },
          onEnd: () {
            // Restart animation
            setState(() {});
          },
        );
      }),
    );
  }
  
  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, -2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              onChanged: _onTextChanged,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: _sendMessage,
            color: Theme.of(context).primaryColor,
          ),
        ],
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  
  void _showRoomInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Room Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room ID: ${widget.roomId}'),
            Text('Your ID: ${widget.userId}'),
            Text('Active users: ${_typingUsers.length + 1}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageSubscription?.cancel();
    _userEventSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    
    // Leave room
    _broadcastService.leaveRoom(widget.roomId, widget.userId);
    
    super.dispose();
  }
}
```

### Real-time Dashboard

```dart
// lib/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/realtime_service.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _realtimeService = RealtimeService(serverName: 'metrics-server');
  final _metricsData = <MetricData>[];
  final _maxDataPoints = 50;
  
  StreamSubscription<RealtimeEvent>? _eventSubscription;
  
  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }
  
  Future<void> _initializeDashboard() async {
    await _realtimeService.connect();
    
    // Subscribe to metrics channels
    await _realtimeService.subscribe('metrics:cpu');
    await _realtimeService.subscribe('metrics:memory');
    await _realtimeService.subscribe('metrics:network');
    
    _eventSubscription = _realtimeService.events.listen((event) {
      if (!event.isSystemEvent) {
        _handleMetricEvent(event);
      }
    });
  }
  
  void _handleMetricEvent(RealtimeEvent event) {
    setState(() {
      final metric = MetricData.fromEvent(event);
      _metricsData.add(metric);
      
      // Keep only recent data points
      if (_metricsData.length > _maxDataPoints) {
        _metricsData.removeAt(0);
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Real-time Dashboard'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _buildMetricCard(
              'CPU Usage',
              _getMetricValues('cpu'),
              Colors.blue,
            ),
            SizedBox(height: 16),
            _buildMetricCard(
              'Memory Usage',
              _getMetricValues('memory'),
              Colors.green,
            ),
            SizedBox(height: 16),
            _buildMetricCard(
              'Network I/O',
              _getMetricValues('network'),
              Colors.orange,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMetricCard(String title, List<double> values, Color color) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 8),
            Text(
              values.isEmpty ? '0' : '${values.last.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _createSpots(values),
                      isCurved: true,
                      color: color,
                      barWidth: 3,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withOpacity(0.2),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(enabled: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  List<FlSpot> _createSpots(List<double> values) {
    if (values.isEmpty) return [FlSpot(0, 0)];
    
    return values.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value);
    }).toList();
  }
  
  List<double> _getMetricValues(String metricType) {
    return _metricsData
        .where((data) => data.type == metricType)
        .map((data) => data.value)
        .toList();
  }
  
  @override
  void dispose() {
    _eventSubscription?.cancel();
    _realtimeService.dispose();
    super.dispose();
  }
}

class MetricData {
  final String type;
  final double value;
  final DateTime timestamp;
  
  MetricData({
    required this.type,
    required this.value,
    required this.timestamp,
  });
  
  factory MetricData.fromEvent(RealtimeEvent event) {
    final channelParts = event.channel.split(':');
    final metricType = channelParts.last;
    final data = event.data as Map<String, dynamic>;
    
    return MetricData(
      type: metricType,
      value: data['value'].toDouble(),
      timestamp: event.timestamp,
    );
  }
}
```

## Stream Management

### Buffered Streams

```dart
// lib/utils/stream_buffer.dart
import 'dart:async';

class StreamBuffer<T> {
  final int bufferSize;
  final Duration bufferTime;
  final void Function(List<T>) onFlush;
  
  final _buffer = <T>[];
  Timer? _flushTimer;
  bool _isDisposed = false;
  
  StreamBuffer({
    required this.bufferSize,
    required this.bufferTime,
    required this.onFlush,
  });
  
  StreamTransformer<T, List<T>> get transformer {
    return StreamTransformer<T, List<T>>.fromHandlers(
      handleData: (data, sink) {
        _buffer.add(data);
        
        if (_buffer.length >= bufferSize) {
          _flush(sink);
        } else {
          _scheduleFlush(sink);
        }
      },
      handleDone: (sink) {
        if (_buffer.isNotEmpty) {
          _flush(sink);
        }
        sink.close();
      },
    );
  }
  
  void _scheduleFlush(EventSink<List<T>> sink) {
    _flushTimer?.cancel();
    _flushTimer = Timer(bufferTime, () {
      if (!_isDisposed) {
        _flush(sink);
      }
    });
  }
  
  void _flush(EventSink<List<T>> sink) {
    if (_buffer.isEmpty) return;
    
    final items = List<T>.from(_buffer);
    _buffer.clear();
    
    sink.add(items);
    onFlush(items);
    
    _flushTimer?.cancel();
  }
  
  void dispose() {
    _isDisposed = true;
    _flushTimer?.cancel();
    _buffer.clear();
  }
}
```

### Rate-Limited Streams

```dart
// lib/utils/rate_limiter.dart
import 'dart:async';

class RateLimiter<T> {
  final Duration interval;
  final int maxEvents;
  
  final _eventTimes = <DateTime>[];
  Timer? _timer;
  
  RateLimiter({
    required this.interval,
    required this.maxEvents,
  });
  
  StreamTransformer<T, T> get transformer {
    return StreamTransformer<T, T>.fromHandlers(
      handleData: (data, sink) {
        final now = DateTime.now();
        
        // Remove old events
        _eventTimes.removeWhere((time) {
          return now.difference(time) > interval;
        });
        
        // Check if we can emit
        if (_eventTimes.length < maxEvents) {
          _eventTimes.add(now);
          sink.add(data);
        } else {
          // Schedule for later
          final oldestEvent = _eventTimes.first;
          final waitTime = interval - now.difference(oldestEvent);
          
          _timer?.cancel();
          _timer = Timer(waitTime, () {
            sink.add(data);
            _eventTimes.add(DateTime.now());
          });
        }
      },
      handleDone: (sink) {
        _timer?.cancel();
        sink.close();
      },
    );
  }
  
  void dispose() {
    _timer?.cancel();
    _eventTimes.clear();
  }
}
```

## Testing Real-time Features

```dart
// test/realtime_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('Realtime Service Tests', () {
    late RealtimeService service;
    late MockMCPServer mockServer;
    
    setUp(() {
      mockServer = MockMCPServer();
      service = RealtimeService(serverName: 'test-server');
    });
    
    test('subscribes to channels', () async {
      final mockSubscription = MockStreamSubscription<dynamic>();
      when(mockServer.subscribe('test-channel'))
          .thenAnswer((_) async => mockSubscription);
      
      await service.subscribe('test-channel');
      
      verify(mockServer.subscribe('test-channel')).called(1);
    });
    
    test('handles disconnection events', () async {
      when(mockServer.eventStream).thenAnswer((_) => Stream.value(
        MCPEvent(type: MCPEventType.disconnected),
      ));
      
      expectLater(
        service.events,
        emits(predicate<RealtimeEvent>((event) {
          return event.isSystemEvent &&
              event.systemEventType == SystemEventType.disconnected;
        })),
      );
      
      await service.connect();
    });
    
    test('resubscribes after reconnection', () async {
      // Subscribe to channel
      await service.subscribe('test-channel');
      
      // Simulate reconnection
      when(mockServer.eventStream).thenAnswer((_) => Stream.value(
        MCPEvent(type: MCPEventType.connected),
      ));
      
      await service.connect();
      
      // Should resubscribe
      verify(mockServer.subscribe('test-channel')).called(2);
    });
  });
  
  group('Stream Buffer Tests', () {
    test('buffers items until size limit', () async {
      final flushedItems = <List<int>>[];
      
      final buffer = StreamBuffer<int>(
        bufferSize: 3,
        bufferTime: Duration(seconds: 1),
        onFlush: flushedItems.add,
      );
      
      final stream = Stream.fromIterable([1, 2, 3, 4, 5])
          .transform(buffer.transformer);
      
      await for (final items in stream) {
        flushedItems.add(items);
      }
      
      expect(flushedItems, [
        [1, 2, 3],
        [4, 5],
      ]);
    });
    
    test('flushes on timeout', () async {
      final flushedItems = <List<int>>[];
      
      final buffer = StreamBuffer<int>(
        bufferSize: 10,
        bufferTime: Duration(milliseconds: 100),
        onFlush: flushedItems.add,
      );
      
      final controller = StreamController<int>();
      final stream = controller.stream.transform(buffer.transformer);
      
      stream.listen((items) => flushedItems.add(items));
      
      controller.add(1);
      controller.add(2);
      
      await Future.delayed(Duration(milliseconds: 150));
      
      expect(flushedItems, [[1, 2]]);
      
      controller.close();
    });
  });
}
```

## Best Practices

### Connection Management

1. **Auto-reconnect**: Implement automatic reconnection logic
2. **Exponential Backoff**: Use exponential backoff for retries
3. **Connection Pooling**: Reuse connections when possible
4. **Error Recovery**: Handle connection errors gracefully
5. **State Synchronization**: Sync state after reconnection

### Performance Optimization

```dart
// Optimize stream processing
class OptimizedStreamProcessor<T> {
  final _cache = <String, T>{};
  final _deduplicationWindow = Duration(milliseconds: 100);
  DateTime? _lastEventTime;
  
  StreamTransformer<T, T> get deduplicator {
    return StreamTransformer<T, T>.fromHandlers(
      handleData: (data, sink) {
        final now = DateTime.now();
        final key = data.toString();
        
        // Check deduplication window
        if (_lastEventTime != null &&
            now.difference(_lastEventTime!) < _deduplicationWindow &&
            _cache.containsKey(key)) {
          return; // Skip duplicate
        }
        
        _cache[key] = data;
        _lastEventTime = now;
        sink.add(data);
        
        // Clean old cache entries
        if (_cache.length > 1000) {
          _cache.clear();
        }
      },
    );
  }
}
```

### Resource Management

```dart
// Manage stream subscriptions
class StreamManager {
  final _subscriptions = <String, StreamSubscription>{};
  
  void addSubscription(String key, StreamSubscription subscription) {
    _subscriptions[key]?.cancel();
    _subscriptions[key] = subscription;
  }
  
  void removeSubscription(String key) {
    _subscriptions[key]?.cancel();
    _subscriptions.remove(key);
  }
  
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
```

## Next Steps

- Explore [Desktop Applications](./desktop-applications.md)
- Learn about [Web Applications](./web-applications.md)
- Try [Android Integration](./android-integration.md)