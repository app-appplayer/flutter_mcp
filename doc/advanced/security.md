# Security Best Practices

This guide covers security considerations when using Flutter MCP.

## Credential Security

### Secure Storage

Flutter MCP uses platform-specific secure storage mechanisms:

```dart
import 'package:flutter_mcp/flutter_mcp.dart';

// Store sensitive data
await FlutterMCP.secureStorage.set('api_key', 'your-secret-key');

// Retrieve sensitive data
final apiKey = await FlutterMCP.secureStorage.get('api_key');

// Delete sensitive data
await FlutterMCP.secureStorage.delete('api_key');
```

### Platform-Specific Storage

- **Android**: Android Keystore
- **iOS**: iOS Keychain
- **macOS**: macOS Keychain
- **Windows**: Windows Credential Manager
- **Linux**: Secret Service API (libsecret)
- **Web**: localStorage with encryption

### Credential Manager

```dart
// Create credential manager
final credentialManager = CredentialManager();

// Store credentials
await credentialManager.storeCredentials(
  'service-name',
  Credentials(
    username: 'user',
    password: 'pass',
    tokens: {
      'access_token': 'token',
      'refresh_token': 'refresh',
    },
  ),
);

// Retrieve credentials
final credentials = await credentialManager.getCredentials('service-name');

// Update tokens
await credentialManager.updateTokens(
  'service-name',
  {
    'access_token': 'new-token',
    'refresh_token': 'new-refresh',
  },
);
```

## Communication Security

### TLS/SSL Configuration

```dart
// Configure secure communication
final config = MCPConfig(
  servers: {
    'secure-server': ServerConfig(
      uri: 'https://api.example.com',
      tls: TLSConfig(
        enabled: true,
        verifyHost: true,
        verifyPeer: true,
        certificates: ['/path/to/cert.pem'],
        allowSelfSigned: false,
      ),
    ),
  },
);

await FlutterMCP.initialize(config);
```

### Certificate Pinning

```dart
// Configure certificate pinning
final config = MCPConfig(
  servers: {
    'pinned-server': ServerConfig(
      uri: 'https://api.example.com',
      tls: TLSConfig(
        enabled: true,
        pinning: CertificatePinning(
          publicKeyHashes: [
            'SPKI-SHA256-BASE64==',
            'BACKUP-SPKI-SHA256-BASE64==',
          ],
          allowBackup: true,
          maxAge: Duration(days: 30),
        ),
      ),
    ),
  },
);
```

## Data Encryption

### Encrypting Local Data

```dart
// Use built-in encryption utilities
import 'package:flutter_mcp/flutter_mcp.dart';

// Encrypt data
final encrypted = await FlutterMCP.crypto.encrypt(
  data: 'sensitive data',
  key: 'encryption-key',
);

// Decrypt data
final decrypted = await FlutterMCP.crypto.decrypt(
  data: encrypted,
  key: 'encryption-key',
);

// Hash data
final hash = await FlutterMCP.crypto.hash(
  data: 'data to hash',
  algorithm: HashAlgorithm.sha256,
);
```

### Secure Key Generation

```dart
// Generate secure keys
final key = await FlutterMCP.crypto.generateKey(
  length: 256,
  algorithm: KeyAlgorithm.aes,
);

// Generate key pair
final keyPair = await FlutterMCP.crypto.generateKeyPair(
  algorithm: KeyPairAlgorithm.rsa,
  keySize: 2048,
);
```

## Access Control

### Permission-Based Access

```dart
// Define permissions
class ServerPermissions {
  final bool canRead;
  final bool canWrite;
  final bool canExecute;
  final List<String> allowedMethods;
  
  const ServerPermissions({
    this.canRead = true,
    this.canWrite = false,
    this.canExecute = false,
    this.allowedMethods = const [],
  });
}

// Configure server with permissions
final config = MCPConfig(
  servers: {
    'restricted-server': ServerConfig(
      uri: 'https://api.example.com',
      permissions: ServerPermissions(
        canRead: true,
        canWrite: true,
        allowedMethods: ['getData', 'updateData'],
      ),
    ),
  },
);
```

