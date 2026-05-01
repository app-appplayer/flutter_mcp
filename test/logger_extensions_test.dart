import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/logger.dart';

void main() {
  group('LoggerExtensions', () {
    final captured = <String>[];

    setUpAll(() {
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((r) {
        captured.add('${r.level.name}:${r.message}');
      });
    });

    setUp(() => captured.clear());

    test('debug routes to FINE', () {
      Logger('test.ext.debug').debug('msg');
      expect(captured, contains('FINE:msg'));
    });

    test('error routes to SEVERE', () {
      Logger('test.ext.error').error('msg');
      expect(captured, contains('SEVERE:msg'));
    });

    test('warn routes to WARNING', () {
      Logger('test.ext.warn').warn('msg');
      expect(captured, contains('WARNING:msg'));
    });

    test('trace routes to FINEST', () {
      Logger('test.ext.trace').trace('msg');
      expect(captured, contains('FINEST:msg'));
    });
  });

  group('FlutterMcpLogging.createLogger', () {
    test('returns a Logger under the flutter_mcp parent', () {
      final logger = FlutterMcpLogging.createLogger('my_component');
      // The logging package uses dot-hierarchy: the leaf name is just the
      // last segment, but the fullName chains to the root.
      expect(logger, isA<Logger>());
      expect(logger.name, 'my_component');
      expect(logger.fullName, 'flutter_mcp.my_component');
    });
  });

  group('FlutterMcpLogging.configure', () {
    test('configure with enableDebugLogging sets root level to FINE', () {
      FlutterMcpLogging.configure(enableDebugLogging: true);
      expect(Logger.root.level, Level.FINE);
    });

    test('configure without debug uses requested level', () {
      FlutterMcpLogging.configure(level: Level.WARNING);
      expect(Logger.root.level, Level.WARNING);
    });

    test('configure default uses INFO', () {
      FlutterMcpLogging.configure();
      expect(Logger.root.level, Level.INFO);
    });
  });

  group('MCPLogger typedef', () {
    test('is an alias for Logger', () {
      // ignore: prefer_const_constructors
      final l = MCPLogger('alias.test');
      expect(l, isA<Logger>());
    });
  });
}
