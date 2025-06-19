import 'dart:async';
import 'package:flutter/services.dart';
import '../../config/tray_config.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import 'tray_manager.dart';

/// macOS Tray manager implementation
class MacOSTrayManager implements TrayManager {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/events');

  final Logger _logger = Logger('flutter_mcp.macos_tray');
  StreamSubscription? _eventSubscription;

  // Store menu items for reference and updating
  final Map<String, TrayMenuItem> _menuItems = {};

  // Menu item IDs for tracking
  int _menuItemIdCounter = 0;

  // Event listeners
  final List<TrayEventListener> _eventListeners = [];

  // Current tray state
  bool _isVisible = false;

  @override
  Future<void> initialize(TrayConfig? config) async {
    _logger.fine('macOS tray manager initializing');

    // Initialize event listener
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (error) {
        _logger.severe('Event channel error', error);
      },
    );

    try {
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

      _logger.fine('macOS tray manager initialized successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize macOS tray manager', e, stackTrace);
      throw MCPException(
          'Failed to initialize macOS tray manager: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final dataRaw = event['data'];
    final data = dataRaw is Map
        ? Map<String, dynamic>.from(dataRaw)
        : <String, dynamic>{};

    _logger.fine('Received tray event: $type');

    if (type == 'trayEvent') {
      final action = data['action'] as String?;

      switch (action) {
        case 'menuItemClicked':
          final itemId = data['itemId'] as String?;
          if (itemId != null && _menuItems.containsKey(itemId)) {
            _menuItems[itemId]?.onTap?.call();
          }
          break;

        case 'trayIconClicked':
          for (final listener in _eventListeners) {
            listener.onTrayMouseDown?.call();
          }
          break;

        case 'trayIconRightClicked':
          for (final listener in _eventListeners) {
            listener.onTrayRightMouseDown?.call();
          }
          break;
      }
    }
  }

  @override
  Future<void> setIcon(String path) async {
    _logger.fine('Setting macOS tray icon: $path');

    try {
      await _channel.invokeMethod('showTrayIcon', {
        'iconPath': path,
      });
      _isVisible = true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to set macOS tray icon', e, stackTrace);
      throw MCPException(
          'Failed to set macOS tray icon: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> setTooltip(String tooltip) async {
    _logger.fine('Setting macOS tray tooltip: $tooltip');

    try {
      await _channel.invokeMethod('updateTrayTooltip', {
        'tooltip': tooltip,
      });
    } catch (e, stackTrace) {
      _logger.severe('Failed to set macOS tray tooltip', e, stackTrace);
      throw MCPException(
          'Failed to set macOS tray tooltip: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> setContextMenu(List<TrayMenuItem> items) async {
    _logger.fine('Setting macOS tray context menu');

    try {
      // Clear stored items
      _menuItems.clear();

      // Convert to native menu items format
      final List<Map<String, dynamic>> nativeItems = [];

      for (int i = 0; i < items.length; i++) {
        final item = items[i];

        if (item.isSeparator) {
          nativeItems.add({
            'isSeparator': true,
          });
        } else {
          // Generate ID for this item
          final itemId = 'item_${_menuItemIdCounter++}';
          _menuItems[itemId] = item;

          nativeItems.add({
            'id': itemId,
            'label': item.label ?? '',
            'disabled': item.disabled,
            'isSeparator': false,
          });
        }
      }

      // Set tray menu using native implementation
      await _channel.invokeMethod('setTrayMenu', {
        'items': nativeItems,
      });
    } catch (e, stackTrace) {
      _logger.severe('Failed to set macOS tray context menu', e, stackTrace);
      throw MCPException(
          'Failed to set macOS tray context menu: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<void> dispose() async {
    _logger.fine('Disposing macOS tray manager');

    try {
      // Hide the tray icon
      await _channel.invokeMethod('hideTrayIcon');

      // Cancel event subscription
      _eventSubscription?.cancel();

      // Clear internal state
      _menuItems.clear();
      _eventListeners.clear();
      _isVisible = false;
    } catch (e, stackTrace) {
      _logger.severe('Failed to dispose macOS tray manager', e, stackTrace);
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
  Future<Map<String, double>?> getIconBounds() async {
    try {
      // This would need to be implemented in native code
      // For now, return null
      return null;
    } catch (e) {
      _logger.severe('Failed to get tray icon bounds', e);
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

  /// Show the tray icon
  Future<void> show() async {
    if (!_isVisible) {
      await _channel.invokeMethod('showTrayIcon', {});
      _isVisible = true;
    }
  }

  /// Hide the tray icon
  Future<void> hide() async {
    if (_isVisible) {
      await _channel.invokeMethod('hideTrayIcon');
      _isVisible = false;
    }
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
