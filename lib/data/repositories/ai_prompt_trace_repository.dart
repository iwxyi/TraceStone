import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_prompt_trace.dart';

class AiPromptTraceRepository {
  const AiPromptTraceRepository();

  static const _prefix = 'ai.promptTraces.';

  Future<void> saveTrace(AiPromptTrace trace) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix${trace.id}', jsonEncode(trace.toJson()));
  }

  Future<AiPromptTrace?> getTrace(String id) async {
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
      return AiPromptTrace.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> deleteTrace(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
  }

  Future<int> deleteAllTraces() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
    return keys.length;
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    return value is String ? value : null;
  }
}
