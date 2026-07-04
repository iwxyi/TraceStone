import '../models/ai_profile.dart';
import '../models/ai_profile_preference.dart';

enum AiProfileDecisionKind {
  confirmed,
  corrected,
  hidden,
  conflict,
  mergeCandidate,
  observe,
}

class AiProfileDecision {
  const AiProfileDecision({
    required this.kind,
    required this.targetType,
    required this.targetId,
    required this.title,
    required this.actionLabel,
    required this.reason,
    this.debugLine = '',
  });

  final AiProfileDecisionKind kind;
  final AiProfilePreferenceTargetType targetType;
  final String targetId;
  final String title;
  final String actionLabel;
  final String reason;
  final String debugLine;
}

class AiProfileDecisionService {
  const AiProfileDecisionService();

  List<AiProfileDecision> buildProfileFactDecisions({
    required List<ProfileFact> facts,
    required List<AiProfilePreference> preferences,
    List<ProfileConflictNote> conflicts = const [],
  }) {
    final decisions = <AiProfileDecision>[];
    final factsById = {for (final fact in facts) fact.id: fact};
    final prefsById = {
      for (final preference in preferences) preference.id: preference,
    };
    final factsByField = <String, List<ProfileFact>>{};
    for (final fact in facts) {
      factsByField.putIfAbsent(fact.field.toLowerCase(), () => []).add(fact);
    }

    for (final fact in facts) {
      final preference = prefsById[AiProfilePreference.keyFor(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: fact.id,
      )];
      final conflictCount =
          conflicts.where((item) => item.targetId == fact.id).length;
      final siblingCount = factsByField[fact.field.toLowerCase()]?.length ?? 0;
      final baseDebug =
          'target=${fact.id} status=${fact.status.name} confidence=${fact.confidence.toStringAsFixed(2)} evidence=${fact.evidenceCount} days=${fact.distinctDays}';

      if (preference?.correctedValue.trim().isNotEmpty ?? false) {
        decisions.add(AiProfileDecision(
          kind: AiProfileDecisionKind.corrected,
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: fact.id,
          title: fact.field,
          actionLabel: '使用用户修正',
          reason: preference!.correctedValue.trim(),
          debugLine: '$baseDebug preference=corrected',
        ));
        continue;
      }
      if (preference?.confirmed == true || fact.userConfirmed) {
        decisions.add(AiProfileDecision(
          kind: AiProfileDecisionKind.confirmed,
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: fact.id,
          title: fact.field,
          actionLabel: '用户已确认',
          reason: fact.value,
          debugLine: '$baseDebug preference=confirmed',
        ));
        continue;
      }
      if (conflictCount > 0) {
        decisions.add(AiProfileDecision(
          kind: AiProfileDecisionKind.conflict,
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: fact.id,
          title: fact.field,
          actionLabel: '需要核对冲突',
          reason: '有 $conflictCount 条新证据可能改变这条画像',
          debugLine: '$baseDebug conflicts=$conflictCount',
        ));
        continue;
      }
      if (siblingCount > 1) {
        decisions.add(AiProfileDecision(
          kind: AiProfileDecisionKind.mergeCandidate,
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: fact.id,
          title: fact.field,
          actionLabel: '同字段候选',
          reason: '同一字段下有 $siblingCount 条候选，需要确认是否合并或保留条件',
          debugLine: '$baseDebug siblingFacts=$siblingCount',
        ));
        continue;
      }
      decisions.add(AiProfileDecision(
        kind: fact.isStable
            ? AiProfileDecisionKind.mergeCandidate
            : AiProfileDecisionKind.observe,
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: fact.id,
        title: fact.field,
        actionLabel: fact.isStable ? '可进入稳定画像' : '继续观察',
        reason: fact.isStable ? fact.value : '证据仍少，暂不自动强化为稳定画像',
        debugLine: baseDebug,
      ));
    }

    for (final preference in preferences.where((item) =>
        item.targetType == AiProfilePreferenceTargetType.profileFact &&
        item.hidden &&
        !factsById.containsKey(item.targetId))) {
      decisions.add(AiProfileDecision(
        kind: AiProfileDecisionKind.hidden,
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: preference.targetId,
        title: preference.targetId,
        actionLabel: '用户已隐藏',
        reason: '当前投影中没有展示这条画像候选',
        debugLine:
            'target=${preference.targetId} preference=hidden updatedAt=${preference.updatedAt.toIso8601String()}',
      ));
    }

    decisions.sort(_compare);
    return decisions;
  }

