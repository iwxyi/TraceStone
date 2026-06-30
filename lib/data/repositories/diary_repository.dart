import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';
import 'diary_change_bus.dart';

class DiaryRepository {
  const DiaryRepository();

  static const _indexKey = 'diary.entries.index';
  static const _entryPrefix = 'diary.entries.';
  static const _trashPrefix = 'diary.trash.';
  static const _recoveryPrefix = 'diary.recovery.';

  Future<void> saveEntry(DiaryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_entryPrefix${entry.id}', jsonEncode(entry.toJson()));
    final index = prefs.getStringList(_indexKey) ?? [];
    if (!index.contains(entry.id)) {
      index.add(entry.id);
      await prefs.setStringList(_indexKey, index);
    }
    await prefs.remove('$_recoveryPrefix${entry.id}');
    DiaryChangeBus.bump();
  }

  Future<DiaryEntry?> getEntryById(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_entryPrefix$id');
    if (raw == null) return null;
    return DiaryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<List<DiaryEntry>> listEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey) ?? [];
    final entries = <DiaryEntry>[];
    for (final id in index) {
      final raw = prefs.getString('$_entryPrefix$id');
      if (raw == null) continue;
      entries.add(DiaryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    entries.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return b.createdAt.compareTo(a.createdAt);
    });
    return entries;
  }

  Future<DiaryEntry?> getEntry(DateTime date) async {
    final entries = await getEntriesForDate(date);
    return entries.firstOrNull;
  }

  Future<List<DiaryEntry>> getEntriesForDate(DateTime date) async {
    final dayKey = DiaryEntry.dateKey(date);
    final entries = await listEntries();
    return entries.where((entry) => entry.dayKey == dayKey).toList();
  }

  Future<List<DiaryEntry>> listEntriesForYear(int year) async {
    final entries = await listEntries();
    return entries.where((entry) => entry.date.year == year).toList();
  }

  Future<List<DiaryEntry>> listEntriesForMonth(DateTime date) async {
    final entries = await listEntries();
    return entries
        .where((entry) =>
            entry.date.year == date.year && entry.date.month == date.month)
        .toList();
  }

  Future<void> moveToTrash(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_entryPrefix$id');
    if (raw == null) return;
    await prefs.setString('$_trashPrefix$id', raw);
    await prefs.remove('$_entryPrefix$id');
    final index = prefs.getStringList(_indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
    await prefs.remove('$_recoveryPrefix$id');
    DiaryChangeBus.bump();
  }

  Future<void> moveManyToTrash(Iterable<String> ids) async {
    for (final id in ids) {
      await moveToTrash(id);
    }
  }

  Future<void> saveRecoverySnapshot(DiaryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_recoveryPrefix${entry.id}', jsonEncode(entry.toJson()));
  }

  Future<DiaryEntry?> getRecoverySnapshot(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_recoveryPrefix$id');
    if (raw == null) return null;
    return DiaryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteRecoverySnapshot(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_recoveryPrefix$id');
  }

  Future<DiaryEntry?> recoverLatestSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshots = <DiaryEntry>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_recoveryPrefix)) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      snapshots
          .add(DiaryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    snapshots.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return snapshots.firstOrNull;
  }
}
