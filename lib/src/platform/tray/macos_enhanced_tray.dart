import 'dart:async';
import 'package:flutter/services.dart';
import '../../utils/enhanced_error_handler.dart';
import 'enhanced_tray_manager.dart';

/// Enhanced macOS tray manager implementation
class MacOSEnhancedTrayManager extends EnhancedTrayManager {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/tray_events');
  
  StreamSubscription? _eventSubscription;
  
  MacOSEnhancedTrayManager() : super(
    'macos',
    supportsAnimation: true,
    supportsColorIcons: true,
    supportsSubmenu: true,
    supportsBalloon: false, // macOS uses native notifications instead
  );
  
  @override
  Future<void> platformInitialize() async {
    // Set up event channel
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleNativeEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (error) {
        logger.severe('Tray event channel error', error);
      },
    );
    
    // Initialize native tray
    await _channel.invokeMethod('initializeTray', {
      'platform': 'macos',
    });
  }
  
  @override
  Future<void> platformSetIcon(String path) async {
    await _channel.invokeMethod('setTrayIcon', {
      'path': path,
      'isTemplate': path.contains('Template'), // macOS template images
    });
  }
  
  @override
  Future<void> platformSetIconFromBytes(Uint8List bytes) async {
    await _channel.invokeMethod('setTrayIconFromBytes', {
      'bytes': bytes,
      'isTemplate': false,
    });
  }
  
  @override
  Future<void> platformSetTooltip(String tooltip) async {
    await _channel.invokeMethod('setTrayTooltip', {
      'tooltip': tooltip,
    });
  }
  
  @override
  Future<void> platformSetContextMenu(List<EnhancedTrayMenuItem> items) async {
    final menuData = _buildMenuData(items);
    await _channel.invokeMethod('setTrayContextMenu', {
      'items': menuData,
    });
  }
  
  @override
  Future<void> platformShow() async {
    await _channel.invokeMethod('showTray');
  }
  
  @override
  Future<void> platformHide() async {
    await _channel.invokeMethod('hideTray');
  }
  
  @override
  Future<void> platformShowBalloon({
    required String title,
    required String message,
    required BalloonIconType iconType,
    Duration? timeout,
  }) async {
    // macOS doesn't support balloon notifications
    // Use native notification system instead
    logger.warning('Balloon notifications not supported on macOS. Use notifications instead.');
  }
  
  @override
  Future<void> platformUpdateMenuItem(
    String itemId, {
    String? label,
    bool? disabled,
    bool? checked,
    String? iconPath,
  }) async {
    await _channel.invokeMethod('updateTrayMenuItem', {
      'itemId': itemId,
      'label': label,
      'disabled': disabled,
      'checked': checked,
      'iconPath': iconPath,
    });
  }
  
  @override
  Future<void> platformDispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    
    await _channel.invokeMethod('disposeTray');
  }
  
  /// Build menu data for native platform
  List<Map<String, dynamic>> _buildMenuData(List<EnhancedTrayMenuItem> items) {
    return items.map((item) {
      if (item.isSeparator) {
        return {'type': 'separator'};
      }
      
      final data = <String, dynamic>{
        'id': item.id ?? item.label?.replaceAll(' ', '_').toLowerCase(),
        'label': item.label,
        'disabled': item.disabled,
        'visible': item.visible,
      };
      
      // macOS specific properties
      if (item.iconPath != null) {
        data['icon'] = item.iconPath;
      }
      
      if (item.shortcut != null) {
        data['shortcut'] = _parseShortcut(item.shortcut!);
      }
      
      if (item.type != MenuItemType.normal) {
        data['type'] = item.type.name;
        data['checked'] = item.checked;
      }
      
      if (item.submenu != null && item.submenu!.isNotEmpty) {
        data['submenu'] = _buildMenuData(item.submenu!);
      }
      
      return data;
    }).toList();
  }
  
  /// Parse keyboard shortcut for macOS
  Map<String, dynamic> _parseShortcut(String shortcut) {
    // Parse shortcuts like "Cmd+Q", "Ctrl+Shift+A", etc.
    final parts = shortcut.split('+');
    final modifiers = <String>[];
    String? key;
    
    for (final part in parts) {
      switch (part.toLowerCase()) {
        case 'cmd':
        case 'command':
          modifiers.add('cmd');
          break;
        case 'ctrl':
        case 'control':
          modifiers.add('ctrl');
          break;
        case 'alt':
        case 'option':
          modifiers.add('alt');
          break;
        case 'shift':
          modifiers.add('shift');
          break;
        default:
          key = part;
      }
    }
    
    return {
      'modifiers': modifiers,
      'key': key,
    };
  }
  
  /// Handle events from native platform
  void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? {};
    
    logger.fine('Received native tray event: $type');
    
    switch (type) {
      case 'menu_item_clicked':
        final itemId = data['itemId'] as String?;
        if (itemId != null) {
          handleMenuItemClick(itemId);
        }
        break;
        
      case 'tray_clicked':
        final clickType = data['clickType'] as String?;
        switch (clickType) {
          case 'left':
            handleTrayClick();
            break;
          case 'right':
            handleTrayRightClick();
            break;
          case 'double':
            handleTrayDoubleClick();
            break;
        }
        break;
        
      case 'menu_will_open':
        logger.fine('Tray menu will open');
        break;
        
      case 'menu_did_close':
        logger.fine('Tray menu did close');
        break;
        
      default:
        logger.fine('Unknown tray event type: $type');
    }
  }
  
  /// Set status bar item properties (macOS specific)
  Future<void> setStatusBarItemProperties({
    double? width,
    bool? highlightMode,
    String? title,
  }) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await _channel.invokeMethod('setStatusBarItemProperties', {
          'width': width,
          'highlightMode': highlightMode,
          'title': title,
        });
      },
      context: 'set_status_bar_properties',
      component: 'tray_manager',
    );
  }
  
  /// Set menu bar visibility (macOS specific)
  Future<void> setMenuBarVisibility(bool visible) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await _channel.invokeMethod('setMenuBarVisibility', {
          'visible': visible,
        });
      },
      context: 'set_menu_bar_visibility',
      component: 'tray_manager',
    );
  }
}