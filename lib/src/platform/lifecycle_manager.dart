import 'package:flutter/widgets.dart';
import '../utils/logger.dart';
import '../utils/event_system.dart';

/// Lifecycle manager for handling app lifecycle events
class LifecycleManager with WidgetsBindingObserver {
  final MCPLogger _logger = MCPLogger('mcp.lifecycle_manager');

  // Lifecycle change callback
  Function(AppLifecycleState)? _onLifecycleStateChange;

  // Previous lifecycle state
  AppLifecycleState? _previousState;

  // Whether manager is initialized
  bool _initialized = false;

  // Event topics
  static const String _topicForeground = 'lifecycle.foreground';
  static const String _topicBackground = 'lifecycle.background';
  static const String _topicInactive = 'lifecycle.inactive';
  static const String _topicDetached = 'lifecycle.detached';
  static const String _topicAny = 'lifecycle.any';

  /// Initialize lifecycle manager
  void initialize() {
    if (_initialized) {
      _logger.warning('Lifecycle manager already initialized');
      return;
    }

    _logger.debug('Initializing lifecycle manager');
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }

  /// Register lifecycle change listener
  void setLifecycleChangeListener(Function(AppLifecycleState) listener) {
    _onLifecycleStateChange = listener;
  }

  /// Subscribe to app becoming foreground
  String onForeground(Function() callback) {
    return EventSystem.instance.subscribe<AppLifecycleState>(
      _topicForeground,
          (_) => callback(),
    );
  }

  /// Subscribe to app going to background
  String onBackground(Function() callback) {
    return EventSystem.instance.subscribe<AppLifecycleState>(
      _topicBackground,
          (_) => callback(),
    );
  }

  /// Subscribe to app becoming inactive
  String onInactive(Function() callback) {
    return EventSystem.instance.subscribe<AppLifecycleState>(
      _topicInactive,
          (_) => callback(),
    );
  }

  /// Subscribe to app being detached
  String onDetached(Function() callback) {
    return EventSystem.instance.subscribe<AppLifecycleState>(
      _topicDetached,
          (_) => callback(),
    );
  }

  /// Subscribe to any lifecycle change
  String onLifecycleChange(Function(AppLifecycleState) callback) {
    return EventSystem.instance.subscribe<AppLifecycleState>(
      _topicAny,
      callback,
    );
  }

  /// Unsubscribe from lifecycle events
  void unsubscribe(String token) {
    EventSystem.instance.unsubscribe(token);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.debug('App lifecycle state changed: $state');

    final previousState = _previousState;
    _previousState = state;

    // Handle lifecycle state change
    switch (state) {
      case AppLifecycleState.resumed:
        _logger.debug('App resumed to foreground');
        EventSystem.instance.publish(_topicForeground, state);
        break;
      case AppLifecycleState.inactive:
        _logger.debug('App became inactive');
        EventSystem.instance.publish(_topicInactive, state);
        break;
      case AppLifecycleState.paused:
        _logger.debug('App paused to background');
        EventSystem.instance.publish(_topicBackground, state);
        break;
      case AppLifecycleState.detached:
        _logger.debug('App detached');
        EventSystem.instance.publish(_topicDetached, state);
        break;
      default:
        _logger.debug('Unknown lifecycle state: $state');
    }

    // Publish to any listener
    EventSystem.instance.publish(_topicAny, state);

    // Call callback
    if (_onLifecycleStateChange != null) {
      _onLifecycleStateChange!(state);
    }

    // Handle specific transitions
    if (previousState != null) {
      _handleLifecycleTransition(previousState, state);
    }
  }

  /// Handle specific lifecycle transitions
  void _handleLifecycleTransition(AppLifecycleState from, AppLifecycleState to) {
    // Detect app coming to foreground from background
    if (from == AppLifecycleState.paused && to == AppLifecycleState.resumed) {
      _logger.debug('App returned to foreground from background');
      // Any specific foreground transition handling
    }

    // Detect app going to background from foreground
    if (from == AppLifecycleState.inactive && to == AppLifecycleState.paused) {
      _logger.debug('App moved to background from foreground');
      // Any specific background transition handling
    }
  }

  /// Clean up resources
  void dispose() {
    if (!_initialized) {
      return;
    }

    _logger.debug('Disposing lifecycle manager');
    WidgetsBinding.instance.removeObserver(this);
    _onLifecycleStateChange = null;
    _initialized = false;
  }

  /// Current app lifecycle state (if initialized)
  AppLifecycleState? get currentState => _previousState;

  /// Check if app is in foreground
  bool get isInForeground =>
      _previousState == AppLifecycleState.resumed;

  /// Check if app is in background
  bool get isInBackground =>
      _previousState == AppLifecycleState.paused ||
          _previousState == AppLifecycleState.detached;
}