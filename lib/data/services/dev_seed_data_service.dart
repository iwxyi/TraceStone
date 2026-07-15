import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../repositories/ai_analysis_queue_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/insight_repository.dart';

class DevSeedDataService {
  DevSeedDataService({
    DiaryRepository? diaryRepository,
    AiAnalysisQueueRepository? queueRepository,
    InsightRepository? insightRepository,
    AssetBundle? assetBundle,
  })  : _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _queueRepository = queueRepository ?? const AiAnalysisQueueRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _assetBundle = assetBundle ?? rootBundle;

  static const defaultAssetPath = 'assets/dev/diary_seed_dataset.json';

  final DiaryRepository _diaryRepository;
  final AiAnalysisQueueRepository _queueRepository;
  final InsightRepository _insightRepository;
  final AssetBundle _assetBundle;

  Future<DevSeedImportResult> importDiaryDataset({
    String assetPath = defaultAssetPath,
    bool enqueueAi = true,
  }) async {
    final raw = await _assetBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('测试数据格式错误：根节点必须是对象');
    }
    final entriesJson = decoded['entries'];
    if (entriesJson is! List) {
      throw const FormatException('测试数据格式错误：entries 必须是数组');
    }
    final importedIds = <String>[];
    var created = 0;
    var updated = 0;
    var enqueued = 0;
    final batchStartedAt = DateTime.now();
    final batchId = 'dev-seed:${batchStartedAt.microsecondsSinceEpoch}';
    final batchLabel = '开发者测试日记 ${_dateLabel(batchStartedAt)}';

    for (final item in entriesJson) {
      if (item is! Map) continue;
      final json = {
        for (final entry in item.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      final entry = DiaryEntry.fromJson(json);
      if (entry.id.trim().isEmpty || entry.content.trim().isEmpty) continue;
      final existing = await _diaryRepository.getEntryById(entry.id);
      await _diaryRepository.saveEntry(entry);
      importedIds.add(entry.id);
      if (existing == null) {
        created += 1;
      } else {
        updated += 1;
      }
      if (enqueueAi) {
        await _queueRepository.enqueueEntry(
          entry,
          batchId: batchId,
          batchLabel: batchLabel,
        );
        await _insightRepository.saveStatus(DiaryAnalysisStatus(
          entryId: entry.id,
          state: DiaryAnalysisState.queued,
          updatedAt: DateTime.now(),
          message: '开发者测试数据已导入，等待整理 AI 资料',
        ));
        enqueued += 1;
      }
    }
    return DevSeedImportResult(
      importedIds: importedIds,
      createdCount: created,
      updatedCount: updated,
      enqueuedCount: enqueued,
    );
  }

  String _dateLabel(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}

class DevSeedImportResult {
  const DevSeedImportResult({
    required this.importedIds,
    required this.createdCount,
    required this.updatedCount,
    required this.enqueuedCount,
  });

  final List<String> importedIds;
  final int createdCount;
  final int updatedCount;
  final int enqueuedCount;

  int get totalCount => importedIds.length;

  String get summary =>
      'total=$totalCount created=$createdCount updated=$updatedCount '
      'queued=$enqueuedCount';
}
