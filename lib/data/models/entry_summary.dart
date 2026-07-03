class EntrySummary {
  const EntrySummary({
    required this.entryId,
    required this.date,
    required this.entryUpdatedAt,
    required this.generatedAt,
    required this.title,
    required this.brief,
    required this.keyPoints,
    required this.topics,
    required this.people,
    required this.places,
    required this.emotion,
    required this.importance,
    required this.importantQuotes,
    required this.generator,
  });

  final String entryId;
  final DateTime date;
  final DateTime entryUpdatedAt;
  final DateTime generatedAt;
  final String title;
  final String brief;
  final List<String> keyPoints;
  final List<String> topics;
  final List<String> people;
  final List<String> places;
  final String emotion;
  final double importance;
  final List<String> importantQuotes;
  final String generator;

  EntrySummary copyWith({
    DateTime? date,
    DateTime? generatedAt,
    String? title,
    String? brief,
    List<String>? keyPoints,
    List<String>? topics,
    List<String>? people,
    List<String>? places,
    String? emotion,
    double? importance,
    List<String>? importantQuotes,
    String? generator,
  }) {
    return EntrySummary(
      entryId: entryId,
      date: date ?? this.date,
      entryUpdatedAt: entryUpdatedAt,
      generatedAt: generatedAt ?? this.generatedAt,
      title: title ?? this.title,
      brief: brief ?? this.brief,
      keyPoints: keyPoints ?? this.keyPoints,
      topics: topics ?? this.topics,
      people: people ?? this.people,
      places: places ?? this.places,
      emotion: emotion ?? this.emotion,
      importance: importance ?? this.importance,
      importantQuotes: importantQuotes ?? this.importantQuotes,
      generator: generator ?? this.generator,
    );
  }

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'date': date.toIso8601String(),
        'entryUpdatedAt': entryUpdatedAt.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
        'title': title,
        'brief': brief,
        'keyPoints': keyPoints,
        'topics': topics,
        'people': people,
        'places': places,
        'emotion': emotion,
        'importance': importance,
        'importantQuotes': importantQuotes,
        'generator': generator,
      };

  static EntrySummary fromJson(Map<String, dynamic> json) {
    final entryUpdatedAt =
        DateTime.tryParse(json['entryUpdatedAt'] as String? ?? '') ??
            DateTime.now();
    return EntrySummary(
      entryId: json['entryId'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? entryUpdatedAt,
      entryUpdatedAt: entryUpdatedAt,
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      title: json['title'] as String? ?? '',
      brief: json['brief'] as String? ?? '',
      keyPoints: _stringList(json['keyPoints']),
      topics: _stringList(json['topics']),
      people: _stringList(json['people']),
      places: _stringList(json['places']),
      emotion: json['emotion'] as String? ?? '',
      importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
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
