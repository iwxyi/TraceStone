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
}
