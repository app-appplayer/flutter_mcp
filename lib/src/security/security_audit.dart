import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../events/enhanced_typed_event_system.dart';
import '../events/event_models.dart';

/// Security event types for audit logging
enum SecurityEventType {
  authentication,
  authorization,
  dataAccess,
  configurationChange,
  suspicious,
  breach,
  compliance,
}

/// Security audit event
class SecurityAuditEvent {
  final String eventId;
  final SecurityEventType type;
  final String? userId;
  final String? sessionId;
  final String action;
  final String resource;
  final bool success;
  final String? reason;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;
  final String? ipAddress;
  final String? userAgent;
  final int riskScore;

  SecurityAuditEvent({
    required this.eventId,
    required this.type,
    this.userId,
    this.sessionId,
    required this.action,
    required this.resource,
    required this.success,
    this.reason,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
    this.ipAddress,
    this.userAgent,
    this.riskScore = 0,
  }) : metadata = metadata ?? {},
       timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'type': type.name,
    'userId': userId,
    'sessionId': sessionId,
    'action': action,
    'resource': resource,
    'success': success,
    'reason': reason,
    'metadata': metadata,
    'timestamp': timestamp.toIso8601String(),
    'ipAddress': ipAddress,
    'userAgent': userAgent,
    'riskScore': riskScore,
  };

  factory SecurityAuditEvent.fromJson(Map<String, dynamic> json) => SecurityAuditEvent(
    eventId: json['eventId'] as String,
    type: SecurityEventType.values.byName(json['type'] as String),
    userId: json['userId'] as String?,
    sessionId: json['sessionId'] as String?,
    action: json['action'] as String,
    resource: json['resource'] as String,
    success: json['success'] as bool,
    reason: json['reason'] as String?,
    metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    timestamp: DateTime.parse(json['timestamp'] as String),
    ipAddress: json['ipAddress'] as String?,
    userAgent: json['userAgent'] as String?,
    riskScore: json['riskScore'] as int? ?? 0,
  );
}

/// Security policy configuration
class SecurityPolicy {
  final int maxFailedAttempts;
  final Duration lockoutDuration;
  final Duration sessionTimeout;
  final int passwordMinLength;
  final bool requireStrongPasswords;
  final Duration auditRetention;
  final List<String> blockedActions;
  final Map<String, int> riskThresholds;
  final bool enableRealTimeMonitoring;
  final int maxConcurrentSessions;

  SecurityPolicy({
    this.maxFailedAttempts = 5,
    this.lockoutDuration = const Duration(minutes: 15),
    this.sessionTimeout = const Duration(hours: 8),
    this.passwordMinLength = 12,
    this.requireStrongPasswords = true,
    this.auditRetention = const Duration(days: 90),
    this.blockedActions = const [],
    Map<String, int>? riskThresholds,
    this.enableRealTimeMonitoring = true,
    this.maxConcurrentSessions = 5,
  }) : riskThresholds = riskThresholds ?? {
    'low': 25,
    'medium': 50,
    'high': 75,
    'critical': 90,
  };
}

/// Security audit manager
class SecurityAuditManager {
  final Logger _logger = Logger('flutter_mcp.security_audit');
  final EnhancedTypedEventSystem _eventSystem = EnhancedTypedEventSystem.instance;
  
  // Audit event storage
  final List<SecurityAuditEvent> _auditLog = [];
  final Map<String, List<SecurityAuditEvent>> _userAuditLog = {};
  
  // Security monitoring
  final Map<String, int> _failedAttempts = {};
  final Map<String, DateTime> _lockoutTimes = {};
  final Map<String, List<String>> _activeSessions = {};
  
  // Security policy
  SecurityPolicy _policy = SecurityPolicy();
  
  // Risk assessment cache
  final Map<String, _RiskAssessment> _riskCache = {};
  
  // Singleton instance
  static SecurityAuditManager? _instance;
  
  /// Get singleton instance
  static SecurityAuditManager get instance {
    _instance ??= SecurityAuditManager._internal();
    return _instance!;
  }
  
  SecurityAuditManager._internal();
  
  /// Initialize security audit manager
  void initialize({SecurityPolicy? policy}) {
    if (policy != null) {
      _policy = policy;
    }
    
    // Start periodic cleanup
    _startPeriodicCleanup();
    
    _logger.info('Security audit manager initialized');
  }
  
