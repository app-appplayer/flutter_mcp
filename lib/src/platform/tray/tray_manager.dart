import '../../config/tray_config.dart';

/// 트레이 메뉴 항목
class TrayMenuItem {
  /// 메뉴 항목 라벨
  final String? label;

  /// 메뉴 항목 클릭 핸들러
  final Function()? onTap;

  /// 메뉴 항목 비활성화 여부
  final bool disabled;

  /// 구분선 여부
  final bool isSeparator;

  /// 메뉴 항목 생성
  TrayMenuItem({
    this.label,
    this.onTap,
    this.disabled = false,
  }) : isSeparator = false;

  /// 구분선 생성
  TrayMenuItem.separator()
      : label = null,
        onTap = null,
        disabled = false,
        isSeparator = true;
}

/// 트레이 관리자 인터페이스
abstract class TrayManager {
  /// 트레이 관리자 초기화
  Future<void> initialize(TrayConfig? config);

  /// 아이콘 설정
  Future<void> setIcon(String path);

  /// 툴팁 설정
  Future<void> setTooltip(String tooltip);

  /// 컨텍스트 메뉴 설정
  Future<void> setContextMenu(List<TrayMenuItem> items);

  /// 리소스 해제
  Future<void> dispose();
}

/// 기능 없는 트레이 관리자 (지원하지 않는 플랫폼용)
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