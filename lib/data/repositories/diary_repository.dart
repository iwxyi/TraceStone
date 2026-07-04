import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';
import '../models/diary_analysis_status.dart';
import 'ai_analysis_queue_repository.dart';
import 'ai_embedding_repository.dart';
import 'ai_feedback_repository.dart';
import 'ai_profile_preference_repository.dart';
import 'ai_prompt_trace_repository.dart';
import 'ai_retrieval_trace_repository.dart';
import 'diary_change_bus.dart';
import 'entry_summary_repository.dart';
import 'insight_repository.dart';
import 'memory_repository.dart';
import 'period_summary_repository.dart';
import 'stone_task_repository.dart';
import '../services/profile_projection_service.dart';

class DiaryRepository {
  const DiaryRepository();

  static const _indexKey = 'diary.entries.index';
  static const _trashIndexKey = 'diary.trash.index';
  static const _entryPrefix = 'diary.entries.';
  static const _trashPrefix = 'diary.trash.';
  static const _recoveryPrefix = 'diary.recovery.';
  static const trashRetention = Duration(days: 90);

  Future<void> saveEntry(DiaryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_entryPrefix${entry.id}', jsonEncode(entry.toJson()));
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    if (!index.contains(entry.id)) {
      index.add(entry.id);
      await prefs.setStringList(_indexKey, index);
    }
    await prefs.remove('$_recoveryPrefix${entry.id}');
    DiaryChangeBus.bump();
  }

