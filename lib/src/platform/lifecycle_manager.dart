import 'package:flutter/widgets.dart';
import '../utils/logger.dart';
import '../events/event_system.dart';

/// Lifecycle manager for handling app lifecycle events
class LifecycleManager with WidgetsBindingObserver {
  final Logger _logger = Logger('flutter_mcp.lifecycle_manager');

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

    _logger.fine('Initializing lifecycle manager');
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }

  /// Register lifecycle change listener
  void setLifecycleChangeListener(Function(AppLifecycleState) listener) {
    _onLifecycleStateChange = listener;
  }

  /// Subscribe to app becoming foreground
  Future<String> onForeground(Function() callback) async {
    return await EventSystem.instance.subscribeTopic(
      _topicForeground,
      (_) => callback(),
    );
  }

  /// Subscribe to app going to background
  Future<String> onBackground(Function() callback) async {
    return await EventSystem.instance.subscribeTopic(
      _topicBackground,
      (_) => callback(),
    );
  }

  /// Subscribe to app becoming inactive
  Future<String> onInactive(Function() callback) async {
    return await EventSystem.instance.subscribeTopic(
      _topicInactive,
      (_) => callback(),
    );
  }

  /// Subscribe to app being detached
  Future<String> onDetached(Function() callback) async {
    return await EventSystem.instance.subscribeTopic(
      _topicDetached,
      (_) => callback(),
    );
  }

  /// Subscribe to any lifecycle change
  Future<String> onLifecycleChange(Function(AppLifecycleState) callback) async {
    return await EventSystem.instance.subscribeTopic(
      _topicAny,
      (data) => callback(data as AppLifecycleState),
    );
  }

  /// Unsubscribe from lifecycle events
  void unsubscribe(String token) {
    EventSystem.instance.unsubscribe(token);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.fine('App lifecycle state changed: $state');

    final previousState = _previousState;
    _previousState = state;

    // Handle lifecycle state change
    switch (state) {
      case AppLifecycleState.resumed:
        _logger.fine('App resumed to foreground');
        EventSystem.instance.publishTopic(_topicForeground, state);
        break;
      case AppLifecycleState.inactive:
        _logger.fine('App became inactive');
        EventSystem.instance.publishTopic(_topicInactive, state);
        break;
      case AppLifecycleState.paused:
        _logger.fine('App paused to background');
        EventSystem.instance.publishTopic(_topicBackground, state);
        break;
      case AppLifecycleState.detached:
        _logger.fine('App detached');
        EventSystem.instance.publishTopic(_topicDetached, state);
        break;
      default:
        _logger.fine('Unknown lifecycle state: $state');
    }

    // Publish to any listener
    EventSystem.instance.publishTopic(_topicAny, state);

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
  void _handleLifecycleTransition(
      AppLifecycleState from, AppLifecycleState to) {
    // Detect app coming to foreground from background
    if (from == AppLifecycleState.paused && to == AppLifecycleState.resumed) {
      _logger.fine('App returned to foreground from background');
      // Any specific foreground transition handling
    }

    // Detect app going to background from foreground
    if (from == AppLifecycleState.inactive && to == AppLifecycleState.paused) {
      _logger.fine('App moved to background from foreground');
      // Any specific background transition handling
    }
  }

  /// Clean up resources
  void dispose() {
    if (!_initialized) {
      return;
    }

    _logger.fine('Disposing lifecycle manager');
    WidgetsBinding.instance.removeObserver(this);
    _onLifecycleStateChange = null;
    _initialized = false;
  }

  /// Current app lifecycle state (if initialized)
  AppLifecycleState? get currentState => _previousState;

  /// Check if app is in foreground
  bool get isInForeground => _previousState == AppLifecycleState.resumed;

  /// Check if app is in background
  bool get isInBackground =>
      _previousState == AppLifecycleState.paused ||
      _previousState == AppLifecycleState.detached;
}
