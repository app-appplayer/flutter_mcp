import 'package:tray_manager/tray_manager.dart' as native_tray;
import '../../config/tray_config.dart';
import '../../utils/logger.dart';
import 'tray_manager.dart';

/// Linux tray manager implementation
class LinuxTrayManager implements TrayManager {
  final MCPLogger _logger = MCPLogger('mcp.linux_tray');

  @override
  Future<void> initialize(TrayConfig? config) async {
    _logger.debug('Linux tray manager initialization');

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
  }

  @override
  Future<void> setIcon(String path) async {
    _logger.debug('Setting Linux tray icon: $path');

    try {
      await native_tray.TrayManager.instance.setIcon(path);
    } catch (e) {
      _logger.error('Failed to set Linux tray icon', e);
    }
  }

  @override
  Future<void> setTooltip(String tooltip) async {
    _logger.debug('Setting Linux tray tooltip: $tooltip');

    try {
      await native_tray.TrayManager.instance.setToolTip(tooltip);
    } catch (e) {
      _logger.error('Failed to set Linux tray tooltip', e);
    }
  }

  @override
  Future<void> setContextMenu(List<TrayMenuItem> items) async {
    _logger.debug('Setting Linux tray context menu');

    try {
      // Convert to native menu items
      final nativeItems = _convertToNativeMenuItems(items);

      // Create menu directly with items
      final menu = native_tray.Menu(
        items: nativeItems,
      );

      // Set tray menu
      await native_tray.TrayManager.instance.setContextMenu(menu);
    } catch (e) {
      _logger.error('Failed to set Linux tray context menu', e);
    }
  }

  @override
  Future<void> dispose() async {
    _logger.debug('Disposing Linux tray manager');

    try {
      await native_tray.TrayManager.instance.destroy();
    } catch (e) {
      _logger.error('Failed to dispose Linux tray manager', e);
    }
  }

  /// Convert menu items
  List<native_tray.MenuItem> _convertToNativeMenuItems(List<TrayMenuItem> items) {
    final nativeItems = <native_tray.MenuItem>[];

    for (final item in items) {
      if (item.isSeparator) {
        nativeItems.add(native_tray.MenuItem.separator());
      } else {
        nativeItems.add(
          native_tray.MenuItem(
            label: item.label ?? '',
            disabled: item.disabled,
            onClick: item.onTap != null ? (_) => item.onTap!() : null,
          ),
        );
      }
    }

    return nativeItems;
  }
}