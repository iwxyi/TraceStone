class EntrySummary {
  const EntrySummary({
    required this.entryId,
    required this.entryUpdatedAt,
    required this.generatedAt,
    required this.brief,
    required this.keyPoints,
    required this.topics,
    required this.people,
    required this.places,
    required this.importantQuotes,
    required this.generator,
  });

  final String entryId;
  final DateTime entryUpdatedAt;
  final DateTime generatedAt;
  final String brief;
  final List<String> keyPoints;
  final List<String> topics;
  final List<String> people;
  final List<String> places;
  final List<String> importantQuotes;
  final String generator;

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'entryUpdatedAt': entryUpdatedAt.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
        'brief': brief,
        'keyPoints': keyPoints,
        'topics': topics,
        'people': people,
        'places': places,
        'importantQuotes': importantQuotes,
        'generator': generator,
      };

  static EntrySummary fromJson(Map<String, dynamic> json) {
    return EntrySummary(
      entryId: json['entryId'] as String? ?? '',
      entryUpdatedAt:
          DateTime.tryParse(json['entryUpdatedAt'] as String? ?? '') ??
              DateTime.now(),
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      brief: json['brief'] as String? ?? '',
      keyPoints: _stringList(json['keyPoints']),
      topics: _stringList(json['topics']),
      people: _stringList(json['people']),
      places: _stringList(json['places']),
      importantQuotes: _stringList(json['importantQuotes']),
      generator: json['generator'] as String? ?? 'unknown',
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
}
