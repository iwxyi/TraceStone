import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_analysis_status.dart';
import '../models/diary_insight.dart';

class InsightRepository {
  const InsightRepository();

  static const _prefix = 'diary.insights.';
  static const _indexKey = 'diary.insights.index';
  static const _statusPrefix = 'diary.insights.status.';
  static const _latestKey = 'diary.insights.latest';

  Future<void> saveInsight(DiaryInsight insight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_prefix${insight.entryId}', jsonEncode(insight.toJson()));
    final index = prefs.getStringList(_indexKey) ?? [];
    if (!index.contains(insight.entryId)) {
      index.add(insight.entryId);
      await prefs.setStringList(_indexKey, index);
    }
    await prefs.setString(_latestKey, insight.entryId);
    await saveStatus(DiaryAnalysisStatus(
      entryId: insight.entryId,
      state: DiaryAnalysisState.completed,
      updatedAt: DateTime.now(),
    ));
  }

  Future<DiaryInsight?> getInsight(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$entryId');
    if (raw == null) return null;
    return DiaryInsight.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<List<DiaryInsight>> listInsights() async {
    final prefs = await SharedPreferences.getInstance();
    final indexed = prefs.getStringList(_indexKey) ?? [];
    final scanned = prefs
        .getKeys()
        .where((key) =>
            key.startsWith(_prefix) &&
            key != _indexKey &&
            key != _latestKey &&
            !key.startsWith(_statusPrefix))
        .map((key) => key.substring(_prefix.length));
    final ids = <String>{...indexed, ...scanned}
        .where((id) =>
            id.isNotEmpty && id != 'latest' && !id.startsWith('status.'))
        .toList();
    await prefs.setStringList(_indexKey, ids);

    final insights = <DiaryInsight>[];
    for (final id in ids) {
      final raw = prefs.getString('$_prefix$id');
      if (raw == null) continue;
      insights
          .add(DiaryInsight.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    insights.sort((a, b) => b.entryDate.compareTo(a.entryDate));
    return insights;
  }

  Future<DiaryInsight?> getLatestInsight() async {
    final prefs = await SharedPreferences.getInstance();
    final entryId = prefs.getString(_latestKey);
    if (entryId == null) return null;
    return getInsight(entryId);
  }

  Future<void> saveStatus(DiaryAnalysisStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_statusPrefix${status.entryId}', jsonEncode(status.toJson()));
  }

  Future<DiaryAnalysisStatus?> getStatus(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_statusPrefix$entryId');
    if (raw == null) return null;
    return DiaryAnalysisStatus.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$entryId');
    await prefs.remove('$_statusPrefix$entryId');
    final index = prefs.getStringList(_indexKey) ?? [];
    index.remove(entryId);
    await prefs.setStringList(_indexKey, index);
    if (prefs.getString(_latestKey) == entryId) {
      await prefs.remove(_latestKey);
    }
  }
}
