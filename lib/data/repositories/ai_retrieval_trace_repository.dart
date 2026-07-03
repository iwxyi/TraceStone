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
    final raw = prefs.getString('$_prefix$entryId');
    if (raw == null) return null;
    return AiRetrievalTrace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$entryId');
  }
}
