import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class FlutterMcpPlatform extends PlatformInterface {
  FlutterMcpPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterMcpPlatform? _instance;

  static FlutterMcpPlatform get instance {
    if (_instance == null) {
      throw UnimplementedError(
        'FlutterMcpPlatform has not been initialized. Please register a platform implementation (e.g. FlutterMcpWeb.registerWith).',
      );
    }
    return _instance!;
  }

  static set instance(FlutterMcpPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }
}
