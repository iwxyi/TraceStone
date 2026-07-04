import '../models/ai_profile.dart';
import '../models/diary_insight.dart';

class ProfileProjection {
  const ProfileProjection({
    required this.profileFacts,
    required this.relationshipProfiles,
  });

  final List<ProfileFact> profileFacts;
  final List<RelationshipProfile> relationshipProfiles;
}

class ProfileProjectionService {
  const ProfileProjectionService();

  ProfileProjection build(List<DiaryInsight> insights) {
    return ProfileProjection(
      profileFacts: buildProfileFacts(insights),
      relationshipProfiles: buildRelationshipProfiles(insights),
    );
  }

  List<ProfileConflictNote> buildConflictNotes(List<DiaryInsight> insights) {
    final notes = <ProfileConflictNote>[];
    for (final insight in insights) {
      for (final contradiction in insight.contradictions) {
        final targetId = contradiction.oldMemoryId.trim();
        final newEvidence = contradiction.newEvidence.trim();
        final interpretation = contradiction.interpretation.trim();
        if (targetId.isEmpty && newEvidence.isEmpty) continue;
        notes.add(ProfileConflictNote(
          targetId: targetId.isEmpty ? 'unknown' : targetId,
          entryId: insight.entryId,
          entryDate: insight.entryDate,
          newEvidence: newEvidence,
          interpretation: interpretation,
          confidence: (contradiction.confidence ?? 0.55).clamp(0, 1),
          evidence: contradiction.evidence,
        ));
      }
    }
    notes.sort((a, b) {
      final byConfidence = b.confidence.compareTo(a.confidence);
      if (byConfidence != 0) return byConfidence;
      return b.entryDate.compareTo(a.entryDate);
    });
    return notes;
  }

  List<ProfileFact> buildProfileFacts(List<DiaryInsight> insights) {
    final buckets = <String, _ProfileFactBucket>{};
    for (final insight in insights) {
      for (final candidate in insight.profileUpdateCandidates) {
        final field = candidate.field.trim();
        final value = candidate.value.trim();
        if (field.isEmpty || value.isEmpty) continue;
        final key = '${field.toLowerCase()}\n${value.toLowerCase()}';
        final bucket = buckets.putIfAbsent(
          key,
          () => _ProfileFactBucket(field: field, value: value),
        );
        bucket.add(insight, candidate);
      }
    }
    final facts = buckets.values.map((bucket) => bucket.toFact()).toList();
    facts.sort((a, b) {
      final byStatus = _statusRank(b.status).compareTo(_statusRank(a.status));
      if (byStatus != 0) return byStatus;
      final byConfidence = b.confidence.compareTo(a.confidence);
      if (byConfidence != 0) return byConfidence;
      return b.lastSeenAt.compareTo(a.lastSeenAt);
    });
    return facts;
  }

  List<RelationshipProfile> buildRelationshipProfiles(
    List<DiaryInsight> insights,
  ) {
    final buckets = <String, _RelationshipBucket>{};
    for (final insight in insights) {
      for (final update in insight.relationshipUpdates) {
        final name = update.personName.trim();
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        final bucket = buckets.putIfAbsent(
          key,
          () => _RelationshipBucket(personName: name),
        );
        bucket.add(insight, update);
      }
    }
    final profiles =
        buckets.values.map((bucket) => bucket.toProfile()).toList();
    profiles.sort((a, b) {
      final byStatus = _statusRank(b.status).compareTo(_statusRank(a.status));
      if (byStatus != 0) return byStatus;
      final byCount = b.interactionCount.compareTo(a.interactionCount);
      if (byCount != 0) return byCount;
      return b.lastInteractionAt.compareTo(a.lastInteractionAt);
    });
    return profiles;
  }

  static ProfileFactStatus statusFor({
    required int evidenceCount,
    required int distinctDays,
    required double confidence,
  }) {
    if (evidenceCount >= 3 && distinctDays >= 2 && confidence >= 0.58) {
      return ProfileFactStatus.stable;
    }
    if (evidenceCount >= 2 || confidence >= 0.62) {
      return ProfileFactStatus.emerging;
    }
    return ProfileFactStatus.weak;
  }

  static int _statusRank(ProfileFactStatus status) {
    switch (status) {
      case ProfileFactStatus.stable:
        return 3;
      case ProfileFactStatus.emerging:
        return 2;
      case ProfileFactStatus.weak:
        return 1;
    }
  }
}

class _ProfileFactBucket {
  _ProfileFactBucket({required this.field, required this.value});

