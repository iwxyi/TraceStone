class DiaryInsight {
  const DiaryInsight({
    required this.entryId,
    required this.entryDate,
    required this.generatedAt,
    required this.reflection,
    required this.relatedMemories,
    required this.emotion,
    required this.keywords,
    required this.people,
    required this.stoneTitle,
    required this.stoneDescription,
    required this.memorySummary,
    required this.memoryTags,
  });

  final String entryId;
  final DateTime entryDate;
  final DateTime generatedAt;
  final String reflection;
  final List<RelatedMemoryInsight> relatedMemories;
  final String emotion;
  final List<String> keywords;
  final List<String> people;
  final String stoneTitle;
  final String stoneDescription;
  final String memorySummary;
  final List<String> memoryTags;

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'entryDate': entryDate.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
        'reflection': reflection,
        'relatedMemories': relatedMemories.map((item) => item.toJson()).toList(),
        'emotion': emotion,
        'keywords': keywords,
        'people': people,
        'stoneTitle': stoneTitle,
        'stoneDescription': stoneDescription,
        'memorySummary': memorySummary,
        'memoryTags': memoryTags,
      };

  static DiaryInsight fromJson(Map<String, dynamic> json) {
    return DiaryInsight(
      entryId: json['entryId'] as String? ?? '',
      entryDate: DateTime.tryParse(json['entryDate'] as String? ?? '') ??
          DateTime.now(),
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      reflection: json['reflection'] as String? ?? '',
      relatedMemories: (json['relatedMemories'] as List<dynamic>? ?? [])
          .map((item) => RelatedMemoryInsight.fromJson(
              item as Map<String, dynamic>? ?? const {}))
          .toList(),
      emotion: json['emotion'] as String? ?? '',
      keywords: _stringList(json['keywords']),
      people: _stringList(json['people']),
      stoneTitle: json['stoneTitle'] as String? ?? '',
      stoneDescription: json['stoneDescription'] as String? ?? '',
      memorySummary: json['memorySummary'] as String? ?? '',
      memoryTags: _stringList(json['memoryTags']),
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
}

class RelatedMemoryInsight {
  const RelatedMemoryInsight({
    required this.title,
    required this.reason,
    this.entryId,
  });

  final String title;
  final String reason;
  final String? entryId;

  Map<String, dynamic> toJson() => {
        'title': title,
        'reason': reason,
        'entryId': entryId,
      };

  static RelatedMemoryInsight fromJson(Map<String, dynamic> json) {
    return RelatedMemoryInsight(
      title: json['title'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      entryId: json['entryId'] as String?,
    );
  }
}
