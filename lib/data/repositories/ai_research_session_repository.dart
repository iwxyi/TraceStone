import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_research_session.dart';

class AiResearchSessionRepository {
  const AiResearchSessionRepository();

  static const _prefix = 'ai.researchSessions.';
  static const _indexKey = 'ai.researchSessions.index';
  static const _lastKey = 'ai.researchSessions.last';

  Future<void> saveSession(AiResearchSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_prefix${session.id}', jsonEncode(session.toJson()));
    await prefs.setString(_lastKey, session.id);
    final ids = _safeStringList(prefs, _indexKey).toList();
    ids.remove(session.id);
    ids.insert(0, session.id);
    await prefs.setStringList(_indexKey, ids.take(20).toList());
  }

  Future<AiResearchSession?> getSession(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix$id';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      return AiResearchSession.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<AiResearchSession?> getLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = _safeGetString(prefs, _lastKey);
    if (id == null || id.trim().isEmpty) return null;
    return getSession(id);
  }

  Future<List<AiResearchSession>> listRecentSessions({int limit = 10}) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = _safeStringList(prefs, _indexKey);
    final sessions = <AiResearchSession>[];
    final keptIds = <String>[];
    for (final id in ids) {
      final session = await getSession(id);
      if (session == null) continue;
      sessions.add(session);
      keptIds.add(id);
      if (sessions.length >= limit) break;
    }
    if (keptIds.length != ids.length) {
      await prefs.setStringList(_indexKey, keptIds);
    }
    return sessions;
  }

  Future<int> deleteAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
    await prefs.remove(_indexKey);
    await prefs.remove(_lastKey);
    return keys.length;
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }

  List<String> _safeStringList(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      if (value is List<String>) return value;
    } catch (_) {
      return const [];
    }
    return const [];
  }
}
