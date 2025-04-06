import '../../config/tray_config.dart';

/// Tray menu item
class TrayMenuItem {
  /// Menu item label
  final String? label;

  /// Menu item click handler
  final Function()? onTap;

  /// Whether menu item is disabled
  final bool disabled;

  /// Whether item is a separator
  final bool isSeparator;

  /// Create menu item
  TrayMenuItem({
    this.label,
    this.onTap,
    this.disabled = false,
  }) : isSeparator = false;

  /// Create separator
  TrayMenuItem.separator()
      : label = null,
        onTap = null,
        disabled = false,
        isSeparator = true;
}

/// Tray manager interface
abstract class TrayManager {
  /// Initialize tray manager
  Future<void> initialize(TrayConfig? config);

  /// Set icon
  Future<void> setIcon(String path);

  /// Set tooltip
  Future<void> setTooltip(String tooltip);

  /// Set context menu
  Future<void> setContextMenu(List<TrayMenuItem> items);

  /// Dispose resources
  Future<void> dispose();
}

/// No-op tray manager (for platforms without tray support)
class NoOpTrayManager implements TrayManager {
  @override
  Future<void> initialize(TrayConfig? config) async {}

  @override
  Future<void> setIcon(String path) async {}

  @override
  Future<void> setTooltip(String tooltip) async {}

  @override
  Future<void> setContextMenu(List<TrayMenuItem> items) async {}

  @override
  Future<void> dispose() async {}
}
