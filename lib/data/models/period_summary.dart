enum PeriodSummaryType { month, year }

class PeriodSummary {
  const PeriodSummary({
    required this.id,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.generatedAt,
    required this.entryCount,
    required this.brief,
    required this.themes,
    required this.emotions,
    required this.representativeEntryIds,
    required this.generator,
  });

  final String id;
  final PeriodSummaryType type;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime generatedAt;
  final int entryCount;
  final String brief;
  final List<String> themes;
  final List<String> emotions;
  final List<String> representativeEntryIds;
  final String generator;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
        'entryCount': entryCount,
        'brief': brief,
        'themes': themes,
        'emotions': emotions,
        'representativeEntryIds': representativeEntryIds,
        'generator': generator,
      };

  static PeriodSummary fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? PeriodSummaryType.month.name;
    return PeriodSummary(
      id: json['id'] as String? ?? '',
      type: PeriodSummaryType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => PeriodSummaryType.month,
      ),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '') ??
          DateTime.now(),
      endDate:
          DateTime.tryParse(json['endDate'] as String? ?? '') ?? DateTime.now(),
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      entryCount: json['entryCount'] as int? ?? 0,
      brief: json['brief'] as String? ?? '',
      themes: _stringList(json['themes']),
      emotions: _stringList(json['emotions']),
      representativeEntryIds: _stringList(json['representativeEntryIds']),
      generator: json['generator'] as String? ?? 'unknown',
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
}
