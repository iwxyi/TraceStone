import 'diary_insight.dart';

enum ProfileFactStatus { stable, emerging, weak }

class ProfileFact {
  const ProfileFact({
    required this.id,
    required this.field,
    required this.value,
    required this.status,
    required this.confidence,
    required this.evidenceCount,
    required this.distinctDays,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.evidence = const [],
    this.userConfirmed = false,
  });

  final String id;
  final String field;
  final String value;
  final ProfileFactStatus status;
  final double confidence;
  final int evidenceCount;
  final int distinctDays;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final List<InsightEvidence> evidence;
  final bool userConfirmed;

  bool get isStable => status == ProfileFactStatus.stable || userConfirmed;

  ProfileFact copyWith({
    String? value,
    ProfileFactStatus? status,
    double? confidence,
    bool? userConfirmed,
  }) {
    return ProfileFact(
      id: id,
      field: field,
      value: value ?? this.value,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      evidenceCount: evidenceCount,
      distinctDays: distinctDays,
      firstSeenAt: firstSeenAt,
      lastSeenAt: lastSeenAt,
      evidence: evidence,
      userConfirmed: userConfirmed ?? this.userConfirmed,
    );
  }
}

class RelationshipProfile {
  const RelationshipProfile({
    required this.personName,
    required this.names,
    required this.status,
    required this.confidence,
    required this.interactionCount,
    required this.distinctDays,
    required this.lastInteractionAt,
    this.relationship,
    this.recentInteractions = const [],
    this.emotions = const [],
    this.patterns = const [],
    this.evidence = const [],
    this.userConfirmed = false,
  });

  final String personName;
  final List<String> names;
  final ProfileFactStatus status;
  final double confidence;
  final int interactionCount;
  final int distinctDays;
  final DateTime lastInteractionAt;
  final String? relationship;
  final List<RelationshipInteraction> recentInteractions;
  final List<String> emotions;
  final List<String> patterns;
  final List<InsightEvidence> evidence;
  final bool userConfirmed;

  bool get isStable => status == ProfileFactStatus.stable || userConfirmed;

  RelationshipProfile copyWith({
    String? relationship,
    ProfileFactStatus? status,
    double? confidence,
    bool? userConfirmed,
  }) {
    return RelationshipProfile(
      personName: personName,
      names: names,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      interactionCount: interactionCount,
      distinctDays: distinctDays,
      lastInteractionAt: lastInteractionAt,
      relationship: relationship ?? this.relationship,
      recentInteractions: recentInteractions,
      emotions: emotions,
      patterns: patterns,
      evidence: evidence,
      userConfirmed: userConfirmed ?? this.userConfirmed,
    );
  }
}

class RelationshipInteraction {
  const RelationshipInteraction({
    required this.entryId,
    required this.date,
    required this.summary,
    this.emotion,
    this.confidence,
  });

  final String entryId;
  final DateTime date;
  final String summary;
  final String? emotion;
  final double? confidence;
}

class ProfileConflictNote {
  const ProfileConflictNote({
    required this.targetId,
    required this.entryId,
    required this.entryDate,
    required this.newEvidence,
    required this.interpretation,
    required this.confidence,
    this.evidence = const [],
  });

  final String targetId;
  final String entryId;
  final DateTime entryDate;
  final String newEvidence;
  final String interpretation;
  final double confidence;
  final List<InsightEvidence> evidence;
}
