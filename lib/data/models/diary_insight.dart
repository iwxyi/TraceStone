class DiaryInsight {
  const DiaryInsight({
    required this.entryId,
    required this.entryDate,
    required this.generatedAt,
    required this.reflection,
    required this.relatedMemories,
    required this.emotion,
    required this.keywords,
    required this.people,
    required this.stoneTitle,
    required this.stoneDescription,
    required this.memorySummary,
    required this.memoryTags,
    this.facts = const [],
    this.signals = const [],
    this.hypotheses = const [],
    this.suggestions = const [],
    this.profileUpdateCandidates = const [],
    this.relationshipUpdates = const [],
    this.contradictions = const [],
  });

  final String entryId;
  final DateTime entryDate;
  final DateTime generatedAt;
  final String reflection;
  final List<RelatedMemoryInsight> relatedMemories;
  final String emotion;
  final List<String> keywords;
  final List<String> people;
  final String stoneTitle;
  final String stoneDescription;
  final String memorySummary;
  final List<String> memoryTags;
  final List<InsightClaim> facts;
  final List<InsightClaim> signals;
  final List<InsightClaim> hypotheses;
  final List<InsightClaim> suggestions;
  final List<ProfileUpdateCandidate> profileUpdateCandidates;
  final List<RelationshipUpdateCandidate> relationshipUpdates;
  final List<InsightContradiction> contradictions;

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'entryDate': entryDate.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
        'reflection': reflection,
        'relatedMemories':
            relatedMemories.map((item) => item.toJson()).toList(),
        'emotion': emotion,
        'keywords': keywords,
        'people': people,
        'stoneTitle': stoneTitle,
        'stoneDescription': stoneDescription,
        'memorySummary': memorySummary,
        'memoryTags': memoryTags,
        'facts': facts.map((item) => item.toJson()).toList(),
        'signals': signals.map((item) => item.toJson()).toList(),
        'hypotheses': hypotheses.map((item) => item.toJson()).toList(),
        'suggestions': suggestions.map((item) => item.toJson()).toList(),
        'profileUpdateCandidates':
            profileUpdateCandidates.map((item) => item.toJson()).toList(),
        'relationshipUpdates':
            relationshipUpdates.map((item) => item.toJson()).toList(),
        'contradictions': contradictions.map((item) => item.toJson()).toList(),
      };

  static DiaryInsight fromJson(Map<String, dynamic> json) {
    return DiaryInsight(
      entryId: json['entryId'] as String? ?? '',
      entryDate: DateTime.tryParse(json['entryDate'] as String? ?? '') ??
          DateTime.now(),
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      reflection: json['reflection'] as String? ?? '',
      relatedMemories: (json['relatedMemories'] as List<dynamic>? ?? [])
          .map((item) => RelatedMemoryInsight.fromJson(
              item as Map<String, dynamic>? ?? const {}))
          .toList(),
      emotion: json['emotion'] as String? ?? '',
      keywords: _stringList(json['keywords']),
      people: _stringList(json['people']),
      stoneTitle: json['stoneTitle'] as String? ?? '',
      stoneDescription: json['stoneDescription'] as String? ?? '',
      memorySummary: json['memorySummary'] as String? ?? '',
      memoryTags: _stringList(json['memoryTags']),
      facts: _claimList(json['facts']),
      signals: _claimList(json['signals']),
      hypotheses: _claimList(json['hypotheses']),
      suggestions: _claimList(json['suggestions']),
      profileUpdateCandidates: _profileUpdateList(
        json['profileUpdateCandidates'] ?? json['profile_update_candidates'],
      ),
      relationshipUpdates: _relationshipUpdateList(
        json['relationshipUpdates'] ?? json['relationship_updates'],
      ),
      contradictions: _contradictionList(json['contradictions']),
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();

  static List<InsightClaim> _claimList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) =>
              InsightClaim.fromJson(item as Map<String, dynamic>? ?? const {}))
          .where((item) => item.text.isNotEmpty)
          .toList();

  static List<ProfileUpdateCandidate> _profileUpdateList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => ProfileUpdateCandidate.fromJson(
              item as Map<String, dynamic>? ?? const {}))
          .where((item) => item.field.isNotEmpty && item.value.isNotEmpty)
          .toList();

  static List<RelationshipUpdateCandidate> _relationshipUpdateList(
          Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => RelationshipUpdateCandidate.fromJson(
              item as Map<String, dynamic>? ?? const {}))
          .where(
              (item) => item.personName.isNotEmpty || item.summary.isNotEmpty)
          .toList();

  static List<InsightContradiction> _contradictionList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => InsightContradiction.fromJson(
              item as Map<String, dynamic>? ?? const {}))
          .where((item) =>
              item.oldMemoryId.isNotEmpty || item.newEvidence.isNotEmpty)
          .toList();
}

class RelatedMemoryInsight {
  const RelatedMemoryInsight({
    required this.title,
    required this.reason,
    this.entryId,
  });

  final String title;
  final String reason;
  final String? entryId;

  Map<String, dynamic> toJson() => {
        'title': title,
        'reason': reason,
        'entryId': entryId,
      };

