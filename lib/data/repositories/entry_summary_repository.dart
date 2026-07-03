import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_segment.dart';
import '../models/entry_summary.dart';

class EntrySummaryRepository {
  const EntrySummaryRepository();

  static const _summaryPrefix = 'ai.entrySummaries.';
  static const _segmentIndexPrefix = 'ai.entrySegments.index.';
  static const _segmentPrefix = 'ai.entrySegments.';

  Future<void> saveSummary(EntrySummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_summaryPrefix${summary.entryId}', jsonEncode(summary.toJson()));
  }

  Future<EntrySummary?> getSummary(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_summaryPrefix$entryId');
    if (raw == null) return null;
    return EntrySummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSegments(String entryId, List<DiarySegment> segments) async {
    final prefs = await SharedPreferences.getInstance();
    final oldIds = prefs.getStringList('$_segmentIndexPrefix$entryId') ?? [];
    for (final id in oldIds) {
      await prefs.remove('$_segmentPrefix$id');
    }
    final ids = <String>[];
    for (final segment in segments) {
      ids.add(segment.id);
      await prefs.setString(
          '$_segmentPrefix${segment.id}', jsonEncode(segment.toJson()));
    }
    await prefs.setStringList('$_segmentIndexPrefix$entryId', ids);
  }

  Future<List<DiarySegment>> listSegments(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('$_segmentIndexPrefix$entryId') ?? [];
    final segments = <DiarySegment>[];
    for (final id in ids) {
      final raw = prefs.getString('$_segmentPrefix$id');
      if (raw == null) continue;
      segments
          .add(DiarySegment.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    segments.sort((a, b) => a.index.compareTo(b.index));
    return segments;
  }

  Future<void> deleteForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_summaryPrefix$entryId');
    final ids = prefs.getStringList('$_segmentIndexPrefix$entryId') ?? [];
    for (final id in ids) {
      await prefs.remove('$_segmentPrefix$id');
    }
    await prefs.remove('$_segmentIndexPrefix$entryId');
  }
}
