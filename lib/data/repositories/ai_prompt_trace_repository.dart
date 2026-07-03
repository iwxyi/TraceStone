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
    final raw = prefs.getString('$_prefix$id');
    if (raw == null) return null;
    return AiPromptTrace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteTrace(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
  }
}
