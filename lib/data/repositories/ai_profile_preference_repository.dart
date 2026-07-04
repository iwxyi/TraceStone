import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_profile.dart';
import '../models/ai_profile_preference.dart';

class AiProfilePreferenceRepository {
  const AiProfilePreferenceRepository();

  static const _indexKey = 'ai.profilePreferences.index';
  static const _prefix = 'ai.profilePreferences.';
  static const _mergeHistoryIndexKey = 'ai.relationshipMergeHistory.index';
  static const _mergeHistoryPrefix = 'ai.relationshipMergeHistory.';

  Future<List<AiProfilePreference>> listPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = _safeGetStringList(prefs, _indexKey) ?? [];
    final items = <AiProfilePreference>[];
    for (final id in ids) {
      final item = await _getPreferenceById(prefs, id);
      if (item == null) continue;
      if (item.targetId.isNotEmpty) items.add(item);
    }
    await prefs.setStringList(_indexKey, items.map((item) => item.id).toList());
    return items;
  }

  Future<AiProfilePreference?> getPreference({
    required AiProfilePreferenceTargetType targetType,
    required String targetId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final id = AiProfilePreference.keyFor(
      targetType: targetType,
      targetId: targetId,
    );
    return _getPreferenceById(prefs, id);
  }

  Future<void> setConfirmed({
    required AiProfilePreferenceTargetType targetType,
    required String targetId,
    required bool confirmed,
  }) async {
    final existing = await getPreference(
      targetType: targetType,
      targetId: targetId,
    );
    await _savePreference(
      (existing ??
              AiProfilePreference(
                targetType: targetType,
                targetId: targetId,
                updatedAt: DateTime.now(),
              ))
          .copyWith(
        confirmed: confirmed,
        hidden: false,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> setHidden({
    required AiProfilePreferenceTargetType targetType,
    required String targetId,
    required bool hidden,
  }) async {
    final existing = await getPreference(
      targetType: targetType,
      targetId: targetId,
    );
    await _savePreference(
      (existing ??
              AiProfilePreference(
                targetType: targetType,
                targetId: targetId,
                updatedAt: DateTime.now(),
              ))
          .copyWith(
        hidden: hidden,
        confirmed: hidden ? false : existing?.confirmed,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> setCorrectedValue({
    required AiProfilePreferenceTargetType targetType,
    required String targetId,
    required String correctedValue,
  }) async {
    final existing = await getPreference(
      targetType: targetType,
      targetId: targetId,
    );
    final value = correctedValue.trim();
    await _savePreference(
      (existing ??
              AiProfilePreference(
                targetType: targetType,
                targetId: targetId,
                updatedAt: DateTime.now(),
              ))
          .copyWith(
        correctedValue: value,
        confirmed: value.isNotEmpty ? true : existing?.confirmed,
        hidden: false,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> setMergedRelationship({
    required String sourcePersonName,
    required String targetPersonName,
  }) async {
    final source = sourcePersonName.trim();
    final target = targetPersonName.trim();
    if (source.isEmpty || target.isEmpty) return;
    if (source.toLowerCase() == target.toLowerCase()) return;
    final existing = await getPreference(
      targetType: AiProfilePreferenceTargetType.relationship,
      targetId: source,
    );
    await _savePreference(
      (existing ??
              AiProfilePreference(
                targetType: AiProfilePreferenceTargetType.relationship,
                targetId: source,
                updatedAt: DateTime.now(),
              ))
          .copyWith(
        hidden: true,
        confirmed: false,
        mergedInto: target,
        updatedAt: DateTime.now(),
      ),
    );
    await _saveRelationshipMergeEvent(
      sourcePersonName: source,
      targetPersonName: target,
      action: AiRelationshipMergeEventAction.merge,
    );
  }

  Future<void> recordRelationshipMergeUndo({
    required String sourcePersonName,
    required String targetPersonName,
  }) async {
    final source = sourcePersonName.trim();
    final target = targetPersonName.trim();
    if (source.isEmpty || target.isEmpty) return;
    await _saveRelationshipMergeEvent(
      sourcePersonName: source,
      targetPersonName: target,
      action: AiRelationshipMergeEventAction.undo,
    );
  }

  Future<List<AiRelationshipMergeEvent>> listRelationshipMergeHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = _safeGetStringList(prefs, _mergeHistoryIndexKey) ?? [];
    final items = <AiRelationshipMergeEvent>[];
    for (final id in ids) {
      final item = await _getRelationshipMergeEventById(prefs, id);
      if (item == null) continue;
      if (item.id.isNotEmpty &&
          item.sourcePersonName.isNotEmpty &&
          item.targetPersonName.isNotEmpty) {
        items.add(item);
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await prefs.setStringList(
      _mergeHistoryIndexKey,
      items.map((item) => item.id).toList(growable: false),
    );
    return items;
  }

  Future<void> savePreference(AiProfilePreference item) async {
    await _savePreference(item);
  }

  Future<void> deletePreference({
    required AiProfilePreferenceTargetType targetType,
    required String targetId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final id = AiProfilePreference.keyFor(
      targetType: targetType,
      targetId: targetId,
    );
    await prefs.remove('$_prefix$id');
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
  }

  Future<List<ProfileFact>> applyToProfileFacts(
    List<ProfileFact> facts,
  ) async {
    final preferences = {
      for (final item in await listPreferences()) item.id: item,
    };
    final visible = <ProfileFact>[];
    for (final fact in facts) {
      final preference = preferences[AiProfilePreference.keyFor(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: fact.id,
      )];
      if (preference?.hidden == true) continue;
      final correctedValue = preference?.correctedValue.trim() ?? '';
      final isConfirmed =
          preference?.confirmed == true || correctedValue.isNotEmpty;
      visible.add(fact.copyWith(
        value: correctedValue.isNotEmpty ? correctedValue : fact.value,
        status: isConfirmed ? ProfileFactStatus.stable : fact.status,
        confidence: isConfirmed
            ? fact.confidence.clamp(0.72, 1).toDouble()
            : fact.confidence,
        userConfirmed: isConfirmed,
      ));
    }
    return visible;
  }

  Future<List<RelationshipProfile>> applyToRelationshipProfiles(
    List<RelationshipProfile> profiles,
  ) async {
    final preferences = {
      for (final item in await listPreferences()) item.id: item,
    };
    final mergedProfiles = <String, RelationshipProfile>{
      for (final profile in profiles) profile.personName.toLowerCase(): profile,
    };
    for (final profile in profiles) {
      final preference = preferences[AiProfilePreference.keyFor(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: profile.personName,
      )];
      final mergedInto = preference?.mergedInto.trim() ?? '';
      if (mergedInto.isEmpty) continue;
      final targetKey = mergedInto.toLowerCase();
      final sourceKey = profile.personName.toLowerCase();
      if (targetKey == sourceKey) continue;
      final target = mergedProfiles[targetKey];
      if (target == null) continue;
      mergedProfiles[targetKey] = _mergeRelationshipProfiles(
        target: target,
        source: profile,
        targetName: mergedInto,
      );
      mergedProfiles.remove(sourceKey);
    }

    final visible = <RelationshipProfile>[];
    for (final profile in mergedProfiles.values) {
      final preference = preferences[AiProfilePreference.keyFor(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: profile.personName,
      )];
      if (preference?.hidden == true &&
          (preference?.mergedInto.trim().isEmpty ?? true)) {
        continue;
      }
      final correctedRelationship = preference?.correctedValue.trim() ?? '';
      final isConfirmed =
          preference?.confirmed == true || correctedRelationship.isNotEmpty;
      visible.add(profile.copyWith(
        relationship: correctedRelationship.isNotEmpty
            ? correctedRelationship
            : profile.relationship,
        status: isConfirmed ? ProfileFactStatus.stable : profile.status,
        confidence: isConfirmed
            ? profile.confidence.clamp(0.72, 1).toDouble()
            : profile.confidence,
        userConfirmed: isConfirmed,
      ));
    }
    visible.sort((a, b) {
      final byStatus = _statusRank(b.status).compareTo(_statusRank(a.status));
      if (byStatus != 0) return byStatus;
      final byCount = b.interactionCount.compareTo(a.interactionCount);
      if (byCount != 0) return byCount;
      return b.lastInteractionAt.compareTo(a.lastInteractionAt);
    });
    return visible;
  }

  RelationshipProfile _mergeRelationshipProfiles({
    required RelationshipProfile target,
    required RelationshipProfile source,
    required String targetName,
  }) {
    final interactions = [
      ...target.recentInteractions,
      ...source.recentInteractions,
    ]..sort((a, b) => b.date.compareTo(a.date));
    final names = <String>{
      targetName,
      target.personName,
      source.personName,
      ...target.names,
      ...source.names,
    }.where((value) => value.trim().isNotEmpty).toList(growable: false);
    final emotions = <String>{...target.emotions, ...source.emotions}
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    final patterns = <String>{...target.patterns, ...source.patterns}
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    final evidence = [...target.evidence, ...source.evidence];
    final confidence =
        ((target.confidence + source.confidence) / 2).clamp(0, 1).toDouble();
    return RelationshipProfile(
      personName: targetName,
      names: names,
      status: _maxStatus(target.status, source.status),
      confidence: confidence,
      interactionCount: target.interactionCount + source.interactionCount,
      distinctDays: _distinctInteractionDays(interactions),
      lastInteractionAt:
          target.lastInteractionAt.isAfter(source.lastInteractionAt)
              ? target.lastInteractionAt
              : source.lastInteractionAt,
      relationship: target.relationship ?? source.relationship,
      recentInteractions: interactions.take(5).toList(growable: false),
      emotions: emotions,
      patterns: patterns,
      evidence: evidence,
      userConfirmed: target.userConfirmed || source.userConfirmed,
    );
  }

  int _distinctInteractionDays(List<RelationshipInteraction> interactions) {
    return interactions
        .map((item) => '${item.date.year}-${item.date.month}-${item.date.day}')
        .toSet()
        .length;
  }

  ProfileFactStatus _maxStatus(
    ProfileFactStatus first,
    ProfileFactStatus second,
  ) {
    return _statusRank(first) >= _statusRank(second) ? first : second;
  }

  int _statusRank(ProfileFactStatus status) {
    switch (status) {
      case ProfileFactStatus.stable:
        return 3;
      case ProfileFactStatus.emerging:
        return 2;
      case ProfileFactStatus.weak:
        return 1;
    }
  }

  Future<void> deleteObsoletePreferences({
    required Iterable<String> profileFactIds,
    required Iterable<String> relationshipIds,
  }) async {
    final validIds = <String>{
      for (final id in profileFactIds)
        AiProfilePreference.keyFor(
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: id,
        ),
      for (final id in relationshipIds)
        AiProfilePreference.keyFor(
          targetType: AiProfilePreferenceTargetType.relationship,
          targetId: id,
        ),
    };
    final prefs = await SharedPreferences.getInstance();
    final preferences = await listPreferences();
    for (final preference in preferences) {
      if (validIds.contains(preference.id)) continue;
      await prefs.remove('$_prefix${preference.id}');
    }
    final remaining = preferences
        .where((preference) => validIds.contains(preference.id))
        .map((preference) => preference.id)
        .toList(growable: false);
    await prefs.setStringList(_indexKey, remaining);
  }

  Future<void> _savePreference(AiProfilePreference item) async {
    final prefs = await SharedPreferences.getInstance();
    final id = item.id;
    await prefs.setString('$_prefix$id', jsonEncode(item.toJson()));
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    if (!index.contains(id)) {
      index.add(id);
      await prefs.setStringList(_indexKey, index);
    }
  }

  Future<void> _saveRelationshipMergeEvent({
    required String sourcePersonName,
    required String targetPersonName,
    required AiRelationshipMergeEventAction action,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final id = [
      now.microsecondsSinceEpoch,
      action.name,
      sourcePersonName.toLowerCase(),
      targetPersonName.toLowerCase(),
    ].join(':');
    final item = AiRelationshipMergeEvent(
      id: id,
      sourcePersonName: sourcePersonName,
      targetPersonName: targetPersonName,
      action: action,
      createdAt: now,
    );
    await prefs.setString('$_mergeHistoryPrefix$id', jsonEncode(item.toJson()));
    final index = _safeGetStringList(prefs, _mergeHistoryIndexKey) ?? [];
    if (!index.contains(id)) {
      index.add(id);
      await prefs.setStringList(_mergeHistoryIndexKey, index);
    }
  }

  Future<AiProfilePreference?> _getPreferenceById(
    SharedPreferences prefs,
    String id,
  ) async {
    final key = '$_prefix$id';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      final item = AiProfilePreference.fromJson(decoded);
      return item.targetId.isEmpty ? null : item;
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<AiRelationshipMergeEvent?> _getRelationshipMergeEventById(
    SharedPreferences prefs,
    String id,
  ) async {
    final key = '$_mergeHistoryPrefix$id';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      final item = AiRelationshipMergeEvent.fromJson(decoded);
      return item.id.isEmpty ? null : item;
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }

  List<String>? _safeGetStringList(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      if (value is List<String>) return List<String>.from(value);
      if (value is List) return value.whereType<String>().toList();
      return null;
    } on Object {
      return null;
    }
  }
}
