class CompanionAnswer {
  const CompanionAnswer({
    required this.answer,
    required this.followUp,
    required this.sources,
    required this.usedFallback,
  });

  final String answer;
  final String followUp;
  final List<CompanionAnswerSource> sources;
  final bool usedFallback;
}

class CompanionAnswerSource {
  const CompanionAnswerSource({
    required this.title,
    required this.reason,
    required this.score,
  });

  final String title;
  final String reason;
  final int score;
}
