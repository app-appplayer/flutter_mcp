import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import '../utils/logger.dart';

/// Network security implementation for TLS certificate pinning and request signing
class NetworkSecurity {
  static final Logger _logger = Logger('flutter_mcp.network_security');

  // Singleton instance
  static final NetworkSecurity _instance = NetworkSecurity._internal();
  static NetworkSecurity get instance => _instance;

  // Certificate fingerprints for pinning
  final Set<String> _pinnedCertificates = {};

  // API key for request signing
  String? _apiKey;

  // Request signing secret
  String? _signingSecret;

  NetworkSecurity._internal();

  /// Configure network security with API key and signing secret
  void configure({
    required String apiKey,
    required String signingSecret,
    List<String>? pinnedCertificates,
  }) {
    _apiKey = apiKey;
    _signingSecret = signingSecret;

    if (pinnedCertificates != null) {
      _pinnedCertificates.clear();
      _pinnedCertificates.addAll(pinnedCertificates);
    }

    _logger.info(
        'Network security configured with ${_pinnedCertificates.length} pinned certificates');
  }

  /// Add a certificate fingerprint for pinning
  void addPinnedCertificate(String fingerprint) {
    _pinnedCertificates.add(fingerprint.toUpperCase());
    _logger.fine('Added pinned certificate: ${fingerprint.substring(0, 8)}...');
  }

  /// Remove a certificate fingerprint
  void removePinnedCertificate(String fingerprint) {
    _pinnedCertificates.remove(fingerprint.toUpperCase());
    _logger
        .fine('Removed pinned certificate: ${fingerprint.substring(0, 8)}...');
  }

  /// Verify certificate fingerprint
  bool verifyCertificate(String fingerprint) {
    if (_pinnedCertificates.isEmpty) {
      // No pinning configured, allow all certificates
      return true;
    }

    final normalized = fingerprint.toUpperCase();
    final isValid = _pinnedCertificates.contains(normalized);

    if (!isValid) {
      _logger.warning(
          'Certificate verification failed: ${fingerprint.substring(0, 8)}...');
    }

    return isValid;
  }

  /// Sign a request with HMAC-SHA256
  Map<String, String> signRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    if (_apiKey == null || _signingSecret == null) {
      throw StateError('Network security not configured');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _generateNonce();

    // Create canonical request
    final canonicalRequest = _createCanonicalRequest(
      method: method,
      path: path,
      timestamp: timestamp,
      nonce: nonce,
      body: body,
    );

    // Generate signature
    final signature = _generateSignature(canonicalRequest);

    // Create signed headers
    final signedHeaders = <String, String>{
      'X-API-Key': _apiKey!,
      'X-Timestamp': timestamp,
      'X-Nonce': nonce,
      'X-Signature': signature,
    };

    // Add custom headers if provided
    if (headers != null) {
      signedHeaders.addAll(headers);
    }

    return signedHeaders;
  }

  /// Verify a signed request
  bool verifyRequest({
    required String method,
    required String path,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) {
    if (_signingSecret == null) {
      throw StateError('Network security not configured');
    }

    // Extract required headers
    final apiKey = headers['X-API-Key'] ?? headers['x-api-key'];
    final timestamp = headers['X-Timestamp'] ?? headers['x-timestamp'];
    final nonce = headers['X-Nonce'] ?? headers['x-nonce'];
    final signature = headers['X-Signature'] ?? headers['x-signature'];

    if (apiKey == null ||
        timestamp == null ||
        nonce == null ||
        signature == null) {
      _logger.warning('Missing required headers for request verification');
      return false;
    }

    // Verify API key
    if (apiKey != _apiKey) {
      _logger.warning('Invalid API key');
      return false;
    }

    // Verify timestamp (allow 5 minute window)
    final requestTime = int.tryParse(timestamp);
    if (requestTime == null) {
      _logger.warning('Invalid timestamp format');
      return false;
    }

    final currentTime = DateTime.now().millisecondsSinceEpoch;
    final timeDiff = (currentTime - requestTime).abs();
    if (timeDiff > 300000) {
      // 5 minutes in milliseconds
      _logger.warning('Request timestamp outside allowed window');
      return false;
    }

    // Create canonical request
    final canonicalRequest = _createCanonicalRequest(
      method: method,
      path: path,
      timestamp: timestamp,
      nonce: nonce,
      body: body,
    );

    // Verify signature
    final expectedSignature = _generateSignature(canonicalRequest);
    final isValid = signature == expectedSignature;

    if (!isValid) {
      _logger.warning('Invalid request signature');
    }

    return isValid;
  }

  /// Create canonical request string for signing
  String _createCanonicalRequest({
    required String method,
    required String path,
    required String timestamp,
    required String nonce,
    Map<String, dynamic>? body,
  }) {
    final parts = <String>[
      method.toUpperCase(),
      path,
      timestamp,
      nonce,
    ];

    // Add body hash if present
    if (body != null && body.isNotEmpty) {
      final bodyJson = jsonEncode(body);
      final bodyHash = crypto.sha256.convert(utf8.encode(bodyJson)).toString();
      parts.add(bodyHash);
    }

    return parts.join('\n');
  }

  /// Generate HMAC-SHA256 signature
  String _generateSignature(String data) {
    if (_signingSecret == null) {
      throw StateError('Signing secret not configured');
    }

    final key = utf8.encode(_signingSecret!);
    final bytes = utf8.encode(data);

    final hmac = crypto.Hmac(crypto.sha256, key);
    final digest = hmac.convert(bytes);

    return base64Url.encode(digest.bytes);
  }

  /// Generate a cryptographically secure random nonce
  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Clear all security configuration
  void clear() {
    _apiKey = null;
    _signingSecret = null;
    _pinnedCertificates.clear();
    _logger.info('Network security configuration cleared');
  }
}

/// Certificate pinning interceptor for HTTP clients
class CertificatePinningInterceptor {
  final NetworkSecurity _security = NetworkSecurity.instance;

  /// Verify server certificate
  bool onBadCertificate(cert, String host, int port) {
    try {
      // Calculate certificate fingerprint (SHA-256)
      final der = cert.der;
      final digest = crypto.sha256.convert(der);
      final fingerprint = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();

      // Verify against pinned certificates
      final isValid = _security.verifyCertificate(fingerprint);

      if (!isValid) {
        Logger('flutter_mcp.certificate_pinning')
            .warning('Certificate verification failed for $host:$port');
      }

      return isValid;
    } catch (e) {
      Logger('flutter_mcp.certificate_pinning')
          .severe('Error verifying certificate', e);
      return false;
    }
  }
}

/// Request signing interceptor for HTTP clients
class RequestSigningInterceptor {
  final NetworkSecurity _security = NetworkSecurity.instance;

  /// Add signature headers to request
  Map<String, String> signRequest({
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    return _security.signRequest(
      method: method,
      path: uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : ''),
      body: body,
      headers: headers,
    );
  }

  /// Verify incoming request signature
  bool verifyRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) {
    return _security.verifyRequest(
      method: method,
      path: uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : ''),
      headers: headers,
      body: body,
    );
  }
}
