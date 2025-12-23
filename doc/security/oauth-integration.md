# OAuth Integration Guide

This guide explains how to implement OAuth 2.1 authentication with Flutter MCP for secure API access.

## Overview

Flutter MCP provides built-in OAuth support for authenticating with various providers including:
- Google
- GitHub
- Microsoft
- Custom OAuth providers

## Basic OAuth Setup

### 1. Initialize OAuth Configuration

```dart
import 'package:flutter_mcp/flutter_mcp.dart';

// Configure OAuth
await FlutterMCP.instance.initializeOAuth(
  OAuthConfig(
    clientId: 'your-client-id',
    clientSecret: 'your-client-secret',
    authorizeUrl: 'https://provider.com/oauth/authorize',
    tokenUrl: 'https://provider.com/oauth/token',
    scopes: ['read', 'write'],
    redirectUri: 'myapp://oauth/callback',
  ),
);
```

### 2. Authenticate User

```dart
try {
  // Authenticate with OAuth provider
  final token = await FlutterMCP.instance.authenticateOAuth(
    provider: 'google',
    additionalParams: {
      'access_type': 'offline', // Request refresh token
      'prompt': 'consent',      // Force consent screen
    },
  );
  
  print('Access Token: ${token.accessToken}');
  print('Expires In: ${token.expiresIn} seconds');
  
} on MCPAuthenticationException catch (e) {
  print('Authentication failed: ${e.message}');
}
```

## Provider-Specific Configuration

### Google OAuth

```dart
// Google OAuth configuration
await FlutterMCP.instance.initializeOAuth(
  OAuthConfig(
    clientId: 'your-google-client-id.apps.googleusercontent.com',
    clientSecret: 'your-client-secret',
    authorizeUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenUrl: 'https://oauth2.googleapis.com/token',
    scopes: [
      'https://www.googleapis.com/auth/userinfo.profile',
      'https://www.googleapis.com/auth/userinfo.email',
    ],
    redirectUri: 'com.example.app:/oauth2redirect',
  ),
);
```

### GitHub OAuth

```dart
// GitHub OAuth configuration
await FlutterMCP.instance.initializeOAuth(
  OAuthConfig(
    clientId: 'your-github-client-id',
    clientSecret: 'your-github-client-secret',
    authorizeUrl: 'https://github.com/login/oauth/authorize',
    tokenUrl: 'https://github.com/login/oauth/access_token',
    scopes: ['user', 'repo'],
    redirectUri: 'myapp://oauth/github',
  ),
);
```

### Microsoft OAuth

```dart
// Microsoft OAuth configuration
await FlutterMCP.instance.initializeOAuth(
  OAuthConfig(
    clientId: 'your-azure-client-id',
    clientSecret: 'your-client-secret',
    authorizeUrl: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    tokenUrl: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    scopes: [
      'openid',
      'profile',
      'email',
      'offline_access',
    ],
    redirectUri: 'msauth.com.example.app://auth',
  ),
);
```

## Using OAuth with MCP Clients

### 1. Create OAuth-Authenticated Client

```dart
// Check if authenticated
if (FlutterMCP.instance.isOAuthAuthenticated('google')) {
  // Get OAuth headers
  final headers = FlutterMCP.instance.getOAuthHeaders('google');
  
  // Create client with OAuth headers
  final clientId = await FlutterMCP.instance.clientManager.createClient(
    MCPClientConfig(
      name: 'OAuth Client',
      version: '1.0.0',
      transportType: 'streamablehttp',
      serverUrl: 'https://api.example.com/mcp',
      headers: headers, // OAuth headers automatically included
    ),
  );
  
  await FlutterMCP.instance.connectClient(clientId);
}
```

### 2. Automatic Token Refresh

Flutter MCP automatically handles token refresh when configured:

```dart
class OAuthMCPService {
  String? _clientId;
  
  Future<void> connectWithOAuth() async {
    // Ensure OAuth is authenticated
    if (!FlutterMCP.instance.isOAuthAuthenticated('google')) {
      await FlutterMCP.instance.authenticateOAuth(provider: 'google');
    }
    
    // Headers will include fresh tokens
    final headers = FlutterMCP.instance.getOAuthHeaders('google');
    
    _clientId = await FlutterMCP.instance.createClient(
      name: 'OAuth Client',
      version: '1.0.0',
      serverUrl: 'https://api.example.com/mcp',
      headers: headers,
    );
  }
  
  Future<dynamic> makeAuthenticatedRequest(String tool, Map<String, dynamic> args) async {
    if (_clientId == null) {
      throw MCPException('Not connected');
    }
    
    try {
      return await FlutterMCP.instance.clientManager.callTool(_clientId!, tool, args);
    } on MCPAuthenticationException {
      // Token might be expired, re-authenticate
      await FlutterMCP.instance.authenticateOAuth(provider: 'google');
      // Retry with new token
      return await FlutterMCP.instance.clientManager.callTool(_clientId!, tool, args);
    }
  }
}
```

## Advanced OAuth Features

### Multiple Provider Support

```dart
class MultiProviderOAuth {
  final Map<String, OAuthConfig> _providers = {
    'google': OAuthConfig(
      clientId: 'google-client-id',
      // ... Google config
    ),
    'github': OAuthConfig(
      clientId: 'github-client-id',
      // ... GitHub config
    ),
    'custom': OAuthConfig(
      clientId: 'custom-client-id',
      // ... Custom provider config
    ),
  };
  
  Future<void> initializeProviders() async {
    for (final entry in _providers.entries) {
      await FlutterMCP.instance.initializeOAuth(entry.value);
    }
  }
  
  Future<void> authenticateWithProvider(String provider) async {
    if (!_providers.containsKey(provider)) {
      throw MCPException('Unknown provider: $provider');
    }
    
    await FlutterMCP.instance.authenticateOAuth(provider: provider);
  }
}
```

