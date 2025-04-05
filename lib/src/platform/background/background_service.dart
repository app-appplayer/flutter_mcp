import '../../config/background_config.dart';

/// 백그라운드 서비스 인터페이스
abstract class BackgroundService {
  /// 서비스 초기화
  Future<void> initialize(BackgroundConfig? config);

  /// 서비스 시작
  Future<bool> start();

  /// 서비스 중지
  Future<bool> stop();

  /// 서비스 실행 여부
  bool get isRunning;
}

/// 기능이 없는 백그라운드 서비스 (지원하지 않는 플랫폼용)
class NoOpBackgroundService implements BackgroundService {
  @override
  bool get isRunning => false;

  @override
  Future<void> initialize(BackgroundConfig? config) async {}

  @override
  Future<bool> start() async {
    return false;
  }

  @override
  Future<bool> stop() async {
    return false;
  }
}