  static RelatedMemoryInsight fromJson(Map<String, dynamic> json) {
    return RelatedMemoryInsight(
      title: json['title'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      entryId: json['entryId'] as String?,
    );
  }
}

class InsightClaim {
  const InsightClaim({
    required this.text,
    this.confidence,
    this.evidence = const [],
  });

  final String text;
  final double? confidence;
  final List<InsightEvidence> evidence;

  Map<String, dynamic> toJson() => {
        'text': text,
        'confidence': confidence,
        'evidence': evidence.map((item) => item.toJson()).toList(),
      };

  static InsightClaim fromJson(Map<String, dynamic> json) {
    return InsightClaim(
      text: json['text'] as String? ?? '',
      confidence: _doubleValue(json['confidence']),
      evidence: (json['evidence'] as List<dynamic>? ?? [])
          .map((item) => InsightEvidence.fromJson(
              item as Map<String, dynamic>? ?? const {}))
          .where((item) => item.type.isNotEmpty || item.id.isNotEmpty)
          .toList(),
    );
  }

  static double? _doubleValue(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class InsightEvidence {
  const InsightEvidence({
    required this.type,
    required this.id,
    this.date,
    this.quote,
    this.summary,
    this.relevance,
  });

  final String type;
  final String id;
  final DateTime? date;
  final String? quote;
  final String? summary;
  final String? relevance;

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'date': date?.toIso8601String(),
        'quote': quote,
        'summary': summary,
        'relevance': relevance,
      };

  static InsightEvidence fromJson(Map<String, dynamic> json) {
    return InsightEvidence(
      type: json['type'] as String? ?? '',
      id: json['id'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? ''),
      quote: json['quote'] as String?,
      summary: json['summary'] as String?,
      relevance: json['relevance'] as String?,
    );
  }
}

class ProfileUpdateCandidate {
  const ProfileUpdateCandidate({
    required this.field,
    required this.value,
    this.action = 'candidate',
    this.confidence,
    this.evidence = const [],
  });

  final String field;
  final String value;
  final String action;
  final double? confidence;
  final List<InsightEvidence> evidence;

  Map<String, dynamic> toJson() => {
        'field': field,
        'value': value,
        'action': action,
        'confidence': confidence,
        'evidence': evidence.map((item) => item.toJson()).toList(),
      };

  static ProfileUpdateCandidate fromJson(Map<String, dynamic> json) {
    return ProfileUpdateCandidate(
      field: json['field'] as String? ?? '',
      value: json['value'] as String? ?? '',
      action: json['action'] as String? ?? 'candidate',
      confidence: _doubleValue(json['confidence']),
      evidence: _evidenceList(json['evidence']),
    );
  }
}

class RelationshipUpdateCandidate {
  const RelationshipUpdateCandidate({
    required this.personName,
    required this.summary,
    this.relationship,
    this.emotion,
    this.pattern,
    this.confidence,
    this.evidence = const [],
  });

  final String personName;
  final String summary;
  final String? relationship;
  final String? emotion;
  final String? pattern;
  final double? confidence;
  final List<InsightEvidence> evidence;

  Map<String, dynamic> toJson() => {
        'personName': personName,
        'summary': summary,
        'relationship': relationship,
        'emotion': emotion,
        'pattern': pattern,
        'confidence': confidence,
        'evidence': evidence.map((item) => item.toJson()).toList(),
      };

  static RelationshipUpdateCandidate fromJson(Map<String, dynamic> json) {
    return RelationshipUpdateCandidate(
      personName:
          json['personName'] as String? ?? json['person'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      relationship: json['relationship'] as String?,
      emotion: json['emotion'] as String?,
      pattern: json['pattern'] as String?,
      confidence: _doubleValue(json['confidence']),
      evidence: _evidenceList(json['evidence']),
    );
  }
}

class InsightContradiction {
  const InsightContradiction({
    required this.oldMemoryId,
    required this.newEvidence,
    required this.interpretation,
    this.confidence,
    this.evidence = const [],
  });

  final String oldMemoryId;
  final String newEvidence;
  final String interpretation;
  final double? confidence;
  final List<InsightEvidence> evidence;

  Map<String, dynamic> toJson() => {
        'oldMemoryId': oldMemoryId,
        'newEvidence': newEvidence,
        'interpretation': interpretation,
        'confidence': confidence,
        'evidence': evidence.map((item) => item.toJson()).toList(),
      };

  static InsightContradiction fromJson(Map<String, dynamic> json) {
    return InsightContradiction(
      oldMemoryId: json['oldMemoryId'] as String? ??
          json['old_memory_id'] as String? ??
          '',
      newEvidence: json['newEvidence'] as String? ??
          json['new_evidence'] as String? ??
          '',
      interpretation: json['interpretation'] as String? ?? '',
      confidence: _doubleValue(json['confidence']),
      evidence: _evidenceList(json['evidence']),
    );
  }
}

List<InsightEvidence> _evidenceList(Object? value) {
  return (value as List<dynamic>? ?? [])
      .map((item) =>
          InsightEvidence.fromJson(item as Map<String, dynamic>? ?? const {}))
      .where((item) => item.type.isNotEmpty || item.id.isNotEmpty)
      .toList();
}

double? _doubleValue(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