  final String field;
  final String value;
  final List<_ProfileFactEvidence> items = [];

  void add(DiaryInsight insight, ProfileUpdateCandidate candidate) {
    items.add(_ProfileFactEvidence(
      insight: insight,
      candidate: candidate,
    ));
  }

  ProfileFact toFact() {
    final dates = items.map((item) => _dayKey(item.insight.entryDate)).toSet();
    final confidences = items
        .map((item) => item.candidate.confidence)
        .whereType<double>()
        .toList();
    final averageConfidence = confidences.isEmpty
        ? 0.5
        : confidences.reduce((a, b) => a + b) / confidences.length;
    final sorted = [...items]
      ..sort((a, b) => a.insight.entryDate.compareTo(b.insight.entryDate));
    final evidence = <InsightEvidence>[
      for (final item in sorted)
        if (item.candidate.evidence.isEmpty)
          InsightEvidence(
            type: 'current_entry',
            id: item.insight.entryId,
            quote: item.candidate.value,
          )
        else
          ...item.candidate.evidence,
    ];
    return ProfileFact(
      id: '${field.toLowerCase()}:${value.toLowerCase()}',
      field: field,
      value: value,
      status: ProfileProjectionService.statusFor(
        evidenceCount: items.length,
        distinctDays: dates.length,
        confidence: averageConfidence,
      ),
      confidence: averageConfidence,
      evidenceCount: items.length,
      distinctDays: dates.length,
      firstSeenAt: sorted.first.insight.entryDate,
      lastSeenAt: sorted.last.insight.entryDate,
      evidence: evidence,
    );
  }
}

class _ProfileFactEvidence {
  const _ProfileFactEvidence({
    required this.insight,
    required this.candidate,
  });

  final DiaryInsight insight;
  final ProfileUpdateCandidate candidate;
}

class _RelationshipBucket {
  _RelationshipBucket({required this.personName});

  final String personName;
  final List<_RelationshipEvidence> items = [];

  void add(DiaryInsight insight, RelationshipUpdateCandidate update) {
    items.add(_RelationshipEvidence(insight: insight, update: update));
  }

  RelationshipProfile toProfile() {
    final dates = items.map((item) => _dayKey(item.insight.entryDate)).toSet();
    final confidences = items
        .map((item) => item.update.confidence)
        .whereType<double>()
        .toList();
    final averageConfidence = confidences.isEmpty
        ? 0.5
        : confidences.reduce((a, b) => a + b) / confidences.length;
    final sorted = [...items]
      ..sort((a, b) => b.insight.entryDate.compareTo(a.insight.entryDate));
    final relationship = _mostCommon(
      sorted
          .map((item) => item.update.relationship ?? '')
          .where((value) => value.trim().isNotEmpty),
    );
    final emotions = _topValues(
      sorted
          .map((item) => item.update.emotion ?? '')
          .where((value) => value.trim().isNotEmpty),
      limit: 4,
    );
    final patterns = _topValues(
      sorted
          .map((item) => item.update.pattern ?? '')
          .where((value) => value.trim().isNotEmpty),
      limit: 4,
    );
    final evidence = <InsightEvidence>[
      for (final item in sorted)
        if (item.update.evidence.isEmpty)
          InsightEvidence(
            type: 'current_entry',
            id: item.insight.entryId,
            quote: item.update.summary,
          )
        else
          ...item.update.evidence,
    ];
    return RelationshipProfile(
      personName: personName,
      names: [personName],
      status: ProfileProjectionService.statusFor(
        evidenceCount: items.length,
        distinctDays: dates.length,
        confidence: averageConfidence,
      ),
      confidence: averageConfidence,
      interactionCount: items.length,
      distinctDays: dates.length,
      lastInteractionAt: sorted.first.insight.entryDate,
      relationship: relationship,
      recentInteractions: [
        for (final item in sorted.take(5))
          RelationshipInteraction(
            entryId: item.insight.entryId,
            date: item.insight.entryDate,
            summary: item.update.summary,
            emotion: item.update.emotion,
            confidence: item.update.confidence,
          ),
      ],
      emotions: emotions,
      patterns: patterns,
      evidence: evidence,
    );
  }
}

class _RelationshipEvidence {
  const _RelationshipEvidence({
    required this.insight,
    required this.update,
  });

  final DiaryInsight insight;
  final RelationshipUpdateCandidate update;
}

String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

String? _mostCommon(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.first.key;
}

List<String> _topValues(Iterable<String> values, {required int limit}) {
  final counts = <String, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  return entries.take(limit).map((entry) => entry.key).toList();
}