### Token Management

```dart
class TokenManager {
  // Get current token info
  OAuthToken? getToken(String provider) {
    if (!FlutterMCP.instance.isOAuthAuthenticated(provider)) {
      return null;
    }
    
    // Token is managed internally, but you can access headers
    final headers = FlutterMCP.instance.getOAuthHeaders(provider);
    // Headers contain 'Authorization: Bearer <token>'
    
    return null; // Token details are managed internally
  }
  
  // Revoke token
  Future<void> logout(String provider) async {
    await FlutterMCP.instance.revokeOAuthToken(provider);
  }
  
  // Check token validity
  bool isTokenValid(String provider) {
    return FlutterMCP.instance.isOAuthAuthenticated(provider);
  }
}
```

### Custom OAuth Flow

For providers not using standard OAuth 2.0 flow:

```dart
class CustomOAuthProvider {
  Future<void> authenticateCustom() async {
    // 1. Get authorization code manually
    final authCode = await _launchCustomAuthFlow();
    
    // 2. Exchange for token
    final tokenResponse = await http.post(
      Uri.parse('https://custom-provider.com/token'),
      body: {
        'grant_type': 'authorization_code',
        'code': authCode,
        'client_id': 'your-client-id',
        'client_secret': 'your-client-secret',
      },
    );
    
    final tokenData = jsonDecode(tokenResponse.body);
    
    // 3. Create custom OAuth config with token
    await FlutterMCP.instance.initializeOAuth(
      OAuthConfig(
        clientId: 'your-client-id',
        clientSecret: 'your-client-secret',
        authorizeUrl: 'https://custom-provider.com/auth',
        tokenUrl: 'https://custom-provider.com/token',
        scopes: ['custom_scope'],
      ),
    );
    
    // Token is now managed by Flutter MCP
  }
  
  Future<String> _launchCustomAuthFlow() async {
    // Implement custom authorization flow
    // Return authorization code
    return 'auth-code';
  }
}
```

## Security Best Practices

### 1. Secure Token Storage

Flutter MCP automatically stores tokens securely using platform-specific secure storage:

- **iOS**: Keychain
- **Android**: Android Keystore
- **Windows**: Windows Credential Manager
- **macOS**: Keychain
- **Linux**: libsecret

### 2. Scope Management

Request only necessary scopes:

```dart
// Bad - requesting all scopes
scopes: ['*']

// Good - specific scopes only
scopes: ['user:email', 'repo:read']
```

### 3. PKCE (Proof Key for Code Exchange)

For mobile apps, use PKCE for enhanced security:

```dart
await FlutterMCP.instance.authenticateOAuth(
  provider: 'custom',
  additionalParams: {
    'code_challenge': generateCodeChallenge(),
    'code_challenge_method': 'S256',
  },
);
```

### 4. State Parameter

Always use state parameter to prevent CSRF:

```dart
final state = generateRandomState();

await FlutterMCP.instance.authenticateOAuth(
  provider: 'custom',
  additionalParams: {
    'state': state,
  },
);
```

## Error Handling

```dart
try {
  await FlutterMCP.instance.authenticateOAuth(provider: 'google');
} on MCPAuthenticationException catch (e) {
  switch (e.code) {
    case 'invalid_grant':
      print('Invalid or expired authorization code');
      break;
    case 'access_denied':
      print('User denied access');
      break;
    case 'invalid_client':
      print('Invalid client credentials');
      break;
    default:
      print('Authentication error: ${e.message}');
  }
}
```

## Platform-Specific Setup

### Android

Add to `AndroidManifest.xml`:

```xml
<activity
    android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
    android:exported="true">
    <intent-filter android:label="flutter_web_auth_2">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="myapp" android:host="oauth" />
    </intent-filter>
</activity>
```

### iOS

Add to `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>myapp</string>
        </array>
    </dict>
</array>
```

## Testing OAuth

```dart
void main() {
  group('OAuth Integration Tests', () {
    setUp(() async {
      await FlutterMCP.instance.init(
        MCPConfig(
          appName: 'Test App',
          appVersion: '1.0.0',
        ),
      );
    });
    
    test('OAuth authentication flow', () async {
      // Mock OAuth configuration
      await FlutterMCP.instance.initializeOAuth(
        OAuthConfig(
          clientId: 'test-client',
          clientSecret: 'test-secret',
          authorizeUrl: 'https://test.com/auth',
          tokenUrl: 'https://test.com/token',
          scopes: ['test'],
        ),
      );
      
      // Test authentication
      expect(
        FlutterMCP.instance.isOAuthAuthenticated('test'),
        isFalse,
      );
      
      // Authenticate (would need mocking in real tests)
      // await FlutterMCP.instance.authenticateOAuth(provider: 'test');
    });
  });
}
```

## Troubleshooting

### Common Issues

1. **"Invalid redirect URI"**
   - Ensure redirect URI matches exactly in app and provider config
   - Check URL scheme registration on mobile platforms

2. **"Token expired"**
   - Flutter MCP should auto-refresh, but you can force re-authentication
   - Check if refresh token is being requested

3. **"Network error during authentication"**
   - Check App Transport Security (iOS)
   - Verify internet permissions (Android)

### Debug Mode

Enable OAuth debug logging:

```dart
FlutterMcpLogging.configure(
  level: Level.FINE,
  enableDebugLogging: true,
);
```

## See Also

- [Security Guide](../advanced/security.md)
- [Credential Management](credential-management.md)
- [API Reference - OAuth Methods](../api/flutter-mcp-api.md#oauth-methods)