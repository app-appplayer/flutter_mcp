import '../platform/tray/tray_manager.dart';

/// 트레이 설정
class TrayConfig {
  /// 트레이 아이콘 경로
  final String? iconPath;

  /// 트레이 툴팁
  final String? tooltip;

  /// 트레이 메뉴 항목
  final List<TrayMenuItem>? menuItems;

  TrayConfig({
    this.iconPath,
    this.tooltip,
    this.menuItems,
  });
}