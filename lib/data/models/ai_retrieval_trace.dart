class AiRetrievalTrace {
  const AiRetrievalTrace({
    required this.entryId,
    required this.generatedAt,
    required this.items,
    this.scenario,
    this.contextSummary,
    this.sourceCount = 0,
  });

  final String entryId;
  final DateTime generatedAt;
  final List<AiRetrievalTraceItem> items;
  final String? scenario;
  final String? contextSummary;
  final int sourceCount;

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'generatedAt': generatedAt.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'scenario': scenario,
        'contextSummary': contextSummary,
        'sourceCount': sourceCount,
      };

  static AiRetrievalTrace fromJson(Map<String, dynamic> json) {
    return AiRetrievalTrace(
      entryId: _stringValue(json['entryId']),
      generatedAt: DateTime.tryParse(_stringValue(json['generatedAt'])) ??
          DateTime.now(),
      scenario: _nullableString(json['scenario']),
      contextSummary: _nullableString(json['contextSummary']),
      sourceCount: _intValue(json['sourceCount']),
      items: _mapList(json['items'])
          .map((item) => AiRetrievalTraceItem.fromJson(item))
          .toList(),
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static String? _nullableString(Object? value) =>
      value is String ? value : null;

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => {
              for (final entry in item.entries)
                if (entry.key is String) entry.key as String: entry.value,
            })
        .toList();
  }
}

class AiRetrievalTraceItem {
  const AiRetrievalTraceItem({
    required this.sourceType,
    required this.sourceId,
    required this.title,
    required this.summary,
    required this.score,
    required this.reasons,
    required this.matchedTokens,
  });

  final String sourceType;
  final String sourceId;
  final String title;
  final String summary;
  final int score;
  final List<String> reasons;
  final List<String> matchedTokens;

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType,
        'sourceId': sourceId,
        'title': title,
        'summary': summary,
        'score': score,
        'reasons': reasons,
        'matchedTokens': matchedTokens,
      };

  static AiRetrievalTraceItem fromJson(Map<String, dynamic> json) {
    return AiRetrievalTraceItem(
      sourceType: _stringValue(json['sourceType']),
      sourceId: _stringValue(json['sourceId']),
      title: _stringValue(json['title']),
      summary: _stringValue(json['summary']),
      score: _intValue(json['score']),
      reasons: _stringList(json['reasons']),
      matchedTokens: _stringList(json['matchedTokens']),
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
