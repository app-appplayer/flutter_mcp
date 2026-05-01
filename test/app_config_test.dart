import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/config/app_config.dart';

void main() {
  // AppConfig is a singleton with global state. Reset between tests.
  setUp(() {
    AppConfig.instance.reset();
  });

  group('AppConfig — defaults + get', () {
    test('exposes nested defaults via dot notation', () {
      final cfg = AppConfig.instance;
      expect(cfg.get<int>('async.defaultMaxRetries'), 3);
      expect(cfg.get<int>('async.defaultInitialDelay'), 500);
      expect(cfg.get<double>('async.defaultBackoffFactor'), 2.0);
      expect(cfg.get<int>('memory.monitoringInterval'), 30000);
    });

    test('returns defaultValue when key is missing', () {
      final cfg = AppConfig.instance;
      expect(cfg.get<int>('nonexistent', defaultValue: 99), 99);
      expect(cfg.get<String>('nope.also.missing', defaultValue: 'fallback'),
          'fallback');
    });

    test('throws ConfigException when key missing and no default', () {
      final cfg = AppConfig.instance;
      expect(
        () => cfg.get<int>('definitely.missing'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws ConfigException on type mismatch without default', () {
      final cfg = AppConfig.instance;
      expect(
        () => cfg.get<String>('async.defaultMaxRetries'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('returns defaultValue on type mismatch when default provided', () {
      final cfg = AppConfig.instance;
      // defaultMaxRetries is int 3, ask for String with fallback.
      expect(cfg.get<String>('async.defaultMaxRetries', defaultValue: 'x'), 'x');
    });
  });

  group('AppConfig — set / containsKey / toMap / toJson', () {
    test('set creates a nested key', () {
      final cfg = AppConfig.instance;
      cfg.set('custom.feature.flag', true);
      expect(cfg.get<bool>('custom.feature.flag'), isTrue);
    });

    test('containsKey returns true for present key', () {
      expect(AppConfig.instance.containsKey('async.defaultMaxRetries'), isTrue);
    });

    test('containsKey returns false for missing key', () {
      expect(AppConfig.instance.containsKey('does.not.exist'), isFalse);
    });

    test('toMap returns a copy of the configuration', () {
      final cfg = AppConfig.instance;
      cfg.set('marker', 'A');
      final m = cfg.toMap();
      m['marker'] = 'B'; // mutate copy
      expect(cfg.get<String>('marker'), 'A');
    });

    test('toJson produces parseable JSON containing keys', () {
      final json = AppConfig.instance.toJson();
      expect(json, isNotEmpty);
      expect(json, contains('async'));
    });
  });

  group('AppConfig.initialize', () {
    test('applies overrides on initialize', () async {
      AppConfig.instance.reset();
      await AppConfig.initialize(overrides: {
        'async': {'defaultMaxRetries': 9},
      });
      expect(AppConfig.instance.get<int>('async.defaultMaxRetries'), 9);
      expect(AppConfig.instance.isInitialized, isTrue);
    });

    test('subsequent initialize calls are no-ops once initialized', () async {
      AppConfig.instance.reset();
      await AppConfig.initialize(
        overrides: {'async': {'defaultMaxRetries': 100}},
      );
      await AppConfig.initialize(
        overrides: {'async': {'defaultMaxRetries': 200}},
      );
      expect(AppConfig.instance.get<int>('async.defaultMaxRetries'), 100);
    });
  });

  group('AppConfig.scoped + ScopedConfig', () {
    test('scoped get/set/containsKey/toMap', () {
      final cfg = AppConfig.instance;
      final scope = cfg.scoped('memory');
      expect(scope.get<int>('monitoringInterval'), 30000);

      scope.set('threshold', 256);
      expect(scope.get<int>('threshold'), 256);
      expect(cfg.get<int>('memory.threshold'), 256);

      expect(scope.containsKey('threshold'), isTrue);
      expect(scope.containsKey('absent'), isFalse);

      final scopeMap = scope.toMap();
      expect(scopeMap['monitoringInterval'], 30000);
      expect(scopeMap['threshold'], 256);
    });

    test('scoped getDuration converts milliseconds', () {
      final cfg = AppConfig.instance;
      cfg.set('timeouts.request', 1500);
      final scope = cfg.scoped('timeouts');
      expect(scope.getDuration('request'),
          const Duration(milliseconds: 1500));
    });

    test('scoped getDuration uses defaultValue when key missing', () {
      final scope = AppConfig.instance.scoped('absent_scope');
      expect(
        scope.getDuration('any', defaultValue: const Duration(seconds: 2)),
        const Duration(seconds: 2),
      );
    });

    test('scoped toMap is empty when prefix has no entries', () {
      final scope = AppConfig.instance.scoped('completely_empty');
      expect(scope.toMap(), isEmpty);
    });
  });

  group('AppConfig.getXxxConfig typed accessors', () {
    test('getMemoryConfig + getLoggingConfig + getPerformanceConfig + getSecurityConfig + getPlatformConfig',
        () {
      final cfg = AppConfig.instance;
      // These should round-trip via TypedAppConfig types without throwing.
      expect(cfg.getMemoryConfig(), isNotNull);
      expect(cfg.getLoggingConfig(), isNotNull);
      expect(cfg.getPerformanceConfig(), isNotNull);
      expect(cfg.getSecurityConfig(), isNotNull);
      expect(cfg.getPlatformConfig(), isNotNull);
      expect(cfg.getTypedConfig(), isNotNull);
    });
  });

  group('ConfigException', () {
    test('toString embeds the message', () {
      const e = ConfigException('boom');
      expect(e.toString(), contains('boom'));
    });
  });
}
