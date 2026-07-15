import 'companion_answer.dart';

enum AiResearchSessionState {
  running,
  completed,
  failed,
}

class AiResearchSession {
  const AiResearchSession({
    required this.id,
    required this.question,
    required this.startedAt,
    required this.updatedAt,
    required this.state,
    this.completedAt,
    this.error,
    this.answerPreview = '',
    this.steps = const [],
  });

  final String id;
  final String question;
  final DateTime startedAt;
  final DateTime updatedAt;
  final AiResearchSessionState state;
  final DateTime? completedAt;
  final String? error;
  final String answerPreview;
  final List<CompanionResearchStep> steps;

  int get evidenceCount {
    var count = 0;
    for (final step in steps) {
      count += step.evidence.length;
      for (final batch in step.batchSummaries) {
        count += batch.evidence.length;
      }
    }
    return count;
  }

  int get compressedCandidateCount {
    var count = 0;
    for (final step in steps) {
      for (final batch in step.batchSummaries) {
        count += batch.candidateCount;
      }
    }
    return count;
  }

  AiResearchSession copyWith({
    DateTime? updatedAt,
    AiResearchSessionState? state,
    DateTime? completedAt,
    String? error,
    String? answerPreview,
    List<CompanionResearchStep>? steps,
  }) {
    return AiResearchSession(
      id: id,
      question: question,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      state: state ?? this.state,
      completedAt: completedAt ?? this.completedAt,
      error: error,
      answerPreview: answerPreview ?? this.answerPreview,
      steps: steps ?? this.steps,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'startedAt': startedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'state': state.name,
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        if (error != null) 'error': error,
        'answerPreview': answerPreview,
        'steps': steps.map((step) => step.toJson()).toList(),
      };

  factory AiResearchSession.fromJson(Map<String, dynamic> json) {
    final startedAt = _date(json['startedAt']);
    return AiResearchSession(
      id: _string(json['id']),
      question: _string(json['question']),
      startedAt: startedAt,
      updatedAt: _date(json['updatedAt'], fallback: startedAt),
      state: AiResearchSessionState.values.firstWhere(
        (state) => state.name == json['state'],
        orElse: () => AiResearchSessionState.failed,
      ),
      completedAt: _nullableDate(json['completedAt']),
      error: json['error'] is String ? json['error'] as String : null,
      answerPreview: _string(json['answerPreview']),
      steps: _list(json['steps'])
          .whereType<Map<String, dynamic>>()
          .map(CompanionResearchStep.fromJson)
          .toList(growable: false),
    );
  }

  static String _string(Object? value) =>
      value is String ? value : '${value ?? ''}';

  static DateTime _date(Object? value, {DateTime? fallback}) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _nullableDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static List<Object?> _list(Object? value) {
    if (value is List) return value;
    return const [];
  }
}
