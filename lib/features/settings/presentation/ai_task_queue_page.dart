import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/ai_analysis_job.dart';
import '../../../data/repositories/ai_analysis_queue_bus.dart';
import '../../../data/repositories/ai_analysis_queue_repository.dart';
import '../../../data/repositories/ai_embedding_repository.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/services/ai_analysis_queue_runner.dart';
import '../../../data/services/embedding_service.dart';

class AiTaskQueuePage extends StatefulWidget {
  const AiTaskQueuePage({super.key});

  @override
  State<AiTaskQueuePage> createState() => _AiTaskQueuePageState();
}

class _AiTaskQueuePageState extends State<AiTaskQueuePage> {
  final _queueRepository = const AiAnalysisQueueRepository();
  final _queueRunner = const AiAnalysisQueueRunner();
  final _embeddingRepository = const AiEmbeddingRepository();
  final _embeddingService = const EmbeddingService();
  final _diaryRepository = const DiaryRepository();

  late Future<_AiTaskQueueData> _dataFuture = _loadData();

  @override
  void initState() {
    super.initState();
    AiAnalysisQueueBus.version.addListener(_refresh);
  }

  @override
  void dispose() {
    AiAnalysisQueueBus.version.removeListener(_refresh);
    super.dispose();
  }

  Future<_AiTaskQueueData> _loadData() async {
    final snapshot = await _queueRepository.snapshot();
    final embeddingSignature = await _embeddingService.currentTargetSignature();
    final outdatedEmbeddingEntryIds =
        await _embeddingRepository.listOutdatedEntryIds(
      modelId: embeddingSignature.modelId,
      modelVersion: embeddingSignature.modelVersion,
      dimensions: embeddingSignature.dimensions,
    );
    final entries = await _diaryRepository.listEntries();
    return _AiTaskQueueData(
      snapshot: snapshot,
      embeddingSignature: embeddingSignature,
      outdatedEmbeddingCount: outdatedEmbeddingEntryIds.length,
      rebuildableEmbeddingCount:
          entries.where((entry) => entry.content.trim().isNotEmpty).length,
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<void> _refreshAsync() async {
    setState(() {
      _dataFuture = _loadData();
    });
    await _dataFuture;
  }

  Future<void> _continueQueue() async {
    final messenger = ScaffoldMessenger.of(context);
    await _queueRepository.setPaused(false);
    final repaired = await _queueRepository.enqueueMissingPeriodDependencies();
    await _queueRunner.processUntilIdle(maxJobs: 1);
    await _refreshAsync();
    if (!mounted) return;
    final snapshot = await _queueRepository.snapshot();
    messenger.showSnackBar(
      SnackBar(content: Text(_continueResultLabel(repaired, snapshot))),
    );
  }

  String _continueResultLabel(
    int repaired,
    AiAnalysisQueueSnapshot snapshot,
  ) {
    final firstDependency = snapshot.dependencyReasons.values.firstOrNull;
    final parts = [
      if (repaired > 0) '已补齐 $repaired 个依赖任务' else '没有新增依赖任务',
      '可运行 ${snapshot.runnableCount}',
      if (snapshot.dependencyReasons.isNotEmpty)
        '阻塞 ${snapshot.dependencyReasons.length}',
      if (firstDependency != null) firstDependency,
    ];
    return parts.join(' · ');
  }

  Future<void> _togglePaused(bool paused) async {
    await _queueRepository.setPaused(paused);
    if (!paused) {
      await _queueRepository.enqueueMissingPeriodDependencies();
      unawaited(_queueRunner.processUntilIdle(maxJobs: 1));
    }
    await _refreshAsync();
  }

  Future<void> _enqueueEmbeddingRebuild() async {
    final count = await _queueRunner.enqueueAllEmbeddingRebuild();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count == 0 ? '没有可重建的日记' : '已加入后台整理：$count 篇日记'),
    ));
    unawaited(_queueRunner.processUntilIdle(maxJobs: 1));
    await _refreshAsync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 整理进度')),
      body: RefreshIndicator(
        onRefresh: _refreshAsync,
        child: FutureBuilder<_AiTaskQueueData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _UnifiedQueueSection(
                  snapshot: data.snapshot,
                  targetLabel: data.embeddingSignature.label,
                  outdatedEmbeddingCount: data.outdatedEmbeddingCount,
                  rebuildableEmbeddingCount: data.rebuildableEmbeddingCount,
                  onContinue: _continueQueue,
                  onRebuild: _enqueueEmbeddingRebuild,
                  onPauseChanged: _togglePaused,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AiTaskQueueData {
  const _AiTaskQueueData({
    required this.snapshot,
    required this.embeddingSignature,
    required this.outdatedEmbeddingCount,
    required this.rebuildableEmbeddingCount,
  });

  final AiAnalysisQueueSnapshot snapshot;
  final EmbeddingModelSignature embeddingSignature;
  final int outdatedEmbeddingCount;
  final int rebuildableEmbeddingCount;
}

class _UnifiedQueueSection extends StatelessWidget {
  const _UnifiedQueueSection({
    required this.snapshot,
    required this.targetLabel,
    required this.outdatedEmbeddingCount,
    required this.rebuildableEmbeddingCount,
    required this.onContinue,
    required this.onRebuild,
    required this.onPauseChanged,
  });

  final AiAnalysisQueueSnapshot snapshot;
  final String targetLabel;
  final int outdatedEmbeddingCount;
  final int rebuildableEmbeddingCount;
  final VoidCallback onContinue;
  final VoidCallback onRebuild;
  final Future<void> Function(bool paused) onPauseChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleJobs = snapshot.jobs
        .where((job) =>
            job.canRun ||
            job.state == AiAnalysisJobState.running ||
            job.state == AiAnalysisJobState.incomplete ||
            job.state == AiAnalysisJobState.failed ||
            job.state == AiAnalysisJobState.completed)
        .toList(growable: false);
    final current = snapshot.currentJob;
    final runnableCount = visibleJobs.where((job) => job.canRun).length;
    final activeCount =
        runnableCount + (current?.state == AiAnalysisJobState.running ? 1 : 0);
    final completedCount = visibleJobs
        .where((job) => job.state == AiAnalysisJobState.completed)
        .length;
    final incompleteCount = visibleJobs
        .where((job) => job.state == AiAnalysisJobState.incomplete)
        .length;
    final failedCount = visibleJobs
        .where((job) => job.state == AiAnalysisJobState.failed)
        .length;
    final progress = visibleJobs.isEmpty
        ? 0.0
        : (completedCount / visibleJobs.length).clamp(0.0, 1.0).toDouble();
    final latestJobs = visibleJobs.take(6).toList(growable: false);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_motion_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('AI 整理队列', style: theme.textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => onPauseChanged(!snapshot.isPaused),
                  child: Text(snapshot.isPaused ? '继续' : '暂停'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, minHeight: 4),
            const SizedBox(height: 10),
            if (visibleJobs.isEmpty)
              Text('没有正在等待的整理任务。', style: theme.textTheme.bodyMedium)
            else
              Text(
                snapshot.isPaused
                    ? '后台整理已暂停'
                    : current == null
                        ? '等待继续'
                        : current.stageLabel,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CountChip(label: '运行/待处理', count: activeCount),
                _CountChip(label: '待恢复', count: incompleteCount),
                _CountChip(label: '失败', count: failedCount),
                _CountChip(label: '已完成', count: completedCount),
                _CountChip(label: '向量待重建', count: outdatedEmbeddingCount),
              ],
            ),
            const SizedBox(height: 8),
            Text('向量目标：$targetLabel', style: theme.textTheme.bodySmall),
            if (snapshot.estimatedRemainingLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('预计剩余 ${snapshot.estimatedRemainingLabel}',
                  style: theme.textTheme.bodySmall),
            ],
            if (snapshot.batches.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('批次进度', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final batch in snapshot.batches.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BatchLine(batch: batch),
                ),
            ],
            if (latestJobs.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('最近任务', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final job in latestJobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _QueueJobTile(job: job),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: snapshot.hasVisibleWork ? onContinue : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('继续整理'),
                ),
                OutlinedButton.icon(
                  onPressed: rebuildableEmbeddingCount > 0 ? onRebuild : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('全量重建向量'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueJobTile extends StatelessWidget {
  const _QueueJobTile({required this.job});

  final AiAnalysisJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(_jobStateIcon(job.state), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${_jobTypeLabel(job.type)} · ${job.stageLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _BatchLine extends StatelessWidget {
  const _BatchLine({required this.batch});

  final AiAnalysisBatchSnapshot batch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(batch.label)),
            Text(batch.progressLabel, style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: batch.progress, minHeight: 3),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $count'));
  }
}

String _jobTypeLabel(AiAnalysisJobType type) {
  switch (type) {
    case AiAnalysisJobType.diary:
      return '日记';
    case AiAnalysisJobType.embeddingRebuild:
      return '向量';
    case AiAnalysisJobType.monthSummary:
      return '月报';
    case AiAnalysisJobType.yearSummary:
      return '年报';
    case AiAnalysisJobType.userProfile:
      return '画像';
  }
}

IconData _jobStateIcon(AiAnalysisJobState state) {
  switch (state) {
    case AiAnalysisJobState.pending:
    case AiAnalysisJobState.incomplete:
      return Icons.schedule;
    case AiAnalysisJobState.running:
      return Icons.autorenew;
    case AiAnalysisJobState.completed:
      return Icons.check_circle_outline;
    case AiAnalysisJobState.failed:
      return Icons.error_outline;
  }
}
