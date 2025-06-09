# State Management Example

This example demonstrates integrating Flutter MCP with popular state management solutions.

## Overview

This example shows how to:
- Integrate with Provider
- Use with Riverpod
- Implement with Bloc
- Manage MCP state effectively

## Provider Integration

### MCP Provider Setup

```dart
// lib/providers/mcp_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class MCPProvider extends ChangeNotifier {
  final MCPConfig _config;
  final Map<String, MCPServer> _servers = {};
  final Map<String, ServerState> _serverStates = {};
  final Map<String, dynamic> _cachedData = {};
  
  bool _initialized = false;
  String? _error;
  
  MCPProvider(this._config);
  
  bool get initialized => _initialized;
  String? get error => _error;
  Map<String, ServerState> get serverStates => Map.unmodifiable(_serverStates);
  
  Future<void> initialize() async {
    try {
      await FlutterMCP.initialize(_config);
      _initialized = true;
      _error = null;
      
      // Initialize server states
      for (final serverName in _config.servers.keys) {
        _serverStates[serverName] = ServerState.disconnected;
      }
      
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
  
  Future<void> connectServer(String serverName) async {
    _serverStates[serverName] = ServerState.connecting;
    notifyListeners();
    
    try {
      final server = await FlutterMCP.connect(serverName);
      _servers[serverName] = server;
      _serverStates[serverName] = ServerState.connected;
      
      // Monitor server connection
      server.connectionState.listen((state) {
        _serverStates[serverName] = _mapConnectionState(state);
        notifyListeners();
      });
      
      notifyListeners();
    } catch (e) {
      _serverStates[serverName] = ServerState.error;
      _error = 'Failed to connect to $serverName: $e';
      notifyListeners();
    }
  }
  
  Future<T> executeMethod<T>(String serverName, String method, Map<String, dynamic> params) async {
    final server = _servers[serverName];
    if (server == null) {
      throw MCPException('Server not connected: $serverName');
    }
    
    try {
      final result = await server.execute(method, params);
      
      // Cache result
      final cacheKey = '$serverName:$method:${jsonEncode(params)}';
      _cachedData[cacheKey] = result;
      
      notifyListeners();
      return result as T;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }
  
  T? getCachedData<T>(String serverName, String method, Map<String, dynamic> params) {
    final cacheKey = '$serverName:$method:${jsonEncode(params)}';
    return _cachedData[cacheKey] as T?;
  }
  
  void clearCache() {
    _cachedData.clear();
    notifyListeners();
  }
  
  ServerState _mapConnectionState(ConnectionState state) {
    switch (state) {
      case ConnectionState.connected:
        return ServerState.connected;
      case ConnectionState.connecting:
        return ServerState.connecting;
      case ConnectionState.disconnected:
        return ServerState.disconnected;
      default:
        return ServerState.error;
    }
  }
  
  @override
  void dispose() {
    for (final server in _servers.values) {
      server.disconnect();
    }
    super.dispose();
  }
}

enum ServerState {
  disconnected,
  connecting,
  connected,
  error,
}
```

### Provider Usage Example

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/mcp_provider.dart';
import 'screens/provider_example_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => MCPProvider(MCPConfig(
        servers: {
          'main-server': ServerConfig(
            uri: 'ws://localhost:3000',
          ),
        },
      )),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Provider Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ProviderExampleScreen(),
    );
  }
}
```

```dart
// lib/screens/provider_example_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mcp_provider.dart';

class ProviderExampleScreen extends StatefulWidget {
  @override
  _ProviderExampleScreenState createState() => _ProviderExampleScreenState();
}

