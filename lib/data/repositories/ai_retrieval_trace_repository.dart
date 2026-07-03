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
    final value = entryId.trim();
    if (value.isEmpty) return;
    await _deleteWhere((trace) => _traceReferencesEntry(trace, value));
  }

  Future<void> deleteForSourceIds(Iterable<String> sourceIds) async {
    final values =
        sourceIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (values.isEmpty) return;
    await _deleteWhere((trace) => _traceReferencesAny(trace, values));
  }

  Future<void> _deleteWhere(bool Function(AiRetrievalTrace trace) test) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList(growable: false);
    for (final key in keys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          await prefs.remove(key);
          continue;
        }
        final trace = AiRetrievalTrace.fromJson(decoded);
        if (test(trace)) {
          await prefs.remove(key);
        }
      } on Object {
        await prefs.remove(key);
      }
    }
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

  bool _traceReferencesEntry(AiRetrievalTrace trace, String entryId) {
    if (trace.entryId == entryId) return true;
    return trace.items.any((item) {
      final sourceId = item.sourceId.trim();
      return sourceId == entryId ||
          sourceId.startsWith('$entryId#') ||
          item.title.contains(entryId) ||
          item.summary.contains(entryId) ||
          item.reasons.any((reason) => reason.contains(entryId)) ||
          item.matchedTokens.any((token) => token.contains(entryId));
    });
  }

  bool _traceReferencesAny(AiRetrievalTrace trace, Set<String> sourceIds) {
    if (sourceIds.contains(trace.entryId)) return true;
    return trace.items.any((item) {
      return sourceIds.any((sourceId) {
        if (item.sourceId == sourceId) return true;
        if (!sourceId.contains(':') && item.sourceId == 'memory:$sourceId') {
          return true;
        }
        return item.title.contains(sourceId) ||
            item.summary.contains(sourceId) ||
            item.reasons.any((reason) => reason.contains(sourceId)) ||
            item.matchedTokens.any((token) => token.contains(sourceId));
      });
    });
  }
}
