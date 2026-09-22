import 'package:uuid/uuid.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/memory/domain/entities/memory_entry.dart';
import 'package:khwarizmi/features/memory/services/embedding_service.dart';

class ScoredMemory {
  final MemoryEntry entry;
  final double score;

  const ScoredMemory({required this.entry, required this.score});
}

class MemoryRepository {
  static const _uuid = Uuid();

  /// Saves a memory entry into SQLite, generating vector embedding if apiKey is available.
  static Future<MemoryEntry> storeMemory({
    required String content,
    String category = 'general',
    int importance = 1,
    String? apiKey,
  }) async {
    List<double>? embedding;
    if (apiKey != null && apiKey.isNotEmpty) {
      embedding = await EmbeddingService.getEmbedding(content, apiKey);
    }

    final entry = MemoryEntry(
      id: _uuid.v4(),
      content: content.trim(),
      category: category.trim().toLowerCase(),
      createdAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
      importance: importance.clamp(1, 5),
      embedding: embedding,
    );

    await MemoryDatabase.insertMemory(entry);
    return entry;
  }

  /// Performs hybrid search (Semantic Vector Cosine Similarity + Keyword Match)
  static Future<List<ScoredMemory>> searchMemory({
    required String query,
    int limit = 5,
    double minScore = 0.25,
    String? apiKey,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final allMemories = await MemoryDatabase.getAllMemories(limit: 200);
    if (allMemories.isEmpty) return [];

    List<double>? queryEmbedding;
    if (apiKey != null && apiKey.isNotEmpty) {
      queryEmbedding = await EmbeddingService.getEmbedding(cleanQuery, apiKey);
    }

    final queryWords = cleanQuery
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();

    final scored = <ScoredMemory>[];

    for (final memory in allMemories) {
      double semanticScore = 0.0;
      if (queryEmbedding != null && memory.embedding != null) {
        semanticScore =
            EmbeddingService.cosineSimilarity(queryEmbedding, memory.embedding!);
      }

      double textScore = 0.0;
      final memText = memory.content.toLowerCase();
      final memCat = memory.category.toLowerCase();

      if (memText.contains(cleanQuery.toLowerCase())) {
        textScore = 1.0;
      } else if (queryWords.isNotEmpty) {
        int matches = 0;
        for (final word in queryWords) {
          if (memText.contains(word) || memCat.contains(word)) {
            matches++;
          }
        }
        textScore = matches / queryWords.length;
      }

      double finalScore;
      if (queryEmbedding != null && memory.embedding != null) {
        finalScore = (semanticScore * 0.7) + (textScore * 0.3);
      } else {
        finalScore = textScore;
      }

      finalScore += (memory.importance - 1) * 0.03;

      if (finalScore >= minScore) {
        scored.add(ScoredMemory(entry: memory, score: finalScore));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    final results = scored.take(limit).toList();

    // Update access stats in the background — fire-and-forget so the caller
    // is not held up by these secondary writes.
    for (final sm in results) {
      MemoryDatabase.updateAccessStats(sm.entry.id).catchError((_) {});
    }

    return results;
  }

  /// Retrieves the most recent and important memories for automatic agent context injection.
  static Future<List<MemoryEntry>> getRelevantContextMemories(
      {int limit = 6}) async {
    final all = await MemoryDatabase.getAllMemories(limit: 30);
    if (all.isEmpty) return [];

    all.sort((a, b) {
      final impCmp = b.importance.compareTo(a.importance);
      if (impCmp != 0) return impCmp;
      return b.createdAt.compareTo(a.createdAt);
    });

    return all.take(limit).toList();
  }

  /// Returns the count of memories that still need embeddings generated.
  /// This is async to avoid blocking the UI thread with a synchronous DB read.
  static Future<int> getPendingEmbeddingsCount() async {
    final pending =
        await MemoryDatabase.getMemoriesPendingEmbedding(limit: 500);
    return pending.length;
  }

  /// Scans for any memories stored without embeddings (e.g. stored while offline)
  /// and generates their embeddings using the current API key.
  static Future<int> syncPendingEmbeddings(String apiKey) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) return 0;

    final pending =
        await MemoryDatabase.getMemoriesPendingEmbedding(limit: 30);
    if (pending.isEmpty) return 0;

    int synced = 0;
    for (final entry in pending) {
      try {
        final embedding =
            await EmbeddingService.getEmbedding(entry.content, cleanKey);
        if (embedding != null && embedding.isNotEmpty) {
          await MemoryDatabase.updateMemoryEmbedding(entry.id, embedding);
          synced++;
        }
      } catch (_) {}
    }
    return synced;
  }

  static Future<List<MemoryEntry>> getAllMemories({int limit = 100}) {
    return MemoryDatabase.getAllMemories(limit: limit);
  }

  static Future<void> deleteMemory(String id) {
    return MemoryDatabase.deleteMemory(id);
  }

  static Future<void> clearAll() {
    return MemoryDatabase.clearAll();
  }
}


