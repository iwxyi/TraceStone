import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/ai_analysis_job.dart';
import '../../../data/repositories/ai_analysis_queue_bus.dart';
import '../../../data/repositories/ai_analysis_queue_repository.dart';
import '../../../data/repositories/ai_embedding_repository.dart';
import '../../../data/repositories/ai_feedback_repository.dart';
import '../../../data/repositories/ai_prompt_trace_repository.dart';
import '../../../data/repositories/ai_retrieval_trace_repository.dart';
import '../../../data/repositories/entry_summary_repository.dart';
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
              _QueueSummaryCard(queue: queue, onContinue: _continueQueue),
              const SizedBox(height: 16),
              const _CompanionTraceCard(),
              const SizedBox(height: 16),
              if (queue.jobs.isEmpty)
                const Center(child: Text('暂无 AI 队列任务'))
              else
                for (final job in queue.jobs) ...[
                  _JobCard(job: job),
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
  });

  final AiAnalysisQueueSnapshot queue;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    final running = queue.jobs
        .where((job) => job.state == AiAnalysisJobState.running)
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
                _StatusChip(label: '失败', count: queue.failedCount),
                _StatusChip(label: '完成', count: completed),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: queue.pendingCount > 0 || queue.failedCount > 0
                  ? onContinue
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('继续队列'),
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
  const _JobCard({required this.job});

  final AiAnalysisJob job;

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
                if (artifacts != null) ...[
                  const Divider(height: 20),
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
                  if (artifacts.feedback.isNotEmpty)
                    _DebugLine(label: 'feedback', value: artifacts.feedback),
                  _DebugLine(
                      label: 'retrieval.sources',
                      value: '${artifacts.retrievalCount}'),
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
    required this.feedback,
    required this.retrievalCount,
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
  final String feedback;
  final int retrievalCount;
  final List<String> retrievalLines;

  static Future<_JobArtifacts> load(String entryId) async {
    const summaryRepository = EntrySummaryRepository();
    const embeddingRepository = AiEmbeddingRepository();
    const feedbackRepository = AiFeedbackRepository();
    const traceRepository = AiRetrievalTraceRepository();
    const promptTraceRepository = AiPromptTraceRepository();
    final summary = await summaryRepository.getSummary(entryId);
    final segments = await summaryRepository.listSegments(entryId);
    final embeddings = await embeddingRepository.listForEntry(entryId);
    final trace = await traceRepository.getTrace(entryId);
    final promptTrace = await promptTraceRepository.getTrace(entryId);
    final feedback = await feedbackRepository.getFeedback(entryId);
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
      feedback: feedback == null
          ? ''
          : [
              feedback.value.name,
              feedback.createdAt.toIso8601String(),
              if (feedback.note?.isNotEmpty ?? false) feedback.note!,
            ].join(' '),
      retrievalCount: trace?.items.length ?? 0,
      retrievalLines: [
        for (final item in trace?.items ?? [])
          '${item.sourceType}:${item.sourceId} score=${item.score} ${item.title} ${item.reasons.join('；')}',
      ],
    );
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
