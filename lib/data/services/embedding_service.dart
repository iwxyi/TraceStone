import 'dart:math';

import '../models/ai_embedding.dart';

class EmbeddingService {
  const EmbeddingService();

  static const modelId = 'local-hashing-embedding';
  static const modelVersion = 'v1';
  static const dimensions = 128;

  AiEmbeddingResult embed(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final vector = List<double>.filled(dimensions, 0);
    final tokens = _tokens(normalized);
    for (final token in tokens) {
      final hash = _hash(token);
      final index = hash.abs() % dimensions;
      final sign = hash.isEven ? 1.0 : -1.0;
      final weight = token.length >= 4 ? 1.4 : 1.0;
      vector[index] += sign * weight;
    }
    _normalize(vector);
    return AiEmbeddingResult(
      modelId: modelId,
      modelVersion: modelVersion,
      dimensions: dimensions,
      vector: vector,
      textHash: _hash(normalized).toRadixString(16),
    );
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    final length = min(a.length, b.length);
    if (length == 0) return 0;
    var dot = 0.0;
    var aNorm = 0.0;
    var bNorm = 0.0;
    for (var index = 0; index < length; index++) {
      dot += a[index] * b[index];
      aNorm += a[index] * a[index];
      bNorm += b[index] * b[index];
    }
    if (aNorm == 0 || bNorm == 0) return 0;
    return dot / (sqrt(aNorm) * sqrt(bNorm));
  }

  Set<String> _tokens(String text) {
    final cleaned = text
        .replaceAll(
            RegExp(r'[\s\n\r\t，。！？；：、“”‘’（）《》【】,.!?;:#>*_`\[\](){}/\\-]+'), ' ')
        .trim();
    final tokens = <String>{};
    for (final part in cleaned.split(' ')) {
      final value = part.trim();
      if (value.length >= 2) tokens.add(value);
      if (value.length >= 4) {
        for (var i = 0; i <= value.length - 2; i++) {
          tokens.add(value.substring(i, i + 2));
        }
      }
    }
    return tokens;
  }

  void _normalize(List<double> vector) {
    var norm = 0.0;
    for (final value in vector) {
      norm += value * value;
    }
    if (norm == 0) return;
    final divisor = sqrt(norm);
    for (var index = 0; index < vector.length; index++) {
      vector[index] = vector[index] / divisor;
    }
  }

  int _hash(String text) {
    var hash = 0x811c9dc5;
    for (final codeUnit in text.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
