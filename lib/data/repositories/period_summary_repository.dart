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
    final raw = prefs.getString('$_prefix$id');
    if (raw == null) return null;
    return PeriodSummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteSummary(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
  }

  static String monthId(DateTime month) =>
      'month:${month.year}-${month.month.toString().padLeft(2, '0')}';

  static String yearId(int year) => 'year:$year';
}
