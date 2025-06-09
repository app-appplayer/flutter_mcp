# Security Implementation Examples

This document provides practical examples of implementing security features in Flutter MCP applications.

## Complete Security Setup Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:logging/logging.dart';

class SecureApp extends StatefulWidget {
  @override
  _SecureAppState createState() => _SecureAppState();
}

class _SecureAppState extends State<SecureApp> {
  final Logger _logger = Logger('flutter_mcp.secure_app');
  late SecurityAuditManager _auditManager;
  late EncryptionManager _encryptionManager;
  String? _currentUserId;
  String? _currentSessionId;
  String? _dataEncryptionKey;

  @override
  void initState() {
    super.initState();
    _initializeSecurity();
  }

  Future<void> _initializeSecurity() async {
    // Initialize Flutter MCP with security features
    await FlutterMCP.instance.init(MCPConfig(
      appName: 'Secure MCP App',
      appVersion: '1.0.0',
      enablePerformanceMonitoring: true,
      secure: true, // Enable security features
    ));

    // Get security managers
    _auditManager = SecurityAuditManager.instance;
    _encryptionManager = EncryptionManager.instance;

    // Configure security policy
    _auditManager.initialize(policy: SecurityPolicy(
      maxFailedAttempts: 3,
      lockoutDuration: Duration(minutes: 30),
      sessionTimeout: Duration(hours: 4),
      passwordMinLength: 12,
      requireStrongPasswords: true,
      auditRetention: Duration(days: 365),
      blockedActions: ['admin_delete', 'bulk_export'],
      riskThresholds: {
        'low': 20,
        'medium': 40,
        'high': 70,
        'critical': 90,
      },
      enableRealTimeMonitoring: true,
      maxConcurrentSessions: 2,
    ));

    // Initialize encryption with strict settings
    _encryptionManager.initialize(
      minKeyLength: 256,
      keyRotationInterval: Duration(days: 60),
      requireChecksums: true,
    );

    // Generate application data encryption key
    _dataEncryptionKey = _encryptionManager.generateKey(
      EncryptionAlgorithm.aes256,
      alias: 'app_data_key',
      expiresIn: Duration(days: 365),
      metadata: {
        'purpose': 'application_data',
        'created_by': 'system',
      },
    );

    // Set up security event monitoring
    _setupSecurityMonitoring();

    _logger.info('Security system initialized');
  }

  void _setupSecurityMonitoring() {
    // Listen for security alerts
    EnhancedTypedEventSystem.instance.listen<SecurityAlert>((alert) {
      _handleSecurityAlert(alert);
    });

    // Listen for security events
    EnhancedTypedEventSystem.instance.listen<SecurityEvent>((event) {
      _handleSecurityEvent(event);
    });
  }

  void _handleSecurityAlert(SecurityAlert alert) {
    _logger.warning('Security Alert: ${alert.title} - ${alert.message}');
    
    // Show user notification for high-severity alerts
    if (alert.severity == AlertSeverity.high || 
        alert.severity == AlertSeverity.critical) {
      _showSecurityNotification(alert);
    }
  }

  void _handleSecurityEvent(SecurityEvent event) {
    _logger.info('Security Event: ${event.eventType_} - ${event.message}');
    
    // Log to external security system if needed
    _logToExternalSecuritySystem(event);
  }

