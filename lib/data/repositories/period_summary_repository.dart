import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/period_summary.dart';

class PeriodSummaryRepository {
  const PeriodSummaryRepository();

  static const _prefix = 'ai.periodSummaries.';

  Future<void> saveSummary(PeriodSummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_prefix${summary.id}', jsonEncode(summary.toJson()));
  }

  Future<PeriodSummary?> getSummary(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return _getSummary(prefs, '$_prefix$id');
  }

  Future<List<PeriodSummary>> listSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final summaries = <PeriodSummary>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final summary = await _getSummary(prefs, key);
      if (summary != null) summaries.add(summary);
    }
    summaries.sort((a, b) {
      final byGeneratedAt = b.generatedAt.compareTo(a.generatedAt);
      if (byGeneratedAt != 0) return byGeneratedAt;
      return b.startDate.compareTo(a.startDate);
    });
    return summaries;
  }

  Future<PeriodSummary?> _getSummary(
      SharedPreferences prefs, String key) async {
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      return PeriodSummary.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> deleteSummary(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
  }

  Future<void> deleteForEntry(String entryId) async {
    final value = entryId.trim();
    if (value.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final summary = await _getSummary(prefs, key);
      if (summary == null) continue;
      if (_summaryReferencesEntry(summary, value)) {
        await prefs.remove(key);
      }
    }
  }

  static String monthId(DateTime month) =>
      'month:${month.year}-${month.month.toString().padLeft(2, '0')}';

  static String yearId(int year) => 'year:$year';

  String? _safeGetString(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    return value is String ? value : null;
  }

  bool _summaryReferencesEntry(PeriodSummary summary, String entryId) {
    if (summary.representativeEntryIds.contains(entryId)) return true;
    final markers = [
      ':$entryId',
      'entry=$entryId',
      'sourceEntry=$entryId',
      'sourceEntry:$entryId',
    ];
    return summary.contextSourceLines
        .any((line) => markers.any((marker) => line.contains(marker)));
  }
}
