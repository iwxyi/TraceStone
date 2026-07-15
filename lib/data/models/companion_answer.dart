class CompanionAnswer {
  const CompanionAnswer({
    required this.answer,
    required this.followUp,
    required this.sources,
    required this.usedFallback,
    this.researchSteps = const [],
  });

  final String answer;
  final String followUp;
  final List<CompanionAnswerSource> sources;
  final bool usedFallback;
  final List<CompanionResearchStep> researchSteps;
}

class CompanionAnswerSource {
  const CompanionAnswerSource({
    required this.title,
    required this.reason,
    required this.score,
    this.sourceType,
    this.sourceId,
  });

  final String title;
  final String reason;
  final int score;
  final String? sourceType;
  final String? sourceId;
}

class CompanionResearchStep {
  const CompanionResearchStep({
    required this.title,
    required this.status,
    this.detail = '',
    this.evidence = const [],
    this.batchSummaries = const [],
    this.developerDetail = '',
  });

  final String title;
  final String status;
  final String detail;
  final List<CompanionResearchEvidence> evidence;
  final List<CompanionResearchBatchSummary> batchSummaries;
  final String developerDetail;

  Map<String, dynamic> toJson() => {
        'title': title,
        'status': status,
        'detail': detail,
        'evidence': evidence.map((item) => item.toJson()).toList(),
        'batchSummaries': batchSummaries.map((item) => item.toJson()).toList(),
        'developerDetail': developerDetail,
      };

  factory CompanionResearchStep.fromJson(Map<String, dynamic> json) {
    return CompanionResearchStep(
      title: _string(json['title']),
      status: _string(json['status']),
      detail: _string(json['detail']),
      evidence: _list(json['evidence'])
          .whereType<Map<String, dynamic>>()
          .map(CompanionResearchEvidence.fromJson)
          .toList(growable: false),
      batchSummaries: _list(json['batchSummaries'])
          .whereType<Map<String, dynamic>>()
          .map(CompanionResearchBatchSummary.fromJson)
          .toList(growable: false),
      developerDetail: _string(json['developerDetail']),
    );
  }
}

class CompanionResearchBatchSummary {
  const CompanionResearchBatchSummary({
    required this.title,
    required this.summary,
    required this.candidateCount,
    this.evidence = const [],
    this.developerDetail = '',
  });

  final String title;
  final String summary;
  final int candidateCount;
  final List<CompanionResearchEvidence> evidence;
  final String developerDetail;

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'candidateCount': candidateCount,
        'evidence': evidence.map((item) => item.toJson()).toList(),
        'developerDetail': developerDetail,
      };

  factory CompanionResearchBatchSummary.fromJson(Map<String, dynamic> json) {
    return CompanionResearchBatchSummary(
      title: _string(json['title']),
      summary: _string(json['summary']),
      candidateCount: _int(json['candidateCount']),
      evidence: _list(json['evidence'])
          .whereType<Map<String, dynamic>>()
          .map(CompanionResearchEvidence.fromJson)
          .toList(growable: false),
      developerDetail: _string(json['developerDetail']),
    );
  }
}

class CompanionResearchEvidence {
  const CompanionResearchEvidence({
    required this.title,
    required this.summary,
    required this.reason,
    required this.score,
    this.sourceType,
    this.sourceId,
    this.entryId,
  });

  final String title;
  final String summary;
  final String reason;
  final int score;
  final String? sourceType;
  final String? sourceId;
  final String? entryId;

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'reason': reason,
        'score': score,
        if (sourceType != null) 'sourceType': sourceType,
        if (sourceId != null) 'sourceId': sourceId,
        if (entryId != null) 'entryId': entryId,
      };

  factory CompanionResearchEvidence.fromJson(Map<String, dynamic> json) {
    return CompanionResearchEvidence(
      title: _string(json['title']),
      summary: _string(json['summary']),
      reason: _string(json['reason']),
      score: _int(json['score']),
      sourceType: _nullableString(json['sourceType']),
      sourceId: _nullableString(json['sourceId']),
      entryId: _nullableString(json['entryId']),
    );
  }
}

String _string(Object? value) => value is String ? value : '${value ?? ''}';

String? _nullableString(Object? value) => value is String ? value : null;

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

List<Object?> _list(Object? value) {
  if (value is List) return value;
  return const [];
}
