import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/object_pool.dart';

class _Box {
  int value = 0;
}

void main() {
  group('ObjectPool — construction', () {
    test('initialSize pre-populates the pool', () {
      var creates = 0;
      final pool = ObjectPool<_Box>(
        create: () {
          creates++;
          return _Box();
        },
        reset: (b) => b.value = 0,
        initialSize: 3,
      );
      expect(pool.size, 3);
      expect(pool.inUseCount, 0);
      expect(pool.totalCreated, 3);
      expect(creates, 3);
    });

    test('default initialSize is 0', () {
      final pool = ObjectPool<_Box>(
        create: _Box.new,
        reset: (b) => b.value = 0,
      );
      expect(pool.size, 0);
      expect(pool.totalCreated, 0);
    });
  });

  group('ObjectPool — acquire / release', () {
    test('acquire from empty pool creates a new object', () {
      var creates = 0;
      final pool = ObjectPool<_Box>(
        create: () {
          creates++;
          return _Box();
        },
        reset: (b) => b.value = 0,
      );
      final obj = pool.acquire();
      expect(obj, isA<_Box>());
      expect(creates, 1);
      expect(pool.totalCreated, 1);
      expect(pool.inUseCount, 1);
    });

    test('release returns the object to the pool and resets it', () {
      var resets = 0;
      final pool = ObjectPool<_Box>(
        create: _Box.new,
        reset: (b) {
          resets++;
          b.value = 0;
        },
      );
      final obj = pool.acquire()..value = 7;
      pool.release(obj);
      expect(pool.size, 1);
      expect(pool.inUseCount, 0);
      expect(resets, 1);
      expect(obj.value, 0);
    });

    test('acquire reuses a released object instead of creating new', () {
      var creates = 0;
      final pool = ObjectPool<_Box>(
        create: () {
          creates++;
          return _Box();
        },
        reset: (b) => b.value = 0,
      );
      final a = pool.acquire();
      pool.release(a);
      final b = pool.acquire();
      expect(identical(a, b), isTrue);
      expect(creates, 1);
    });

    test('release for a foreign object is a no-op', () {
      final pool = ObjectPool<_Box>(
        create: _Box.new,
        reset: (b) {},
      );
      final stranger = _Box();
      pool.release(stranger);
      expect(pool.size, 0);
      expect(pool.inUseCount, 0);
    });

    test('release respects maxSize and discards over-the-cap objects', () {
      final pool = ObjectPool<_Box>(
        create: _Box.new,
        reset: (b) {},
        maxSize: 2,
      );
      final a = pool.acquire();
      final b = pool.acquire();
      final c = pool.acquire();
      pool.release(a);
      pool.release(b);
      pool.release(c); // exceeds maxSize → discarded from pool
      expect(pool.size, 2);
      expect(pool.totalCreated, 3);
    });
  });

  group('ObjectPool — clear / trim', () {
    test('clear empties the pool but leaves in-use objects intact', () {
      final pool = ObjectPool<_Box>(
        create: _Box.new,
        reset: (b) {},
        initialSize: 3,
      );
      final inUse = pool.acquire();
      pool.clear();
      expect(pool.size, 0);
      expect(pool.inUseCount, 1);
      // Releasing the in-use object after clear works.
      pool.release(inUse);
      expect(pool.size, 1);
    });

    test('trim halves pool when over threshold', () {
      final pool = ObjectPool<_Box>(
        create: _Box.new,
        reset: (b) {},
        initialSize: 12,
      );
      pool.trim();
      expect(pool.size, 6);
    });

    test('trim is a no-op when below threshold', () {
      final pool = ObjectPool<_Box>(
        create: _Box.new,
        reset: (b) {},
        initialSize: 5,
      );
      pool.trim();
      expect(pool.size, 5);
    });
  });
}
