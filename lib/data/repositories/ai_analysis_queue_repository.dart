import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_analysis_job.dart';
import '../models/diary_entry.dart';
import 'diary_repository.dart';
import 'entry_summary_repository.dart';
import 'period_summary_repository.dart';
import 'ai_analysis_queue_bus.dart';

class AiAnalysisQueueRepository {
  const AiAnalysisQueueRepository({
    DiaryRepository? diaryRepository,
    EntrySummaryRepository? summaryRepository,
    PeriodSummaryRepository? periodSummaryRepository,
  })  : _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _summaryRepository =
            summaryRepository ?? const EntrySummaryRepository(),
        _periodSummaryRepository =
            periodSummaryRepository ?? const PeriodSummaryRepository();

  static const _indexKey = 'ai.analysis.jobs.index';
  static const _pausedKey = 'ai.analysis.jobs.paused';
  static const _prefix = 'ai.analysis.jobs.';
  static const _staleRunningAge = Duration(minutes: 10);

  final DiaryRepository _diaryRepository;
  final EntrySummaryRepository _summaryRepository;
  final PeriodSummaryRepository _periodSummaryRepository;

  Future<AiAnalysisJob> enqueueEntry(
    DiaryEntry entry, {
    String? batchId,
    String? batchLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final existing = await getJob(entry.id);
    final job = AiAnalysisJob(
      id: entry.id,
      entryId: entry.id,
      pipelineVersion: entry.updatedAt.microsecondsSinceEpoch,
      state: AiAnalysisJobState.pending,
      currentStage: AiAnalysisStage.queued,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      batchId: batchId ?? existing?.batchId,
      batchLabel: batchLabel ?? existing?.batchLabel,
    );
    await prefs.setString('$_prefix${job.id}', jsonEncode(job.toJson()));
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    if (!index.contains(job.id)) {
      index.add(job.id);
      await prefs.setStringList(_indexKey, index);
    }
    AiAnalysisQueueBus.bump();
    return job;
  }

  Future<List<AiAnalysisJob>> enqueueEntries(
    Iterable<DiaryEntry> entries, {
    String? batchId,
    String? batchLabel,
  }) async {
    final scoped = entries.toList(growable: false);
    if (scoped.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    final indexed = index.toSet();
    final jobs = <AiAnalysisJob>[];
    for (final entry in scoped) {
      final existing = _jobFromPrefs(prefs, entry.id);
      final job = AiAnalysisJob(
        id: entry.id,
        entryId: entry.id,
        pipelineVersion: entry.updatedAt.microsecondsSinceEpoch,
        state: AiAnalysisJobState.pending,
        currentStage: AiAnalysisStage.queued,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        batchId: batchId ?? existing?.batchId,
        batchLabel: batchLabel ?? existing?.batchLabel,
      );
      await prefs.setString('$_prefix${job.id}', jsonEncode(job.toJson()));
      if (indexed.add(job.id)) index.add(job.id);
      jobs.add(job);
    }
    await prefs.setStringList(_indexKey, index);
    AiAnalysisQueueBus.bump();
    return jobs;
  }

  Future<AiAnalysisJob> enqueueEmbeddingRebuildEntry(
    DiaryEntry entry, {
    String? batchId,
    String? batchLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final id = 'embedding:${entry.id}';
    final existing = await getJob(id);
    final job = AiAnalysisJob(
      id: id,
      entryId: entry.id,
      type: AiAnalysisJobType.embeddingRebuild,
      targetId: entry.id,
      pipelineVersion: entry.updatedAt.microsecondsSinceEpoch,
      state: AiAnalysisJobState.pending,
      currentStage: AiAnalysisStage.queued,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      batchId: batchId ?? existing?.batchId,
      batchLabel: batchLabel ?? existing?.batchLabel,
    );
    await prefs.setString('$_prefix${job.id}', jsonEncode(job.toJson()));
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    if (!index.contains(job.id)) {
      index.add(job.id);
      await prefs.setStringList(_indexKey, index);
    }
    AiAnalysisQueueBus.bump();
    return job;
  }

  Future<AiAnalysisJob> enqueueMonthSummary(
    DateTime month, {
    int? pipelineVersion,
    String? batchId,
    String? batchLabel,
  }) async {
    final target = DateTime(month.year, month.month);
    final targetPipelineVersion =
        pipelineVersion ?? DateTime.now().microsecondsSinceEpoch;
    final targetBatchId = batchId ??
        'period:${PeriodSummaryRepository.monthId(target)}:$targetPipelineVersion';
    final targetBatchLabel =
        batchLabel ?? '月度总结前置资料 ${_dateTimeLabel(DateTime.now())}';
    await _enqueueDiaryDependenciesForMonth(
      target,
      batchId: targetBatchId,
      batchLabel: targetBatchLabel,
    );
    return _enqueuePeriodSummary(
      id: PeriodSummaryRepository.monthId(target),
      type: AiAnalysisJobType.monthSummary,
      targetId: PeriodSummaryRepository.monthId(target),
      pipelineVersion: targetPipelineVersion,
      batchId: targetBatchId,
      batchLabel: targetBatchLabel,
    );
  }

  Future<AiAnalysisJob> enqueueYearSummary(
    int year, {
    int? pipelineVersion,
    String? batchId,
    String? batchLabel,
  }) async {
    final targetPipelineVersion =
        pipelineVersion ?? DateTime.now().microsecondsSinceEpoch;
    final monthBatchId = batchId ?? 'period:$year';
    final monthBatchLabel =
        batchLabel ?? '年度总结前置月度总结 ${_dateTimeLabel(DateTime.now())}';
    final entries = await _diaryRepository.listEntries();
    final monthsWithEntries = entries
        .where((entry) => entry.date.year == year)
        .map((entry) => entry.date.month)
        .toSet()
        .toList()
      ..sort();
    for (final month in monthsWithEntries) {
      await enqueueMonthSummary(
        DateTime(year, month),
        pipelineVersion: targetPipelineVersion,
        batchId: monthBatchId,
        batchLabel: monthBatchLabel,
      );
    }
    return _enqueuePeriodSummary(
      id: PeriodSummaryRepository.yearId(year),
      type: AiAnalysisJobType.yearSummary,
      targetId: PeriodSummaryRepository.yearId(year),
      pipelineVersion: targetPipelineVersion,
      batchId: monthBatchId,
      batchLabel: monthBatchLabel,
    );
  }

  Future<AiAnalysisJob> enqueueUserProfile({
    int? pipelineVersion,
    String? batchId,
    String? batchLabel,
  }) {
    return _enqueuePeriodSummary(
      id: 'user-profile',
      type: AiAnalysisJobType.userProfile,
      targetId: 'ai-user-profile',
      pipelineVersion: pipelineVersion ?? DateTime.now().microsecondsSinceEpoch,
      batchId: batchId,
      batchLabel: batchLabel,
    );
  }

  Future<AiAnalysisJob> _enqueuePeriodSummary({
    required String id,
    required AiAnalysisJobType type,
    required String targetId,
    required int pipelineVersion,
    String? batchId,
    String? batchLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final existing = await getJob(id);
    final job = AiAnalysisJob(
      id: id,
      entryId: targetId,
      type: type,
      targetId: targetId,
      pipelineVersion: pipelineVersion,
      state: AiAnalysisJobState.pending,
      currentStage: AiAnalysisStage.queued,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      batchId: batchId ?? existing?.batchId,
      batchLabel: batchLabel ?? existing?.batchLabel,
    );
    await prefs.setString('$_prefix${job.id}', jsonEncode(job.toJson()));
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    if (!index.contains(job.id)) {
      index.add(job.id);
      await prefs.setStringList(_indexKey, index);
    }
    AiAnalysisQueueBus.bump();
    return job;
  }

  Future<int> enqueueMissingPeriodDependencies({int limit = 200}) async {
    if (await isPaused()) return 0;
    final jobs = await listJobs();
    var enqueued = 0;
    for (final job in jobs) {
      if (enqueued >= limit) break;
      if (!job.canRun) continue;
      if (job.type == AiAnalysisJobType.monthSummary) {
        final month = _monthFromId(job.targetId);
        if (month == null) continue;
        enqueued += await _enqueueDiaryDependenciesForMonth(
          month,
          batchId:
              job.batchId ?? 'period:${job.targetId}:${job.pipelineVersion}',
          batchLabel:
              job.batchLabel ?? '周期总结前置资料 ${_dateTimeLabel(DateTime.now())}',
          limit: limit - enqueued,
        );
        continue;
      }
      if (job.type == AiAnalysisJobType.yearSummary) {
        final year = _yearFromId(job.targetId);
        if (year == null) continue;
        final months = (await _diaryRepository.listEntries())
            .where((entry) =>
                entry.date.year == year && entry.content.trim().isNotEmpty)
            .map((entry) => entry.date.month)
            .toSet()
            .toList()
          ..sort();
        for (final monthIndex in months) {
          if (enqueued >= limit) break;
          final month = DateTime(year, monthIndex);
          final monthId = PeriodSummaryRepository.monthId(month);
          final monthJob = await getJob(monthId);
          final monthSummary =
              await _periodSummaryRepository.getSummary(monthId);
          if (monthSummary != null ||
              (monthJob != null &&
                  monthJob.state != AiAnalysisJobState.completed)) {
            continue;
          }
          await enqueueMonthSummary(
            month,
            pipelineVersion: job.pipelineVersion,
            batchId:
                job.batchId ?? 'period:${job.targetId}:${job.pipelineVersion}',
            batchLabel: job.batchLabel ??
                '年度总结前置月度总结 ${_dateTimeLabel(DateTime.now())}',
          );
          enqueued++;
        }
      }
    }
    return enqueued;
  }

  Future<int> _enqueueDiaryDependenciesForMonth(
    DateTime month, {
    required String batchId,
    required String batchLabel,
    int limit = 200,
  }) async {
    final entries = await _diaryRepository.listEntries();
    final scoped = entries.where((entry) {
      return entry.date.year == month.year &&
          entry.date.month == month.month &&
          entry.content.trim().isNotEmpty;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    var enqueued = 0;
    for (final entry in scoped) {
      if (!await _entryNeedsDiaryJob(entry)) continue;
      await enqueueEntry(entry, batchId: batchId, batchLabel: batchLabel);
      enqueued++;
      if (enqueued >= limit) break;
    }
    return enqueued;
  }

  Future<bool> _entryNeedsDiaryJob(DiaryEntry entry) async {
    final existing = await getJob(entry.id);
    final summary = await _summaryRepository.getSummary(entry.id);
    final summaryReady = summary != null &&
        summary.entryUpdatedAt.isAtSameMomentAs(entry.updatedAt);
    if (summaryReady) return false;
    if (existing != null &&
        (existing.state == AiAnalysisJobState.pending ||
            existing.state == AiAnalysisJobState.running ||
            existing.state == AiAnalysisJobState.incomplete ||
            existing.state == AiAnalysisJobState.failed)) {
      return true;
    }
    return true;
  }

  Future<void> saveJob(AiAnalysisJob job) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix${job.id}', jsonEncode(job.toJson()));
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    if (!index.contains(job.id)) {
      index.add(job.id);
      await prefs.setStringList(_indexKey, index);
    }
    AiAnalysisQueueBus.bump();
  }

  Future<AiAnalysisJob?> getJob(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix$id';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    final job = _jobFromRaw(raw);
    if (job == null) await prefs.remove(key);
    return job;
  }

  AiAnalysisJob? _jobFromPrefs(SharedPreferences prefs, String id) {
    final key = '$_prefix$id';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    return _jobFromRaw(raw);
  }

  AiAnalysisJob? _jobFromRaw(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final job = AiAnalysisJob.fromJson(decoded);
      if (job.id.isEmpty) {
        return null;
      }
      return job;
    } on Object {
      return null;
    }
  }

  Future<void> deleteJob(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
    AiAnalysisQueueBus.bump();
  }

  Future<List<AiAnalysisJob>> listJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    final jobs = <AiAnalysisJob>[];
    for (final id in index) {
      final key = '$_prefix$id';
      final raw = _safeGetString(prefs, key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          await prefs.remove(key);
          continue;
        }
        final job = AiAnalysisJob.fromJson(decoded);
        if (job.id.isEmpty) {
          await prefs.remove(key);
          continue;
        }
        jobs.add(job);
      } on Object {
        await prefs.remove(key);
      }
    }
    await prefs.setStringList(_indexKey, jobs.map((job) => job.id).toList());
    jobs.sort((a, b) {
      final byState =
          _statePriority(a.state).compareTo(_statePriority(b.state));
      if (byState != 0) return byState;
      final byType = _typePriority(a.type).compareTo(_typePriority(b.type));
      if (byType != 0) return byType;
      return a.createdAt.compareTo(b.createdAt);
    });
    return jobs;
  }

  Future<AiAnalysisQueueSnapshot> snapshot() async {
    final jobs = await listJobs();
    final paused = await isPaused();
    final dependencyReasons = await _dependencyReasons(jobs);
    final currentJob = paused
        ? jobs
            .where((job) => job.state == AiAnalysisJobState.running)
            .firstOrNull
        : jobs.where((job) {
            return job.state == AiAnalysisJobState.running ||
                (job.canRun && !dependencyReasons.containsKey(job.id));
          }).firstOrNull;
    return AiAnalysisQueueSnapshot(
      jobs: jobs,
      currentJob: currentJob,
      isPaused: paused,
      dependencyReasons: dependencyReasons,
    );
  }

  Future<AiAnalysisJob?> nextRunnableJob() async {
    await markStaleRunningIncomplete();
    if (await isPaused()) return null;
    final jobs = await listJobs();
    final dependencyReasons = await _dependencyReasons(jobs);
    return jobs
        .where((job) => job.canRun && !dependencyReasons.containsKey(job.id))
        .firstOrNull;
  }

  Future<bool> isPaused() async {
    final prefs = await SharedPreferences.getInstance();
    return _safeGetBool(prefs, _pausedKey) ?? false;
  }

  Future<void> setPaused(bool paused) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pausedKey, paused);
    AiAnalysisQueueBus.bump();
  }