  Future<DiaryEntry?> getEntryById(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _safeGetString(prefs, '$_entryPrefix$id');
    if (raw == null) return null;
    return DiaryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<List<DiaryEntry>> listEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    final entries = <DiaryEntry>[];
    for (final id in index) {
      final raw = _safeGetString(prefs, '$_entryPrefix$id');
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
    final raw = _safeGetString(prefs, '$_entryPrefix$id');
    if (raw == null) return;
    final deletedAt = DateTime.now();
    final trashPayload = {
      'entry': jsonDecode(raw),
      'deletedAt': deletedAt.toIso8601String(),
    };
    await prefs.setString('$_trashPrefix$id', jsonEncode(trashPayload));
    await prefs.remove('$_entryPrefix$id');
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
    final trashIndex = _safeGetStringList(prefs, _trashIndexKey) ?? [];
    if (!trashIndex.contains(id)) {
      trashIndex.add(id);
      await prefs.setStringList(_trashIndexKey, trashIndex);
    }
    await prefs.remove('$_recoveryPrefix$id');
    await _deleteAiArtifactsForEntry(id);
    DiaryChangeBus.bump();
  }

  Future<void> moveManyToTrash(Iterable<String> ids) async {
    for (final id in ids) {
      await moveToTrash(id);
    }
  }

  Future<List<DiaryTrashItem>> listTrashEntries() async {
    await purgeExpiredTrash();
    final prefs = await SharedPreferences.getInstance();
    final ids = await _trashIds(prefs);
    final items = <DiaryTrashItem>[];
    for (final id in ids) {
      final item = await _trashItem(prefs, id);
      if (item != null) {
        items.add(item);
      } else {
        await _removeTrashItem(prefs, id);
      }
    }
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  Future<void> restoreFromTrash(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final item = await _trashItem(prefs, id);
    if (item == null) return;
    await prefs.setString(
        '$_entryPrefix${item.entry.id}', jsonEncode(item.entry.toJson()));
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    if (!index.contains(item.entry.id)) {
      index.add(item.entry.id);
      await prefs.setStringList(_indexKey, index);
    }
    await _removeTrashItem(prefs, id);
    await const AiAnalysisQueueRepository().enqueueEntry(item.entry);
    await const InsightRepository().saveStatus(DiaryAnalysisStatus(
      entryId: item.entry.id,
      state: DiaryAnalysisState.queued,
      updatedAt: DateTime.now(),
      message: '已从回收站恢复，等待重新整理 AI 资料',
    ));
    DiaryChangeBus.bump();
  }

  Future<void> permanentlyDeleteFromTrash(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await _removeTrashItem(prefs, id);
    await _deleteAiArtifactsForEntry(id);
    DiaryChangeBus.bump();
  }

  Future<void> purgeExpiredTrash() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _trashIds(prefs);
    final now = DateTime.now();
    for (final id in ids) {
      final item = await _trashItem(prefs, id);
      if (item == null) {
        await _removeTrashItem(prefs, id);
        continue;
      }
      if (now.isAfter(item.expiresAt)) {
        await _removeTrashItem(prefs, id);
        await _deleteAiArtifactsForEntry(id);
      }
    }
  }

  Future<void> saveRecoverySnapshot(DiaryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_recoveryPrefix${entry.id}', jsonEncode(entry.toJson()));
  }

  Future<DiaryEntry?> getRecoverySnapshot(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _safeGetString(prefs, '$_recoveryPrefix$id');
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
      final raw = _safeGetString(prefs, key);
      if (raw == null) continue;
      snapshots
          .add(DiaryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    snapshots.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return snapshots.firstOrNull;
  }

  Future<List<String>> _trashIds(SharedPreferences prefs) async {
    final indexed = _safeGetStringList(prefs, _trashIndexKey) ?? [];
    final scanned = prefs
        .getKeys()
        .where((key) => key.startsWith(_trashPrefix) && key != _trashIndexKey)
        .map((key) => key.substring(_trashPrefix.length));
    final ids = <String>{...indexed, ...scanned}
        .where((id) => id.isNotEmpty && id != 'index')
        .toList();
    await prefs.setStringList(_trashIndexKey, ids);
    return ids;
  }

  Future<DiaryTrashItem?> _trashItem(SharedPreferences prefs, String id) async {
    final key = '$_trashPrefix$id';
    final value = _safeGetValue(prefs, key);
    if (value == null) {
      if (prefs.containsKey(key)) {
        await _removeTrashItem(prefs, id);
      }
      return null;
    }
    if (value is! String) {
      await _removeTrashItem(prefs, id);
      return null;
    }
    try {
      final parsed = jsonDecode(value) as Map<String, dynamic>;
      final hasMetadata = parsed['entry'] is Map<String, dynamic>;
      final entryJson =
          hasMetadata ? parsed['entry'] as Map<String, dynamic> : parsed;
      final entry = DiaryEntry.fromJson(entryJson);
      final deletedAtRaw = parsed['deletedAt'];
      final deletedAt =
          deletedAtRaw is String ? DateTime.tryParse(deletedAtRaw) : null;
      return DiaryTrashItem(
        entry: entry,
        deletedAt: deletedAt ?? entry.updatedAt,
        expiresAt: (deletedAt ?? entry.updatedAt).add(trashRetention),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _deleteAiArtifactsForEntry(String id) async {
    const memoryRepository = MemoryRepository();
    const promptTraceRepository = AiPromptTraceRepository();
    const retrievalTraceRepository = AiRetrievalTraceRepository();
    final memoryIds = await memoryRepository.memoryIdsForSourceEntry(id);
    await const InsightRepository().deleteForEntry(id);
    await _pruneProfilePreferences();
    await promptTraceRepository.deleteForSourceIds(memoryIds);
    await retrievalTraceRepository.deleteForSourceIds(memoryIds);
    await memoryRepository.deleteForSourceEntry(id);
    await const StoneTaskRepository().deleteForSourceEntry(id);
    await const AiAnalysisQueueRepository().deleteJob(id);
    await const AiEmbeddingRepository().deleteForEntry(id);
    await const AiFeedbackRepository().deleteFeedback(id);
    await promptTraceRepository.deleteForEntry(id);
    await const EntrySummaryRepository().deleteForEntry(id);
    await retrievalTraceRepository.deleteForEntry(id);
    await const PeriodSummaryRepository().deleteForEntry(id);
  }

  Future<void> _pruneProfilePreferences() async {
    final insights = await const InsightRepository().listInsights();
    final projection = const ProfileProjectionService().build(insights);
    await const AiProfilePreferenceRepository().deleteObsoletePreferences(
      profileFactIds: projection.profileFacts.map((fact) => fact.id),
      relationshipIds:
          projection.relationshipProfiles.map((profile) => profile.personName),
    );
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = _safeGetValue(prefs, key);
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }

  List<String>? _safeGetStringList(SharedPreferences prefs, String key) {
    try {
      final value = _safeGetValue(prefs, key);
      if (value is List<String>) return List<String>.from(value);
      if (value is List) return value.whereType<String>().toList();
      return null;
    } catch (_) {
      return null;
    }
  }

  Object? _safeGetValue(SharedPreferences prefs, String key) {
    try {
      return prefs.get(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeTrashItem(SharedPreferences prefs, String id) async {
    await prefs.remove('$_trashPrefix$id');
    final trashIndex = _safeGetStringList(prefs, _trashIndexKey) ?? [];
    trashIndex.remove(id);
    await prefs.setStringList(_trashIndexKey, trashIndex);
  }
}

class DiaryTrashItem {
  const DiaryTrashItem({
    required this.entry,
    required this.deletedAt,
    required this.expiresAt,
  });

  final DiaryEntry entry;
  final DateTime deletedAt;
  final DateTime expiresAt;

  int get daysRemaining {
    final remaining = expiresAt.difference(DateTime.now()).inDays + 1;
    return remaining < 0 ? 0 : remaining;
  }
}
