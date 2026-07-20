import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/ai_analysis_job.dart';
import '../../../data/models/period_summary.dart';
import '../../../data/repositories/ai_analysis_queue_bus.dart';
import '../../../data/repositories/ai_analysis_queue_repository.dart';
import '../../../data/repositories/ai_embedding_repository.dart';
import '../../../data/repositories/period_summary_repository.dart';
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
  final _periodRepository = const PeriodSummaryRepository();
  final _embeddingRepository = const AiEmbeddingRepository();
  final _embeddingService = const EmbeddingService();

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
    final summaries = await _periodRepository.listSummaries();
    final statuses = await _periodRepository.listStatuses();
    final statusById = {for (final status in statuses) status.id: status};
    final periodJobs = snapshot.jobs
        .where((job) =>
            job.type == AiAnalysisJobType.monthSummary ||
            job.type == AiAnalysisJobType.yearSummary)
        .toList();
    final jobById = {for (final job in periodJobs) job.targetId: job};
    final periodItems = <_PeriodTaskItem>[];
    for (final summary in summaries.take(8)) {
      periodItems.add(_PeriodTaskItem(
        id: summary.id,
        summary: summary,
        status: statusById[summary.id],
        job: jobById[summary.id],
        dependencyReason: snapshot.dependencyReasons[summary.id],
      ));
    }
    final existingIds = periodItems.map((item) => item.id).toSet();
    for (final status in statuses) {
      if (existingIds.contains(status.id)) continue;
      periodItems.add(_PeriodTaskItem(
        id: status.id,
        status: status,
        job: jobById[status.id],
        dependencyReason: snapshot.dependencyReasons[status.id],
      ));
      existingIds.add(status.id);
      if (periodItems.length >= 8) break;
    }
    for (final job in periodJobs) {
      if (existingIds.contains(job.targetId)) continue;
      periodItems.add(_PeriodTaskItem(
        id: job.targetId,
        job: job,
        dependencyReason: snapshot.dependencyReasons[job.targetId],
      ));
      existingIds.add(job.targetId);
      if (periodItems.length >= 8) break;
    }
    return _AiTaskQueueData(
      snapshot: snapshot,
      periodItems: periodItems,
      embeddingSignature: embeddingSignature,
      outdatedEmbeddingCount: outdatedEmbeddingEntryIds.length,
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _dataFuture = _loadData());
  }

  Future<void> _refreshAsync() async {
    setState(() => _dataFuture = _loadData());
    await _dataFuture;
  }

  Future<void> _continueQueue() async {
    await _queueRepository.setPaused(false);
    await _queueRunner.processUntilIdle(maxJobs: 5);
    await _refreshAsync();
  }

  Future<void> _togglePaused(bool paused) async {
    await _queueRepository.setPaused(paused);
    if (!paused) {
      unawaited(_queueRunner.processUntilIdle(maxJobs: 5));
    }
    await _refreshAsync();
  }

  Future<void> _enqueueEmbeddingRebuild() async {
    final count = await _queueRunner.enqueueOutdatedEmbeddingRebuild();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count == 0 ? '没有需要重建的历史相似度' : '已加入后台整理：$count 篇日记'),
    ));
    unawaited(_queueRunner.processUntilIdle(maxJobs: 5));
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
                _DiaryQueueSection(
                  snapshot: data.snapshot,
                  onContinue: _continueQueue,
                  onPauseChanged: _togglePaused,
                ),
                const SizedBox(height: 16),
                _EmbeddingQueueSection(
                  snapshot: data.snapshot,
                  targetLabel: data.embeddingSignature.label,
                  outdatedCount: data.outdatedEmbeddingCount,
                  onRebuild: _enqueueEmbeddingRebuild,
                  onContinue: _continueQueue,
                ),
                const SizedBox(height: 16),
                _PeriodQueueSection(
                  items: data.periodItems,
                  onContinue: _continueQueue,
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
    required this.periodItems,
    required this.embeddingSignature,
    required this.outdatedEmbeddingCount,
  });

  final AiAnalysisQueueSnapshot snapshot;
  final List<_PeriodTaskItem> periodItems;
  final EmbeddingModelSignature embeddingSignature;
  final int outdatedEmbeddingCount;
}

class _PeriodTaskItem {
  const _PeriodTaskItem({
    required this.id,
    this.summary,
    this.status,
    this.job,
    this.dependencyReason,
  });

  final String id;
  final PeriodSummary? summary;
  final PeriodSummaryStatus? status;
  final AiAnalysisJob? job;
  final String? dependencyReason;
}

class _DiaryQueueSection extends StatelessWidget {
  const _DiaryQueueSection({
    required this.snapshot,
    required this.onContinue,
    required this.onPauseChanged,
  });

