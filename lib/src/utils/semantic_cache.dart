import 'dart:async';
import 'dart:collection';
import 'dart:math';

/// Semantic cache entry with vector similarity support
class SemanticCacheEntry<T> {
  final String key;
  final T value;
  final List<double>? embedding;
  final DateTime timestamp;

  SemanticCacheEntry({
    required this.key,
    required this.value,
    this.embedding,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Check if the entry has expired
  bool isExpired(Duration ttl) {
    return DateTime.now().difference(timestamp) > ttl;
  }
}

/// Semantic cache for vector-based similarity search
class SemanticCache<T> {
  final LinkedHashMap<String, SemanticCacheEntry<T>> _exactCache =
      LinkedHashMap();
  final List<SemanticCacheEntry<T>> _semanticEntries = [];

  final int maxSize;
  final Duration ttl;
  final Future<List<double>> Function(String)? embeddingFunction;
  final double similarityThreshold;

  int _hits = 0;
  int _misses = 0;

  /// Creates a semantic cache
  ///
  /// [maxSize]: Maximum number of entries
  /// [ttl]: Time-to-live for entries
  /// [embeddingFunction]: Function to create embeddings for keys
  /// [similarityThreshold]: Similarity threshold for semantic matches (0.0-1.0)
  SemanticCache({
    this.maxSize = 100,
    this.ttl = const Duration(hours: 1),
    this.embeddingFunction,
    this.similarityThreshold = 0.85,
  });

  /// Get an item from the cache (exact match first, then semantic match)
  Future<T?> get(String key) async {
    // Check for exact match first
    if (_exactCache.containsKey(key)) {
      final entry = _exactCache[key]!;

      // Check if expired
      if (entry.isExpired(ttl)) {
        _exactCache.remove(key);
        return null;
      }

      // Found a match
      _hits++;
      return entry.value;
    }

    // Try semantic search if embedding function available
    if (embeddingFunction != null && _semanticEntries.isNotEmpty) {
      try {
        // Generate embedding for query
        final queryEmbedding = await embeddingFunction!(key);

        // Find most similar entry
        SemanticCacheEntry<T>? mostSimilar;
        double highestSimilarity = similarityThreshold;

        for (final entry in _semanticEntries) {
          if (entry.embedding != null) {
            // Skip expired entries
            if (entry.isExpired(ttl)) continue;

            final similarity =
                _cosineSimilarity(queryEmbedding, entry.embedding!);
            if (similarity > highestSimilarity) {
              highestSimilarity = similarity;
              mostSimilar = entry;
            }
          }
        }

        if (mostSimilar != null) {
          _hits++;
          return mostSimilar.value;
        }
      } catch (e) {
        // If embedding fails, just continue with cache miss
        //print('Semantic search error: $e');
      }
    }

    // Cache miss
    _misses++;
    return null;
  }

  /// Put an item in the cache
  Future<void> put(String key, T value) async {
    // Create entry
    final entry = SemanticCacheEntry<T>(
      key: key,
      value: value,
    );

    // Add to exact cache
    _exactCache[key] = entry;

    // Ensure we're under size limit
    if (_exactCache.length > maxSize) {
      // Remove oldest entry
      _exactCache.remove(_exactCache.keys.first);
    }

    // Add semantic entry if embedding function available
    if (embeddingFunction != null) {
      try {
        final embedding = await embeddingFunction!(key);
        final semanticEntry = SemanticCacheEntry<T>(
          key: key,
          value: value,
          embedding: embedding,
        );

        _semanticEntries.add(semanticEntry);

        // Ensure we're under size limit
        if (_semanticEntries.length > maxSize) {
          _semanticEntries.removeAt(0);
        }
      } catch (e) {
        // If embedding fails, just continue with exact match only
        //print('Embedding generation error: $e');
      }
    }
  }

  /// Remove expired entries
  Future<int> removeExpiredEntries() async {
    int removedCount = 0;

    // Remove expired exact cache entries
    final expiredKeys = <String>[];
    for (final entry in _exactCache.entries) {
      if (entry.value.isExpired(ttl)) {
        expiredKeys.add(entry.key);
      }
    }
    for (final key in expiredKeys) {
      _exactCache.remove(key);
      removedCount++;
    }

    // Remove expired semantic entries
    _semanticEntries.removeWhere((entry) {
      final expired = entry.isExpired(ttl);
      if (expired) removedCount++;
      return expired;
    });

    return removedCount;
  }

  /// Shrink the cache by the given factor (0.0-1.0)
  Future<void> shrink(double factor) async {
    if (factor <= 0 || factor >= 1) return;

    // Calculate new sizes
    final newExactSize = max(1, (_exactCache.length * factor).ceil());
    final newSemanticSize = max(1, (_semanticEntries.length * factor).ceil());

    // Trim exact cache to new size
    while (_exactCache.length > newExactSize) {
      _exactCache.remove(_exactCache.keys.first);
    }

    // Trim semantic entries to new size
    while (_semanticEntries.length > newSemanticSize) {
      _semanticEntries.removeAt(0);
    }
  }

  /// Clear the cache
  Future<void> clear() async {
    _exactCache.clear();
    _semanticEntries.clear();
  }

  /// Calculate cosine similarity between two vectors
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must be of the same dimension');
    }

    double dotProduct = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    normA = sqrt(normA);
    normB = sqrt(normB);

    if (normA == 0 || normB == 0) return 0;

    return dotProduct / (normA * normB);
  }

  /// Current size of the cache
  int get size => _exactCache.length;

  /// Hit rate (percentage of successful gets)
  double get hitRate {
    final total = _hits + _misses;
    if (total == 0) return 0;
    return _hits / total;
  }
}
