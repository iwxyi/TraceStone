import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_profile.dart';
import '../models/ai_profile_preference.dart';

class AiProfilePreferenceRepository {
  const AiProfilePreferenceRepository();

  static const _indexKey = 'ai.profilePreferences.index';
  static const _prefix = 'ai.profilePreferences.';

  Future<List<AiProfilePreference>> listPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_indexKey) ?? [];
    final items = <AiProfilePreference>[];
    for (final id in ids) {
      final raw = prefs.getString('$_prefix$id');
      if (raw == null) continue;
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final item = AiProfilePreference.fromJson(parsed);
      if (item.targetId.isNotEmpty) items.add(item);
    }
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
    final raw = prefs.getString('$_prefix$id');
    if (raw == null) return null;
    return AiProfilePreference.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
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
    final visible = <RelationshipProfile>[];
    for (final profile in profiles) {
      final preference = preferences[AiProfilePreference.keyFor(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: profile.personName,
      )];
      if (preference?.hidden == true) continue;
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
    return visible;
  }

  Future<void> _savePreference(AiProfilePreference item) async {
    final prefs = await SharedPreferences.getInstance();
    final id = item.id;
    await prefs.setString('$_prefix$id', jsonEncode(item.toJson()));
    final index = prefs.getStringList(_indexKey) ?? [];
    if (!index.contains(id)) {
      index.add(id);
      await prefs.setStringList(_indexKey, index);
    }
  }
}
