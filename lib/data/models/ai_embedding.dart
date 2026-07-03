enum AiEmbeddingSourceType { entry, summary, segment, memory }

class AiEmbedding {
  const AiEmbedding({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.entryId,
    required this.modelId,
    required this.modelVersion,
    required this.dimensions,
    required this.vector,
    required this.generatedAt,
    required this.textHash,
  });

  final String id;
  final AiEmbeddingSourceType sourceType;
  final String sourceId;
  final String entryId;
  final String modelId;
  final String modelVersion;
  final int dimensions;
  final List<double> vector;
  final DateTime generatedAt;
  final String textHash;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceType': sourceType.name,
        'sourceId': sourceId,
        'entryId': entryId,
        'modelId': modelId,
        'modelVersion': modelVersion,
        'dimensions': dimensions,
        'vector': vector,
        'generatedAt': generatedAt.toIso8601String(),
        'textHash': textHash,
      };

  static AiEmbedding fromJson(Map<String, dynamic> json) {
    final sourceTypeName =
        json['sourceType'] as String? ?? AiEmbeddingSourceType.entry.name;
    return AiEmbedding(
      id: json['id'] as String? ?? '',
      sourceType: AiEmbeddingSourceType.values.firstWhere(
        (item) => item.name == sourceTypeName,
        orElse: () => AiEmbeddingSourceType.entry,
      ),
      sourceId: json['sourceId'] as String? ?? '',
      entryId: json['entryId'] as String? ?? '',
      modelId: json['modelId'] as String? ?? 'unknown',
      modelVersion: json['modelVersion'] as String? ?? 'unknown',
      dimensions: json['dimensions'] as int? ?? 0,
      vector: (json['vector'] as List<dynamic>? ?? [])
          .map((item) => (item as num).toDouble())
          .toList(),
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      textHash: json['textHash'] as String? ?? '',
    );
  }
}

class AiEmbeddingResult {
  const AiEmbeddingResult({
    required this.modelId,
    required this.modelVersion,
    required this.dimensions,
    required this.vector,
    required this.textHash,
  });

  final String modelId;
  final String modelVersion;
  final int dimensions;
  final List<double> vector;
  final String textHash;
}
