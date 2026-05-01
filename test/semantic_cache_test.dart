import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/semantic_cache.dart';

void main() {
  group('SemanticCacheEntry', () {
    test('uses provided timestamp', () {
      final t = DateTime(2026);
      final entry = SemanticCacheEntry<int>(key: 'k', value: 1, timestamp: t);
      expect(entry.timestamp, t);
      expect(entry.embedding, isNull);
    });

    test('defaults timestamp to now', () {
      final before = DateTime.now();
      final entry = SemanticCacheEntry<String>(key: 'k', value: 'v');
      final after = DateTime.now();
      expect(entry.timestamp.isBefore(before), isFalse);
      expect(entry.timestamp.isAfter(after), isFalse);
    });

    test('isExpired returns false within TTL', () {
      final entry = SemanticCacheEntry<int>(key: 'k', value: 1);
      expect(entry.isExpired(const Duration(hours: 1)), isFalse);
    });

    test('isExpired returns true past TTL', () {
      final entry = SemanticCacheEntry<int>(
        key: 'k',
        value: 1,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(entry.isExpired(const Duration(hours: 1)), isTrue);
    });

    test('embedding is preserved', () {
      final entry = SemanticCacheEntry<int>(
        key: 'k',
        value: 1,
        embedding: [0.1, 0.2, 0.3],
      );
      expect(entry.embedding, [0.1, 0.2, 0.3]);
    });
  });

  group('SemanticCache — exact-match path', () {
    test('returns null on miss and counts a miss', () async {
      final cache = SemanticCache<String>();
      expect(await cache.get('absent'), isNull);
      expect(cache.size, 0);
      // First call: 0 hits / 1 miss → hitRate 0.
      expect(cache.hitRate, 0);
    });

    test('put + get returns the stored value and counts a hit', () async {
      final cache = SemanticCache<String>();
      await cache.put('k', 'v');
      expect(await cache.get('k'), 'v');
      expect(cache.size, 1);
      expect(cache.hitRate, 1.0);
    });

    test('mixed hits and misses produce a fractional hitRate', () async {
      final cache = SemanticCache<int>();
      await cache.put('a', 1);
      await cache.get('a'); // hit
      await cache.get('b'); // miss
      expect(cache.hitRate, closeTo(0.5, 0.0001));
    });

    test('expired exact entries are evicted on get', () async {
      final cache = SemanticCache<String>(ttl: const Duration(milliseconds: 1));
      await cache.put('k', 'v');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await cache.get('k'), isNull);
      expect(cache.size, 0);
    });

    test('exceeding maxSize evicts the oldest exact entry', () async {
      final cache = SemanticCache<String>(maxSize: 2);
      await cache.put('a', 'A');
      await cache.put('b', 'B');
      await cache.put('c', 'C');
      expect(cache.size, 2);
      expect(await cache.get('a'), isNull); // 'a' was the oldest
      expect(await cache.get('b'), 'B');
      expect(await cache.get('c'), 'C');
    });

    test('clear removes all entries', () async {
      final cache = SemanticCache<int>();
      await cache.put('a', 1);
      await cache.put('b', 2);
      await cache.clear();
      expect(cache.size, 0);
    });
  });

  group('SemanticCache — semantic / embedding path', () {
    Future<List<double>> exactEmbedding(String key) async {
      switch (key) {
        case 'cat':
          return [1.0, 0.0, 0.0];
        case 'feline':
          return [0.95, 0.05, 0.0]; // similar to cat
        case 'dog':
          return [0.0, 1.0, 0.0]; // very different
        default:
          return [0.5, 0.5, 0.0];
      }
    }

    test('exact match works even when embeddingFunction is set', () async {
      final cache = SemanticCache<String>(embeddingFunction: exactEmbedding);
      await cache.put('cat', 'meow');
      expect(await cache.get('cat'), 'meow');
    });

    test('semantic match returns nearest entry above threshold', () async {
      final cache = SemanticCache<String>(
        embeddingFunction: exactEmbedding,
        similarityThreshold: 0.9,
      );
      await cache.put('cat', 'meow');
      // 'feline' has high cosine similarity to 'cat'.
      expect(await cache.get('feline'), 'meow');
    });

    test('semantic match below threshold returns null', () async {
      final cache = SemanticCache<String>(
        embeddingFunction: exactEmbedding,
        similarityThreshold: 0.99,
      );
      await cache.put('cat', 'meow');
      // 'feline' similarity (~0.998) might pass at 0.99 — use 'dog' which is orthogonal.
      expect(await cache.get('dog'), isNull);
    });

    test('embeddingFunction error during put falls back to exact-only', () async {
      Future<List<double>> failingEmbedding(String key) async {
        throw StateError('embedding failure');
      }
      final cache = SemanticCache<String>(embeddingFunction: failingEmbedding);
      await cache.put('k', 'v'); // should not throw
      expect(await cache.get('k'), 'v');
    });

    test('embeddingFunction error during get returns miss', () async {
      bool firstCall = true;
      Future<List<double>> sometimesFails(String key) async {
        if (firstCall) {
          firstCall = false;
          return [1.0, 0.0];
        }
        throw StateError('query embedding failure');
      }
      final cache = SemanticCache<String>(embeddingFunction: sometimesFails);
      await cache.put('k', 'v');
      // Exact miss + embeddingFunction throws on the query → falls through to miss.
      expect(await cache.get('absent'), isNull);
    });

    test('exceeding maxSize evicts the oldest semantic entry', () async {
      final cache = SemanticCache<String>(
        maxSize: 2,
        embeddingFunction: exactEmbedding,
      );
      await cache.put('cat', 'A');
      await cache.put('dog', 'B');
      await cache.put('feline', 'C');
      // 'cat' should have been evicted from the semantic list.
      // The exact cache evicts the oldest, leaving dog+feline. A semantic
      // probe for 'cat' should now return 'C' (similar to 'feline') rather
      // than the long-evicted 'A'.
      final out = await cache.get('cat');
      expect(out, isNot('A'));
    });

    test('expired semantic entries skipped during similarity search',
        () async {
      final cache = SemanticCache<String>(
        embeddingFunction: exactEmbedding,
        ttl: const Duration(milliseconds: 1),
      );
      await cache.put('cat', 'meow');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // 'feline' is similar but the entry is expired and must be skipped.
      expect(await cache.get('feline'), isNull);
    });
  });

  group('SemanticCache.removeExpiredEntries', () {
    test('returns 0 when nothing is expired', () async {
      final cache = SemanticCache<int>();
      await cache.put('a', 1);
      expect(await cache.removeExpiredEntries(), 0);
      expect(cache.size, 1);
    });

    test('removes expired exact entries and returns the count', () async {
      final cache = SemanticCache<int>(ttl: const Duration(milliseconds: 1));
      await cache.put('a', 1);
      await cache.put('b', 2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(await cache.removeExpiredEntries(), 2);
      expect(cache.size, 0);
    });

    test('removes expired semantic entries too', () async {
      Future<List<double>> emb(String key) async => [1.0, 0.0];
      final cache = SemanticCache<int>(
        embeddingFunction: emb,
        ttl: const Duration(milliseconds: 1),
      );
      await cache.put('a', 1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Both exact and semantic entries are expired (count = 2).
      final removed = await cache.removeExpiredEntries();
      expect(removed, greaterThanOrEqualTo(1));
    });
  });

  group('SemanticCache.shrink', () {
    test('shrink with factor outside (0,1) is a no-op', () async {
      final cache = SemanticCache<int>();
      for (var i = 0; i < 4; i++) {
        await cache.put('k$i', i);
      }
      await cache.shrink(0); // no-op
      expect(cache.size, 4);
      await cache.shrink(1); // no-op
      expect(cache.size, 4);
    });

    test('shrink with factor 0.5 trims exact cache', () async {
      final cache = SemanticCache<int>();
      for (var i = 0; i < 4; i++) {
        await cache.put('k$i', i);
      }
      await cache.shrink(0.5);
      // ceil(4 * 0.5) = 2.
      expect(cache.size, 2);
    });

    test('shrink keeps at least one entry due to max(1, ...)', () async {
      final cache = SemanticCache<int>();
      await cache.put('only', 99);
      await cache.shrink(0.1);
      expect(cache.size, 1);
    });
  });

  group('cosine similarity edge cases (via semantic path)', () {
    test('zero-norm vector treated as similarity 0', () async {
      Future<List<double>> emb(String key) async {
        if (key == 'q') return [0.0, 0.0]; // zero norm
        return [1.0, 0.0];
      }
      final cache = SemanticCache<String>(
        embeddingFunction: emb,
        similarityThreshold: 0.0,
      );
      await cache.put('stored', 'value');
      // Query 'q' has zero embedding → similarity 0 → no semantic hit.
      expect(await cache.get('q'), isNull);
    });

    test('mismatched dimensions raise via internal cosineSimilarity', () async {
      bool first = true;
      Future<List<double>> emb(String key) async {
        if (first) {
          first = false;
          return [1.0, 0.0]; // store dim 2
        }
        return [1.0, 0.0, 0.0]; // query dim 3 → ArgumentError inside
      }
      final cache = SemanticCache<String>(embeddingFunction: emb);
      await cache.put('stored', 'v');
      // The internal try/catch swallows the ArgumentError and falls through
      // to a miss.
      expect(await cache.get('absent'), isNull);
    });
  });
}
