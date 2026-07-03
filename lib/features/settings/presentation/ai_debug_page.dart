import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/ai_analysis_job.dart';
import '../../../data/models/ai_embedding.dart';
import '../../../data/models/ai_prompt_trace.dart';
import '../../../data/models/ai_retrieval_trace.dart';
import '../../../data/models/entry_summary.dart';
import '../../../data/models/period_summary.dart';
import '../../../data/repositories/ai_analysis_queue_bus.dart';
import '../../../data/repositories/ai_analysis_queue_repository.dart';
import '../../../data/repositories/ai_embedding_repository.dart';
import '../../../data/repositories/ai_feedback_repository.dart';
import '../../../data/repositories/ai_prompt_trace_repository.dart';
import '../../../data/repositories/ai_retrieval_trace_repository.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/entry_summary_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/repositories/memory_repository.dart';
import '../../../data/repositories/period_summary_repository.dart';
import '../../../data/services/ai_analysis_queue_runner.dart';
import '../../../data/services/ai_embedding_text_builder.dart';
import '../../../data/services/embedding_service.dart';

class AiDebugPage extends StatefulWidget {
  const AiDebugPage({super.key});

  @override
  State<AiDebugPage> createState() => _AiDebugPageState();
}

class _AiDebugPageState extends State<AiDebugPage> {
  final _queueRepository = const AiAnalysisQueueRepository();
  final _queueRunner = const AiAnalysisQueueRunner();
  late Future<AiAnalysisQueueSnapshot> _snapshotFuture =
      _queueRepository.snapshot();

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

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _snapshotFuture = _queueRepository.snapshot();
    });
  }

  Future<void> _continueQueue() async {
    await _queueRunner.processUntilIdle(maxJobs: 5);
    _refresh();
  }

  Future<void> _enqueueBackfill() async {
    final count = await _queueRunner.enqueueBackfill();
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(count == 0 ? '没有需要补建的日记' : '已入队 $count 篇日记')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 调试'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<AiAnalysisQueueSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          final queue = snapshot.data;
          if (queue == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _QueueSummaryCard(
                queue: queue,
                onContinue: _continueQueue,
                onBackfill: _enqueueBackfill,
              ),
              const SizedBox(height: 16),
              const _RecentRetrievalTraceCard(),
              const SizedBox(height: 16),
              const _RecentPeriodSummaryCard(),
              const SizedBox(height: 16),
              const _CompanionTraceCard(),
              const SizedBox(height: 16),
              if (queue.jobs.isEmpty)
                const Center(child: Text('暂无 AI 队列任务'))
              else
                for (final job in queue.jobs) ...[
                  _JobCard(job: job, onChanged: _refresh),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _RecentRetrievalTraceCard extends StatefulWidget {
  const _RecentRetrievalTraceCard();

  @override
  State<_RecentRetrievalTraceCard> createState() =>
      _RecentRetrievalTraceCardState();
}

class _RecentRetrievalTraceCardState extends State<_RecentRetrievalTraceCard> {
  late Future<_RecentRetrievalTraces> _future = _RecentRetrievalTraces.load();

  Future<void> _clear() async {
    const repository = AiRetrievalTraceRepository();
    await repository.deleteForEntry('search:last');
    await repository.deleteForEntry('question:last');
    await repository.deleteForEntry('period:last');
    if (!mounted) return;
    setState(() {
      _future = _RecentRetrievalTraces.load();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除最近检索调试记录')),
    );
  }

  Future<void> _copy(
      BuildContext context, _RecentRetrievalTraces traces) async {
    await Clipboard.setData(ClipboardData(text: traces.toDebugText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制最近检索调试上下文')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        final traces = snapshot.data;
        if (traces == null || traces.items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('最近检索上下文',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                    TextButton.icon(
                      onPressed: () => _copy(context, traces),
                      icon: const Icon(Icons.copy),
                      label: const Text('复制'),
                    ),
                    TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('清除'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final trace in traces.items) ...[
                  _DebugLine(label: trace.label, value: trace.summary),
                  for (final line in trace.lines.take(4))
                    _DebugLine(label: 'source', value: line),
                  if (trace != traces.items.last) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentPeriodSummaryCard extends StatelessWidget {
  const _RecentPeriodSummaryCard();

  Future<void> _copy(
      BuildContext context, _RecentPeriodSummaries summaries) async {
    await Clipboard.setData(ClipboardData(text: summaries.toDebugText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制周期总结调试上下文')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _RecentPeriodSummaries.load(),
      builder: (context, snapshot) {
        final summaries = snapshot.data;
        if (summaries == null || summaries.items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('最近周期总结',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                    TextButton.icon(
                      onPressed: () => _copy(context, summaries),
                      icon: const Icon(Icons.copy),
                      label: const Text('复制总结'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final summary in summaries.items) ...[
                  _DebugLine(label: summary.label, value: summary.brief),
                  for (final line in summary.lines)
                    _DebugLine(label: 'summary', value: line),
                  if (summary != summaries.items.last)
                    const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompanionTraceCard extends StatefulWidget {
  const _CompanionTraceCard();

  @override
  State<_CompanionTraceCard> createState() => _CompanionTraceCardState();
}

class _CompanionTraceCardState extends State<_CompanionTraceCard> {
  late Future<AiPromptTrace?> _future =
      const AiPromptTraceRepository().getTrace('companion:last');

  Future<void> _copyTrace(BuildContext context, AiPromptTrace trace) async {
    final text = [
      '## Companion Prompt Trace',
      'scenario=${trace.scenario}',
      'createdAt=${trace.createdAt.toIso8601String()}',
      'context=${trace.contextSummary}',
      'systemLength=${trace.systemPromptLength}',
      'userLength=${trace.userPromptLength}',
      if ((trace.systemPrompt ?? '').isNotEmpty)
        'SYSTEM:\n${trace.systemPrompt}'
      else if (trace.systemPromptPreview.isNotEmpty)
        'SYSTEM PREVIEW:\n${trace.systemPromptPreview}',
      if ((trace.userPrompt ?? '').isNotEmpty)
        'USER:\n${trace.userPrompt}'
      else if (trace.userPromptPreview.isNotEmpty)
        'USER PREVIEW:\n${trace.userPromptPreview}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制陪伴问答调试上下文')),
    );
  }

  Future<void> _clearTrace(BuildContext context) async {
    await const AiPromptTraceRepository().deleteTrace('companion:last');
    if (!context.mounted) return;
    setState(() {
      _future = const AiPromptTraceRepository().getTrace('companion:last');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除陪伴问答调试记录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        final trace = snapshot.data;
        if (trace == null) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('最近陪伴问答',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyTrace(context, trace),
                      icon: const Icon(Icons.copy),
                      label: const Text('复制'),
                    ),
                    TextButton.icon(
                      onPressed: () => _clearTrace(context),
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('清除'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _DebugLine(label: 'scenario', value: trace.scenario),
                _DebugLine(
                    label: 'createdAt',
                    value: trace.createdAt.toIso8601String()),
                _DebugLine(label: 'context', value: trace.contextSummary),
                _DebugLine(
                    label: 'prompt.length',
                    value:
                        'system=${trace.systemPromptLength} user=${trace.userPromptLength}'),
                if (trace.systemPromptPreview.isNotEmpty)
                  _DebugLine(
                      label: 'system.preview',
                      value: trace.systemPromptPreview),
                if (trace.userPromptPreview.isNotEmpty)
                  _DebugLine(
                      label: 'user.preview', value: trace.userPromptPreview),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QueueSummaryCard extends StatelessWidget {
  const _QueueSummaryCard({
    required this.queue,
    required this.onContinue,
    required this.onBackfill,
  });

  final AiAnalysisQueueSnapshot queue;
  final Future<void> Function() onContinue;
  final Future<void> Function() onBackfill;

  @override
  Widget build(BuildContext context) {
    final running = queue.jobs
        .where((job) => job.state == AiAnalysisJobState.running)
        .length;
    final incomplete = queue.jobs
        .where((job) => job.state == AiAnalysisJobState.incomplete)
        .length;
    final completed = queue.jobs
        .where((job) => job.state == AiAnalysisJobState.completed)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('队列概览',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(label: '运行中', count: running),
                _StatusChip(label: '待处理', count: queue.pendingCount),
                _StatusChip(label: '待恢复', count: incomplete),
                _StatusChip(label: '失败', count: queue.failedCount),
                _StatusChip(label: '完成', count: completed),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: queue.pendingCount > 0 || queue.failedCount > 0
                      ? onContinue
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('继续队列'),
                ),
                OutlinedButton.icon(
                  onPressed: onBackfill,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('补建缺失资料'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $count'));
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onChanged});

  final AiAnalysisJob job;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFailed = job.state == AiAnalysisJobState.failed;
    return FutureBuilder<_JobArtifacts>(
      future: _JobArtifacts.load(job.entryId),
      builder: (context, snapshot) {
        final artifacts = snapshot.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _stateIcon(job.state),
                      color: isFailed ? theme.colorScheme.error : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(job.state.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(job.stageLabel, style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 10),
                _DebugLine(label: 'entryId', value: job.entryId),
                _DebugLine(
                    label: 'pipelineVersion', value: '${job.pipelineVersion}'),
                _DebugLine(label: 'retryCount', value: '${job.retryCount}'),
                _DebugLine(
                    label: 'updatedAt', value: job.updatedAt.toIso8601String()),
                if (job.completedStages.isNotEmpty)
                  _DebugLine(
                    label: 'completedStages',
                    value:
                        job.completedStages.map((item) => item.name).join(', '),
                  ),
                if (job.stageLogs.isNotEmpty) ...[
                  _DebugLine(
                      label: 'stageLogs', value: '${job.stageLogs.length}'),
                  for (final log in job.stageLogs.reversed.take(4))
                    _DebugLine(label: 'stageLog', value: _stageLogLine(log)),
                ],
                if (artifacts != null) ...[
                  const Divider(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showDebugDetails(context, artifacts),
                        icon: const Icon(Icons.article_outlined),
                        label: const Text('详情'),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _copyPipelineContext(context, artifacts),
                        icon: const Icon(Icons.copy_all_outlined),
                        label: const Text('复制上下文'),
                      ),
                      TextButton.icon(
                        onPressed: artifacts.hasSummary
                            ? () => _correctSummary(context, artifacts)
                            : null,
                        icon: const Icon(Icons.edit_note_outlined),
                        label: const Text('修正摘要'),
                      ),
                      TextButton.icon(
                        onPressed: job.state == AiAnalysisJobState.running
                            ? null
                            : () => _reenqueue(context),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('继续/重试'),
                      ),
                      TextButton.icon(
                        onPressed: job.state == AiAnalysisJobState.running
                            ? null
                            : () => _rebuildArtifacts(context),
                        icon: const Icon(Icons.refresh_outlined),
                        label: const Text('重建资料'),
                      ),
                      TextButton.icon(
                        onPressed: job.state == AiAnalysisJobState.running
                            ? null
                            : () => _deleteJob(context),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除任务'),
                      ),
                      TextButton.icon(
                        onPressed: () => _clearDebugTraces(context),
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('清除调试'),
                      ),
                    ],
                  ),
                  _DebugLine(label: 'summary.brief', value: artifacts.brief),
                  if (artifacts.summaryMeta.isNotEmpty)
                    _DebugLine(
                        label: 'summary.meta', value: artifacts.summaryMeta),
                  _DebugLine(
                      label: 'segments', value: '${artifacts.segmentCount}'),
                  if (artifacts.firstSegment.isNotEmpty)
                    _DebugLine(
                        label: 'segments[0]', value: artifacts.firstSegment),
                  _DebugLine(
                      label: 'embeddings',
                      value:
                          '${artifacts.embeddingCount} ${artifacts.embeddingModel}'),
                  if (artifacts.embeddingTypes.isNotEmpty)
                    _DebugLine(
                        label: 'embedding.types',
                        value: artifacts.embeddingTypes),
                  for (final line in artifacts.embeddingLines.take(3))
                    _DebugLine(label: 'embedding', value: line),
                  if (artifacts.contextSummary.isNotEmpty)
                    _DebugLine(
                        label: 'context', value: artifacts.contextSummary),
                  if (artifacts.promptSummary.isNotEmpty)
                    _DebugLine(label: 'prompt', value: artifacts.promptSummary),
                  if (artifacts.promptPreview.isNotEmpty)
                    _DebugLine(
                        label: 'prompt.preview',
                        value: artifacts.promptPreview),
                  if (artifacts.claimSummary.isNotEmpty)
                    _DebugLine(
                        label: 'insight.claims', value: artifacts.claimSummary),
                  for (final line in artifacts.claimLines.take(4))
                    _DebugLine(label: 'claim', value: line),
                  if (artifacts.updateCandidateSummary.isNotEmpty)
                    _DebugLine(
                      label: 'insight.updateCandidates',
                      value: artifacts.updateCandidateSummary,
                    ),
                  for (final line in artifacts.updateCandidateLines.take(4))
                    _DebugLine(label: 'updateCandidate', value: line),
                  if (artifacts.feedback.isNotEmpty)
                    _DebugLine(label: 'feedback', value: artifacts.feedback),
                  if (artifacts.memoryLifecycle.isNotEmpty)
                    _DebugLine(
                        label: 'memory.lifecycle',
                        value: artifacts.memoryLifecycle),
                  _DebugLine(
                      label: 'retrieval.sources',
                      value: '${artifacts.retrievalCount}'),
                  if (artifacts.calendarCount > 0)
                    _DebugLine(
                        label: 'calendar.sources',
                        value: '${artifacts.calendarCount}'),
                  for (final line in artifacts.retrievalLines.take(3))
                    _DebugLine(label: 'retrieval', value: line),
                ],
                if (job.lastError != null && job.lastError!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(job.lastError!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _reenqueue(BuildContext context) async {
    const diaryRepository = DiaryRepository();
    const queueRunner = AiAnalysisQueueRunner();
    final entry = await diaryRepository.getEntryById(job.entryId);
    if (!context.mounted) return;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日记不存在，无法重新入队')),
      );
      return;
    }
    await queueRunner.enqueue(entry, start: false);
    if (!context.mounted) return;
    onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入队列，将继续或重试未完成阶段')),
    );
  }

  Future<void> _rebuildArtifacts(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重建本篇 AI 资料？'),
        content: const Text(
          '这会清除本篇已生成的摘要、分段、向量、今日洞察和调试记录，然后重新加入队列。原始日记不会被修改。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重建'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    const diaryRepository = DiaryRepository();
    final entry = await diaryRepository.getEntryById(job.entryId);
    if (!context.mounted) return;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日记不存在，无法重建')),
      );
      return;
    }
    await const InsightRepository().deleteForEntry(entry.id);
    await const AiEmbeddingRepository().deleteForEntry(entry.id);
    await const EntrySummaryRepository().deleteForEntry(entry.id);
    await const AiPromptTraceRepository().deleteTrace(entry.id);
    await const AiRetrievalTraceRepository().deleteForEntry(entry.id);
    await const AiAnalysisQueueRunner().enqueue(entry, start: false);
    if (!context.mounted) return;
    onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除本篇 AI 资料并重新加入队列')),
    );
  }

  Future<void> _deleteJob(BuildContext context) async {
    const repository = AiAnalysisQueueRepository();
    await repository.deleteJob(job.id);
    if (!context.mounted) return;
    onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除队列任务')),
    );
  }

  Future<void> _clearDebugTraces(BuildContext context) async {
    const promptRepository = AiPromptTraceRepository();
    const retrievalRepository = AiRetrievalTraceRepository();
    await promptRepository.deleteTrace(job.entryId);
    await retrievalRepository.deleteForEntry(job.entryId);
    if (!context.mounted) return;
    onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除本篇调试记录')),
    );
  }

  Future<void> _correctSummary(
    BuildContext context,
    _JobArtifacts artifacts,
  ) async {
    final corrected = await showDialog<_SummaryCorrectionResult>(
      context: context,
      builder: (context) =>
          _SummaryCorrectionDialog(summary: artifacts.summary!),
    );
    if (corrected == null || corrected.brief.isEmpty) {
      return;
    }
    final current = artifacts.summary;
    if (current != null &&
        corrected.brief == current.brief.trim() &&
        corrected.title == current.title.trim() &&
        corrected.emotion == current.emotion.trim() &&
        corrected.importance == current.importance &&
        _sameList(corrected.keyPoints, current.keyPoints) &&
        _sameList(corrected.importantQuotes, current.importantQuotes)) {
      return;
    }
    final updated = await const EntrySummaryRepository().correctSummaryPackage(
      entryId: job.entryId,
      brief: corrected.brief,
      title: corrected.title,
      emotion: corrected.emotion,
      importance: corrected.importance,
      keyPoints: corrected.keyPoints,
      importantQuotes: corrected.importantQuotes,
    );
    if (!context.mounted) return;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('摘要不存在，无法修正')),
      );
      return;
    }
    await _refreshEntryEmbedding(updated);
    await _appendSummaryCorrectionLog(updated);
    if (!context.mounted) return;
    onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已修正摘要并刷新摘要向量')),
    );
  }

  Future<void> _copyPipelineContext(
    BuildContext context,
    _JobArtifacts artifacts,
  ) async {
    final allowed = await _confirmCopyDebugContext(context);
    if (allowed != true) return;
    final text = [
      '## AI Pipeline Job',
      'id=${job.id}',
      'entryId=${job.entryId}',
      'state=${job.state.name}',
      'stage=${job.currentStage.name}',
      'pipelineVersion=${job.pipelineVersion}',
      'createdAt=${job.createdAt.toIso8601String()}',
      'updatedAt=${job.updatedAt.toIso8601String()}',
      'retryCount=${job.retryCount}',
      if (job.lastError?.isNotEmpty ?? false) 'lastError=${job.lastError}',
      if (job.completedStages.isNotEmpty)
        'completedStages=${job.completedStages.map((item) => item.name).join(',')}',
      if (job.stageLogs.isNotEmpty) ...[
        '',
        '## Stage Logs',
        for (final log in job.stageLogs) _stageLogExportLine(log),
      ],
      '',
      artifacts.toDebugText(),
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制 Pipeline 调试上下文')),
    );
  }

  Future<void> _appendSummaryCorrectionLog(EntrySummary summary) async {
    const repository = AiAnalysisQueueRepository();
    final latest = await repository.getJob(job.id) ?? job;
    final log = AiAnalysisStageLog(
      stage: AiAnalysisStage.generatingSummary,
      startedAt: DateTime.now(),
      message: '用户修正摘要包',
      inputSummary: 'entryId=${summary.entryId}',
      outputSummary: [
        'generator=${summary.generator}',
        'importance=${summary.importance.toStringAsFixed(2)}',
        'keyPoints=${summary.keyPoints.length}',
        'quotes=${summary.importantQuotes.length}',
      ].join(' '),
      retryCount: latest.retryCount,
    );
    final logs = [...latest.stageLogs, log];
    await repository.saveJob(latest.copyWith(
      updatedAt: DateTime.now(),
      stageLogs: logs.length <= 80 ? logs : logs.sublist(logs.length - 80),
    ));
  }

  Future<void> _refreshEntryEmbedding(EntrySummary summary) async {
    final entry = await const DiaryRepository().getEntryById(summary.entryId);
    if (entry == null) return;
    const textBuilder = AiEmbeddingTextBuilder();
    const embeddingService = EmbeddingService();
    const embeddingRepository = AiEmbeddingRepository();
    final result =
        embeddingService.embed(textBuilder.entryText(entry, summary));
    await embeddingRepository.saveEmbedding(AiEmbedding(
      id: '${AiEmbeddingSourceType.entry.name}:${entry.id}',
      sourceType: AiEmbeddingSourceType.entry,
      sourceId: entry.id,
      entryId: entry.id,
      modelId: result.modelId,
      modelVersion: result.modelVersion,
      dimensions: result.dimensions,
      vector: result.vector,
      generatedAt: DateTime.now(),
      textHash: result.textHash,
    ));
  }

  bool _sameList(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  void _showDebugDetails(BuildContext context, _JobArtifacts artifacts) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('AI 调试详情',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600)),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyDebugDetails(context, artifacts),
                      icon: const Icon(Icons.copy),
                      label: const Text('复制'),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _DebugSection(
                      title: '上下文',
                      lines: [
                        artifacts.contextSummary,
                        if (artifacts.summaryMeta.isNotEmpty)
                          'summary meta: ${artifacts.summaryMeta}',
                        'summary: ${artifacts.brief}',
                        ...artifacts.summaryPackageLines,
                        'segments: ${artifacts.segmentCount}',
                        'embeddings: ${artifacts.embeddingCount} ${artifacts.embeddingModel}',
                        if (artifacts.embeddingTypes.isNotEmpty)
                          'embedding types: ${artifacts.embeddingTypes}',
                        ...artifacts.embeddingLines,
                      ],
                    ),
                    _DebugSection(
                      title: 'Prompt',
                      lines: [
                        artifacts.promptSummary,
                        artifacts.systemPrompt,
                        artifacts.userPrompt,
                      ],
                    ),
                    _DebugSection(
                      title: '结论分层',
                      lines: [
                        artifacts.claimSummary,
                        ...artifacts.claimLines,
                      ],
                    ),
                    _DebugSection(
                      title: '更新候选',
                      lines: [
                        artifacts.updateCandidateSummary,
                        ...artifacts.updateCandidateLines,
                      ],
                    ),
                    _DebugSection(
                      title: '检索来源',
                      lines: [
                        'retrieval=${artifacts.retrievalCount} calendar=${artifacts.calendarCount}',
                        ...artifacts.retrievalLines,
                      ],
                    ),
                    _DebugSection(
                      title: '记忆与反馈',
                      lines: [
                        artifacts.memoryLifecycle,
                        artifacts.feedback,
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyDebugDetails(
    BuildContext context,
    _JobArtifacts artifacts,
  ) async {
    final allowed = await _confirmCopyDebugContext(context);
    if (allowed != true) return;
    final text = artifacts.toDebugText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制调试上下文')),
    );
  }

  Future<bool?> _confirmCopyDebugContext(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('复制调试上下文？'),
        content: const Text(
          '调试上下文可能包含日记摘要、检索来源、完整 Prompt 和 AI 生成结果。'
          '这些内容只会复制到本机剪贴板，请确认不会粘贴到不可信的位置。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }

  IconData _stateIcon(AiAnalysisJobState state) {
    switch (state) {
      case AiAnalysisJobState.pending:
        return Icons.schedule;
      case AiAnalysisJobState.running:
        return Icons.sync;
      case AiAnalysisJobState.incomplete:
        return Icons.pause_circle_outline;
      case AiAnalysisJobState.failed:
        return Icons.error_outline;
      case AiAnalysisJobState.completed:
        return Icons.check_circle_outline;
    }
  }

  String _stageLogLine(AiAnalysisStageLog log) {
    final parts = [
      log.stage.name,
      log.message,
      if (log.outputSummary.isNotEmpty) log.outputSummary,
      if (log.error?.isNotEmpty ?? false) 'error=${log.error}',
      'retry=${log.retryCount}',
    ];
    return parts.join(' | ');
  }

  String _stageLogExportLine(AiAnalysisStageLog log) {
    final parts = [
      '- ${log.startedAt.toIso8601String()} ${log.stage.name}',
      log.message,
      if (log.inputSummary.isNotEmpty) 'input=${log.inputSummary}',
      if (log.outputSummary.isNotEmpty) 'output=${log.outputSummary}',
      if (log.error?.isNotEmpty ?? false) 'error=${log.error}',
      'retry=${log.retryCount}',
    ];
    return parts.join(' | ');
  }
}

class _DebugSection extends StatelessWidget {
  const _DebugSection({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final visibleLines =
        lines.map((line) => line.trim()).where((line) => line.isNotEmpty);
    if (visibleLines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final line in visibleLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText(line),
            ),
        ],
      ),
    );
  }
}

class _JobArtifacts {
  const _JobArtifacts({
    required this.summary,
    required this.brief,
    required this.summaryMeta,
    required this.segmentCount,
    required this.firstSegment,
    required this.embeddingCount,
    required this.embeddingModel,
    required this.embeddingTypes,
    required this.embeddingLines,
    required this.contextSummary,
    required this.promptSummary,
    required this.promptPreview,
    required this.systemPrompt,
    required this.userPrompt,
    required this.claimSummary,
    required this.claimLines,
    required this.updateCandidateSummary,
    required this.updateCandidateLines,
    required this.feedback,
    required this.memoryLifecycle,
    required this.retrievalCount,
    required this.calendarCount,
    required this.retrievalLines,
  });

  final EntrySummary? summary;
  final String brief;
  final String summaryMeta;
  final int segmentCount;
  final String firstSegment;
  final int embeddingCount;
  final String embeddingModel;
  final String embeddingTypes;
  final List<String> embeddingLines;
  final String contextSummary;
  final String promptSummary;
  final String promptPreview;
  final String systemPrompt;
  final String userPrompt;
  final String claimSummary;
  final List<String> claimLines;
  final String updateCandidateSummary;
  final List<String> updateCandidateLines;
  final String feedback;
  final String memoryLifecycle;
  final int retrievalCount;
  final int calendarCount;
  final List<String> retrievalLines;

  bool get hasSummary => summary != null;

  List<String> get summaryPackageLines {
    final value = summary;
    if (value == null) return const [];
    return [
      if (value.keyPoints.isNotEmpty)
        'summary keyPoints: ${value.keyPoints.join('；')}',
      if (value.importantQuotes.isNotEmpty)
        'summary quotes: ${value.importantQuotes.join('；')}',
      if (value.topics.isNotEmpty) 'summary topics: ${value.topics.join('、')}',
      if (value.people.isNotEmpty) 'summary people: ${value.people.join('、')}',
      if (value.places.isNotEmpty) 'summary places: ${value.places.join('、')}',
    ];
  }

  static Future<_JobArtifacts> load(String entryId) async {
    const summaryRepository = EntrySummaryRepository();
    const embeddingRepository = AiEmbeddingRepository();
    const feedbackRepository = AiFeedbackRepository();
    const traceRepository = AiRetrievalTraceRepository();
    const promptTraceRepository = AiPromptTraceRepository();
    const memoryRepository = MemoryRepository();
    const insightRepository = InsightRepository();
    final summary = await summaryRepository.getSummary(entryId);
    final segments = await summaryRepository.listSegments(entryId);
    final embeddings = await embeddingRepository.listForEntry(entryId);
    final trace = await traceRepository.getTrace(entryId);
    final promptTrace = await promptTraceRepository.getTrace(entryId);
    final feedback = await feedbackRepository.getFeedback(entryId);
    final insight = await insightRepository.getInsight(entryId);
    final memories = await memoryRepository.listMemories();
    final sourceMemory = memories
        .where((memory) => memory.allSourceEntryIds.contains(entryId))
        .firstOrNull;
    final typeCounts = <String, int>{};
    for (final embedding in embeddings) {
      typeCounts[embedding.sourceType.name] =
          (typeCounts[embedding.sourceType.name] ?? 0) + 1;
    }
    return _JobArtifacts(
      summary: summary,
      brief: summary?.brief ?? '未生成',
      segmentCount: segments.length,
      firstSegment: segments.isEmpty ? '' : segments.first.summary,
      embeddingCount: embeddings.length,
      embeddingModel: embeddings.isEmpty
          ? '未生成'
          : '${embeddings.first.modelId}/${embeddings.first.modelVersion}/${embeddings.first.dimensions}d',
      embeddingTypes: typeCounts.entries
          .map((entry) => '${entry.key}:${entry.value}')
          .join(', '),
      embeddingLines: [
        for (final embedding in embeddings)
          '${embedding.sourceType.name}:${embedding.sourceId} entry=${embedding.entryId} '
              '${embedding.dimensions}d hash=${embedding.textHash} '
              'generatedAt=${embedding.generatedAt.toIso8601String()}',
      ],
      contextSummary: trace?.contextSummary ??
          (trace?.scenario == null
              ? ''
              : '${trace!.scenario} sources=${trace.sourceCount}'),
      promptSummary: promptTrace == null
          ? ''
          : '${promptTrace.scenario} system=${promptTrace.systemPromptLength} user=${promptTrace.userPromptLength}',
      promptPreview: promptTrace?.userPromptPreview ?? '',
      systemPrompt:
          promptTrace?.systemPrompt ?? promptTrace?.systemPromptPreview ?? '',
      userPrompt:
          promptTrace?.userPrompt ?? promptTrace?.userPromptPreview ?? '',
      claimSummary: insight == null
          ? ''
          : 'facts=${insight.facts.length} signals=${insight.signals.length} hypotheses=${insight.hypotheses.length} suggestions=${insight.suggestions.length}',
      claimLines: [
        for (final item in insight?.facts ?? []) 'fact: ${item.text}',
        for (final item in insight?.signals ?? []) 'signal: ${item.text}',
        for (final item in insight?.hypotheses ?? [])
          'hypothesis: ${item.text}',
        for (final item in insight?.suggestions ?? [])
          'suggestion: ${item.text}',
      ],
      updateCandidateSummary: insight == null
          ? ''
          : 'profile=${insight.profileUpdateCandidates.length} relationship=${insight.relationshipUpdates.length} contradictions=${insight.contradictions.length}',
      updateCandidateLines: [
        for (final item in insight?.profileUpdateCandidates ?? [])
          'profile: ${item.field}=${item.value} confidence=${item.confidence ?? ''}',
        for (final item in insight?.relationshipUpdates ?? [])
          'relationship: ${item.personName} ${item.summary} confidence=${item.confidence ?? ''}',
        for (final item in insight?.contradictions ?? [])
          'contradiction: ${item.oldMemoryId} ${item.newEvidence} ${item.interpretation} confidence=${item.confidence ?? ''}',
      ],
      feedback: feedback == null
          ? ''
          : [
              feedback.value.name,
              feedback.createdAt.toIso8601String(),
              if (feedback.note?.isNotEmpty ?? false) feedback.note!,
            ].join(' '),
      memoryLifecycle: sourceMemory == null
          ? ''
          : [
              'importance=${sourceMemory.importance.toStringAsFixed(2)}',
              'confidence=${sourceMemory.confidence.toStringAsFixed(2)}',
              'referenceCount=${sourceMemory.referenceCount}',
              'decay=${sourceMemory.decay.toStringAsFixed(2)}',
              'archived=${sourceMemory.archived}',
              'lastReferencedAt=${sourceMemory.lastReferencedAt.toIso8601String()}',
            ].join(' '),
      retrievalCount: trace?.items.length ?? 0,
      calendarCount: (trace?.items ?? const [])
          .where((item) => item.sourceType == 'calendar')
          .length,
      retrievalLines: [
        for (final item in trace?.items ?? [])
          '${item.sourceType}:${item.sourceId} score=${item.score} ${item.title} ${item.reasons.join('；')}${item.matchedTokens.isEmpty ? '' : ' tokens=${item.matchedTokens.join(',')}'}',
      ],
      summaryMeta: summary == null
          ? ''
          : [
              if (summary.title.isNotEmpty) 'title=${summary.title}',
              'date=${summary.date.toIso8601String()}',
              if (summary.emotion.isNotEmpty) 'emotion=${summary.emotion}',
              'importance=${summary.importance.toStringAsFixed(2)}',
              'generator=${summary.generator}',
            ].join(' '),
    );
  }

  String toDebugText() {
    final sections = <String>[
      _section('Context', [
        contextSummary,
        if (summaryMeta.isNotEmpty) 'summary meta: $summaryMeta',
        'summary: $brief',
        ...summaryPackageLines,
        'segments: $segmentCount',
        'embeddings: $embeddingCount $embeddingModel',
        if (embeddingTypes.isNotEmpty) 'embedding types: $embeddingTypes',
        ...embeddingLines,
      ]),
      _section('Prompt', [
        promptSummary,
        if (systemPrompt.isNotEmpty) 'SYSTEM:\n$systemPrompt',
        if (userPrompt.isNotEmpty) 'USER:\n$userPrompt',
        if (systemPrompt.isEmpty && promptPreview.isNotEmpty) promptPreview,
      ]),
      _section('Claims', [claimSummary, ...claimLines]),
      _section('Update Candidates',
          [updateCandidateSummary, ...updateCandidateLines]),
      _section('Retrieval', [
        'retrieval=$retrievalCount calendar=$calendarCount',
        ...retrievalLines,
      ]),
      _section('Memory And Feedback', [memoryLifecycle, feedback]),
    ];
    return sections.where((section) => section.trim().isNotEmpty).join('\n\n');
  }

  String _section(String title, List<String> lines) {
    final visible =
        lines.map((line) => line.trim()).where((line) => line.isNotEmpty);
    if (visible.isEmpty) return '';
    return ['## $title', ...visible].join('\n');
  }
}

class _RecentRetrievalTraces {
  const _RecentRetrievalTraces({required this.items});

  final List<_RecentRetrievalTraceItem> items;

  static Future<_RecentRetrievalTraces> load() async {
    const repository = AiRetrievalTraceRepository();
    final traces = <AiRetrievalTrace?>[
      await repository.getTrace('search:last'),
      await repository.getTrace('question:last'),
      await repository.getTrace('period:last'),
    ].whereType<AiRetrievalTrace>().toList()
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    return _RecentRetrievalTraces(
      items: traces.map(_RecentRetrievalTraceItem.fromTrace).toList(),
    );
  }

  String toDebugText() {
    return [
      '## Recent Retrieval Traces',
      for (final item in items) ...[
        '',
        '### ${item.label}',
        item.summary,
        ...item.lines,
      ],
    ].join('\n');
  }
}

class _RecentRetrievalTraceItem {
  const _RecentRetrievalTraceItem({
    required this.label,
    required this.summary,
    required this.lines,
  });

  final String label;
  final String summary;
  final List<String> lines;

  static _RecentRetrievalTraceItem fromTrace(AiRetrievalTrace trace) {
    final scenario = trace.scenario ?? '';
    final label = switch (scenario) {
      'search' => '搜索',
      'question' => '问答',
      'periodSummary' => '周期总结',
      _ => scenario.isEmpty ? '检索' : scenario,
    };
    final context = (trace.contextSummary?.toString() ?? '').trim();
    final summary = [
      if (context.isNotEmpty) context else 'sources=${trace.sourceCount}',
      trace.generatedAt.toIso8601String(),
    ].join(' | ');
    return _RecentRetrievalTraceItem(
      label: label,
      summary: summary,
      lines: [
        for (final item in trace.items)
          '${item.sourceType}:${item.sourceId} score=${item.score} '
              '${item.title} ${item.reasons.join('；')}'
              '${item.matchedTokens.isEmpty ? '' : ' tokens=${item.matchedTokens.join(',')}'}',
      ],
    );
  }
}

class _RecentPeriodSummaries {
  const _RecentPeriodSummaries({required this.items});

  final List<_RecentPeriodSummaryItem> items;

  static Future<_RecentPeriodSummaries> load() async {
    const repository = PeriodSummaryRepository();
    final summaries = await repository.listSummaries();
    return _RecentPeriodSummaries(
      items:
          summaries.take(3).map(_RecentPeriodSummaryItem.fromSummary).toList(),
    );
  }

  String toDebugText() {
    return [
      '## Recent Period Summaries',
      for (final item in items) ...[
        '',
        '### ${item.label}',
        item.brief,
        ...item.lines,
      ],
    ].join('\n');
  }
}

class _RecentPeriodSummaryItem {
  const _RecentPeriodSummaryItem({
    required this.label,
    required this.brief,
    required this.lines,
  });

  final String label;
  final String brief;
  final List<String> lines;

  static _RecentPeriodSummaryItem fromSummary(PeriodSummary summary) {
    final label = summary.type == PeriodSummaryType.month
        ? '月度总结 ${summary.startDate.year}-${summary.startDate.month.toString().padLeft(2, '0')}'
        : '年度总结 ${summary.startDate.year}';
    return _RecentPeriodSummaryItem(
      label: label,
      brief: [
        '${summary.entryCount}篇',
        'generatedAt=${summary.generatedAt.toIso8601String()}',
        'generator=${summary.generator}',
      ].join(' | '),
      lines: [
        if (summary.contextDebugSummary.isNotEmpty)
          'context=${summary.contextDebugSummary}',
        if (summary.themes.isNotEmpty) 'themes=${summary.themes.join('、')}',
        if (summary.emotions.isNotEmpty)
          'emotions=${summary.emotions.join('、')}',
        if (summary.representativeEntryIds.isNotEmpty)
          'representative=${summary.representativeEntryIds.join(',')}',
        for (final line in summary.relationshipHighlights.take(2))
          'relationship=$line',
        for (final line in summary.stoneHighlights.take(2)) 'stone=$line',
      ],
    );
  }
}

class _SummaryCorrectionDialog extends StatefulWidget {
  const _SummaryCorrectionDialog({required this.summary});

  final EntrySummary summary;

  @override
  State<_SummaryCorrectionDialog> createState() =>
      _SummaryCorrectionDialogState();
}

class _SummaryCorrectionDialogState extends State<_SummaryCorrectionDialog> {
  late final TextEditingController _briefController =
      TextEditingController(text: widget.summary.brief);
  late final TextEditingController _titleController =
      TextEditingController(text: widget.summary.title);
  late final TextEditingController _emotionController =
      TextEditingController(text: widget.summary.emotion);
  late final TextEditingController _importanceController =
      TextEditingController(text: widget.summary.importance.toStringAsFixed(2));
  late final TextEditingController _keyPointsController =
      TextEditingController(text: widget.summary.keyPoints.join('\n'));
  late final TextEditingController _quotesController =
      TextEditingController(text: widget.summary.importantQuotes.join('\n'));

  @override
  void dispose() {
    _briefController.dispose();
    _titleController.dispose();
    _emotionController.dispose();
    _importanceController.dispose();
    _keyPointsController.dispose();
    _quotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修正摘要'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _briefController,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '更准确的日记摘要',
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '摘要标题'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _emotionController,
                      decoration: const InputDecoration(labelText: '情绪'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _importanceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '重要度 0-1'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _keyPointsController,
                minLines: 3,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: '关键点（每行一条）',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _quotesController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '重要原文短句（每行一条）',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _briefController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_SummaryCorrectionResult(
                    brief: _briefController.text.trim(),
                    title: _titleController.text.trim(),
                    emotion: _emotionController.text.trim(),
                    importance: _importance(),
                    keyPoints: _lines(_keyPointsController.text),
                    importantQuotes: _lines(_quotesController.text),
                  )),
          child: const Text('保存'),
        ),
      ],
    );
  }

  List<String> _lines(String value) {
    return value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  double _importance() {
    final parsed = double.tryParse(_importanceController.text.trim());
    return (parsed ?? widget.summary.importance).clamp(0, 1).toDouble();
  }
}

class _SummaryCorrectionResult {
  const _SummaryCorrectionResult({
    required this.brief,
    required this.title,
    required this.emotion,
    required this.importance,
    required this.keyPoints,
    required this.importantQuotes,
  });

  final String brief;
  final String title;
  final String emotion;
  final double importance;
  final List<String> keyPoints;
  final List<String> importantQuotes;
}

class _DebugLine extends StatelessWidget {
  const _DebugLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SelectableText('$label: $value'),
    );
  }
}
