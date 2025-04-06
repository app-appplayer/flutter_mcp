import 'dart:async';
import 'dart:ui' show Rect;
import 'package:tray_manager/tray_manager.dart' as native_tray;
import '../../config/tray_config.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import 'tray_manager.dart';

/// macOS Tray manager implementation
class MacOSTrayManager implements TrayManager {
  final MCPLogger _logger = MCPLogger('mcp.macos_tray');

  // Store menu items for reference and updating
  final Map<String, TrayMenuItem> _menuItems = {};

  // Menu item IDs for tracking
  int _menuItemIdCounter = 0;

  // Event listeners
  final List<TrayEventListener> _eventListeners = [];

  // Current tray state
  String? _currentIconPath;
  String? _currentTooltip;

  // Native implementation event listener
  native_tray.TrayListener? _nativeListener;

  @override
  Future<void> initialize(TrayConfig? config) async {
    _logger.debug('macOS tray manager initializing');

    // Initialize native tray manager
    try {
      // Set up native listener to forward events
      _nativeListener = _createNativeListener();
      native_tray.TrayManager.instance.addListener(_nativeListener!);

      // Initial setup
      if (config != null) {
        if (config.iconPath != null) {
          await setIcon(config.iconPath!);
        }

        if (config.tooltip != null) {
          await setTooltip(config.tooltip!);
        }

        if (config.menuItems != null) {
          await setContextMenu(config.menuItems!);
        }
      }

      _logger.debug('macOS tray manager initialized successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize macOS tray manager', e, stackTrace);
      throw MCPException(
          'Failed to initialize macOS tray manager: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<void> setIcon(String path) async {
    _logger.debug('Setting macOS tray icon: $path');

    try {
      await native_tray.TrayManager.instance.setIcon(path);
      _currentIconPath = path;
    } catch (e, stackTrace) {
      _logger.error('Failed to set macOS tray icon', e, stackTrace);
      throw MCPException(
          'Failed to set macOS tray icon: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> setTooltip(String tooltip) async {
    _logger.debug('Setting macOS tray tooltip: $tooltip');

    try {
      await native_tray.TrayManager.instance.setToolTip(tooltip);
      _currentTooltip = tooltip;
    } catch (e, stackTrace) {
      _logger.error('Failed to set macOS tray tooltip', e, stackTrace);
      throw MCPException(
          'Failed to set macOS tray tooltip: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> setContextMenu(List<TrayMenuItem> items) async {
    _logger.debug('Setting macOS tray context menu');

    try {
      // Clear stored items
      _menuItems.clear();

      // Convert to native menu items
      final nativeItems = _convertToNativeMenuItems(items);

      // Create menu with the items
      final menu = native_tray.Menu(items: nativeItems);

      // Set tray menu
      await native_tray.TrayManager.instance.setContextMenu(menu);
    } catch (e, stackTrace) {
      _logger.error('Failed to set macOS tray context menu', e, stackTrace);
      throw MCPException(
          'Failed to set macOS tray context menu: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<void> dispose() async {
    _logger.debug('Disposing macOS tray manager');

    try {
      // Remove event listener
      if (_nativeListener != null) {
        native_tray.TrayManager.instance.removeListener(_nativeListener!);
      }

      // Destroy the tray
      await native_tray.TrayManager.instance.destroy();

      // Clear internal state
      _menuItems.clear();
      _eventListeners.clear();
    } catch (e, stackTrace) {
      _logger.error('Failed to dispose macOS tray manager', e, stackTrace);
      throw MCPException(
          'Failed to dispose macOS tray manager: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  /// Add a tray event listener
  void addEventListener(TrayEventListener listener) {
    _eventListeners.add(listener);
  }

  /// Remove a tray event listener
  void removeEventListener(TrayEventListener listener) {
    _eventListeners.remove(listener);
  }

  /// Get the tray icon bounds (for positioning popups)
  Future<Rect?> getIconBounds() async {
    try {
      return await native_tray.TrayManager.instance.getBounds();
    } catch (e) {
      _logger.error('Failed to get tray icon bounds', e);
      return null;
    }
  }

  /// Update a single menu item
  Future<void> updateMenuItem(String id,
      {String? label, bool? disabled}) async {
    if (!_menuItems.containsKey(id)) {
      _logger.warning('Menu item with ID $id not found');
      return;
    }

    final item = _menuItems[id]!;

    // Update properties
    if (label != null || disabled != null) {
      // Create updated menu item
      final updatedItem = TrayMenuItem(
        label: label ?? item.label,
        disabled: disabled ?? item.disabled,
        onTap: item.onTap,
      );

      // Store updated item
      _menuItems[id] = updatedItem;

      // Rebuild the entire menu
      final allItems = _menuItems.values.toList();
      await setContextMenu(allItems);
    }
  }

  /// Create a native tray listener to forward events
  native_tray.TrayListener _createNativeListener() {
    return _MacOSTrayListener(
      onTrayMouseDown: () {
        for (final listener in _eventListeners) {
          listener.onTrayMouseDown?.call();
        }
      },
      onTrayMouseUp: () {
        for (final listener in _eventListeners) {
          listener.onTrayMouseUp?.call();
        }
      },
      onTrayRightMouseDown: () {
        for (final listener in _eventListeners) {
          listener.onTrayRightMouseDown?.call();
        }
      },
      onTrayRightMouseUp: () {
        for (final listener in _eventListeners) {
          listener.onTrayRightMouseUp?.call();
        }
      },
      onTrayBalloonShow: () {},
      onTrayBalloonClick: () {},
      onTrayBalloonClosed: () {},
    );
  }

  /// Convert menu items
  List<native_tray.MenuItem> _convertToNativeMenuItems(
      List<TrayMenuItem> items) {
    final nativeItems = <native_tray.MenuItem>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];

      if (item.isSeparator) {
        nativeItems.add(native_tray.MenuItem.separator());
      } else {
        // Generate ID for this item if it doesn't have one
        final itemId = 'item_${_menuItemIdCounter++}';
        _menuItems[itemId] = item;

        nativeItems.add(
          native_tray.MenuItem(
            label: item.label ?? '',
            disabled: item.disabled,
            onClick: item.onTap != null
                ? (_) {
                    // Execute the callback if provided
                    item.onTap!();
                  }
                : null,
          ),
        );
      }
    }

    return nativeItems;
  }
}

/// Native tray listener implementation
class _MacOSTrayListener implements native_tray.TrayListener {
  final Function()? _iconMouseDown;
  final Function()? _iconMouseUp;
  final Function()? _iconRightMouseDown;
  final Function()? _iconRightMouseUp;
  final Function()? _balloonShow;
  final Function()? _balloonClick;
  final Function()? _balloonClosed;
  final Function(native_tray.MenuItem)? _menuItemClick;

  _MacOSTrayListener({
    Function()? onTrayMouseDown,
    Function()? onTrayMouseUp,
    Function()? onTrayRightMouseDown,
    Function()? onTrayRightMouseUp,
    Function()? onTrayBalloonShow,
    Function()? onTrayBalloonClick,
    Function()? onTrayBalloonClosed,
    Function(native_tray.MenuItem)? onTrayMenuItemClick,
  })  : _iconMouseDown = onTrayMouseDown,
        _iconMouseUp = onTrayMouseUp,
        _iconRightMouseDown = onTrayRightMouseDown,
        _iconRightMouseUp = onTrayRightMouseUp,
        _balloonShow = onTrayBalloonShow,
        _balloonClick = onTrayBalloonClick,
        _balloonClosed = onTrayBalloonClosed,
        _menuItemClick = onTrayMenuItemClick;

  @override
  void onTrayIconMouseDown() {
    _iconMouseDown?.call();
  }

  @override
  void onTrayIconMouseUp() {
    _iconMouseUp?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    _iconRightMouseDown?.call();
  }

  @override
  void onTrayIconRightMouseUp() {
    _iconRightMouseUp?.call();
  }

  // This method is not part of the native_tray.TrayListener interface
  void onTrayBalloonShow() {
    _balloonShow?.call();
  }

  // This method is not part of the native_tray.TrayListener interface
  void onTrayBalloonClick() {
    _balloonClick?.call();
  }

  // This method is not part of the native_tray.TrayListener interface
  void onTrayBalloonClosed() {
    _balloonClosed?.call();
  }

  @override
  void onTrayMenuItemClick(native_tray.MenuItem item) {
    _menuItemClick?.call(item);
  }
}

/// Tray event listener interface
class TrayEventListener {
  final Function()? onTrayMouseDown;
  final Function()? onTrayMouseUp;
  final Function()? onTrayMouseMove;
  final Function()? onTrayRightMouseDown;
  final Function()? onTrayRightMouseUp;
  final Function()? onTrayRightMouseMove;

  TrayEventListener({
    this.onTrayMouseDown,
    this.onTrayMouseUp,
    this.onTrayMouseMove,
    this.onTrayRightMouseDown,
    this.onTrayRightMouseUp,
    this.onTrayRightMouseMove,
  });
}
