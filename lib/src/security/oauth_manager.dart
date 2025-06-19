import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' as io;
import 'package:crypto/crypto.dart';
import 'package:mcp_llm/mcp_llm.dart' as llm;
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import 'credential_manager.dart';
import '../events/event_system.dart';

/// OAuth configuration
class OAuthConfig {
  final String clientId;
  final String clientSecret;
  final String authorizationUrl;
  final String tokenUrl;
  final List<String> scopes;
  final String? redirectUri;
  final Map<String, String>? additionalParams;
  final String? revokeUrl;
  final String? userInfoUrl;
  final bool usePKCE;

  OAuthConfig({
    required this.clientId,
    required this.clientSecret,
    required this.authorizationUrl,
    required this.tokenUrl,
    required this.scopes,
    this.redirectUri,
    this.additionalParams,
    this.revokeUrl,
    this.userInfoUrl,
    this.usePKCE = true,
  });
}

/// OAuth token information
class OAuthToken {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String tokenType;
  final List<String> scopes;

  OAuthToken({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    this.tokenType = 'Bearer',
    required this.scopes,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        'tokenType': tokenType,
        'scopes': scopes,
      };

  factory OAuthToken.fromJson(Map<String, dynamic> json) {
    return OAuthToken(
      accessToken: json['accessToken'],
      refreshToken: json['refreshToken'],
      expiresAt: DateTime.parse(json['expiresAt']),
      tokenType: json['tokenType'] ?? 'Bearer',
      scopes: List<String>.from(json['scopes'] ?? []),
    );
  }
}

/// OAuth flow state for managing authorization
class _OAuthFlowState {
  final String state;
  final String? codeVerifier;
  final DateTime createdAt;
  final Completer<String> completer;

  _OAuthFlowState({
    required this.state,
    this.codeVerifier,
    required this.createdAt,
    required this.completer,
  });

  bool get isExpired => DateTime.now().difference(createdAt).inMinutes > 10;
}

/// Manages OAuth 2.1 authentication for MCP
class MCPOAuthManager {
  final Logger _logger = Logger('flutter_mcp.oauth_manager');
  final CredentialManager _credentialManager;
  final Map<String, llm.McpAuthAdapter> _authAdapters = {};
  final Map<String, OAuthToken> _tokenCache = {};
  final Map<String, OAuthConfig> _configs = {};
  final Map<String, _OAuthFlowState> _pendingFlows = {};
  final io.HttpClient _httpClient;

  // Singleton
  static MCPOAuthManager? _instance;

  /// Get singleton instance
  static MCPOAuthManager get instance {
    if (_instance == null) {
      throw MCPException('MCPOAuthManager has not been initialized');
    }
    return _instance!;
  }

  /// Initialize the OAuth manager
  static Future<MCPOAuthManager> initialize({
    required CredentialManager credentialManager,
    io.HttpClient? httpClient,
  }) async {
    if (_instance != null) {
      return _instance!;
    }

    _instance = MCPOAuthManager._internal(
      credentialManager: credentialManager,
      httpClient: httpClient ?? io.HttpClient(),
    );

    // Start cleanup timer for expired flows
    Timer.periodic(Duration(minutes: 1), (_) {
      _instance!._cleanupExpiredFlows();
    });

    return _instance!;
  }

  MCPOAuthManager._internal({
    required CredentialManager credentialManager,
    required io.HttpClient httpClient,
  })  : _credentialManager = credentialManager,
        _httpClient = httpClient;

