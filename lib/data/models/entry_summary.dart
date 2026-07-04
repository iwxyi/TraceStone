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
    this.revision = 1,
    this.correctedAt,
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
  final int revision;
  final DateTime? correctedAt;

  EntrySummary copyWith({
    DateTime? date,
    DateTime? generatedAt,
    DateTime? entryUpdatedAt,
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
    int? revision,
    DateTime? correctedAt,
  }) {
    return EntrySummary(
      entryId: entryId,
      date: date ?? this.date,
      entryUpdatedAt: entryUpdatedAt ?? this.entryUpdatedAt,
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
      revision: revision ?? this.revision,
      correctedAt: correctedAt ?? this.correctedAt,
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
        'revision': revision,
        if (correctedAt != null) 'correctedAt': correctedAt!.toIso8601String(),
      };

  static EntrySummary fromJson(Map<String, dynamic> json) {
    final entryUpdatedAt = _dateValue(json['entryUpdatedAt']) ?? DateTime.now();
    return EntrySummary(
      entryId: _stringValue(json['entryId']),
      date: _dateValue(json['date']) ?? entryUpdatedAt,
      entryUpdatedAt: entryUpdatedAt,
      generatedAt: _dateValue(json['generatedAt']) ?? DateTime.now(),
      title: _stringValue(json['title']),
      brief: _stringValue(json['brief']),
      keyPoints: _stringList(json['keyPoints']),
      topics: _stringList(json['topics']),
      people: _stringList(json['people']),
      places: _stringList(json['places']),
      emotion: _stringValue(json['emotion']),
      importance: _doubleValue(json['importance']) ?? 0.5,
      importantQuotes: _stringList(json['importantQuotes']),
      generator: _stringValue(json['generator'], fallback: 'unknown'),
      revision: _intValue(json['revision']) ?? 1,
      correctedAt: _dateValue(json['correctedAt']),
    );
  }

  static String _stringValue(Object? value, {String fallback = ''}) =>
      value is String ? value : fallback;

  static DateTime? _dateValue(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static double? _doubleValue(Object? value) =>
      value is num ? value.toDouble() : null;

  static int? _intValue(Object? value) => value is num ? value.toInt() : null;

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
