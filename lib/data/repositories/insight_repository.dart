import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_analysis_status.dart';
import '../models/diary_insight.dart';

class InsightRepository {
  const InsightRepository();

  static const _prefix = 'diary.insights.';
  static const _statusPrefix = 'diary.insights.status.';
  static const _latestKey = 'diary.insights.latest';

  Future<void> saveInsight(DiaryInsight insight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_prefix${insight.entryId}', jsonEncode(insight.toJson()));
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
}
