import 'dart:async';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import '../../config/tray_config.dart';
import '../../utils/logger.dart';
import '../../utils/enhanced_error_handler.dart';
import '../../monitoring/health_monitor.dart';
import '../../utils/enhanced_resource_cleanup.dart';
import '../../utils/event_system.dart';
import '../../../flutter_mcp.dart' show MCPHealthStatus, MCPHealthCheckResult;
import 'tray_manager.dart';

/// Enhanced tray menu item with additional features
class EnhancedTrayMenuItem extends TrayMenuItem {
  /// Menu item icon path
  final String? iconPath;
  
  /// Submenu items
  final List<EnhancedTrayMenuItem>? submenu;
  
  /// Menu item type (checkbox, radio, normal)
  final MenuItemType type;
  
  /// Whether checkbox/radio is checked
  final bool checked;
  
  /// Keyboard shortcut
  final String? shortcut;
  
  /// Whether to show item
  final bool visible;
  
  /// Menu item metadata
  final Map<String, dynamic>? metadata;
  
  EnhancedTrayMenuItem({
    String? label,
    String? id,
    Function()? onTap,
    bool disabled = false,
    this.iconPath,
    this.submenu,
    this.type = MenuItemType.normal,
    this.checked = false,
    this.shortcut,
    this.visible = true,
    this.metadata,
  }) : super(
    label: label,
    id: id,
    onTap: onTap,
    disabled: disabled,
  );
  
  /// Create separator
  EnhancedTrayMenuItem.separator() : 
    iconPath = null,
    submenu = null,
    type = MenuItemType.normal,
    checked = false,
    shortcut = null,
    visible = true,
    metadata = null,
    super.separator();
  
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'iconPath': iconPath,
      'submenu': submenu?.map((item) => item.toJson()).toList(),
      'type': type.name,
      'checked': checked,
      'shortcut': shortcut,
      'visible': visible,
      'metadata': metadata,
    });
    return json;
  }
}

/// Menu item types
enum MenuItemType {
  normal,
  checkbox,
  radio,
}

/// Tray icon state
class TrayIconState {
  final bool visible;
  final String? iconPath;
  final String? tooltip;
  final bool animating;
  final Map<String, dynamic>? metadata;
  
  TrayIconState({
    this.visible = false,
    this.iconPath,
    this.tooltip,
    this.animating = false,
    this.metadata,
  });
}

/// Enhanced tray manager base class
abstract class EnhancedTrayManager implements TrayManager, HealthCheckProvider {
  final Logger logger;
  final EventSystem _eventSystem = EventSystem.instance;
  
  // Tray state
  TrayIconState _state = TrayIconState();
  final Map<String, EnhancedTrayMenuItem> _menuItems = {};
  final List<TrayEventListener> _eventListeners = [];
  
  // Animation support
  Timer? _animationTimer;
  List<String>? _animationFrames;
  int _currentFrame = 0;
  
  // Update tracking
  DateTime? _lastUpdate;
  int _updateCount = 0;
  
  // Platform-specific properties
  final bool supportsAnimation;
  final bool supportsColorIcons;
  final bool supportsSubmenu;
  final bool supportsBalloon;
  
  EnhancedTrayManager(
    String platformName, {
    this.supportsAnimation = false,
    this.supportsColorIcons = true,
    this.supportsSubmenu = true,
    this.supportsBalloon = true,
  }) : logger = Logger('flutter_mcp.enhanced_tray.$platformName');
  
  @override
  String get componentId => 'tray_manager';
  
  TrayIconState get state => _state;
  
  @override
  Future<void> initialize(TrayConfig? config) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        logger.fine('Initializing enhanced tray manager');
        
        // Platform-specific initialization
        await platformInitialize();
        
        // Apply configuration
        if (config != null) {
          await applyConfig(config);
        }
        
        // Register for resource cleanup
        EnhancedResourceCleanup.instance.registerResource(
          key: 'tray_manager',
          resource: this,
          disposeFunction: (_) async => await dispose(),
          type: 'TrayManager',
          description: 'System tray manager',
          priority: 200,
        );
        