### Role-Based Access Control

```dart
// Implement RBAC
class RoleManager {
  final Map<String, Set<String>> _rolePermissions = {
    'admin': {'read', 'write', 'delete', 'execute'},
    'user': {'read', 'write'},
    'guest': {'read'},
  };
  
  bool hasPermission(String role, String permission) {
    return _rolePermissions[role]?.contains(permission) ?? false;
  }
  
  void checkPermission(String role, String permission) {
    if (!hasPermission(role, permission)) {
      throw SecurityException('Permission denied: $permission for role: $role');
    }
  }
}
```

## Secure Configuration

### Environment Variables

```dart
// Load configuration from environment
class SecureConfig {
  static String get apiKey => 
    Platform.environment['MCP_API_KEY'] ?? 
    throw ConfigurationException('API key not found');
    
  static String get secretKey => 
    Platform.environment['MCP_SECRET_KEY'] ?? 
    throw ConfigurationException('Secret key not found');
}

// Use in configuration
final config = MCPConfig(
  servers: {
    'api': ServerConfig(
      uri: 'https://api.example.com',
      auth: AuthConfig(
        apiKey: SecureConfig.apiKey,
        secretKey: SecureConfig.secretKey,
      ),
    ),
  },
);
```

### Configuration Validation

```dart
// Validate configuration security
class ConfigValidator {
  static void validateSecurity(MCPConfig config) {
    for (final server in config.servers.values) {
      // Check for secure protocols
      if (!server.uri.startsWith('https://')) {
        throw SecurityException('Server must use HTTPS: ${server.uri}');
      }
      
      // Check for authentication
      if (server.auth == null) {
        throw SecurityException('Server must have authentication configured');
      }
      
      // Check for secure storage
      if (server.auth!.storeCredentials && !server.auth!.useSecureStorage) {
        throw SecurityException('Stored credentials must use secure storage');
      }
    }
  }
}
```

## Audit and Logging

### Security Event Logging

```dart
// Implement security audit logging
class SecurityLogger {
  static void logSecurityEvent(SecurityEvent event) {
    FlutterMCP.logger.log(
      level: LogLevel.security,
      message: event.message,
      context: {
        'event_type': event.type,
        'timestamp': event.timestamp,
        'user': event.user,
        'ip_address': event.ipAddress,
        'action': event.action,
        'result': event.result,
      },
    );
  }
  
  static void logFailedAuth(String user, String reason) {
    logSecurityEvent(SecurityEvent(
      type: SecurityEventType.authFailure,
      message: 'Authentication failed',
      user: user,
      action: 'login',
      result: 'failed',
      details: {'reason': reason},
    ));
  }
  
  static void logSuccessfulAuth(String user) {
    logSecurityEvent(SecurityEvent(
      type: SecurityEventType.authSuccess,
      message: 'Authentication successful',
      user: user,
      action: 'login',
      result: 'success',
    ));
  }
}
```

### Compliance Logging

```dart
// Implement compliance logging
class ComplianceLogger {
  static void logDataAccess(DataAccessEvent event) {
    FlutterMCP.logger.log(
      level: LogLevel.compliance,
      message: 'Data access',
      context: {
        'user': event.user,
        'resource': event.resource,
        'action': event.action,
        'timestamp': event.timestamp,
        'purpose': event.purpose,
        'legal_basis': event.legalBasis,
      },
    );
  }
  
  static void logDataModification(DataModificationEvent event) {
    FlutterMCP.logger.log(
      level: LogLevel.compliance,
      message: 'Data modification',
      context: {
        'user': event.user,
        'resource': event.resource,
        'action': event.action,
        'timestamp': event.timestamp,
        'old_value': event.oldValue,
        'new_value': event.newValue,
        'reason': event.reason,
      },
    );
  }
}
```

