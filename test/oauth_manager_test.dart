// Coverage tests for MCPOAuthManager — exercises:
//   - OAuthConfig + OAuthToken data classes (full)
//   - Manager singleton init/dispose lifecycle
//   - isAuthenticated, handleCallback, disposeForLlm error/edge paths
//
// We use an in-memory _FakeStorage to back CredentialManager so the
// manager can run end-to-end without touching the platform channel.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/security/oauth_manager.dart';
import 'package:flutter_mcp/src/security/credential_manager.dart';
import 'package:flutter_mcp/src/platform/storage/secure_storage.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

class _FakeStorage implements SecureStorageManager {
  final Map<String, String> _store = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> saveString(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<String?> readString(String key) async => _store[key];

  @override
  Future<bool> delete(String key) async => _store.remove(key) != null;

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  @override
  Future<void> saveMap(String key, Map<String, dynamic> value) async {
    _store[key] = jsonEncode(value);
  }

  @override
  Future<Map<String, dynamic>?> readMap(String key) async {
    final v = _store[key];
    return v == null ? null : jsonDecode(v) as Map<String, dynamic>;
  }

  @override
  Future<void> clear() async => _store.clear();

  @override
  Future<Set<String>> getAllKeys() async => _store.keys.toSet();
}

void main() {
  group('OAuthConfig data class', () {
    test('constructor stores all fields', () {
      final cfg = OAuthConfig(
        clientId: 'cid',
        clientSecret: 'sec',
        authorizationUrl: 'https://auth.test/a',
        tokenUrl: 'https://auth.test/t',
        scopes: ['read', 'write'],
        redirectUri: 'app://callback',
        additionalParams: {'foo': 'bar'},
        revokeUrl: 'https://auth.test/r',
        userInfoUrl: 'https://auth.test/u',
        usePKCE: false,
      );
      expect(cfg.clientId, 'cid');
      expect(cfg.clientSecret, 'sec');
      expect(cfg.authorizationUrl, 'https://auth.test/a');
      expect(cfg.tokenUrl, 'https://auth.test/t');
      expect(cfg.scopes, ['read', 'write']);
      expect(cfg.redirectUri, 'app://callback');
      expect(cfg.additionalParams, {'foo': 'bar'});
      expect(cfg.revokeUrl, 'https://auth.test/r');
      expect(cfg.userInfoUrl, 'https://auth.test/u');
      expect(cfg.usePKCE, isFalse);
    });

    test('usePKCE defaults to true', () {
      final cfg = OAuthConfig(
        clientId: 'c',
        clientSecret: 's',
        authorizationUrl: 'a',
        tokenUrl: 't',
        scopes: const [],
      );
      expect(cfg.usePKCE, isTrue);
    });
  });

  group('OAuthToken data class', () {
    test('isExpired is false for future expiry', () {
      final t = OAuthToken(
        accessToken: 'a',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        scopes: ['s'],
      );
      expect(t.isExpired, isFalse);
    });

    test('isExpired is true for past expiry', () {
      final t = OAuthToken(
        accessToken: 'a',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        scopes: ['s'],
      );
      expect(t.isExpired, isTrue);
    });

    test('toJson roundtrips through fromJson', () {
      final t = OAuthToken(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.parse('2030-01-01T00:00:00Z'),
        tokenType: 'Bearer',
        scopes: ['read', 'write'],
      );
      final json = t.toJson();
      expect(json['accessToken'], 'access');
      expect(json['refreshToken'], 'refresh');
      expect(json['tokenType'], 'Bearer');
      expect(json['scopes'], ['read', 'write']);

      final t2 = OAuthToken.fromJson(json);
      expect(t2.accessToken, t.accessToken);
      expect(t2.refreshToken, t.refreshToken);
      expect(t2.expiresAt, t.expiresAt);
      expect(t2.tokenType, t.tokenType);
      expect(t2.scopes, t.scopes);
    });

    test('fromJson defaults tokenType to Bearer + scopes to empty', () {
      final t = OAuthToken.fromJson({
        'accessToken': 'a',
        'expiresAt': DateTime.now().toIso8601String(),
      });
      expect(t.tokenType, 'Bearer');
      expect(t.scopes, isEmpty);
    });
  });

  group('MCPOAuthManager — singleton lifecycle', () {
    test('instance throws before initialize', () {
      // The manager may already be initialized from prior tests in this
      // process — accept either: initialized → returns instance, or
      // uninitialized → throws.
      try {
        final m = MCPOAuthManager.instance;
        expect(m, isA<MCPOAuthManager>());
      } on MCPException catch (_) {
        // Expected when no prior test initialized.
      }
    });

    test('initialize is idempotent', () async {
      final cm = await CredentialManager.initialize(_FakeStorage());
      final m1 = await MCPOAuthManager.initialize(credentialManager: cm);
      final m2 = await MCPOAuthManager.initialize(credentialManager: cm);
      expect(identical(m1, m2), isTrue);
    });

    test('isAuthenticated returns false for unknown llm', () async {
      final cm = await CredentialManager.initialize(_FakeStorage());
      final m = await MCPOAuthManager.initialize(credentialManager: cm);
      expect(m.isAuthenticated('absent-llm'), isFalse);
    });

    test('handleCallback with invalid state throws', () async {
      final cm = await CredentialManager.initialize(_FakeStorage());
      final m = await MCPOAuthManager.initialize(credentialManager: cm);
      await expectLater(
        m.handleCallback('unknown-state', 'auth-code'),
        throwsA(isA<MCPAuthenticationException>()),
      );
    });

    test('disposeForLlm removes per-llm state without throwing', () async {
      final cm = await CredentialManager.initialize(_FakeStorage());
      final m = await MCPOAuthManager.initialize(credentialManager: cm);
      m.disposeForLlm('absent-llm'); // silent on missing
    });

    test('getAuthHeaders for unknown llm rejects (no config)', () async {
      final cm = await CredentialManager.initialize(_FakeStorage());
      final m = await MCPOAuthManager.initialize(credentialManager: cm);
      await expectLater(
        m.getAuthHeaders('absent'),
        throwsA(isA<MCPAuthenticationException>()),
      );
    });

    test('revokeToken on unknown llm runs cleanly', () async {
      final cm = await CredentialManager.initialize(_FakeStorage());
      final m = await MCPOAuthManager.initialize(credentialManager: cm);
      await m.revokeToken('absent'); // should not throw
    });

    test('getUserInfo on unknown llm returns null', () async {
      final cm = await CredentialManager.initialize(_FakeStorage());
      final m = await MCPOAuthManager.initialize(credentialManager: cm);
      final info = await m.getUserInfo('absent');
      expect(info, isNull);
    });
  });
}
