import '../platform/tray/tray_manager.dart';

/// Tray configuration
class TrayConfig {
  /// Tray icon path
  final String? iconPath;

  /// Tray tooltip
  final String? tooltip;

  /// Tray menu items
  final List<TrayMenuItem>? menuItems;

  TrayConfig({
    this.iconPath,
    this.tooltip,
    this.menuItems,
  });
}