  /// Initialize OAuth for an LLM instance
  Future<void> initializeOAuth({
    required String llmId,
    required llm.MCPLlm mcpLlm,
    required OAuthConfig config,
  }) async {
    try {
      _logger.info('Initializing OAuth for LLM: $llmId');

      // Create auth adapter
      // Note: McpAuthAdapter is created but configuration will be applied when
      // the mcp_llm package is updated to accept configuration in constructor
      final authAdapter = llm.McpAuthAdapter();

      _authAdapters[llmId] = authAdapter;
      _configs[llmId] = config;

      // Check for stored token
      final storedToken = await _loadStoredToken(llmId);
      if (storedToken != null && !storedToken.isExpired) {
        _tokenCache[llmId] = storedToken;
        _logger.info('Loaded valid stored token for LLM: $llmId');
      }
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize OAuth', e, stackTrace);
      throw MCPAuthenticationException.withContext(
        'OAuth initialization failed for LLM: $llmId',
        originalError: e,
        originalStackTrace: stackTrace,
        resolution: 'Check OAuth configuration and credentials',
      );
    }
  }

  /// Authenticate and get access token
  Future<String> authenticate(String llmId) async {
    // Check cache first
    final cachedToken = _tokenCache[llmId];
    if (cachedToken != null && !cachedToken.isExpired) {
      return cachedToken.accessToken;
    }

    // If we have a refresh token, try to refresh
    if (cachedToken != null && cachedToken.refreshToken != null) {
      try {
        final newToken = await _refreshToken(llmId, cachedToken.refreshToken!);
        return newToken.accessToken;
      } catch (e) {
        _logger.warning(
            'Token refresh failed, will perform full authentication: $e');
      }
    }

    // Perform full authentication flow
    return await _performAuthenticationFlow(llmId);
  }

  /// Perform full OAuth authentication flow
  Future<String> _performAuthenticationFlow(String llmId) async {
    final config = _configs[llmId];
    if (config == null) {
      throw MCPAuthenticationException('OAuth not initialized for LLM: $llmId');
    }

    try {
      _logger.info('Starting OAuth authentication flow for LLM: $llmId');

      // Generate state and PKCE parameters
      final state = _generateRandomString(32);
      String? codeVerifier;
      String? codeChallenge;

      if (config.usePKCE) {
        codeVerifier = _generateCodeVerifier();
        codeChallenge = _generateCodeChallenge(codeVerifier);
      }

      // Build authorization URL
      final authUri = Uri.parse(config.authorizationUrl).replace(
        queryParameters: {
          'client_id': config.clientId,
          'response_type': 'code',
          'redirect_uri':
              config.redirectUri ?? 'http://localhost:8080/callback',
          'scope': config.scopes.join(' '),
          'state': state,
          if (codeChallenge != null) 'code_challenge': codeChallenge,
          if (codeChallenge != null) 'code_challenge_method': 'S256',
          ...?config.additionalParams,
        },
      );

      _logger.info('Authorization URL: $authUri');

      // Create flow state
      final flowCompleter = Completer<String>();
      _pendingFlows[state] = _OAuthFlowState(
        state: state,
        codeVerifier: codeVerifier,
        createdAt: DateTime.now(),
        completer: flowCompleter,
      );

      // Publish event for the application to handle browser launch
      // Applications can listen to this event and open the URL using their preferred method
      EventSystem.instance.publishTopic('oauth.open_browser', {
        'llmId': llmId,
        'url': authUri.toString(),
      });

      // Publish event for apps to handle the callback
      EventSystem.instance.publishTopic('oauth.authorization_requested', {
        'llmId': llmId,
        'state': state,
        'authUrl': authUri.toString(),
      });

      // Wait for authorization code (with timeout)
      final authCode = await flowCompleter.future.timeout(
        Duration(minutes: 5),
        onTimeout: () {
          _pendingFlows.remove(state);
          throw MCPAuthenticationException('OAuth authorization timeout');
        },
      );

      // Exchange code for token
      final token = await _exchangeCodeForToken(
        llmId: llmId,
        code: authCode,
        codeVerifier: codeVerifier,
      );

      // Cache and store token
      _tokenCache[llmId] = token;
      await _storeToken(llmId, token);

      _logger.info('OAuth authentication successful for LLM: $llmId');
      return token.accessToken;
    } catch (e, stackTrace) {
      _logger.severe('OAuth authentication failed', e, stackTrace);
      throw MCPAuthenticationException.withContext(
        'OAuth authentication failed',
        originalError: e,
        originalStackTrace: stackTrace,
      );
    }
  }

