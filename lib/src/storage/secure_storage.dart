import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/logger.dart';

/// 보안 저장소 관리자 인터페이스
abstract class SecureStorageManager {
  /// 초기화
  Future<void> initialize();

  /// 문자열 저장
  Future<void> saveString(String key, String value);

  /// 문자열 읽기
  Future<String?> readString(String key);

  /// 키 삭제
  Future<bool> delete(String key);

  /// 키 존재 여부 확인
  Future<bool> containsKey(String key);
}

/// 보안 저장소 관리자 구현
class SecureStorageManagerImpl implements SecureStorageManager {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final MCPLogger _logger = MCPLogger('mcp.secure_storage');

  @override
  Future<void> initialize() async {
    _logger.debug('보안 저장소 초기화');
  }

  @override
  Future<void> saveString(String key, String value) async {
    _logger.debug('문자열 저장: $key');
    await _storage.write(key: key, value: value);
  }

  @override
  Future<String?> readString(String key) async {
    _logger.debug('문자열 읽기: $key');
    return await _storage.read(key: key);
  }

  @override
  Future<bool> delete(String key) async {
    _logger.debug('키 삭제: $key');
    await _storage.delete(key: key);
    return true;
  }

  @override
  Future<bool> containsKey(String key) async {
    final value = await _storage.read(key: key);
    return value != null;
  }
}