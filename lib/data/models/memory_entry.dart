class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.sourceEntryId,
    required this.date,
    required this.createdAt,
    required this.summary,
    required this.keywords,
    required this.emotion,
    required this.people,
    required this.tags,
  });

  final String id;
  final String sourceEntryId;
  final DateTime date;
  final DateTime createdAt;
  final String summary;
  final List<String> keywords;
  final String emotion;
  final List<String> people;
  final List<String> tags;

  String get title {
    if (tags.isNotEmpty) return tags.first;
    if (keywords.isNotEmpty) return keywords.first;
    return '${date.month}月${date.day}日的记忆';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceEntryId': sourceEntryId,
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'summary': summary,
        'keywords': keywords,
        'emotion': emotion,
        'people': people,
        'tags': tags,
      };

  static MemoryEntry fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date'] as String? ?? '') ??
        DateTime.now();
    return MemoryEntry(
      id: json['id'] as String? ??
          '${json['sourceEntryId'] ?? 'memory'}-${date.microsecondsSinceEpoch}',
      sourceEntryId: json['sourceEntryId'] as String? ?? '',
      date: date,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? date,
      summary: json['summary'] as String? ?? '',
      keywords: _stringList(json['keywords']),
      emotion: json['emotion'] as String? ?? '',
      people: _stringList(json['people']),
      tags: _stringList(json['tags']),
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
}
