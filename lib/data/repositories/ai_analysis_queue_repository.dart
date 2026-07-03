import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_analysis_job.dart';
import '../models/diary_entry.dart';
import 'ai_analysis_queue_bus.dart';

class AiAnalysisQueueRepository {
  const AiAnalysisQueueRepository();

  static const _indexKey = 'ai.analysis.jobs.index';
  static const _prefix = 'ai.analysis.jobs.';
  static const _staleRunningAge = Duration(minutes: 10);

  Future<AiAnalysisJob> enqueueEntry(DiaryEntry entry) async {
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
    );
    await prefs.setString('$_prefix${job.id}', jsonEncode(job.toJson()));
    final index = prefs.getStringList(_indexKey) ?? [];
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
    final index = prefs.getStringList(_indexKey) ?? [];
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
      return AiAnalysisJob.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> deleteJob(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
    final index = prefs.getStringList(_indexKey) ?? [];
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
        jobs.add(AiAnalysisJob.fromJson(decoded));
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
    final currentJob = jobs.where((job) {
      return job.state == AiAnalysisJobState.running || job.canRun;
    }).firstOrNull;
    return AiAnalysisQueueSnapshot(jobs: jobs, currentJob: currentJob);
  }

  Future<AiAnalysisJob?> nextRunnableJob() async {
    await markStaleRunningIncomplete();
    final jobs = await listJobs();
    return jobs.where((job) => job.canRun).firstOrNull;
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
      ));
    }
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
}
