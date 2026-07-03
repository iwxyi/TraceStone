class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.sourceEntryId,
    required this.date,
    required this.createdAt,
    DateTime? updatedAt,
    DateTime? lastReferencedAt,
    required this.summary,
    required this.keywords,
    required this.emotion,
    required this.people,
    required this.tags,
    this.evidenceEntryIds = const [],
    this.importance = 0.56,
    this.confidence = 0.58,
    this.referenceCount = 0,
    this.decay = 0,
    this.archived = false,
  })  : updatedAt = updatedAt ?? createdAt,
        lastReferencedAt = lastReferencedAt ?? createdAt;

  final String id;
  final String sourceEntryId;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastReferencedAt;
  final String summary;
  final List<String> keywords;
  final String emotion;
  final List<String> people;
  final List<String> tags;
  final List<String> evidenceEntryIds;
  final double importance;
  final double confidence;
  final int referenceCount;
  final double decay;
  final bool archived;

  String get title {
    if (tags.isNotEmpty) return tags.first;
    if (keywords.isNotEmpty) return keywords.first;
    return '${date.month}月${date.day}日的记忆';
  }

  List<String> get allSourceEntryIds {
    final ids = <String>{
      if (sourceEntryId.trim().isNotEmpty) sourceEntryId.trim(),
      ...evidenceEntryIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
    };
    return ids.toList(growable: false);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceEntryId': sourceEntryId,
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastReferencedAt': lastReferencedAt.toIso8601String(),
        'summary': summary,
        'keywords': keywords,
        'emotion': emotion,
        'people': people,
        'tags': tags,
        'evidenceEntryIds': evidenceEntryIds,
        'importance': importance,
        'confidence': confidence,
        'referenceCount': referenceCount,
        'decay': decay,
        'archived': archived,
      };

  static MemoryEntry fromJson(Map<String, dynamic> json) {
    final date =
        DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now();
    final createdAt =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? date;
    return MemoryEntry(
      id: json['id'] as String? ??
          '${json['sourceEntryId'] ?? 'memory'}-${date.microsecondsSinceEpoch}',
      sourceEntryId: json['sourceEntryId'] as String? ?? '',
      date: date,
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? createdAt,
      lastReferencedAt:
          DateTime.tryParse(json['lastReferencedAt'] as String? ?? '') ??
              createdAt,
      summary: json['summary'] as String? ?? '',
      keywords: _stringList(json['keywords']),
      emotion: json['emotion'] as String? ?? '',
      people: _stringList(json['people']),
      tags: _stringList(json['tags']),
      evidenceEntryIds: _stringList(json['evidenceEntryIds']).isEmpty
          ? _legacyEvidenceEntryIds(json['sourceEntryId'])
          : _stringList(json['evidenceEntryIds']),
      importance: _doubleValue(json['importance'], fallback: 0.56),
      confidence: _doubleValue(json['confidence'], fallback: 0.58),
      referenceCount: json['referenceCount'] as int? ?? 0,
      decay: _doubleValue(json['decay'], fallback: 0),
      archived: json['archived'] as bool? ?? false,
    );
  }

  MemoryEntry copyWith({
    String? summary,
    DateTime? updatedAt,
    DateTime? lastReferencedAt,
    double? importance,
    double? confidence,
    int? referenceCount,
    double? decay,
    bool? archived,
    String? sourceEntryId,
    List<String>? evidenceEntryIds,
  }) {
    return MemoryEntry(
      id: id,
      sourceEntryId: sourceEntryId ?? this.sourceEntryId,
      date: date,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReferencedAt: lastReferencedAt ?? this.lastReferencedAt,
      summary: summary ?? this.summary,
      keywords: keywords,
      emotion: emotion,
      people: people,
      tags: tags,
      evidenceEntryIds: evidenceEntryIds ?? this.evidenceEntryIds,
      importance: importance ?? this.importance,
      confidence: confidence ?? this.confidence,
      referenceCount: referenceCount ?? this.referenceCount,
      decay: decay ?? this.decay,
      archived: archived ?? this.archived,
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();

  static List<String> _legacyEvidenceEntryIds(Object? sourceEntryId) {
    final id = sourceEntryId?.toString().trim() ?? '';
    return id.isEmpty ? const [] : [id];
  }

  static double _doubleValue(Object? value, {required double fallback}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
