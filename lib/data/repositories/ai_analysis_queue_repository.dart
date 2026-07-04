import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_analysis_job.dart';
import '../models/diary_entry.dart';
import 'ai_analysis_queue_bus.dart';

class AiAnalysisQueueRepository {
  const AiAnalysisQueueRepository();

  static const _indexKey = 'ai.analysis.jobs.index';
  static const _pausedKey = 'ai.analysis.jobs.paused';
  static const _prefix = 'ai.analysis.jobs.';
  static const _staleRunningAge = Duration(minutes: 10);

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
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      final job = AiAnalysisJob.fromJson(decoded);
      if (job.id.isEmpty) {
        await prefs.remove(key);
        return null;
      }
      return job;
    } on Object {
      await prefs.remove(key);
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
      return a.createdAt.compareTo(b.createdAt);
    });
    return jobs;
  }

  Future<AiAnalysisQueueSnapshot> snapshot() async {
    final jobs = await listJobs();
    final paused = await isPaused();
    final currentJob = paused
        ? jobs
            .where((job) => job.state == AiAnalysisJobState.running)
            .firstOrNull
        : jobs.where((job) {
            return job.state == AiAnalysisJobState.running || job.canRun;
          }).firstOrNull;
    return AiAnalysisQueueSnapshot(
      jobs: jobs,
      currentJob: currentJob,
      isPaused: paused,
    );
  }

  Future<AiAnalysisJob?> nextRunnableJob() async {
    await markStaleRunningIncomplete();
    if (await isPaused()) return null;
    final jobs = await listJobs();
    return jobs.where((job) => job.canRun).firstOrNull;
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
