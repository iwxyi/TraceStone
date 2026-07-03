import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/ai_analysis_job.dart';
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
import '../../../data/services/ai_analysis_queue_runner.dart';

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

class _CompanionTraceCard extends StatelessWidget {
  const _CompanionTraceCard();

  @override
  Widget build(BuildContext context) {
    const repository = AiPromptTraceRepository();
    return FutureBuilder(
      future: repository.getTrace('companion:last'),
      builder: (context, snapshot) {
        final trace = snapshot.data;
        if (trace == null) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('最近陪伴问答',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
                        'summary: ${artifacts.brief}',
                        'segments: ${artifacts.segmentCount}',
                        'embeddings: ${artifacts.embeddingCount} ${artifacts.embeddingModel}',
                        if (artifacts.embeddingTypes.isNotEmpty)
                          'embedding types: ${artifacts.embeddingTypes}',
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
    final allowed = await showDialog<bool>(
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
    if (allowed != true) return;
    final text = artifacts.toDebugText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制调试上下文')),
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
    required this.brief,
    required this.segmentCount,
    required this.firstSegment,
    required this.embeddingCount,
    required this.embeddingModel,
    required this.embeddingTypes,
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

  final String brief;
  final int segmentCount;
  final String firstSegment;
  final int embeddingCount;
  final String embeddingModel;
  final String embeddingTypes;
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
    );
  }

  String toDebugText() {
    final sections = <String>[
      _section('Context', [
        contextSummary,
        'summary: $brief',
        'segments: $segmentCount',
        'embeddings: $embeddingCount $embeddingModel',
        if (embeddingTypes.isNotEmpty) 'embedding types: $embeddingTypes',
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
