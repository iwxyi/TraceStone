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
    final sourceTypeName = _stringValue(json['sourceType']).isEmpty
        ? AiEmbeddingSourceType.entry.name
        : _stringValue(json['sourceType']);
    return AiEmbedding(
      id: _stringValue(json['id']),
      sourceType: AiEmbeddingSourceType.values.firstWhere(
        (item) => item.name == sourceTypeName,
        orElse: () => AiEmbeddingSourceType.entry,
      ),
      sourceId: _stringValue(json['sourceId']),
      entryId: _stringValue(json['entryId']),
      modelId: _stringValue(json['modelId']).isEmpty
          ? 'unknown'
          : _stringValue(json['modelId']),
      modelVersion: _stringValue(json['modelVersion']).isEmpty
          ? 'unknown'
          : _stringValue(json['modelVersion']),
      dimensions: _intValue(json['dimensions']),
      vector: _doubleList(json['vector']),
      generatedAt: DateTime.tryParse(_stringValue(json['generatedAt'])) ??
          DateTime.now(),
      textHash: _stringValue(json['textHash']),
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<double> _doubleList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) {
          if (item is num) return item.toDouble();
          return double.tryParse(item?.toString() ?? '');
        })
        .whereType<double>()
        .toList();
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