## Input Validation

### Sanitizing User Input

```dart
// Implement input sanitization
class InputValidator {
  static String sanitizeString(String input, {
    int? maxLength,
    RegExp? allowedPattern,
    bool stripHtml = true,
  }) {
    var sanitized = input.trim();
    
    // Strip HTML if requested
    if (stripHtml) {
      sanitized = sanitized.replaceAll(RegExp(r'<[^>]*>'), '');
    }
    
    // Apply length limit
    if (maxLength != null && sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }
    
    // Apply pattern validation
    if (allowedPattern != null) {
      if (!allowedPattern.hasMatch(sanitized)) {
        throw ValidationException('Invalid input format');
      }
    }
    
    return sanitized;
  }
  
  static Map<String, dynamic> sanitizeJson(Map<String, dynamic> input, {
    required Map<String, InputSchema> schema,
  }) {
    final sanitized = <String, dynamic>{};
    
    for (final entry in schema.entries) {
      final key = entry.key;
      final fieldSchema = entry.value;
      final value = input[key];
      
      if (value == null && fieldSchema.required) {
        throw ValidationException('Required field missing: $key');
      }
      
      if (value != null) {
        sanitized[key] = fieldSchema.validate(value);
      }
    }
    
    return sanitized;
  }
}
```

### SQL Injection Prevention

```dart
// Prevent SQL injection in custom queries
class SafeQuery {
  static String buildQuery(String template, Map<String, dynamic> params) {
    var query = template;
    
    for (final entry in params.entries) {
      final placeholder = ':${entry.key}';
      final value = _escapeValue(entry.value);
      query = query.replaceAll(placeholder, value);
    }
    
    return query;
  }
  
  static String _escapeValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is num) return value.toString();
    if (value is String) {
      // Escape single quotes
      return "'${value.replaceAll("'", "''")}'";
    }
    throw ArgumentError('Unsupported value type: ${value.runtimeType}');
  }
}
```

## Security Headers

### Web Security Headers

```dart
// Configure security headers for web
class WebSecurityHeaders {
  static Map<String, String> getSecurityHeaders() {
    return {
      'Content-Security-Policy': "default-src 'self'; script-src 'self' 'unsafe-inline'",
      'X-Frame-Options': 'DENY',
      'X-Content-Type-Options': 'nosniff',
      'X-XSS-Protection': '1; mode=block',
      'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
      'Referrer-Policy': 'no-referrer',
      'Permissions-Policy': 'geolocation=(), microphone=(), camera=()',
    };
  }
}
```

## Security Checklist

### Development Phase
- [ ] Use secure communication protocols (HTTPS/WSS)
- [ ] Implement proper authentication
- [ ] Store credentials securely
- [ ] Validate all user input
- [ ] Implement proper error handling
- [ ] Use secure random number generation
- [ ] Implement rate limiting
- [ ] Add security logging

### Deployment Phase
- [ ] Disable debug mode
- [ ] Remove development endpoints
- [ ] Configure secure headers
- [ ] Update all dependencies
- [ ] Perform security audit
- [ ] Configure firewall rules
- [ ]Enable monitoring and alerting
- [ ] Document security procedures

### Maintenance Phase
- [ ] Regular security updates
- [ ] Periodic security audits
- [ ] Monitor security logs
- [ ] Update dependencies
- [ ] Review access controls
- [ ] Update documentation
- [ ] Incident response planning
- [ ] Security training

## Security Resources

### Tools
- [OWASP Security Guide](https://owasp.org/www-project-mobile-security/)
- [Flutter Security Best Practices](https://flutter.dev/docs/deployment/security)
- [Platform Security Guidelines](https://developer.android.com/topic/security/best-practices)

### Libraries
- flutter_secure_storage
- cryptography
- pointycastle
- encrypt

### Standards
- OWASP Mobile Top 10
- PCI DSS
- GDPR
- HIPAA
- ISO 27001