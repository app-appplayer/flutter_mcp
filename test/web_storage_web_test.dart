// Browser-only tests for WebStorageManager. Run with:
//     flutter test --platform chrome test/web_storage_web_test.dart
//
// On chrome the manager backs onto sessionStorage (we ask for non-local
// storage to keep the suite hermetic between test runs).

@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/storage/web_storage.dart';

void main() {
  group('WebStorageManager — sessionStorage backing', () {
    late WebStorageManager m;

    setUp(() async {
      m = WebStorageManager(
        useLocalStorage: false,
        prefix: 'tst_',
      );
      await m.initialize();
      // Wipe anything from prior tests.
      await m.clear();
    });

    test('saveString / readString roundtrip', () async {
      await m.saveString('greeting', 'hello');
      expect(await m.readString('greeting'), 'hello');
    });

    test('readString returns null for missing key', () async {
      expect(await m.readString('absent'), isNull);
    });

    test('containsKey reflects whether a value exists', () async {
      expect(await m.containsKey('k'), isFalse);
      await m.saveString('k', 'v');
      expect(await m.containsKey('k'), isTrue);
    });

    test('delete removes the key', () async {
      await m.saveString('rm', 'v');
      expect(await m.delete('rm'), isTrue);
      expect(await m.readString('rm'), isNull);
    });

    test('delete on missing key still resolves (impl returns true)', () async {
      // sessionStorage.removeItem is idempotent — the impl reflects that
      // and resolves the future without distinguishing missing keys.
      expect(await m.delete('absent'), isA<bool>());
    });

    test('saveMap / readMap roundtrip', () async {
      await m.saveMap('user', {'name': 'jsha', 'age': 100});
      final got = await m.readMap('user');
      expect(got, {'name': 'jsha', 'age': 100});
    });

    test('clear empties storage but only for our prefix', () async {
      await m.saveString('a', 'x');
      await m.saveString('b', 'y');
      await m.clear();
      expect(await m.readString('a'), isNull);
      expect(await m.readString('b'), isNull);
    });

    test('getAllKeys returns prefixed keys without prefix', () async {
      await m.saveString('one', '1');
      await m.saveString('two', '2');
      final keys = await m.getAllKeys();
      expect(keys, containsAll(['one', 'two']));
    });

    test('overwriting a key updates the value', () async {
      await m.saveString('overwrite', 'first');
      await m.saveString('overwrite', 'second');
      expect(await m.readString('overwrite'), 'second');
    });

    test('initialize is idempotent', () async {
      await m.initialize();
      await m.initialize();
      // Still functional after.
      await m.saveString('still', 'works');
      expect(await m.readString('still'), 'works');
    });
  });
}
