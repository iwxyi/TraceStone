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

  Future<void> _deleteWhere(bool Function(AiPromptTrace trace) test) async {
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
        final trace = AiPromptTrace.fromJson(decoded);
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

  bool _traceReferencesEntry(AiPromptTrace trace, String entryId) {
    if (trace.id == entryId) return true;
    return [
      trace.contextSummary,
      trace.systemPromptPreview,
      trace.userPromptPreview,
      trace.rawResponsePreview,
      trace.systemPrompt ?? '',
      trace.userPrompt ?? '',
      trace.rawResponse ?? '',
    ].any((value) => value.contains(entryId));
  }

  bool _traceReferencesAny(AiPromptTrace trace, Set<String> sourceIds) {
    final text = [
      trace.id,
      trace.contextSummary,
      trace.systemPromptPreview,
      trace.userPromptPreview,
      trace.rawResponsePreview,
      trace.systemPrompt ?? '',
      trace.userPrompt ?? '',
      trace.rawResponse ?? '',
    ].join('\n');
    return sourceIds.any((sourceId) {
      if (text.contains(sourceId)) return true;
      if (!sourceId.contains(':') && text.contains('memory:$sourceId')) {
        return true;
      }
      return false;
    });
  }
}
