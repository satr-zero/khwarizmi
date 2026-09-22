import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EmbeddingService {
  /// Current official Gemini embedding model
  static const String _embeddingModel = 'gemini-embedding-001';

  /// Output dimensionality using Matryoshka Representation Learning (MRL).
  /// 768 preserves >98% accuracy of 3072 while saving 75% memory/storage and accelerating cosine similarity.
  static const int outputDimensionality = 768;

  /// Generates a dense vector embedding (768-dim) using Gemini Embedding API
  static Future<List<double>?> getEmbedding(String text, String apiKey) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty || text.trim().isEmpty) return null;

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_embeddingModel:embedContent?key=$cleanKey',
      );

      final payload = {
        'model': 'models/$_embeddingModel',
        'content': {
          'parts': [
            {'text': text.trim()}
          ]
        },
        'outputDimensionality': outputDimensionality,
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[EmbeddingService] Failed to get embedding (${response.statusCode}): ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final values = data['embedding']?['values'] as List<dynamic>?;
      if (values == null || values.isEmpty) return null;

      final floats = values.map((e) => (e as num).toDouble()).toList();
      return _normalize(floats);
    } catch (e) {
      debugPrint('[EmbeddingService] Error fetching embedding: $e');
      return null;
    }
  }

  /// Normalizes vector to unit length (L2 norm) for accurate cosine similarity
  static List<double> _normalize(List<double> v) {
    double norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm == 0.0) return v;
    return v.map((x) => x / norm).toList();
  }

  /// Calculates cosine similarity between two float vectors.
  /// Returns a value between -1.0 and 1.0 (typically 0.0 to 1.0 for normalized embeddings).
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      final valA = a[i];
      final valB = b[i];
      dot += valA * valB;
      normA += valA * valA;
      normB += valB * valB;
    }

    if (normA <= 0.0 || normB <= 0.0) return 0.0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}
