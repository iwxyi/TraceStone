import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_retrieval_trace.dart';

class AiRetrievalTraceRepository {
  const AiRetrievalTraceRepository();

  static const _prefix = 'ai.retrievalTraces.';

  Future<void> saveTrace(AiRetrievalTrace trace) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_prefix${trace.entryId}', jsonEncode(trace.toJson()));
  }

  Future<AiRetrievalTrace?> getTrace(String entryId) async {
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
      return AiRetrievalTrace.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> deleteForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$entryId');
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    return value is String ? value : null;
  }
}
