import '../../config/background_config.dart';

/// Background service interface
abstract class BackgroundService {
  /// Initialize service
  Future<void> initialize(BackgroundConfig? config);

  /// Start service
  Future<bool> start();

  /// Stop service
  Future<bool> stop();

  /// Check if service is running
  bool get isRunning;
}

/// No-operation background service (for unsupported platforms)
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