  final AiAnalysisQueueSnapshot snapshot;
  final VoidCallback onContinue;
  final Future<void> Function(bool paused) onPauseChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diaryJobs = snapshot.jobs
        .where((job) => job.type == AiAnalysisJobType.diary)
        .toList(growable: false);
    final current = snapshot.currentJob?.type == AiAnalysisJobType.diary
        ? snapshot.currentJob
        : null;
    final runnableCount = diaryJobs.where((job) => job.canRun).length;
    final activeCount =
        runnableCount + (current?.state == AiAnalysisJobState.running ? 1 : 0);
    final totalVisible = diaryJobs
        .where((job) =>
            job.canRun ||
            job.state == AiAnalysisJobState.running ||
            job.state == AiAnalysisJobState.completed)
        .length;
    final completedCount = diaryJobs
        .where((job) => job.state == AiAnalysisJobState.completed)
        .length;
    final incompleteCount = diaryJobs
        .where((job) => job.state == AiAnalysisJobState.incomplete)
        .length;
    final failedCount =
        diaryJobs.where((job) => job.state == AiAnalysisJobState.failed).length;
    final progress = totalVisible == 0
        ? 0.0
        : (completedCount / totalVisible).clamp(0.0, 1.0).toDouble();

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
                  child: Text('日记 AI 分析', style: theme.textTheme.titleMedium),
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
            if (current == null &&
                runnableCount == 0 &&
                incompleteCount == 0 &&
                failedCount == 0)
              Text('没有正在等待的日记分析。', style: theme.textTheme.bodyMedium)
            else ...[
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
                  _CountChip(label: '已整理', count: completedCount),
                ],
              ),
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
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: snapshot.runnableCount > 0 ? onContinue : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('继续整理'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmbeddingQueueSection extends StatelessWidget {
  const _EmbeddingQueueSection({
    required this.snapshot,
    required this.targetLabel,
    required this.outdatedCount,
    required this.onRebuild,
    required this.onContinue,
  });

  final AiAnalysisQueueSnapshot snapshot;
  final String targetLabel;
  final int outdatedCount;
  final VoidCallback onRebuild;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jobs = snapshot.jobs
        .where((job) => job.type == AiAnalysisJobType.embeddingRebuild)
        .toList(growable: false);
    final activeJobs = jobs
        .where((job) =>
            job.canRun ||
            job.state == AiAnalysisJobState.running ||
            job.state == AiAnalysisJobState.completed)
        .toList(growable: false);
    final completedCount = activeJobs
        .where((job) => job.state == AiAnalysisJobState.completed)
        .length;
    final failedCount =
        jobs.where((job) => job.state == AiAnalysisJobState.failed).length;
    final runningOrPending = jobs
        .where((job) => job.canRun || job.state == AiAnalysisJobState.running)
        .length;
    final progress = activeJobs.isEmpty
        ? 0.0
        : (completedCount / activeJobs.length).clamp(0.0, 1.0).toDouble();
    final batches = snapshot.batches
        .where((batch) => batch.jobs
            .any((job) => job.type == AiAnalysisJobType.embeddingRebuild))
        .toList(growable: false);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.manage_search_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('历史相似度索引', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('当前目标：$targetLabel', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, minHeight: 4),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CountChip(label: '需要重建', count: outdatedCount),
                _CountChip(label: '运行/待处理', count: runningOrPending),
                _CountChip(label: '失败', count: failedCount),
                _CountChip(label: '已整理', count: completedCount),
              ],
            ),
            if (batches.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final batch in batches.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BatchLine(batch: batch),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: outdatedCount > 0 ? onRebuild : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('一键重建'),
                ),
                OutlinedButton.icon(
                  onPressed: runningOrPending > 0 ? onContinue : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('继续重建'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodQueueSection extends StatelessWidget {
  const _PeriodQueueSection({required this.items, required this.onContinue});

  final List<_PeriodTaskItem> items;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRunnableJobs = items.any((item) =>
        item.job != null && item.job!.state != AiAnalysisJobState.completed);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights_outlined),
                const SizedBox(width: 10),
                Text('周期总结', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text('还没有生成过月度或年度总结。', style: theme.textTheme.bodyMedium)
            else
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PeriodTaskTile(item: item),
                ),
            if (hasRunnableJobs) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.play_arrow),
                label: const Text('继续整理周期总结'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeriodTaskTile extends StatelessWidget {
  const _PeriodTaskTile({required this.item});

  final _PeriodTaskItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = item.summary;
    final status = item.status;
    final job = item.job;
    final periodType = summary?.type ??
        (item.id.startsWith('year:')
            ? PeriodSummaryType.year
            : PeriodSummaryType.month);
    final label = summary == null
        ? _periodLabelFromId(item.id)
        : periodType == PeriodSummaryType.month
            ? '${summary.startDate.year}年${summary.startDate.month}月'
            : '${summary.startDate.year}年';
    final dependencyReason = item.dependencyReason;
    final state = status?.state ??
        (job == null
            ? PeriodSummaryState.completed
            : job.state == AiAnalysisJobState.completed
                ? PeriodSummaryState.completed
                : job.state == AiAnalysisJobState.failed
                    ? PeriodSummaryState.failed
                    : PeriodSummaryState.generating);
    return Row(
      children: [
        Icon(_periodStateIcon(state), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '$label ${periodType == PeriodSummaryType.month ? '月度总结' : '年度总结'}'),
              const SizedBox(height: 2),
              Text(
                status?.message ?? (summary == null ? '等待生成' : '已生成'),
                style: theme.textTheme.bodySmall,
              ),
              if ((dependencyReason ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  dependencyReason!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              if (job != null) ...[
                const SizedBox(height: 2),
                Text(job.stageLabel, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        Text((summary?.generator.startsWith('ai-') ?? false) ? 'AI' : '队列',
            style: theme.textTheme.bodySmall),
      ],
    );
  }

  String _periodLabelFromId(String id) {
    if (id.startsWith('year:')) {
      return '${id.substring('year:'.length)}年';
    }
    if (id.startsWith('month:')) {
      final value = id.substring('month:'.length);
      final parts = value.split('-');
      if (parts.length == 2) {
        final month = int.tryParse(parts[1]) ?? parts[1];
        return '${parts[0]}年$month月';
      }
    }
    return id;
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

IconData _periodStateIcon(PeriodSummaryState state) {
  switch (state) {
    case PeriodSummaryState.generating:
      return Icons.autorenew;
    case PeriodSummaryState.completed:
      return Icons.check_circle_outline;
    case PeriodSummaryState.failed:
      return Icons.error_outline;
    case PeriodSummaryState.idle:
      return Icons.schedule;
  }
}
