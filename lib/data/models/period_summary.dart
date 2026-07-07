enum PeriodSummaryType { month, year }

enum PeriodSummaryState {
  idle,
  generating,
  completed,
  failed,
}

class PeriodSummaryStatus {
  const PeriodSummaryStatus({
    required this.id,
    required this.state,
    required this.updatedAt,
    this.message,
  });

  final String id;
  final PeriodSummaryState state;
  final DateTime updatedAt;
  final String? message;

  Map<String, dynamic> toJson() => {
        'id': id,
        'state': state.name,
        'updatedAt': updatedAt.toIso8601String(),
        'message': message,
      };

  static PeriodSummaryStatus fromJson(Map<String, dynamic> json) {
    final stateName = json['state'] is String
        ? json['state'] as String
        : PeriodSummaryState.idle.name;
    return PeriodSummaryStatus(
      id: json['id'] is String ? json['id'] as String : '',
      state: PeriodSummaryState.values.firstWhere(
        (item) => item.name == stateName,
        orElse: () => PeriodSummaryState.idle,
      ),
      updatedAt: json['updatedAt'] is String
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      message: json['message'] is String ? json['message'] as String : null,
    );
  }
}

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
    this.relationshipHighlights = const [],
    this.stoneHighlights = const [],
    this.growthHighlights = const [],
    this.notableChanges = const [],
    this.outlook = '',
    this.contextDebugSummary = '',
    this.contextSourceLines = const [],
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
  final List<String> relationshipHighlights;
  final List<String> stoneHighlights;
  final List<String> growthHighlights;
  final List<String> notableChanges;
  final String outlook;
  final String contextDebugSummary;
  final List<String> contextSourceLines;

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
        'relationshipHighlights': relationshipHighlights,
        'stoneHighlights': stoneHighlights,
        'growthHighlights': growthHighlights,
        'notableChanges': notableChanges,
        'outlook': outlook,
        'contextDebugSummary': contextDebugSummary,
        'contextSourceLines': contextSourceLines,
      };

  static PeriodSummary fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] is String
        ? json['type'] as String
        : PeriodSummaryType.month.name;
    final entryCount = json['entryCount'];
    return PeriodSummary(
      id: json['id'] is String ? json['id'] as String : '',
      type: PeriodSummaryType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => PeriodSummaryType.month,
      ),
      startDate: json['startDate'] is String
          ? DateTime.tryParse(json['startDate'] as String) ?? DateTime.now()
          : DateTime.now(),
      endDate: json['endDate'] is String
          ? DateTime.tryParse(json['endDate'] as String) ?? DateTime.now()
          : DateTime.now(),
      generatedAt: json['generatedAt'] is String
          ? DateTime.tryParse(json['generatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      entryCount: entryCount is num ? entryCount.toInt() : 0,
      brief: json['brief'] is String ? json['brief'] as String : '',
      themes: _stringList(json['themes']),
      emotions: _stringList(json['emotions']),
      representativeEntryIds: _stringList(json['representativeEntryIds']),
      generator:
          json['generator'] is String ? json['generator'] as String : 'unknown',
      relationshipHighlights: _stringList(json['relationshipHighlights']),
      stoneHighlights: _stringList(json['stoneHighlights']),
      growthHighlights: _stringList(json['growthHighlights']),
      notableChanges: _stringList(json['notableChanges']),
      outlook: json['outlook'] is String ? json['outlook'] as String : '',
      contextDebugSummary: json['contextDebugSummary'] is String
          ? json['contextDebugSummary'] as String
          : '',
      contextSourceLines: _stringList(json['contextSourceLines']),
    );
  }

  static List<String> _stringList(Object? value) =>
      (value is List ? value : const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
}