  Future<int> retryFailedJobs() async {
    final jobs = await listJobs();
    var count = 0;
    final now = DateTime.now();
    for (final job in jobs) {
      if (job.state != AiAnalysisJobState.failed) continue;
      await saveJob(job.copyWith(
        state: AiAnalysisJobState.incomplete,
        updatedAt: now,
        retryCount: 0,
        clearLastError: true,
        stageLogs: _appendStageLog(
          job.stageLogs,
          AiAnalysisStageLog(
            stage: job.currentStage,
            startedAt: now,
            message: '用户手动重试',
            inputSummary: 'entryId=${job.entryId}',
            outputSummary: 'state=failed -> incomplete',
          ),
        ),
      ));
      count++;
    }
    return count;
  }

  Future<void> markStaleRunningIncomplete() async {
    final now = DateTime.now();
    final jobs = await listJobs();
    for (final job in jobs) {
      if (job.state != AiAnalysisJobState.running) continue;
      if (now.difference(job.updatedAt) < _staleRunningAge) continue;
      await saveJob(job.copyWith(
        state: AiAnalysisJobState.incomplete,
        updatedAt: now,
        lastError: '上次整理被中断，已等待继续',
        stageLogs: _appendStageLog(
          job.stageLogs,
          AiAnalysisStageLog(
            stage: job.currentStage,
            startedAt: now,
            message: '上次整理被系统中断',
            inputSummary: 'entryId=${job.entryId}',
            outputSummary: 'state=running -> incomplete',
            error: '超过 ${_staleRunningAge.inMinutes} 分钟未更新',
            retryCount: job.retryCount,
          ),
        ),
      ));
    }
  }