  /// Exchange authorization code for token
  Future<OAuthToken> _exchangeCodeForToken({
    required String llmId,
    required String code,
    String? codeVerifier,
  }) async {
    final config = _configs[llmId]!;

    try {
      final body = {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config.redirectUri ?? 'http://localhost:8080/callback',
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        if (codeVerifier != null) 'code_verifier': codeVerifier,
      };

      final request = await _httpClient.postUrl(Uri.parse(config.tokenUrl));
      request.headers.contentType =
          io.ContentType('application', 'x-www-form-urlencoded');
      request.headers.add('Accept', 'application/json');

      final bodyString = body.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      request.write(bodyString);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != io.HttpStatus.ok) {
        throw MCPAuthenticationException(
            'Token exchange failed: ${response.statusCode} $responseBody');
      }

      final data = jsonDecode(responseBody);

      return OAuthToken(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
        expiresAt: DateTime.now().add(
          Duration(seconds: data['expires_in'] ?? 3600),
        ),
        tokenType: data['token_type'] ?? 'Bearer',
        scopes: (data['scope'] as String?)?.split(' ') ?? config.scopes,
      );
    } catch (e, stackTrace) {
      _logger.severe('Code exchange failed', e, stackTrace);
      throw MCPAuthenticationException.withContext(
        'Failed to exchange authorization code for token',
        originalError: e,
        originalStackTrace: stackTrace,
      );
    }
  }

