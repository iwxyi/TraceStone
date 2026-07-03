import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_feedback.dart';

class AiFeedbackRepository {
  const AiFeedbackRepository();

  static const _prefix = 'ai.feedback.';

  Future<void> saveFeedback(AiFeedback feedback) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_prefix${feedback.entryId}', jsonEncode(feedback.toJson()));
  }

  Future<AiFeedback?> getFeedback(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix$entryId';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      return AiFeedback.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> deleteFeedback(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$entryId');
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }
}