  List<AiProfileDecision> buildRelationshipDecisions({
    required List<RelationshipProfile> profiles,
    required List<AiProfilePreference> preferences,
  }) {
    final decisions = <AiProfileDecision>[];
    final profilesByName = {
      for (final profile in profiles) profile.personName.toLowerCase(): profile,
    };
    final prefsById = {
      for (final preference in preferences) preference.id: preference,
    };

    for (final profile in profiles) {
      final preference = prefsById[AiProfilePreference.keyFor(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: profile.personName,
      )];
      final baseDebug =
          'target=${profile.personName} status=${profile.status.name} confidence=${profile.confidence.toStringAsFixed(2)} interactions=${profile.interactionCount} days=${profile.distinctDays}';
      if (preference?.correctedValue.trim().isNotEmpty ?? false) {
        decisions.add(AiProfileDecision(
          kind: AiProfileDecisionKind.corrected,
          targetType: AiProfilePreferenceTargetType.relationship,
          targetId: profile.personName,
          title: profile.personName,
          actionLabel: '使用用户修正',
          reason: preference!.correctedValue.trim(),
          debugLine: '$baseDebug preference=corrected',
        ));
      } else if (preference?.confirmed == true || profile.userConfirmed) {
        decisions.add(AiProfileDecision(
          kind: AiProfileDecisionKind.confirmed,
          targetType: AiProfilePreferenceTargetType.relationship,
          targetId: profile.personName,
          title: profile.personName,
          actionLabel: '用户已确认',
          reason: profile.relationship ?? '关系记录已确认',
          debugLine: '$baseDebug preference=confirmed',
        ));
      } else {
        decisions.add(AiProfileDecision(
          kind: profile.isStable
              ? AiProfileDecisionKind.mergeCandidate
              : AiProfileDecisionKind.observe,
          targetType: AiProfilePreferenceTargetType.relationship,
          targetId: profile.personName,
          title: profile.personName,
          actionLabel: profile.isStable ? '可进入稳定关系档案' : '继续观察',
          reason: profile.isStable
              ? '${profile.interactionCount} 次互动，关系标签：${profile.relationship ?? '未定'}'
              : '互动证据仍少，暂不强化为稳定关系',
          debugLine: baseDebug,
        ));
      }
    }

    for (final preference in preferences.where((item) =>
        item.targetType == AiProfilePreferenceTargetType.relationship &&
        item.hidden &&
        !profilesByName.containsKey(item.targetId.toLowerCase()))) {
      decisions.add(AiProfileDecision(
        kind: AiProfileDecisionKind.hidden,
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: preference.targetId,
        title: preference.targetId,
        actionLabel: '用户已隐藏',
        reason: '当前投影中没有展示这段关系',
        debugLine:
            'target=${preference.targetId} preference=hidden updatedAt=${preference.updatedAt.toIso8601String()}',
      ));
    }

    decisions.sort(_compare);
    return decisions;
  }

  int _compare(AiProfileDecision first, AiProfileDecision second) {
    final byKind = _rank(first.kind).compareTo(_rank(second.kind));
    if (byKind != 0) return byKind;
    return first.title.compareTo(second.title);
  }

  int _rank(AiProfileDecisionKind kind) {
    switch (kind) {
      case AiProfileDecisionKind.conflict:
        return 0;
      case AiProfileDecisionKind.corrected:
        return 1;
      case AiProfileDecisionKind.confirmed:
        return 2;
      case AiProfileDecisionKind.mergeCandidate:
        return 3;
      case AiProfileDecisionKind.observe:
        return 4;
      case AiProfileDecisionKind.hidden:
        return 5;
    }
  }
}