class _ProviderExampleScreenState extends State<ProviderExampleScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize MCP after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MCPProvider>().initialize();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Provider Example'),
      ),
      body: Consumer<MCPProvider>(
        builder: (context, mcpProvider, child) {
          if (!mcpProvider.initialized) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing MCP...'),
                ],
              ),
            );
          }
          
          if (mcpProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Error: ${mcpProvider.error}',
                    style: TextStyle(color: Colors.red),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => mcpProvider.initialize(),
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }
          
          return ListView(
            padding: EdgeInsets.all(16),
            children: [
              _buildServerStatus(context, mcpProvider),
              SizedBox(height: 16),
              _buildDataSection(context, mcpProvider),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildServerStatus(BuildContext context, MCPProvider provider) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server Status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 16),
            ...provider.serverStates.entries.map((entry) {
              final serverName = entry.key;
              final state = entry.value;
              
              return ListTile(
                title: Text(serverName),
                subtitle: Text(state.toString()),
                leading: _getStateIcon(state),
                trailing: ElevatedButton(
                  onPressed: state == ServerState.disconnected
                      ? () => provider.connectServer(serverName)
                      : null,
                  child: Text('Connect'),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDataSection(BuildContext context, MCPProvider provider) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data Operations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _fetchData(context),
              child: Text('Fetch Data'),
            ),
            SizedBox(height: 16),
            Consumer<MCPProvider>(
              builder: (context, provider, _) {
                final cachedData = provider.getCachedData<Map<String, dynamic>>(
                  'main-server',
                  'getData',
                  {},
                );
                
                if (cachedData == null) {
                  return Text('No data yet');
                }
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cached Data:'),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        jsonEncode(cachedData),
                        style: TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _getStateIcon(ServerState state) {
    switch (state) {
      case ServerState.connected:
        return Icon(Icons.check_circle, color: Colors.green);
      case ServerState.connecting:
        return CircularProgressIndicator(strokeWidth: 2);
      case ServerState.disconnected:
        return Icon(Icons.cancel, color: Colors.grey);
      case ServerState.error:
        return Icon(Icons.error, color: Colors.red);
    }
  }
  
  Future<void> _fetchData(BuildContext context) async {
    try {
      await context.read<MCPProvider>().executeMethod(
        'main-server',
        'getData',
        {},
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data fetched successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

## Riverpod Integration

### MCP Riverpod Providers

```dart
// lib/providers/mcp_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

// MCP configuration provider
final mcpConfigProvider = Provider<MCPConfig>((ref) {
  return MCPConfig(
    servers: {
      'main-server': ServerConfig(
        uri: 'ws://localhost:3000',
      ),
      'secondary-server': ServerConfig(
        uri: 'ws://localhost:3001',
      ),
    },
  );
});

// MCP initialization provider
final mcpInitProvider = FutureProvider<void>((ref) async {
  final config = ref.watch(mcpConfigProvider);
  await FlutterMCP.initialize(config);
});

// Server connection state
final serverConnectionProvider = StateNotifierProvider.family<
    ServerConnectionNotifier, AsyncValue<MCPServer>, String>(
  (ref, serverName) => ServerConnectionNotifier(serverName),
);

class ServerConnectionNotifier extends StateNotifier<AsyncValue<MCPServer>> {
  final String serverName;
  
  ServerConnectionNotifier(this.serverName) : super(const AsyncValue.loading()) {
    _connect();
  }
  
  Future<void> _connect() async {
    state = const AsyncValue.loading();
    
    try {
      final server = await FlutterMCP.connect(serverName);
      state = AsyncValue.data(server);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
  
  Future<void> reconnect() async {
    await _connect();
  }
}

// Data fetching provider
final dataProvider = FutureProvider.family<Map<String, dynamic>, DataRequest>(
  (ref, request) async {
    final serverConnection = ref.watch(
      serverConnectionProvider(request.serverName),
    );
    
    final server = serverConnection.valueOrNull;
    if (server == null) {
      throw MCPException('Server not connected');
    }
    
    return await server.execute(request.method, request.params);
  },
);

class DataRequest {
  final String serverName;
  final String method;
  final Map<String, dynamic> params;
  
  DataRequest({
    required this.serverName,
    required this.method,
    required this.params,
  });
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is DataRequest &&
        other.serverName == serverName &&
        other.method == method &&
        mapEquals(other.params, params);
  }
  
  @override
  int get hashCode => Object.hash(serverName, method, params);
}

// Cached data provider with refresh capability
final cachedDataProvider = StateNotifierProvider.family<
    CachedDataNotifier, AsyncValue<Map<String, dynamic>>, DataRequest>(
  (ref, request) => CachedDataNotifier(ref, request),
);

class CachedDataNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final Ref ref;
  final DataRequest request;
  Timer? _refreshTimer;
  
  CachedDataNotifier(this.ref, this.request)
      : super(const AsyncValue.loading()) {
    _loadData();
    _setupAutoRefresh();
  }
  
  Future<void> _loadData() async {
    state = const AsyncValue.loading();
    
    try {
      final data = await ref.read(dataProvider(request).future);
      state = AsyncValue.data(data);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
  
  void _setupAutoRefresh() {
    _refreshTimer = Timer.periodic(Duration(seconds: 30), (_) {
      refresh();
    });
  }
  
  Future<void> refresh() async {
    await _loadData();
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
```

### Riverpod Usage Example

```dart
// lib/screens/riverpod_example_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/mcp_providers.dart';

class RiverpodExampleScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initState = ref.watch(mcpInitProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Riverpod Example'),
      ),
      body: initState.when(
        data: (_) => _buildContent(context, ref),
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, color: Colors.red, size: 48),
              SizedBox(height: 16),
              Text('Error: $error'),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(mcpInitProvider),
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildContent(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _buildServerConnections(context, ref),
        SizedBox(height: 16),
        _buildDataDisplay(context, ref),
      ],
    );
  }
  
  Widget _buildServerConnections(BuildContext context, WidgetRef ref) {
    final config = ref.watch(mcpConfigProvider);
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server Connections',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 16),
            ...config.servers.keys.map((serverName) {
              final connectionState = ref.watch(
                serverConnectionProvider(serverName),
              );
              
              return ListTile(
                title: Text(serverName),
                subtitle: Text(
                  connectionState.when(
                    data: (_) => 'Connected',
                    loading: () => 'Connecting...',
                    error: (error, _) => 'Error: $error',
                  ),
                ),
                leading: connectionState.when(
                  data: (_) => Icon(Icons.check_circle, color: Colors.green),
                  loading: () => CircularProgressIndicator(strokeWidth: 2),
                  error: (_, __) => Icon(Icons.error, color: Colors.red),
                ),
                trailing: connectionState.hasError
                    ? ElevatedButton(
                        onPressed: () => ref
                            .read(serverConnectionProvider(serverName).notifier)
                            .reconnect(),
                        child: Text('Reconnect'),
                      )
                    : null,
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDataDisplay(BuildContext context, WidgetRef ref) {
    final request = DataRequest(
      serverName: 'main-server',
      method: 'getData',
      params: {},
    );
    
    final dataState = ref.watch(cachedDataProvider(request));
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Data Display',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  onPressed: () => ref
                      .read(cachedDataProvider(request).notifier)
                      .refresh(),
                  icon: Icon(Icons.refresh),
                ),
              ],
            ),
            SizedBox(height: 16),
            dataState.when(
              data: (data) => Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  jsonEncode(data),
                  style: TextStyle(fontFamily: 'monospace'),
                ),
              ),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, _) => Text(
                'Error: $error',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

## Bloc Integration

### MCP Bloc Implementation

```dart
// lib/blocs/mcp_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:equatable/equatable.dart';

// Events
abstract class MCPEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class InitializeMCP extends MCPEvent {
  final MCPConfig config;
  
  InitializeMCP(this.config);
  
  @override
  List<Object?> get props => [config];
}

class ConnectServer extends MCPEvent {
  final String serverName;
  
  ConnectServer(this.serverName);
  
  @override
  List<Object?> get props => [serverName];
}

class ExecuteMethod extends MCPEvent {
  final String serverName;
  final String method;
  final Map<String, dynamic> params;
  
  ExecuteMethod({
    required this.serverName,
    required this.method,
    required this.params,
  });
  
  @override
  List<Object?> get props => [serverName, method, params];
}

class RefreshData extends MCPEvent {
  final String key;
  
  RefreshData(this.key);
  
  @override
  List<Object?> get props => [key];
}

// States
abstract class MCPState extends Equatable {
  @override
  List<Object?> get props => [];
}

class MCPInitial extends MCPState {}

class MCPInitializing extends MCPState {}

class MCPInitialized extends MCPState {
  final Map<String, ServerConnectionState> serverStates;
  final Map<String, dynamic> data;
  
  MCPInitialized({
    required this.serverStates,
    required this.data,
  });
  
  @override
  List<Object?> get props => [serverStates, data];
  
  MCPInitialized copyWith({
    Map<String, ServerConnectionState>? serverStates,
    Map<String, dynamic>? data,
  }) {
    return MCPInitialized(
      serverStates: serverStates ?? this.serverStates,
      data: data ?? this.data,
    );
  }
}

class MCPError extends MCPState {
  final String message;
  
  MCPError(this.message);
  
  @override
  List<Object?> get props => [message];
}

enum ServerConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

// Bloc
class MCPBloc extends Bloc<MCPEvent, MCPState> {
  final Map<String, MCPServer> _servers = {};
  
  MCPBloc() : super(MCPInitial()) {
    on<InitializeMCP>(_onInitialize);
    on<ConnectServer>(_onConnectServer);
    on<ExecuteMethod>(_onExecuteMethod);
    on<RefreshData>(_onRefreshData);
  }
  
  Future<void> _onInitialize(
    InitializeMCP event,
    Emitter<MCPState> emit,
  ) async {
    emit(MCPInitializing());
    
    try {
      await FlutterMCP.initialize(event.config);
      
      final serverStates = <String, ServerConnectionState>{};
      for (final serverName in event.config.servers.keys) {
        serverStates[serverName] = ServerConnectionState.disconnected;
      }
      
      emit(MCPInitialized(
        serverStates: serverStates,
        data: {},
      ));
    } catch (e) {
      emit(MCPError(e.toString()));
    }
  }
  
  Future<void> _onConnectServer(
    ConnectServer event,
    Emitter<MCPState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MCPInitialized) return;
    
    emit(currentState.copyWith(
      serverStates: {
        ...currentState.serverStates,
        event.serverName: ServerConnectionState.connecting,
      },
    ));
    
    try {
      final server = await FlutterMCP.connect(event.serverName);
      _servers[event.serverName] = server;
      
      emit(currentState.copyWith(
        serverStates: {
          ...currentState.serverStates,
          event.serverName: ServerConnectionState.connected,
        },
      ));
    } catch (e) {
      emit(currentState.copyWith(
        serverStates: {
          ...currentState.serverStates,
          event.serverName: ServerConnectionState.error,
        },
      ));
    }
  }
  
  Future<void> _onExecuteMethod(
    ExecuteMethod event,
    Emitter<MCPState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MCPInitialized) return;
    
    final server = _servers[event.serverName];
    if (server == null) {
      emit(MCPError('Server not connected: ${event.serverName}'));
      return;
    }
    
    try {
      final result = await server.execute(event.method, event.params);
      
      final dataKey = '${event.serverName}:${event.method}';
      emit(currentState.copyWith(
        data: {
          ...currentState.data,
          dataKey: result,
        },
      ));
    } catch (e) {
      emit(MCPError(e.toString()));
    }
  }
  
  Future<void> _onRefreshData(
    RefreshData event,
    Emitter<MCPState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MCPInitialized) return;
    
    // Parse the key to get server and method
    final parts = event.key.split(':');
    if (parts.length != 2) return;
    
    final serverName = parts[0];
    final method = parts[1];
    
    add(ExecuteMethod(
      serverName: serverName,
      method: method,
      params: {},
    ));
  }
  
  @override
  Future<void> close() {
    for (final server in _servers.values) {
      server.disconnect();
    }
    return super.close();
  }
}
```

### Bloc Usage Example

```dart
// lib/screens/bloc_example_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/mcp_bloc.dart';

class BlocExampleScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MCPBloc()
        ..add(InitializeMCP(MCPConfig(
          servers: {
            'main-server': ServerConfig(
              uri: 'ws://localhost:3000',
            ),
          },
        ))),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Bloc Example'),
        ),
        body: BlocBuilder<MCPBloc, MCPState>(
          builder: (context, state) {
            if (state is MCPInitializing) {
              return Center(child: CircularProgressIndicator());
            }
            
            if (state is MCPError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, color: Colors.red, size: 48),
                    SizedBox(height: 16),
                    Text('Error: ${state.message}'),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.read<MCPBloc>().add(
                        InitializeMCP(MCPConfig(
                          servers: {
                            'main-server': ServerConfig(
                              uri: 'ws://localhost:3000',
                            ),
                          },
                        )),
                      ),
                      child: Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            
            if (state is MCPInitialized) {
              return ListView(
                padding: EdgeInsets.all(16),
                children: [
                  _buildServerSection(context, state),
                  SizedBox(height: 16),
                  _buildDataSection(context, state),
                ],
              );
            }
            
            return Center(child: Text('Unknown state'));
          },
        ),
      ),
    );
  }
  
  Widget _buildServerSection(BuildContext context, MCPInitialized state) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Servers',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 16),
            ...state.serverStates.entries.map((entry) {
              final serverName = entry.key;
              final connectionState = entry.value;
              
              return ListTile(
                title: Text(serverName),
                subtitle: Text(connectionState.toString()),
                leading: _getConnectionIcon(connectionState),
                trailing: ElevatedButton(
                  onPressed: connectionState == ServerConnectionState.disconnected
                      ? () => context.read<MCPBloc>().add(
                            ConnectServer(serverName),
                          )
                      : null,
                  child: Text('Connect'),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDataSection(BuildContext context, MCPInitialized state) {
    final dataKey = 'main-server:getData';
    final data = state.data[dataKey];
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Data',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  onPressed: () => context.read<MCPBloc>().add(
                    RefreshData(dataKey),
                  ),
                  icon: Icon(Icons.refresh),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (data == null) ...[               ElevatedButton(
                onPressed: () => context.read<MCPBloc>().add(
                  ExecuteMethod(
                    serverName: 'main-server',
                    method: 'getData',
                    params: {},
                  ),
                ),
                child: Text('Fetch Data'),
              ),
            ] else ...[               Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  jsonEncode(data),
                  style: TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _getConnectionIcon(ServerConnectionState state) {
    switch (state) {
      case ServerConnectionState.connected:
        return Icon(Icons.check_circle, color: Colors.green);
      case ServerConnectionState.connecting:
        return CircularProgressIndicator(strokeWidth: 2);
      case ServerConnectionState.disconnected:
        return Icon(Icons.cancel, color: Colors.grey);
      case ServerConnectionState.error:
        return Icon(Icons.error, color: Colors.red);
    }
  }
}
```

## Best Practices

### State Management Principles

1. **Separation of Concerns**: Keep MCP logic separate from UI logic
2. **Error Handling**: Always handle connection and execution errors
3. **Loading States**: Show appropriate loading indicators
4. **Caching**: Implement data caching to reduce server calls
5. **Reactive Updates**: Use streams for real-time updates

### Performance Optimization

```dart
// Optimized data provider with caching
class OptimizedMCPProvider extends ChangeNotifier {
  final _cache = ExpiringCache<String, dynamic>();
  final _pendingRequests = <String, Future<dynamic>>{};
  
  Future<T> getCachedData<T>(
    String serverName,
    String method,
    Map<String, dynamic> params, {
    Duration? ttl,
  }) async {
    final cacheKey = '$serverName:$method:${jsonEncode(params)}';
    
    // Check cache first
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      return cached as T;
    }
    
    // Check if request is already pending
    if (_pendingRequests.containsKey(cacheKey)) {
      return await _pendingRequests[cacheKey] as T;
    }
    
    // Make new request
    final future = executeMethod<T>(serverName, method, params);
    _pendingRequests[cacheKey] = future;
    
    try {
      final result = await future;
      _cache.set(cacheKey, result, ttl: ttl ?? Duration(minutes: 5));
      return result;
    } finally {
      _pendingRequests.remove(cacheKey);
    }
  }
}
```

### Testing State Management

```dart
// test/state_management_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

void main() {
  group('MCPProvider Tests', () {
    late MCPProvider provider;
    late MockMCPServer mockServer;
    
    setUp(() {
      mockServer = MockMCPServer();
      provider = MCPProvider(MockMCPConfig());
    });
    
    test('initializes successfully', () async {
      await provider.initialize();
      
      expect(provider.initialized, isTrue);
      expect(provider.error, isNull);
    });
    
    test('handles connection errors', () async {
      when(mockServer.connect()).thenThrow(MCPException('Connection failed'));
      
      await provider.connectServer('test-server');
      
      expect(provider.serverStates['test-server'], ServerState.error);
      expect(provider.error, contains('Connection failed'));
    });
    
    test('caches data correctly', () async {
      final testData = {'key': 'value'};
      when(mockServer.execute('getData', any))
          .thenAnswer((_) async => testData);
      
      final result1 = await provider.executeMethod('test-server', 'getData', {});
      final result2 = provider.getCachedData('test-server', 'getData', {});
      
      expect(result1, equals(testData));
      expect(result2, equals(testData));
      verify(mockServer.execute('getData', any)).called(1);
    });
  });
}
```

## Integration Patterns

### Combined State Management

```dart
// Combining Provider with Riverpod
class HybridStateManagement extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MCPProvider(config)),
      ],
      child: ProviderScope(
        child: MaterialApp(
          home: HybridScreen(),
        ),
      ),
    );
  }
}

class HybridScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use Provider for MCP state
    final mcpProvider = context.watch<MCPProvider>();
    
    // Use Riverpod for UI state
    final uiState = ref.watch(uiStateProvider);
    
    return Scaffold(
      body: Column(
        children: [
          // MCP data from Provider
          if (mcpProvider.initialized)
            DataDisplay(data: mcpProvider.cachedData),
          
          // UI state from Riverpod
          if (uiState.showDetails)
            DetailPanel(),
        ],
      ),
    );
  }
}
```

## Next Steps

- Explore [Real-time Updates](./realtime-updates.md)
- Learn about [Desktop Applications](./desktop-applications.md)
- Try [Web Applications](./web-applications.md)