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
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
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
    return _getInsight(prefs, entryId);
  }

  Future<List<DiaryInsight>> listInsights() async {
    final prefs = await SharedPreferences.getInstance();
    final indexed = _safeGetStringList(prefs, _indexKey) ?? [];
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
      final insight = await _getInsight(prefs, id);
      if (insight != null) insights.add(insight);
    }
    await prefs.setStringList(
        _indexKey, insights.map((insight) => insight.entryId).toList());
    insights.sort((a, b) => b.entryDate.compareTo(a.entryDate));
    return insights;
  }

  Future<DiaryInsight?> getLatestInsight() async {
    final prefs = await SharedPreferences.getInstance();
    final entryId = _safeGetString(prefs, _latestKey);
    if (entryId == null) return null;
    final insight = await _getInsight(prefs, entryId);
    if (insight == null) {
      await prefs.remove(_latestKey);
    }
    return insight;
  }

  Future<void> saveStatus(DiaryAnalysisStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_statusPrefix${status.entryId}', jsonEncode(status.toJson()));
  }

  Future<DiaryAnalysisStatus?> getStatus(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_statusPrefix$entryId';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      return DiaryAnalysisStatus.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> deleteForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$entryId');
    await prefs.remove('$_statusPrefix$entryId');
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    index.remove(entryId);
    await prefs.setStringList(_indexKey, index);
    if (_safeGetString(prefs, _latestKey) == entryId) {
      await prefs.remove(_latestKey);
    }
  }

  Future<DiaryInsight?> _getInsight(
    SharedPreferences prefs,
    String entryId,
  ) async {
    final key = '$_prefix$entryId';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      return DiaryInsight.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }

  List<String>? _safeGetStringList(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      if (value is List<String>) return List<String>.from(value);
      if (value is List) return value.whereType<String>().toList();
      return null;
    } on Object {
      return null;
    }
  }
}
