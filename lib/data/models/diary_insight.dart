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
      entryId: _stringValue(json['entryId']),
      entryDate:
          DateTime.tryParse(_stringValue(json['entryDate'])) ?? DateTime.now(),
      generatedAt: DateTime.tryParse(_stringValue(json['generatedAt'])) ??
          DateTime.now(),
      reflection: _stringValue(json['reflection']),
      relatedMemories: _mapList(json['relatedMemories'])
          .map(RelatedMemoryInsight.fromJson)
          .toList(),
      emotion: _stringValue(json['emotion']),
      keywords: _stringList(json['keywords']),
      people: _stringList(json['people']),
      stoneTitle: _stringValue(json['stoneTitle']),
      stoneDescription: _stringValue(json['stoneDescription']),
      memorySummary: _stringValue(json['memorySummary']),
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

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .where((item) => item != null)
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
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

  static List<InsightClaim> _claimList(Object? value) => _mapList(value)
      .map(InsightClaim.fromJson)
      .where((item) => item.text.isNotEmpty)
      .toList();

  static List<ProfileUpdateCandidate> _profileUpdateList(Object? value) =>
      _mapList(value)
          .map(ProfileUpdateCandidate.fromJson)
          .where((item) => item.field.isNotEmpty && item.value.isNotEmpty)
          .toList();

  static List<RelationshipUpdateCandidate> _relationshipUpdateList(
          Object? value) =>
      _mapList(value)
          .map(RelationshipUpdateCandidate.fromJson)
          .where(
              (item) => item.personName.isNotEmpty || item.summary.isNotEmpty)
          .toList();

  static List<InsightContradiction> _contradictionList(Object? value) =>
      _mapList(value)
          .map(InsightContradiction.fromJson)
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
      title: _stringValue(json['title']),
      reason: _stringValue(json['reason']),
      entryId: _nullableString(json['entryId']) ??
          _nullableString(json['entry_id']) ??
          _nullableString(json['sourceId']) ??
          _nullableString(json['source_id']),
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
      text: _stringValue(json['text']),
      confidence: _doubleValue(json['confidence']),
      evidence: _evidenceList(json['evidence'])
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
      type: _stringValue(json['type']),
      id: _stringValue(json['id']),
      date: DateTime.tryParse(_stringValue(json['date'])),
      quote: _nullableString(json['quote']),
      summary: _nullableString(json['summary']),
      relevance: _nullableString(json['relevance']),
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
      field: _stringValue(json['field']),
      value: _stringValue(json['value']),
      action: _stringValue(json['action']).isEmpty
          ? 'candidate'
          : _stringValue(json['action']),
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
      personName: _stringValue(json['personName']).isNotEmpty
          ? _stringValue(json['personName'])
          : _stringValue(json['person']),
      summary: _stringValue(json['summary']),
      relationship: _nullableString(json['relationship']),
      emotion: _nullableString(json['emotion']),
      pattern: _nullableString(json['pattern']),
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
      oldMemoryId: _stringValue(json['oldMemoryId']).isNotEmpty
          ? _stringValue(json['oldMemoryId'])
          : _stringValue(json['old_memory_id']),
      newEvidence: _stringValue(json['newEvidence']).isNotEmpty
          ? _stringValue(json['newEvidence'])
          : _stringValue(json['new_evidence']),
      interpretation: _stringValue(json['interpretation']),
      confidence: _doubleValue(json['confidence']),
      evidence: _evidenceList(json['evidence']),
    );
  }
}

List<InsightEvidence> _evidenceList(Object? value) {
  return _mapList(value)
      .map(InsightEvidence.fromJson)
      .where((item) => item.type.isNotEmpty || item.id.isNotEmpty)
      .toList();
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => {
            for (final entry in item.entries)
              if (entry.key is String) entry.key as String: entry.value,
          })
      .toList();
}

String _stringValue(Object? value) =>
    value is String ? value : value?.toString() ?? '';

String? _nullableString(Object? value) => value is String ? value : null;

double? _doubleValue(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
