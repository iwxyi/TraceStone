import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';
import '../models/period_summary.dart';

class PeriodSummaryRepository {
  const PeriodSummaryRepository();

  static const _prefix = 'ai.periodSummaries.';
  static const _statusPrefix = 'ai.periodSummaryStatuses.';

  Future<void> saveSummary(PeriodSummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_prefix${summary.id}', jsonEncode(summary.toJson()));
  }

  Future<void> markEntryChanged({
    required DiaryEntry entry,
    required int currentMonthEntryCount,
    required int currentYearEntryCount,
  }) async {
    await _markSummaryNeedsUpdate(
      id: monthId(entry.date),
      entryId: entry.id,
      currentEntryCount: currentMonthEntryCount,
    );
    await _markSummaryNeedsUpdate(
      id: yearId(entry.date.year),
      entryId: entry.id,
      currentEntryCount: currentYearEntryCount,
    );
  }

  Future<PeriodSummary?> getSummary(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return _getSummary(prefs, '$_prefix$id');
  }

  Future<void> saveStatus(PeriodSummaryStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_statusPrefix${status.id}', jsonEncode(status.toJson()));
  }

  Future<PeriodSummaryStatus?> getStatus(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _safeGetString(prefs, '$_statusPrefix$id');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove('$_statusPrefix$id');
        return null;
      }
      return PeriodSummaryStatus.fromJson(decoded);
    } on Object {
      await prefs.remove('$_statusPrefix$id');
      return null;
    }
  }

  Future<List<PeriodSummaryStatus>> listStatuses() async {
    final prefs = await SharedPreferences.getInstance();
    final statuses = <PeriodSummaryStatus>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_statusPrefix)) continue;
      final raw = _safeGetString(prefs, key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          await prefs.remove(key);
          continue;
        }
        final status = PeriodSummaryStatus.fromJson(decoded);
        if (status.id.isNotEmpty) statuses.add(status);
      } on Object {
        await prefs.remove(key);
      }
    }
    statuses.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return statuses;
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
    await prefs.remove('$_statusPrefix$id');
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
        await _markSummaryNeedsUpdate(
          id: summary.id,
          entryId: value,
          currentEntryCount:
              (summary.entryCount - 1).clamp(0, summary.entryCount),
        );
      }
    }
  }

  Future<void> _markSummaryNeedsUpdate({
    required String id,
    required String entryId,
    required int currentEntryCount,
  }) async {
    final summary = await getSummary(id);
    if (summary == null) return;
    final currentStatus = await getStatus(id);
    final changedIds = <String>{
      ...?currentStatus?.changedEntryIds,
      entryId,
    }.toList()
      ..sort();
    final baseEntryCount = currentStatus?.baseEntryCount ??
        (summary.coveredEntryIds.isNotEmpty
            ? summary.coveredEntryIds.length
            : summary.entryCount);
    final status = PeriodSummaryStatus(
      id: id,
      state: currentStatus?.state ?? PeriodSummaryState.completed,
      updatedAt: DateTime.now(),
      message: '有 ${changedIds.length} 篇日记变化，周期总结需要更新',
      needsUpdate: true,
      changedEntryIds: changedIds,
      baseEntryCount: baseEntryCount,
      currentEntryCount: currentEntryCount,
    );
    await saveStatus(status);
  }

  static String monthId(DateTime month) =>
      'month:${month.year}-${month.month.toString().padLeft(2, '0')}';

  static String yearId(int year) => 'year:$year';

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
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