        logger.info('Enhanced tray manager initialized');
        _publishTrayEvent('initialized');
      },
      context: 'tray_manager_init',
      component: 'tray_manager',
    );
  }
  
  /// Apply tray configuration
  Future<void> applyConfig(TrayConfig config) async {
    if (config.iconPath != null) {
      await setIcon(config.iconPath!);
    }
    
    if (config.tooltip != null) {
      await setTooltip(config.tooltip!);
    }
    
    if (config.menuItems != null) {
      final enhancedItems = config.menuItems!.map((item) {
        if (item is EnhancedTrayMenuItem) {
          return item;
        }
        return EnhancedTrayMenuItem(
          label: item.label,
          id: item.id,
          onTap: item.onTap,
          disabled: item.disabled,
        );
      }).toList();
      
      await setContextMenu(enhancedItems);
    }
  }
  
  @override
  Future<void> setIcon(String path) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await platformSetIcon(path);
        _state = TrayIconState(
          visible: _state.visible,
          iconPath: path,
          tooltip: _state.tooltip,
          animating: _state.animating,
          metadata: _state.metadata,
        );
        _updateTracking();
        logger.fine('Tray icon set: $path');
      },
      context: 'tray_set_icon',
      component: 'tray_manager',
    );
  }
  
  /// Set icon from bytes
  Future<void> setIconFromBytes(Uint8List bytes) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await platformSetIconFromBytes(bytes);
        _state = TrayIconState(
          visible: _state.visible,
          iconPath: '<bytes>',
          tooltip: _state.tooltip,
          animating: _state.animating,
          metadata: _state.metadata,
        );
        _updateTracking();
        logger.fine('Tray icon set from bytes');
      },
      context: 'tray_set_icon_bytes',
      component: 'tray_manager',
    );
  }
  
  @override
  Future<void> setTooltip(String tooltip) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await platformSetTooltip(tooltip);
        _state = TrayIconState(
          visible: _state.visible,
          iconPath: _state.iconPath,
          tooltip: tooltip,
          animating: _state.animating,
          metadata: _state.metadata,
        );
        _updateTracking();
        logger.fine('Tray tooltip set: $tooltip');
      },
      context: 'tray_set_tooltip',
      component: 'tray_manager',
    );
  }
  
  @override
  Future<void> setContextMenu(List<TrayMenuItem> items) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        // Convert to enhanced items if needed
        final enhancedItems = items.map((item) {
          if (item is EnhancedTrayMenuItem) {
            return item;
          }
          return EnhancedTrayMenuItem(
            label: item.label,
            id: item.id,
            onTap: item.onTap,
            disabled: item.disabled,
          );
        }).toList();
        
        // Store menu items
        _menuItems.clear();
        for (final item in enhancedItems) {
          if (item.id != null) {
            _menuItems[item.id!] = item;
          }
        }
        
        await platformSetContextMenu(enhancedItems);
        _updateTracking();
        logger.fine('Context menu set with ${items.length} items');
      },
      context: 'tray_set_context_menu',
      component: 'tray_manager',
    );
  }
  
  /// Show tray icon
  Future<void> show() async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await platformShow();
        _state = TrayIconState(
          visible: true,
          iconPath: _state.iconPath,
          tooltip: _state.tooltip,
          animating: _state.animating,
          metadata: _state.metadata,
        );
        _publishTrayEvent('shown');
      },
      context: 'tray_show',
      component: 'tray_manager',
    );
  }
  
  /// Hide tray icon
  Future<void> hide() async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await platformHide();
        _state = TrayIconState(
          visible: false,
          iconPath: _state.iconPath,
          tooltip: _state.tooltip,
          animating: _state.animating,
          metadata: _state.metadata,
        );
        _publishTrayEvent('hidden');
      },
      context: 'tray_hide',
      component: 'tray_manager',
    );
  }
  
  /// Start icon animation
  Future<void> startAnimation(List<String> framePaths, Duration frameDelay) async {
    if (!supportsAnimation) {
      logger.warning('Animation not supported on this platform');
      return;
    }
    
    await EnhancedErrorHandler.instance.handleError(
      () async {
        _animationFrames = framePaths;
        _currentFrame = 0;
        
        _animationTimer?.cancel();
        _animationTimer = Timer.periodic(frameDelay, (_) {
          _currentFrame = (_currentFrame + 1) % _animationFrames!.length;
          setIcon(_animationFrames![_currentFrame]);
        });
        
        _state = TrayIconState(
          visible: _state.visible,
          iconPath: _state.iconPath,
          tooltip: _state.tooltip,
          animating: true,
          metadata: _state.metadata,
        );
        
        logger.fine('Started icon animation with ${framePaths.length} frames');
      },
      context: 'tray_start_animation',
      component: 'tray_manager',
    );
  }
  
  /// Stop icon animation
  Future<void> stopAnimation() async {
    _animationTimer?.cancel();
    _animationTimer = null;
    _animationFrames = null;
    
    _state = TrayIconState(
      visible: _state.visible,
      iconPath: _state.iconPath,
      tooltip: _state.tooltip,
      animating: false,
      metadata: _state.metadata,
    );
    
    logger.fine('Stopped icon animation');
  }
  
  /// Show balloon notification (Windows/Linux)
  Future<void> showBalloon({
    required String title,
    required String message,
    BalloonIconType iconType = BalloonIconType.info,
    Duration? timeout,
  }) async {
    if (!supportsBalloon) {
      logger.warning('Balloon notifications not supported on this platform');
      return;
    }
    
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await platformShowBalloon(
          title: title,
          message: message,
          iconType: iconType,
          timeout: timeout,
        );
        
        _publishTrayEvent('balloon_shown', {
          'title': title,
          'message': message,
          'iconType': iconType.name,
        });
      },
      context: 'tray_show_balloon',
      component: 'tray_manager',
    );
  }
  
  /// Update menu item
  Future<void> updateMenuItem(String itemId, {
    String? label,
    bool? disabled,
    bool? checked,
    String? iconPath,
  }) async {
    final item = _menuItems[itemId];
    if (item == null) {
      logger.warning('Menu item not found: $itemId');
      return;
    }
    
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await platformUpdateMenuItem(
          itemId,
          label: label,
          disabled: disabled,
          checked: checked,
          iconPath: iconPath,
        );
        
        logger.fine('Updated menu item: $itemId');
      },
      context: 'tray_update_menu_item',
      component: 'tray_manager',
    );
  }
  
  /// Add event listener
  void addEventListener(TrayEventListener listener) {
    _eventListeners.add(listener);
  }
  
  /// Remove event listener
  void removeEventListener(TrayEventListener listener) {
    _eventListeners.remove(listener);
  }
  
  @override
  Future<void> dispose() async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        // Stop animation
        await stopAnimation();
        
        // Clear listeners
        _eventListeners.clear();
        
        // Clear menu items
        _menuItems.clear();
        
        // Platform-specific disposal
        await platformDispose();
        
        logger.info('Tray manager disposed');
        _publishTrayEvent('disposed');
      },
      context: 'tray_dispose',
      component: 'tray_manager',
    );
  }
  
  @override
  Future<MCPHealthCheckResult> performHealthCheck() async {
    if (!_state.visible) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.healthy,
        message: 'Tray icon not visible',
        details: getStatistics(),
      );
    }
    
    // Check update frequency
    if (_lastUpdate != null) {
      final timeSinceUpdate = DateTime.now().difference(_lastUpdate!);
      if (timeSinceUpdate > Duration(hours: 1) && _updateCount == 0) {
        return MCPHealthCheckResult(
          status: MCPHealthStatus.degraded,
          message: 'No tray updates in the last hour',
          details: getStatistics(),
        );
      }
    }
    
    return MCPHealthCheckResult(
      status: MCPHealthStatus.healthy,
      message: 'Tray manager operational',
      details: getStatistics(),
    );
  }
  
  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'visible': _state.visible,
      'iconPath': _state.iconPath,
      'tooltip': _state.tooltip,
      'animating': _state.animating,
      'menuItemCount': _menuItems.length,
      'eventListenerCount': _eventListeners.length,
      'updateCount': _updateCount,
      'lastUpdate': _lastUpdate?.toIso8601String(),
      'supportsAnimation': supportsAnimation,
      'supportsColorIcons': supportsColorIcons,
      'supportsSubmenu': supportsSubmenu,
      'supportsBalloon': supportsBalloon,
    };
  }
  
  /// Platform-specific initialization
  @protected
  Future<void> platformInitialize();
  
  /// Platform-specific icon setting
  @protected
  Future<void> platformSetIcon(String path);
  
  /// Platform-specific icon setting from bytes
  @protected
  Future<void> platformSetIconFromBytes(Uint8List bytes);
  
  /// Platform-specific tooltip setting
  @protected
  Future<void> platformSetTooltip(String tooltip);
  
  /// Platform-specific context menu setting
  @protected
  Future<void> platformSetContextMenu(List<EnhancedTrayMenuItem> items);
  
  /// Platform-specific show
  @protected
  Future<void> platformShow();
  
  /// Platform-specific hide
  @protected
  Future<void> platformHide();
  
  /// Platform-specific balloon notification
  @protected
  Future<void> platformShowBalloon({
    required String title,
    required String message,
    required BalloonIconType iconType,
    Duration? timeout,
  });
  
  /// Platform-specific menu item update
  @protected
  Future<void> platformUpdateMenuItem(
    String itemId, {
    String? label,
    bool? disabled,
    bool? checked,
    String? iconPath,
  });
  
  /// Platform-specific disposal
  @protected
  Future<void> platformDispose();
  
  /// Handle menu item click
  @protected
  void handleMenuItemClick(String itemId) {
    final item = _menuItems[itemId];
    if (item != null) {
      item.onTap?.call();
      _publishTrayEvent('menu_item_clicked', {'itemId': itemId});
    }
  }
  
  /// Handle tray icon click
  @protected
  void handleTrayClick() {
    for (final listener in _eventListeners) {
      listener.onTrayMouseDown?.call();
    }
    _publishTrayEvent('tray_clicked');
  }
  
  /// Handle tray icon right-click
  @protected
  void handleTrayRightClick() {
    for (final listener in _eventListeners) {
      listener.onTrayRightMouseDown?.call();
    }
    _publishTrayEvent('tray_right_clicked');
  }
  
  /// Handle tray icon double-click
  @protected
  void handleTrayDoubleClick() {
    for (final listener in _eventListeners) {
      listener.onTrayMouseDoubleDown?.call();
    }
    _publishTrayEvent('tray_double_clicked');
  }
  
  /// Update tracking
  void _updateTracking() {
    _lastUpdate = DateTime.now();
    _updateCount++;
  }
  
  /// Publish tray event
  void _publishTrayEvent(String action, [Map<String, dynamic>? data]) {
    _eventSystem.publish('tray.$action', {
      'timestamp': DateTime.now().toIso8601String(),
      ...?data,
    });
  }
}

/// Balloon icon types
enum BalloonIconType {
  none,
  info,
  warning,
  error,
}

/// Tray event listener
class TrayEventListener {
  final Function()? onTrayMouseDown;
  final Function()? onTrayMouseUp;
  final Function()? onTrayRightMouseDown;
  final Function()? onTrayRightMouseUp;
  final Function()? onTrayMouseDoubleDown;
  final Function()? onTrayMouseMove;
  
  TrayEventListener({
    this.onTrayMouseDown,
    this.onTrayMouseUp,
    this.onTrayRightMouseDown,
    this.onTrayRightMouseUp,
    this.onTrayMouseDoubleDown,
    this.onTrayMouseMove,
  });
}