  /// Update security policy
  void updatePolicy(SecurityPolicy policy) {
    _policy = policy;
    _logger.info('Security policy updated');
    
    // Log policy change
    logSecurityEvent(SecurityAuditEvent(
      eventId: generateEventId(),
      type: SecurityEventType.configurationChange,
      action: 'policy_update',
      resource: 'security_policy',
      success: true,
      metadata: {
        'maxFailedAttempts': policy.maxFailedAttempts,
        'sessionTimeout': policy.sessionTimeout.inMinutes,
        'auditRetention': policy.auditRetention.inDays,
      },
    ));
  }
  
  /// Log security event
  void logSecurityEvent(SecurityAuditEvent event) {
    // Add to audit log
    _auditLog.add(event);
    
    // Add to user-specific log
    if (event.userId != null) {
      _userAuditLog.putIfAbsent(event.userId!, () => []).add(event);
    }
    
    // Publish event for real-time monitoring
    if (_policy.enableRealTimeMonitoring) {
      _eventSystem.publish(SecurityEvent(
        eventType_: event.type.name,
        severity: _calculateSeverity(event),
        message: '${event.action} on ${event.resource}',
        userId: event.userId,
        details: event.toJson(),
      ));
    }
    
    // Check for security violations
    _checkSecurityViolations(event);
    
    // Update risk assessment
    if (event.userId != null) {
      _updateRiskAssessment(event.userId!, event);
    }
    
    _logger.info('Security event logged: ${event.eventId}');
  }
  
  /// Check authentication attempt
  bool checkAuthenticationAttempt(String userId, bool success, {Map<String, dynamic>? metadata}) {
    final event = SecurityAuditEvent(
      eventId: generateEventId(),
      type: SecurityEventType.authentication,
      userId: userId,
      action: 'login_attempt',
      resource: 'authentication_system',
      success: success,
      metadata: metadata ?? {},
    );
    
    logSecurityEvent(event);
    
    if (success) {
      // Reset failed attempts on success
      _failedAttempts.remove(userId);
      _lockoutTimes.remove(userId);
      return true;
    } else {
      // Track failed attempt
      _failedAttempts[userId] = (_failedAttempts[userId] ?? 0) + 1;
      
      // Check if user should be locked out
      if (_failedAttempts[userId]! >= _policy.maxFailedAttempts) {
        _lockoutTimes[userId] = DateTime.now().add(_policy.lockoutDuration);
        
        logSecurityEvent(SecurityAuditEvent(
          eventId: generateEventId(),
          type: SecurityEventType.suspicious,
          userId: userId,
          action: 'account_lockout',
          resource: 'user_account',
          success: true,
          reason: 'Exceeded maximum failed login attempts',
          riskScore: 75,
        ));
        
        return false;
      }
    }
    
    return true;
  }
  
  /// Check if user is locked out
  bool isUserLockedOut(String userId) {
    final lockoutTime = _lockoutTimes[userId];
    if (lockoutTime == null) return false;
    
    if (DateTime.now().isAfter(lockoutTime)) {
      // Lockout has expired
      _lockoutTimes.remove(userId);
      _failedAttempts.remove(userId);
      return false;
    }
    
    return true;
  }
  
  /// Start user session
  String startSession(String userId, {Map<String, dynamic>? metadata}) {
    // Check concurrent session limit
    final userSessions = _activeSessions[userId] ?? [];
    if (userSessions.length >= _policy.maxConcurrentSessions) {
      // Remove oldest session
      userSessions.removeAt(0);
    }
    
    final sessionId = _generateSessionId();
    _activeSessions.putIfAbsent(userId, () => []).add(sessionId);
    
    logSecurityEvent(SecurityAuditEvent(
      eventId: generateEventId(),
      type: SecurityEventType.authentication,
      userId: userId,
      sessionId: sessionId,
      action: 'session_start',
      resource: 'user_session',
      success: true,
      metadata: metadata ?? {},
    ));
    
    return sessionId;
  }
  
  /// End user session
  void endSession(String userId, String sessionId) {
    _activeSessions[userId]?.remove(sessionId);
    if (_activeSessions[userId]?.isEmpty ?? false) {
      _activeSessions.remove(userId);
    }
    
    logSecurityEvent(SecurityAuditEvent(
      eventId: generateEventId(),
      type: SecurityEventType.authentication,
      userId: userId,
      sessionId: sessionId,
      action: 'session_end',
      resource: 'user_session',
      success: true,
    ));
  }
  
