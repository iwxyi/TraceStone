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
    final raw = prefs.getString('$_prefix$entryId');
    if (raw == null) return null;
    return AiFeedback.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteFeedback(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$entryId');
  }
}