  Future<void> _authenticateUser(String username, String password) async {
    try {
      // Check if user is locked out
      if (_auditManager.isUserLockedOut(username)) {
        _showError('Account is temporarily locked. Please try again later.');
        return;
      }

      // Simulate authentication (replace with real authentication)
      bool authSuccess = await _performAuthentication(username, password);

      // Log authentication attempt
      bool allowed = _auditManager.checkAuthenticationAttempt(
        username,
        authSuccess,
        metadata: {
          'loginMethod': 'password',
          'deviceInfo': 'Flutter App',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (authSuccess && allowed) {
        // Start secure session
        _currentUserId = username;
        _currentSessionId = _auditManager.startSession(
          username,
          metadata: {
            'deviceType': 'mobile',
            'appVersion': '1.0.0',
            'loginTime': DateTime.now().toIso8601String(),
          },
        );

        setState(() {});
        _logger.info('User authenticated successfully: $username');
      } else {
        _showError('Authentication failed');
      }
    } catch (e) {
      _logger.severe('Authentication error: $e');
      _showError('Authentication system error');
    }
  }

  Future<bool> _performAuthentication(String username, String password) async {
    // Simulate authentication delay
    await Future.delayed(Duration(milliseconds: 500));
    
    // Simple demo authentication (replace with real implementation)
    return password.isNotEmpty && password.length >= 8;
  }

  Future<void> _accessSensitiveData(String dataType) async {
    if (_currentUserId == null) {
      _showError('Please authenticate first');
      return;
    }

    // Check data access authorization
    bool authorized = _auditManager.checkDataAccess(
      _currentUserId!,
      dataType,
      'read',
      metadata: {
        'requestedAt': DateTime.now().toIso8601String(),
        'sessionId': _currentSessionId,
      },
    );

    if (!authorized) {
      _showError('Access denied');
      return;
    }

    try {
      // Simulate sensitive data access
      String sensitiveData = await _fetchSensitiveData(dataType);
      
      // Encrypt data for local storage
      EncryptedData encrypted = _encryptionManager.encrypt(
        _dataEncryptionKey!,
        sensitiveData,
        parameters: {
          'dataType': dataType,
          'accessedBy': _currentUserId,
          'accessTime': DateTime.now().toIso8601String(),
        },
      );

      // Store encrypted data
      await _storeEncryptedData(dataType, encrypted);

      _showSuccess('Data accessed and stored securely');
    } catch (e) {
      _logger.severe('Data access error: $e');
      _showError('Failed to access data');
    }
  }

  Future<String> _fetchSensitiveData(String dataType) async {
    // Simulate data fetching
    await Future.delayed(Duration(milliseconds: 300));
    return 'Sensitive $dataType data: ${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _storeEncryptedData(String dataType, EncryptedData encrypted) async {
    // Convert to JSON for storage
    String jsonData = jsonEncode(encrypted.toJson());
    
    // Store using secure storage
    await FlutterMCP.instance.secureStore('encrypted_$dataType', jsonData);
  }

  Future<String?> _retrieveAndDecryptData(String dataType) async {
    try {
      // Retrieve from secure storage
      String? jsonData = await FlutterMCP.instance.secureRead('encrypted_$dataType');
      if (jsonData == null) return null;

      // Deserialize encrypted data
      Map<String, dynamic> jsonMap = jsonDecode(jsonData);
      EncryptedData encrypted = EncryptedData.fromJson(jsonMap);

      // Decrypt data
      String decrypted = _encryptionManager.decrypt(encrypted);

      // Log data access
      _auditManager.logSecurityEvent(SecurityAuditEvent(
        eventId: _auditManager.generateEventId(),
        type: SecurityEventType.dataAccess,
        userId: _currentUserId,
        action: 'data_decrypt',
        resource: dataType,
        success: true,
        metadata: {
          'decryptedAt': DateTime.now().toIso8601String(),
          'dataSize': decrypted.length,
        },
      ));

      return decrypted;
    } catch (e) {
      _logger.severe('Data decryption error: $e');
      return null;
    }
  }

  Future<void> _rotateEncryptionKeys() async {
    try {
      // Rotate the main data encryption key
      String newKeyId = _encryptionManager.rotateKey(
        _dataEncryptionKey!,
        metadata: {
          'rotationReason': 'manual_rotation',
          'rotatedBy': _currentUserId,
          'rotatedAt': DateTime.now().toIso8601String(),
        },
      );

      _dataEncryptionKey = newKeyId;
      
      _showSuccess('Encryption keys rotated successfully');
      _logger.info('Encryption keys rotated');
    } catch (e) {
      _logger.severe('Key rotation error: $e');
      _showError('Failed to rotate keys');
    }
  }

  Future<void> _generateSecurityReport() async {
    try {
      // Generate audit report
      Map<String, dynamic> auditReport = _auditManager.generateSecurityReport();
      
      // Generate encryption report
      Map<String, dynamic> encryptionReport = _encryptionManager.generateSecurityReport();

      // Display reports
      _showSecurityReports(auditReport, encryptionReport);
    } catch (e) {
      _logger.severe('Report generation error: $e');
      _showError('Failed to generate security report');
    }
  }

  void _logout() {
    if (_currentUserId != null && _currentSessionId != null) {
      _auditManager.endSession(_currentUserId!, _currentSessionId!);
    }
    
    setState(() {
      _currentUserId = null;
      _currentSessionId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Secure MCP App'),
        actions: [
          if (_currentUserId != null)
            IconButton(
              icon: Icon(Icons.logout),
              onPressed: _logout,
            ),
        ],
      ),
      body: _currentUserId == null ? _buildLoginScreen() : _buildMainScreen(),
    );
  }

  Widget _buildLoginScreen() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: usernameController,
            decoration: InputDecoration(labelText: 'Username'),
          ),
          SizedBox(height: 16),
          TextField(
            controller: passwordController,
            decoration: InputDecoration(labelText: 'Password'),
            obscureText: true,
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => _authenticateUser(
              usernameController.text,
              passwordController.text,
            ),
            child: Text('Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildMainScreen() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome, $_currentUserId!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => _accessSensitiveData('financial'),
            child: Text('Access Financial Data'),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _accessSensitiveData('personal'),
            child: Text('Access Personal Data'),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _retrieveAndDecryptData('financial').then((data) {
              if (data != null) {
                _showInfo('Retrieved data: ${data.substring(0, 50)}...');
              } else {
                _showError('No data found');
              }
            }),
            child: Text('Retrieve Stored Data'),
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: _rotateEncryptionKeys,
            child: Text('Rotate Encryption Keys'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _generateSecurityReport,
            child: Text('Generate Security Report'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );
  }

  void _showSecurityNotification(SecurityAlert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Security Alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Severity: ${alert.severity.name.toUpperCase()}'),
            SizedBox(height: 8),
            Text('Title: ${alert.title}'),
            SizedBox(height: 8),
            Text('Message: ${alert.message}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSecurityReports(Map<String, dynamic> auditReport, Map<String, dynamic> encryptionReport) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Security Reports'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AUDIT REPORT', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Total Events: ${auditReport['totalEvents']}'),
              Text('Events (24h): ${auditReport['events24h']}'),
              Text('Failed Logins (24h): ${auditReport['failedLogins24h']}'),
              Text('Active Sessions: ${auditReport['activeSessions']}'),
              Text('High Risk Users: ${auditReport['highRiskUsers']}'),
              SizedBox(height: 16),
              Text('ENCRYPTION REPORT', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Total Keys: ${encryptionReport['totalKeys']}'),
              Text('Active Keys: ${encryptionReport['activeKeys']}'),
              Text('Expired Keys: ${encryptionReport['expiredKeys']}'),
              Text('Key Aliases: ${encryptionReport['aliases']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _logToExternalSecuritySystem(SecurityEvent event) {
    // Implement integration with external security systems
    // Examples: Splunk, ELK Stack, Azure Sentinel, etc.
    _logger.info('Logging to external security system: ${event.toMap()}');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.blue),
    );
  }

  @override
  void dispose() {
    // Clean up security resources
    _auditManager.dispose();
    _encryptionManager.dispose();
    super.dispose();
  }
}
```

## Enterprise Security Configuration

```dart
// Enterprise-grade security configuration
class EnterpriseSecurityConfig {
  static SecurityPolicy createEnterprisePolicy() {
    return SecurityPolicy(
      maxFailedAttempts: 3, // Strict authentication
      lockoutDuration: Duration(hours: 1), // Longer lockout
      sessionTimeout: Duration(hours: 2), // Shorter sessions
      passwordMinLength: 16, // Strong passwords
      requireStrongPasswords: true,
      auditRetention: Duration(days: 2555), // 7 years for compliance
      blockedActions: [
        'admin_delete',
        'bulk_export',
        'system_config_change',
        'user_privilege_escalation',
      ],
      riskThresholds: {
        'low': 15,      // Lower thresholds
        'medium': 30,
        'high': 60,
        'critical': 80,
      },
      enableRealTimeMonitoring: true,
      maxConcurrentSessions: 1, // Single session per user
    );
  }

  static void initializeEncryption() {
    EncryptionManager.instance.initialize(
      minKeyLength: 256, // AES-256 minimum
      keyRotationInterval: Duration(days: 30), // Monthly rotation
      requireChecksums: true, // Always verify integrity
    );
  }

  static void setupComplianceLogging() {
    // Setup for SOX compliance
    _setupSOXCompliance();
    
    // Setup for HIPAA compliance
    _setupHIPAACompliance();
    
    // Setup for PCI DSS compliance
    _setupPCIDSSCompliance();
  }

  static void _setupSOXCompliance() {
    EnhancedTypedEventSystem.instance.listen<SecurityEvent>((event) {
      if (event.eventType_ == 'financial_data_access') {
        // Log to SOX audit trail
        _logSOXEvent(event);
      }
    });
  }

  static void _setupHIPAACompliance() {
    EnhancedTypedEventSystem.instance.listen<SecurityEvent>((event) {
      if (event.eventType_ == 'healthcare_data_access') {
        // Log to HIPAA audit trail
        _logHIPAAEvent(event);
      }
    });
  }

  static void _setupPCIDSSCompliance() {
    EnhancedTypedEventSystem.instance.listen<SecurityEvent>((event) {
      if (event.eventType_ == 'payment_data_access') {
        // Log to PCI DSS audit trail
        _logPCIDSSEvent(event);
      }
    });
  }

  static void _logSOXEvent(SecurityEvent event) {
    // Implement SOX-specific logging
    final soxLog = {
      'compliance_type': 'SOX',
      'event_id': DateTime.now().millisecondsSinceEpoch.toString(),
      'user_id': event.userId,
      'action': event.eventType_,
      'timestamp': event.timestamp.toIso8601String(),
      'severity': event.severity.name,
      'details': event.details,
    };
    
    // Send to compliance logging system
    _sendToComplianceSystem('SOX', soxLog);
  }

  static void _logHIPAAEvent(SecurityEvent event) {
    // Implement HIPAA-specific logging
    final hipaaLog = {
      'compliance_type': 'HIPAA',
      'event_id': DateTime.now().millisecondsSinceEpoch.toString(),
      'covered_entity': 'YourOrganization',
      'user_id': event.userId,
      'action': event.eventType_,
      'timestamp': event.timestamp.toIso8601String(),
      'phi_involved': event.details['phi_involved'] ?? false,
      'details': event.details,
    };
    
    // Send to compliance logging system
    _sendToComplianceSystem('HIPAA', hipaaLog);
  }

  static void _logPCIDSSEvent(SecurityEvent event) {
    // Implement PCI DSS-specific logging
    final pciLog = {
      'compliance_type': 'PCI_DSS',
      'event_id': DateTime.now().millisecondsSinceEpoch.toString(),
      'user_id': event.userId,
      'action': event.eventType_,
      'timestamp': event.timestamp.toIso8601String(),
      'cardholder_data_involved': event.details['cardholder_data'] ?? false,
      'details': event.details,
    };
    
    // Send to compliance logging system
    _sendToComplianceSystem('PCI_DSS', pciLog);
  }

  static void _sendToComplianceSystem(String type, Map<String, dynamic> log) {
    // Implement sending to external compliance system
    // Examples: Splunk, LogRhythm, IBM QRadar
    print('Compliance Log [$type]: ${jsonEncode(log)}');
  }
}
```

## Multi-Factor Authentication Example

```dart
class MFASecurityExample {
  final SecurityAuditManager _auditManager = SecurityAuditManager.instance;
  final EncryptionManager _encryptionManager = EncryptionManager.instance;

  Future<bool> authenticateWithMFA(String userId, String password, String mfaToken) async {
    try {
      // Step 1: Verify primary credentials
      bool primaryAuth = await _verifyPrimaryCredentials(userId, password);
      if (!primaryAuth) {
        _auditManager.checkAuthenticationAttempt(userId, false, metadata: {
          'step': 'primary_auth',
          'method': 'password',
          'failure_reason': 'invalid_credentials',
        });
        return false;
      }

      // Step 2: Verify MFA token
      bool mfaAuth = await _verifyMFAToken(userId, mfaToken);
      if (!mfaAuth) {
        _auditManager.checkAuthenticationAttempt(userId, false, metadata: {
          'step': 'mfa_auth',
          'method': 'totp',
          'failure_reason': 'invalid_token',
        });
        return false;
      }

      // Step 3: Check additional security factors
      bool additionalChecks = await _performAdditionalSecurityChecks(userId);
      if (!additionalChecks) {
        _auditManager.checkAuthenticationAttempt(userId, false, metadata: {
          'step': 'additional_checks',
          'failure_reason': 'security_violation',
        });
        return false;
      }

      // Success - log comprehensive authentication event
      _auditManager.checkAuthenticationAttempt(userId, true, metadata: {
        'authentication_type': 'MFA',
        'factors_verified': ['password', 'totp'],
        'device_id': await _getDeviceId(),
        'location': await _getLocation(),
        'risk_score': await _calculateAuthRiskScore(userId),
      });

      return true;
    } catch (e) {
      _auditManager.logSecurityEvent(SecurityAuditEvent(
        eventId: _auditManager.generateEventId(),
        type: SecurityEventType.authentication,
        userId: userId,
        action: 'mfa_authentication_error',
        resource: 'authentication_system',
        success: false,
        reason: e.toString(),
        riskScore: 75,
      ));
      return false;
    }
  }

  Future<bool> _verifyPrimaryCredentials(String userId, String password) async {
    // Implement password verification
    await Future.delayed(Duration(milliseconds: 100));
    return password.isNotEmpty && password.length >= 8;
  }

  Future<bool> _verifyMFAToken(String userId, String token) async {
    // Implement TOTP verification
    await Future.delayed(Duration(milliseconds: 50));
    return token.length == 6 && RegExp(r'^\d{6}$').hasMatch(token);
  }

  Future<bool> _performAdditionalSecurityChecks(String userId) async {
    // Check user risk assessment
    Map<String, dynamic> riskAssessment = _auditManager.getUserRiskAssessment(userId);
    if (riskAssessment['riskScore'] > 80) {
      return false; // High-risk user
    }

    // Check for suspicious patterns
    List<SecurityAuditEvent> recentEvents = _auditManager.getUserAuditEvents(userId, limit: 10);
    int recentFailures = recentEvents
        .where((e) => e.type == SecurityEventType.authentication && !e.success)
        .length;
    
    return recentFailures < 3; // Allow if less than 3 recent failures
  }

  Future<String> _getDeviceId() async {
    // Get device identifier
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _getLocation() async {
    // Get user location (IP-based geolocation, GPS, etc.)
    return 'San Francisco, CA';
  }

  Future<int> _calculateAuthRiskScore(String userId) async {
    // Calculate authentication risk based on various factors
    int riskScore = 0;
    
    // Time-based risk (login outside normal hours)
    int hour = DateTime.now().hour;
    if (hour < 6 || hour > 22) {
      riskScore += 15;
    }
    
    // Location-based risk (unusual location)
    // Implementation would check against user's normal locations
    
    // Device-based risk (new/unknown device)
    // Implementation would check device fingerprinting
    
    return riskScore;
  }
}
```

This comprehensive security example demonstrates:

1. **Complete Security Setup**: Full initialization of security systems
2. **Authentication Flow**: Secure user authentication with audit logging
3. **Data Protection**: Encryption/decryption of sensitive data
4. **Security Monitoring**: Real-time event handling and alerting
5. **Key Management**: Secure key generation, rotation, and lifecycle
6. **Compliance**: Enterprise-grade compliance configurations
7. **Multi-Factor Authentication**: Advanced MFA implementation
8. **Risk Assessment**: Dynamic risk scoring and assessment
9. **Audit Reporting**: Comprehensive security reporting
10. **Error Handling**: Robust security exception handling