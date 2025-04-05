import 'package:flutter/widgets.dart';
import '../utils/logger.dart';

/// 라이프사이클 관리자
class LifecycleManager with WidgetsBindingObserver {
  final MCPLogger _logger = MCPLogger('mcp.lifecycle_manager');

  // 라이프사이클 변경 콜백
  Function(AppLifecycleState)? _onLifecycleStateChange;

  /// 초기화
  void initialize() {
    _logger.debug('라이프사이클 관리자 초기화');
    WidgetsBinding.instance.addObserver(this);
  }

  /// 라이프사이클 변경 리스너 등록
  void setLifecycleChangeListener(Function(AppLifecycleState) listener) {
    _onLifecycleStateChange = listener;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.debug('앱 라이프사이클 상태 변경: $state');

    // 라이프사이클 변경 처리
    switch (state) {
      case AppLifecycleState.resumed:
        _logger.debug('앱이 포그라운드로 복귀');
        break;
      case AppLifecycleState.inactive:
        _logger.debug('앱이 비활성화됨');
        break;
      case AppLifecycleState.paused:
        _logger.debug('앱이 백그라운드로 이동');
        break;
      case AppLifecycleState.detached:
        _logger.debug('앱이 분리됨');
        break;
      default:
        _logger.debug('알 수 없는 라이프사이클 상태: $state');
    }

    // 콜백 호출
    if (_onLifecycleStateChange != null) {
      _onLifecycleStateChange!(state);
    }
  }

  /// 리소스 해제
  void dispose() {
    _logger.debug('라이프사이클 관리자 종료');
    WidgetsBinding.instance.removeObserver(this);
    _onLifecycleStateChange = null;
  }
}