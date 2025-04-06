import 'package:tray_manager/tray_manager.dart' as native_tray;
import '../../config/tray_config.dart';
import '../../utils/logger.dart';
import 'tray_manager.dart';

/// Windows 트레이 관리자 구현
class WindowsTrayManager implements TrayManager {
  final MCPLogger _logger = MCPLogger('mcp.windows_tray');

  @override
  Future<void> initialize(TrayConfig? config) async {
    _logger.debug('Windows 트레이 관리자 초기화');

    // 초기 설정
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
    _logger.debug('Windows 트레이 아이콘 설정: $path');

    try {
      await native_tray.TrayManager.instance.setIcon(path);
    } catch (e) {
      _logger.error('Windows 트레이 아이콘 설정 오류', e);
    }
  }

  @override
  Future<void> setTooltip(String tooltip) async {
    _logger.debug('Windows 트레이 툴팁 설정: $tooltip');

    try {
      await native_tray.TrayManager.instance.setToolTip(tooltip);
    } catch (e) {
      _logger.error('Windows 트레이 툴팁 설정 오류', e);
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
      _logger.error('Failed to set windows tray context menu', e);
    }
  }

  @override
  Future<void> dispose() async {
    _logger.debug('Windows 트레이 관리자 종료');

    try {
      await native_tray.TrayManager.instance.destroy();
    } catch (e) {
      _logger.error('Windows 트레이 관리자 종료 오류', e);
    }
  }

  /// 메뉴 항목 변환
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