  /// Check data access authorization
  bool checkDataAccess(String userId, String resource, String action, {Map<String, dynamic>? metadata}) {
    // Check if action is blocked
    if (_policy.blockedActions.contains(action)) {
      logSecurityEvent(SecurityAuditEvent(
        eventId: generateEventId(),
        type: SecurityEventType.authorization,
        userId: userId,
        action: action,
        resource: resource,
        success: false,
        reason: 'Action blocked by security policy',
        riskScore: 50,
        metadata: metadata ?? {},
      ));
      return false;
    }
    
    // Log successful access
    logSecurityEvent(SecurityAuditEvent(
      eventId: generateEventId(),
      type: SecurityEventType.dataAccess,
      userId: userId,
      action: action,
      resource: resource,
      success: true,
      metadata: metadata ?? {},
    ));
    
    return true;
  }
  
  /// Get user risk assessment
  Map<String, dynamic> getUserRiskAssessment(String userId) {
    final assessment = _riskCache[userId];
    if (assessment == null) {
      return {
        'riskScore': 0,
        'riskLevel': 'low',
        'lastUpdated': null,
        'factors': <String>[],
      };
    }
    
    return {
      'riskScore': assessment.score,
      'riskLevel': _getRiskLevel(assessment.score),
      'lastUpdated': assessment.lastUpdated.toIso8601String(),
      'factors': assessment.factors,
    };
  }
  
  /// Get audit events for user
  List<SecurityAuditEvent> getUserAuditEvents(String userId, {int? limit}) {
    final events = _userAuditLog[userId] ?? [];
    if (limit != null && events.length > limit) {
      return events.sublist(events.length - limit);
    }
    return List.unmodifiable(events);
  }
  
  /// Get all audit events
  List<SecurityAuditEvent> getAllAuditEvents({int? limit}) {
    if (limit != null && _auditLog.length > limit) {
      return _auditLog.sublist(_auditLog.length - limit);
    }
    return List.unmodifiable(_auditLog);
  }
  
  /// Generate security report
  Map<String, dynamic> generateSecurityReport() {
    final now = DateTime.now();
    final last24Hours = now.subtract(Duration(hours: 24));
    final last7Days = now.subtract(Duration(days: 7));
    
    final recent24h = _auditLog.where((e) => e.timestamp.isAfter(last24Hours)).toList();
    final recent7d = _auditLog.where((e) => e.timestamp.isAfter(last7Days)).toList();
    
    return {
      'generatedAt': now.toIso8601String(),
      'totalEvents': _auditLog.length,
      'events24h': recent24h.length,
      'events7d': recent7d.length,
      'failedLogins24h': recent24h.where((e) => 
        e.type == SecurityEventType.authentication && !e.success).length,
      'suspiciousEvents24h': recent24h.where((e) => 
        e.type == SecurityEventType.suspicious).length,
      'lockedOutUsers': _lockoutTimes.length,
      'activeSessions': _activeSessions.values.fold<int>(0, (sum, sessions) => sum + sessions.length),
      'highRiskUsers': _riskCache.entries.where((e) => e.value.score > _policy.riskThresholds['high']!).length,
      'eventsByType': _getEventsByType(recent24h),
      'topRiskyUsers': _getTopRiskyUsers(5),
    };
  }
  
  /// Check security violations
  void _checkSecurityViolations(SecurityAuditEvent event) {
    // Check for suspicious patterns
    if (event.riskScore > _policy.riskThresholds['high']!) {
      _eventSystem.publish(SecurityAlert(
        severity: _calculateSeverity(event),  // Use proper severity calculation
        title: 'High Risk Security Event',
        message: 'Event ${event.eventId} has high risk score: ${event.riskScore}',
        details: event.toJson(),
      ));
    }
    
    // Check for rapid failed attempts
    if (event.type == SecurityEventType.authentication && !event.success && event.userId != null) {
      final recentFailures = _userAuditLog[event.userId!]
          ?.where((e) => e.type == SecurityEventType.authentication && 
                        !e.success &&
                        DateTime.now().difference(e.timestamp).inMinutes < 5)
          .length ?? 0;
      
      if (recentFailures >= 3) {
        logSecurityEvent(SecurityAuditEvent(
          eventId: generateEventId(),
          type: SecurityEventType.suspicious,
          userId: event.userId,
          action: 'rapid_failed_attempts',
          resource: 'authentication_system',
          success: true,
          reason: 'Multiple failed login attempts in short time',
          riskScore: 60,
        ));
      }
    }
  }
  