  /// Refresh access token
  Future<OAuthToken> _refreshToken(String llmId, String refreshToken) async {
    final config = _configs[llmId];
    if (config == null) {
      throw MCPAuthenticationException('OAuth not initialized for LLM: $llmId');
    }

    try {
      _logger.info('Refreshing OAuth token for LLM: $llmId');

      final body = {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
      };

      final request = await _httpClient.postUrl(Uri.parse(config.tokenUrl));
      request.headers.contentType =
          io.ContentType('application', 'x-www-form-urlencoded');
      request.headers.add('Accept', 'application/json');

      final bodyString = body.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      request.write(bodyString);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != io.HttpStatus.ok) {
        throw MCPAuthenticationException(
            'Token refresh failed: ${response.statusCode} $responseBody');
      }

      final data = jsonDecode(responseBody);

      final token = OAuthToken(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'] ?? refreshToken,
        expiresAt: DateTime.now().add(
          Duration(seconds: data['expires_in'] ?? 3600),
        ),
        tokenType: data['token_type'] ?? 'Bearer',
        scopes: (data['scope'] as String?)?.split(' ') ?? config.scopes,
      );

      // Update cache and storage
      _tokenCache[llmId] = token;
      await _storeToken(llmId, token);

      _logger.info('Token refresh successful for LLM: $llmId');
      return token;
    } catch (e, stackTrace) {
      _logger.severe('Token refresh failed', e, stackTrace);
      throw MCPAuthenticationException.withContext(
        'Token refresh failed',
        originalError: e,
        originalStackTrace: stackTrace,
      );
    }
  }

  /// Store token securely
  Future<void> _storeToken(String llmId, OAuthToken token) async {
    try {
      await _credentialManager.storeCredential(
        'oauth_token_$llmId',
        jsonEncode(token.toJson()),
      );
    } catch (e) {
      _logger.severe('Failed to store OAuth token', e);
    }
  }

  /// Load stored token
  Future<OAuthToken?> _loadStoredToken(String llmId) async {
    try {
      final dataJson =
          await _credentialManager.getCredential('oauth_token_$llmId');
      if (dataJson != null) {
        final data = jsonDecode(dataJson);
        return OAuthToken.fromJson(data);
      }
    } catch (e) {
      _logger.severe('Failed to load stored OAuth token', e);
    }
    return null;
  }

  /// Handle OAuth callback
  Future<void> handleCallback(String state, String code) async {
    final flowState = _pendingFlows[state];
    if (flowState == null || flowState.isExpired) {
      throw MCPAuthenticationException('Invalid or expired OAuth state');
    }

    // Complete the flow
    flowState.completer.complete(code);
    _pendingFlows.remove(state);

    _logger.info('OAuth callback handled for state: $state');
  }

  /// Revoke token
  Future<void> revokeToken(String llmId) async {
    try {
      final token = _tokenCache[llmId];
      final config = _configs[llmId];

      if (token != null && config != null && config.revokeUrl != null) {
        try {
          final request =
              await _httpClient.postUrl(Uri.parse(config.revokeUrl!));
          request.headers.contentType =
              io.ContentType('application', 'x-www-form-urlencoded');

          final body = {
            'token': token.accessToken,
            'client_id': config.clientId,
            'client_secret': config.clientSecret,
          };

          final bodyString = body.entries
              .map((e) =>
                  '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
              .join('&');
          request.write(bodyString);

          final response = await request.close();
          await response.drain();
        } catch (e) {
          _logger.warning('Token revocation request failed: $e');
        }
      }

      // Clear from cache and storage
      _tokenCache.remove(llmId);
      await _credentialManager.deleteCredential('oauth_token_$llmId');

      _logger.info('Token revoked for LLM: $llmId');
    } catch (e) {
      _logger.severe('Failed to revoke token', e);
    }
  }

  /// Get authentication headers
  Future<Map<String, String>> getAuthHeaders(String llmId) async {
    final token = await authenticate(llmId);
    return {
      'Authorization': 'Bearer $token',
    };
  }

  /// Check if authenticated
  bool isAuthenticated(String llmId) {
    final token = _tokenCache[llmId];
    return token != null && !token.isExpired;
  }

  /// Get user info (if supported)
  Future<Map<String, dynamic>?> getUserInfo(String llmId) async {
    final config = _configs[llmId];
    if (config == null || config.userInfoUrl == null) {
      return null;
    }

    try {
      final token = await authenticate(llmId);

      final request = await _httpClient.getUrl(Uri.parse(config.userInfoUrl!));
      request.headers.add('Authorization', 'Bearer $token');
      request.headers.add('Accept', 'application/json');

      final response = await request.close();

      if (response.statusCode == io.HttpStatus.ok) {
        final responseBody = await response.transform(utf8.decoder).join();
        return jsonDecode(responseBody);
      }
    } catch (e) {
      _logger.severe('Failed to get user info', e);
    }

    return null;
  }

  /// Dispose OAuth manager for an LLM
  void disposeForLlm(String llmId) {
    _authAdapters.remove(llmId);
    _tokenCache.remove(llmId);
    _configs.remove(llmId);
  }

  /// Clean up expired flows
  void _cleanupExpiredFlows() {
    final expiredStates = <String>[];

    _pendingFlows.forEach((state, flow) {
      if (flow.isExpired) {
        expiredStates.add(state);
        flow.completer.completeError(
          MCPAuthenticationException('OAuth flow expired'),
        );
      }
    });

    for (final state in expiredStates) {
      _pendingFlows.remove(state);
    }

    if (expiredStates.isNotEmpty) {
      _logger.fine('Cleaned up ${expiredStates.length} expired OAuth flows');
    }
  }

  /// Generate random string for state parameter
  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Generate PKCE code verifier
  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    final length = 43 + random.nextInt(86); // 43-128 characters
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Generate PKCE code challenge from verifier
  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Dispose all OAuth managers
  void dispose() {
    _authAdapters.clear();
    _tokenCache.clear();
    _configs.clear();
    _pendingFlows.clear();
    _httpClient.close(force: true);
  }
}
