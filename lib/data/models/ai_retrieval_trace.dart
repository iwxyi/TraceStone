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
      entryId: json['entryId'] as String? ?? '',
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      scenario: json['scenario'] as String?,
      contextSummary: json['contextSummary'] as String?,
      sourceCount: json['sourceCount'] as int? ?? 0,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => AiRetrievalTraceItem.fromJson(
              item as Map<String, dynamic>? ?? const {}))
          .toList(),
    );
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
      sourceType: json['sourceType'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      score: json['score'] as int? ?? 0,
      reasons: _stringList(json['reasons']),
      matchedTokens: _stringList(json['matchedTokens']),
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
}
