import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/config/config_parser.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

enum _Color { red, green, blue }

void main() {
  group('ConfigParser.getString', () {
    test('returns value when present', () {
      final p = ConfigParser({'name': 'X'});
      expect(p.getString('name'), 'X');
    });

    test('returns defaultValue when missing and not required', () {
      final p = ConfigParser({});
      expect(p.getString('name', defaultValue: 'fallback'), 'fallback');
    });

    test('returns empty string when missing and no default', () {
      final p = ConfigParser({});
      expect(p.getString('name'), '');
    });

    test('throws when missing and required', () {
      final p = ConfigParser({}, configName: 'cfg');
      expect(
        () => p.getString('name', required: true),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('respects minLength', () {
      final p = ConfigParser({'name': 'ab'});
      expect(
        () => p.getString('name', minLength: 3),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('respects maxLength', () {
      final p = ConfigParser({'name': 'abcdef'});
      expect(
        () => p.getString('name', maxLength: 4),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('respects allowedValues', () {
      final p = ConfigParser({'name': 'banana'});
      expect(
        () => p.getString('name', allowedValues: ['apple', 'orange']),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('passes when allowedValues includes the value', () {
      final p = ConfigParser({'name': 'apple'});
      expect(p.getString('name', allowedValues: ['apple']), 'apple');
    });
  });

  group('ConfigParser.getBool', () {
    test('returns true/false bool values', () {
      expect(ConfigParser({'flag': true}).getBool('flag'), isTrue);
      expect(ConfigParser({'flag': false}).getBool('flag'), isFalse);
    });

    test('parses string variants', () {
      expect(ConfigParser({'flag': 'true'}).getBool('flag'), isTrue);
      expect(ConfigParser({'flag': 'TRUE'}).getBool('flag'), isTrue);
      expect(ConfigParser({'flag': '1'}).getBool('flag'), isTrue);
      expect(ConfigParser({'flag': 'false'}).getBool('flag'), isFalse);
      expect(ConfigParser({'flag': '0'}).getBool('flag'), isFalse);
    });

    test('parses int as truthy', () {
      expect(ConfigParser({'flag': 1}).getBool('flag'), isTrue);
      expect(ConfigParser({'flag': 0}).getBool('flag'), isFalse);
      expect(ConfigParser({'flag': -1}).getBool('flag'), isTrue);
    });

    test('throws on invalid string', () {
      expect(
        () => ConfigParser({'flag': 'yes'}).getBool('flag'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('throws on invalid type', () {
      expect(
        () => ConfigParser({'flag': []}).getBool('flag'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('returns defaultValue when missing', () {
      expect(ConfigParser({}).getBool('flag', defaultValue: true), isTrue);
      expect(ConfigParser({}).getBool('flag'), isFalse);
    });

    test('throws when missing and required', () {
      expect(
        () => ConfigParser({}).getBool('flag', required: true),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigParser.getInt', () {
    test('returns int value as-is', () {
      expect(ConfigParser({'n': 42}).getInt('n'), 42);
    });

    test('truncates double', () {
      expect(ConfigParser({'n': 3.7}).getInt('n'), 3);
    });

    test('parses string', () {
      expect(ConfigParser({'n': '15'}).getInt('n'), 15);
    });

    test('throws on invalid string', () {
      expect(
        () => ConfigParser({'n': 'abc'}).getInt('n'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('throws on invalid type', () {
      expect(
        () => ConfigParser({'n': []}).getInt('n'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('respects min', () {
      expect(
        () => ConfigParser({'n': 5}).getInt('n', min: 10),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('respects max', () {
      expect(
        () => ConfigParser({'n': 50}).getInt('n', max: 10),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('returns defaultValue when missing', () {
      expect(ConfigParser({}).getInt('n', defaultValue: 7), 7);
      expect(ConfigParser({}).getInt('n'), 0);
    });

    test('throws when required and missing', () {
      expect(
        () => ConfigParser({}).getInt('n', required: true),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigParser.getDouble', () {
    test('returns double as-is', () {
      expect(ConfigParser({'x': 3.14}).getDouble('x'), 3.14);
    });

    test('promotes int', () {
      expect(ConfigParser({'x': 5}).getDouble('x'), 5.0);
    });

    test('parses string', () {
      expect(ConfigParser({'x': '2.5'}).getDouble('x'), 2.5);
    });

    test('throws on invalid string', () {
      expect(
        () => ConfigParser({'x': 'abc'}).getDouble('x'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('throws on invalid type', () {
      expect(
        () => ConfigParser({'x': []}).getDouble('x'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('respects min and max', () {
      expect(
        () => ConfigParser({'x': 0.5}).getDouble('x', min: 1.0),
        throwsA(isA<MCPConfigurationException>()),
      );
      expect(
        () => ConfigParser({'x': 100.0}).getDouble('x', max: 10.0),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('returns defaultValue when missing', () {
      expect(ConfigParser({}).getDouble('x', defaultValue: 1.5), 1.5);
      expect(ConfigParser({}).getDouble('x'), 0.0);
    });

    test('throws when required and missing', () {
      expect(
        () => ConfigParser({}).getDouble('x', required: true),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigParser.getDuration', () {
    test('parses milliseconds int', () {
      expect(ConfigParser({'t': 500}).getDuration('t'),
          const Duration(milliseconds: 500));
    });

    test('returns default when missing', () {
      expect(
        ConfigParser({}).getDuration('t',
            defaultValue: const Duration(seconds: 1)),
        const Duration(seconds: 1),
      );
    });

    test('respects duration min/max', () {
      expect(
        () => ConfigParser({'t': 50}).getDuration('t',
            min: const Duration(milliseconds: 100)),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigParser.getEnum', () {
    test('parses by name', () {
      final p = ConfigParser({'c': 'green'});
      expect(p.getEnum<_Color>('c', _Color.values), _Color.green);
    });

    test('throws on unknown enum value', () {
      final p = ConfigParser({'c': 'mauve'});
      expect(
        () => p.getEnum<_Color>('c', _Color.values),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('returns defaultValue when missing', () {
      final p = ConfigParser({});
      expect(
        p.getEnum<_Color>('c', _Color.values, defaultValue: _Color.red),
        _Color.red,
      );
    });
  });

  group('ConfigParser.getList', () {
    test('parses list of items', () {
      final p = ConfigParser({'xs': ['a', 'b', 'c']});
      final out = p.getList<String>('xs', (v) => v as String);
      expect(out, ['a', 'b', 'c']);
    });

    test('returns defaultValue when missing', () {
      final p = ConfigParser({});
      expect(p.getList<String>('xs', (v) => v as String, defaultValue: ['x']),
          ['x']);
    });

    test('returns empty list when missing and no default', () {
      final p = ConfigParser({});
      expect(p.getList<String>('xs', (v) => v as String), isEmpty);
    });

    test('throws when missing and required', () {
      final p = ConfigParser({});
      expect(
        () => p.getList<String>('xs', (v) => v as String, required: true),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('throws on non-list value', () {
      final p = ConfigParser({'xs': 'not-a-list'});
      expect(
        () => p.getList<String>('xs', (v) => v as String),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('throws on minLength violation', () {
      final p = ConfigParser({'xs': ['a']});
      expect(
        () => p.getList<String>('xs', (v) => v as String, minLength: 2),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('throws on maxLength violation', () {
      final p = ConfigParser({'xs': ['a', 'b', 'c']});
      expect(
        () => p.getList<String>('xs', (v) => v as String, maxLength: 2),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('wraps item-parser failure', () {
      final p = ConfigParser({'xs': ['a', 1]});
      expect(
        () => p.getList<String>('xs', (v) => v as String),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigParser.getMap', () {
    test('parses map values', () {
      final p = ConfigParser({'m': {'a': 1, 'b': 2}});
      expect(
        p.getMap<int>('m', (v) => v as int),
        {'a': 1, 'b': 2},
      );
    });

    test('returns defaultValue when missing', () {
      final p = ConfigParser({});
      expect(
        p.getMap<int>('m', (v) => v as int, defaultValue: {'x': 1}),
        {'x': 1},
      );
    });

    test('throws when required and missing', () {
      final p = ConfigParser({});
      expect(
        () => p.getMap<int>('m', (v) => v as int, required: true),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('throws when value is not a Map', () {
      final p = ConfigParser({'m': 'no'});
      expect(
        () => p.getMap<int>('m', (v) => v as int),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('throws on missing required keys', () {
      final p = ConfigParser({'m': {'a': 1}});
      expect(
        () => p.getMap<int>('m', (v) => v as int, requiredKeys: ['a', 'b']),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('wraps value-parser failure', () {
      final p = ConfigParser({'m': {'a': 'not-int'}});
      expect(
        () => p.getMap<int>('m', (v) => v as int),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigParser.getObject + helpers', () {
    test('returns nested ConfigParser', () {
      final p = ConfigParser({'inner': {'x': 1}});
      final inner = p.getObject('inner');
      expect(inner.getInt('x'), 1);
    });

    test('returns empty parser when missing and not required', () {
      final p = ConfigParser({});
      final inner = p.getObject('inner');
      expect(inner.keys, isEmpty);
    });

    test('throws when missing and required', () {
      final p = ConfigParser({});
      expect(
        () => p.getObject('inner', required: true),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('throws when value is not a Map', () {
      final p = ConfigParser({'inner': 'no'});
      expect(
        () => p.getObject('inner'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('hasKey, keys, rawData, toString', () {
      final p = ConfigParser({'a': 1, 'b': 2});
      expect(p.hasKey('a'), isTrue);
      expect(p.hasKey('z'), isFalse);
      expect(p.keys, {'a', 'b'});
      expect(p.rawData, {'a': 1, 'b': 2});
      expect(p.toString(), contains('2 fields'));
    });

    test('validateRequired succeeds when all present', () {
      final p = ConfigParser({'a': 1, 'b': 2});
      // Should not throw.
      p.validateRequired(['a', 'b']);
    });

    test('validateRequired throws when missing', () {
      final p = ConfigParser({'a': 1});
      expect(
        () => p.validateRequired(['a', 'b']),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('validateNoUnknownFields succeeds when only allowed are present', () {
      final p = ConfigParser({'a': 1, 'b': 2});
      // Should not throw.
      p.validateNoUnknownFields(['a', 'b', 'c']);
    });

    test('validateNoUnknownFields throws on unknown', () {
      final p = ConfigParser({'a': 1, 'rogue': 2});
      expect(
        () => p.validateNoUnknownFields(['a']),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigValidator', () {
    test('isValidEmail delegates to InputValidator', () {
      // We're not testing InputValidator's logic here, just that the
      // method routes through.
      expect(ConfigValidator.isValidEmail('a@example.com'), isA<bool>());
    });

    test('isValidUrl recognizes http and https', () {
      expect(ConfigValidator.isValidUrl('http://example.com'), isTrue);
      expect(ConfigValidator.isValidUrl('https://example.com'), isTrue);
      expect(ConfigValidator.isValidUrl('ftp://example.com'), isFalse);
      expect(ConfigValidator.isValidUrl('not a url'), isFalse);
    });

    test('isValidFilePath rejects illegal characters', () {
      expect(ConfigValidator.isValidFilePath('/tmp/safe.txt'), isTrue);
      expect(ConfigValidator.isValidFilePath('/tmp/<bad>.txt'), isFalse);
      expect(ConfigValidator.isValidFilePath('/tmp/with|pipe.txt'), isFalse);
    });

    test('isValidPort respects range', () {
      expect(ConfigValidator.isValidPort(0), isFalse);
      expect(ConfigValidator.isValidPort(1), isTrue);
      expect(ConfigValidator.isValidPort(65535), isTrue);
      expect(ConfigValidator.isValidPort(65536), isFalse);
    });

    test('isValidIPv4 accepts well-formed addresses', () {
      expect(ConfigValidator.isValidIPv4('1.2.3.4'), isTrue);
      expect(ConfigValidator.isValidIPv4('255.255.255.255'), isTrue);
      expect(ConfigValidator.isValidIPv4('256.0.0.0'), isFalse);
      expect(ConfigValidator.isValidIPv4('a.b.c.d'), isFalse);
      expect(ConfigValidator.isValidIPv4('1.2.3'), isFalse);
      expect(ConfigValidator.isValidIPv4('-1.2.3.4'), isFalse);
    });
  });

  group('ConfigPatterns', () {
    test('parseTimeout uses defaultValue when key missing', () {
      final p = ConfigParser({});
      expect(
        ConfigPatterns.parseTimeout(p, 'timeoutMs',
            defaultValue: const Duration(seconds: 5)),
        const Duration(seconds: 5),
      );
    });

    test('parseTimeout respects custom min', () {
      final p = ConfigParser({'timeoutMs': 100});
      expect(
        () => ConfigPatterns.parseTimeout(
          p,
          'timeoutMs',
          min: const Duration(seconds: 1),
        ),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('parseRetryConfig returns defaults when not provided', () {
      final p = ConfigParser({});
      final cfg = ConfigPatterns.parseRetryConfig(p, 'retry');
      expect(cfg.maxRetries, 3);
      expect(cfg.delay, const Duration(seconds: 1));
    });

    test('parseRetryConfig clamps via getInt min/max bounds', () {
      final p = ConfigParser({'retryMaxRetries': 50});
      expect(
        () => ConfigPatterns.parseRetryConfig(p, 'retry'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('parseUrl returns and validates', () {
      final p = ConfigParser({'url': 'https://example.com'});
      expect(ConfigPatterns.parseUrl(p, 'url'), 'https://example.com');
    });

    test('parseUrl throws on invalid url', () {
      final p = ConfigParser({'url': 'bogus'});
      expect(
        () => ConfigPatterns.parseUrl(p, 'url'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('parseUrl returns empty when missing and not required', () {
      final p = ConfigParser({});
      expect(ConfigPatterns.parseUrl(p, 'url'), '');
    });

    test('parseFilePath validates illegal chars', () {
      final p = ConfigParser({'p': '/tmp/<bad>'});
      expect(
        () => ConfigPatterns.parseFilePath(p, 'p'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('parseFilePath returns valid path', () {
      final p = ConfigParser({'p': '/tmp/safe.txt'});
      expect(ConfigPatterns.parseFilePath(p, 'p'), '/tmp/safe.txt');
    });
  });
}