  /// Update risk assessment for user
  void _updateRiskAssessment(String userId, SecurityAuditEvent event) {
    final existing = _riskCache[userId] ?? _RiskAssessment(userId: userId);
    
    // Calculate new risk score based on event
    var additionalRisk = 0;
    final factors = <String>[];
    
    if (!event.success) {
      additionalRisk += 10;
      factors.add('failed_operation');
    }
    
    if (event.type == SecurityEventType.suspicious) {
      additionalRisk += 25;
      factors.add('suspicious_activity');
    }
    
    if (event.riskScore > 0) {
      additionalRisk += (event.riskScore * 0.5).round();
      factors.add('high_risk_event');
    }
    
    // Time-based decay
    final hoursSinceLastUpdate = DateTime.now().difference(existing.lastUpdated).inHours;
    final decayFactor = math.max(0.8, 1.0 - (hoursSinceLastUpdate * 0.01));
    
    final newScore = math.min(100, ((existing.score * decayFactor) + additionalRisk).round());
    
    _riskCache[userId] = _RiskAssessment(
      userId: userId,
      score: newScore,
      factors: [...existing.factors, ...factors].take(10).toList(),
      lastUpdated: DateTime.now(),
    );
  }
  
  /// Calculate event severity
  AlertSeverity _calculateSeverity(SecurityAuditEvent event) {
    if (event.riskScore >= _policy.riskThresholds['critical']!) {
      return AlertSeverity.critical;
    } else if (event.riskScore >= _policy.riskThresholds['high']!) {
      return AlertSeverity.high;
    } else if (event.riskScore >= _policy.riskThresholds['medium']!) {
      return AlertSeverity.medium;
    } else if (!event.success || event.type == SecurityEventType.suspicious) {
      return AlertSeverity.low;
    }
    return AlertSeverity.info;
  }
  
  /// Get risk level string
  String _getRiskLevel(int score) {
    if (score >= _policy.riskThresholds['critical']!) return 'critical';
    if (score >= _policy.riskThresholds['high']!) return 'high';
    if (score >= _policy.riskThresholds['medium']!) return 'medium';
    return 'low';
  }
  
  /// Get events by type for reporting
  Map<String, int> _getEventsByType(List<SecurityAuditEvent> events) {
    final result = <String, int>{};
    for (final event in events) {
      result[event.type.name] = (result[event.type.name] ?? 0) + 1;
    }
    return result;
  }
  
  /// Get top risky users
  List<Map<String, dynamic>> _getTopRiskyUsers(int count) {
    final sorted = _riskCache.entries.toList()
      ..sort((a, b) => b.value.score.compareTo(a.value.score));
    
    return sorted.take(count).map((entry) => {
      'userId': entry.key,
      'riskScore': entry.value.score,
      'riskLevel': _getRiskLevel(entry.value.score),
      'factors': entry.value.factors,
    }).toList();
  }
  
  /// Start periodic cleanup
  void _startPeriodicCleanup() {
    Timer.periodic(Duration(hours: 1), (_) {
      _cleanupOldEvents();
      _cleanupExpiredLockouts();
    });
  }
  
  /// Clean up old audit events
  void _cleanupOldEvents() {
    final cutoff = DateTime.now().subtract(_policy.auditRetention);
    
    _auditLog.removeWhere((event) => event.timestamp.isBefore(cutoff));
    
    for (final userEvents in _userAuditLog.values) {
      userEvents.removeWhere((event) => event.timestamp.isBefore(cutoff));
    }
    
    // Remove empty user logs
    _userAuditLog.removeWhere((_, events) => events.isEmpty);
  }
  
  /// Clean up expired lockouts
  void _cleanupExpiredLockouts() {
    final now = DateTime.now();
    _lockoutTimes.removeWhere((_, lockoutTime) => now.isAfter(lockoutTime));
  }
  
  /// Generate unique event ID
  String generateEventId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random().nextInt(1000000);
    return 'sec_${timestamp}_$random';
  }
  
  /// Generate unique session ID
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random().nextInt(1000000);
    return 'sess_${timestamp}_$random';
  }
  
  /// Dispose resources
  void dispose() {
    _auditLog.clear();
    _userAuditLog.clear();
    _failedAttempts.clear();
    _lockoutTimes.clear();
    _activeSessions.clear();
    _riskCache.clear();
  }
}

/// Risk assessment for a user
class _RiskAssessment {
  final String userId;
  final int score;
  final List<String> factors;
  final DateTime lastUpdated;
  
  _RiskAssessment({
    required this.userId,
    this.score = 0,
    this.factors = const [],
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();
}