  List<AiAnalysisStageLog> _appendStageLog(
    List<AiAnalysisStageLog> logs,
    AiAnalysisStageLog log,
  ) {
    final next = [...logs, log];
    if (next.length <= 80) return next;
    return next.sublist(next.length - 80);
  }

  int _statePriority(AiAnalysisJobState state) {
    switch (state) {
      case AiAnalysisJobState.running:
        return 0;
      case AiAnalysisJobState.pending:
        return 1;
      case AiAnalysisJobState.incomplete:
        return 2;
      case AiAnalysisJobState.failed:
        return 3;
      case AiAnalysisJobState.completed:
        return 4;
    }
  }

  int _typePriority(AiAnalysisJobType type) {
    switch (type) {
      case AiAnalysisJobType.diary:
      case AiAnalysisJobType.embeddingRebuild:
        return 0;
      case AiAnalysisJobType.monthSummary:
        return 1;
      case AiAnalysisJobType.yearSummary:
        return 2;
      case AiAnalysisJobType.userProfile:
        return 3;
    }
  }

  Future<Map<String, String>> _dependencyReasons(
      List<AiAnalysisJob> jobs) async {
    final reasons = <String, String>{};
    final entries = {
      for (final entry in await _diaryRepository.listEntries()) entry.id: entry,
    };
    final monthJobs = <String, AiAnalysisJob>{
      for (final job
          in jobs.where((job) => job.type == AiAnalysisJobType.monthSummary))
        job.targetId: job,
    };
    for (final job in jobs) {
      if (!job.canRun && job.state != AiAnalysisJobState.running) continue;
      if (job.type == AiAnalysisJobType.monthSummary) {
        final month = _monthFromId(job.targetId);
        if (month == null) continue;
        var blockedEntries = 0;
        for (final entry in entries.values.where((entry) =>
            entry.date.year == month.year && entry.date.month == month.month)) {
          final summary = await _summaryRepository.getSummary(entry.id);
          if (summary == null ||
              !summary.entryUpdatedAt.isAtSameMomentAs(entry.updatedAt)) {
            blockedEntries++;
          }
        }
        if (blockedEntries > 0) {
          reasons[job.id] = '等待 $blockedEntries 篇日记整理完成';
        }
      } else if (job.type == AiAnalysisJobType.yearSummary) {
        final year = _yearFromId(job.targetId);
        if (year == null) continue;
        final monthIndexes = entries.values
            .where((entry) => entry.date.year == year)
            .map((entry) => entry.date.month)
            .toSet()
            .toList()
          ..sort();
        final blockedMonths = <DateTime>[];
        for (final monthIndex in monthIndexes) {
          final month = DateTime(year, monthIndex);
          final monthId = PeriodSummaryRepository.monthId(month);
          final monthJob = monthJobs[monthId];
          if (monthJob != null &&
              monthJob.state != AiAnalysisJobState.completed) {
            blockedMonths.add(month);
            continue;
          }
          final summary = await _periodSummaryRepository.getSummary(monthId);
          if (summary == null) {
            blockedMonths.add(month);
          }
        }
        if (blockedMonths.isNotEmpty) {
          final labels = blockedMonths
              .map((item) {
                return '${item.year}年${item.month}月';
              })
              .take(3)
              .toList(growable: false);
          reasons[job.id] =
              '等待 ${blockedMonths.length} 个月度总结完成${labels.isEmpty ? '' : '（${labels.join('、')}）'}';
        }
      }
    }
    return reasons;
  }

  DateTime? _monthFromId(String id) {
    if (!id.startsWith('month:')) return null;
    final value = id.substring('month:'.length);
    final parts = value.split('-');
    if (parts.length != 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return null;
    return DateTime(year, month);
  }

  int? _yearFromId(String id) {
    if (!id.startsWith('year:')) return null;
    return int.tryParse(id.substring('year:'.length));
  }

  String _dateTimeLabel(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
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

  bool? _safeGetBool(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is bool ? value : null;
    } on Object {
      return null;
    }
  }
}
