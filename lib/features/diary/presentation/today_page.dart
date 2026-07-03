import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/ai_analysis_job.dart';
import '../../../data/models/diary_analysis_status.dart';
import '../../../data/models/diary_entry.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/repositories/ai_analysis_queue_bus.dart';
import '../../../data/repositories/ai_analysis_queue_repository.dart';
import '../../../data/repositories/diary_change_bus.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/services/ai_analysis_queue_runner.dart';
import '../../ai_insight/presentation/ai_feedback_bar.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.onDiaryChanged});

  final VoidCallback? onDiaryChanged;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final repository = const DiaryRepository();
  final insightRepository = const InsightRepository();
  final queueRepository = const AiAnalysisQueueRepository();
  final queueRunner = const AiAnalysisQueueRunner();
  late Future<List<DiaryEntry>> _entriesFuture =
      repository.getEntriesForDate(DateTime.now());
  late Future<AiAnalysisQueueSnapshot> _queueSnapshotFuture =
      queueRepository.snapshot();

  @override
  void initState() {
    super.initState();
    DiaryChangeBus.version.addListener(_refreshEntries);
    AiAnalysisQueueBus.version.addListener(_refreshQueue);
    unawaited(_runQueuedAnalysis());
  }

  @override
  void dispose() {
    DiaryChangeBus.version.removeListener(_refreshEntries);
    AiAnalysisQueueBus.version.removeListener(_refreshQueue);
    super.dispose();
  }

  void _refreshEntries() {
    if (!mounted) return;
    setState(() {
      _entriesFuture = repository.getEntriesForDate(DateTime.now());
    });
  }

  void _refreshQueue() {
    if (!mounted) return;
    setState(() {
      _queueSnapshotFuture = queueRepository.snapshot();
    });
  }

  Future<void> _openEditor([String? entryId]) async {
    final result = await Navigator.of(context)
        .pushNamed(AppRoutes.diaryEditPath(entryId), arguments: entryId);
    if (!mounted) return;
    setState(() {
      _entriesFuture = repository.getEntriesForDate(DateTime.now());
    });
    widget.onDiaryChanged?.call();
    if (result is DiaryEntry) {
      unawaited(_enqueueAnalysis(result));
    }
  }

  Future<void> _enqueueAnalysis(DiaryEntry entry) async {
    await queueRunner.enqueue(entry, start: false);
    await _runQueuedAnalysis();
  }

  Future<void> _runQueuedAnalysis() async {
    await queueRunner.processNext();
    if (!mounted) return;
    setState(() {
      _entriesFuture = repository.getEntriesForDate(DateTime.now());
      _queueSnapshotFuture = queueRepository.snapshot();
    });
  }

  Future<void> _retryQueue() async {
    await _runQueuedAnalysis();
  }

  Future<_AnalysisData> _loadAnalysisData(DiaryEntry entry) async {
    final status = await insightRepository.getStatus(entry.id);
    final insight = await insightRepository.getInsight(entry.id);
    return _AnalysisData(status: status, insight: insight);
  }

  Widget _buildQueueCard() {
    return FutureBuilder<AiAnalysisQueueSnapshot>(
      future: _queueSnapshotFuture,
      builder: (context, snapshot) {
        final queue = snapshot.data;
        if (queue == null || !queue.hasVisibleWork) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _AiQueueCard(
            snapshot: queue,
            onRetry: _retryQueue,
          ),
        );
      },
    );
  }

  Widget _buildAnalysisCard(DiaryEntry entry) {
    return FutureBuilder<_AnalysisData>(
      future: _loadAnalysisData(entry),
      builder: (context, snapshot) {
        return _TodayAnalysisCard(
          entry: entry,
          data: snapshot.data,
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant TodayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) {
      unawaited(_runQueuedAnalysis());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DiaryEntry>>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? [];
        final latestEntry = entries.isEmpty ? null : entries.first;

        return Scaffold(
          appBar: AppBar(
            title: _TodayTitle(date: DateTime.now()),
            actions: [
              IconButton(
                tooltip: '搜索',
                onPressed: () {},
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openEditor(),
            child: const Icon(Icons.add),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildQueueCard(),
              if (entries.isEmpty)
                _NewDiaryCard(onTap: () => _openEditor())
              else
                for (final entry in entries) ...[
                  _DiaryPreviewCard(
                    entry: entry,
                    onTap: () => _openEditor(entry.id),
                  ),
                  const SizedBox(height: 10),
                ],
              if (latestEntry != null) ...[
                const SizedBox(height: 16),
                _buildAnalysisCard(latestEntry),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AnalysisData {
  const _AnalysisData({required this.status, required this.insight});

  final DiaryAnalysisStatus? status;
  final DiaryInsight? insight;
}

class _TodayTitle extends StatelessWidget {
  const _TodayTitle({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final title = '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        const SizedBox(height: 2),
        Text('🌧 小雨 · 18°', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _NewDiaryCard extends StatelessWidget {
  const _NewDiaryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      onTap: onTap,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('写日记',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          SizedBox(height: 10),
          Text('写几句话就好，不用完整，也不用漂亮。'),
          SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _DiaryPreviewCard extends StatelessWidget {
  const _DiaryPreviewCard({required this.entry, required this.onTap});

  final DiaryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.title != null) ...[
            Text(entry.title!,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
          ],
          Text(
            entry.bodyPreview,
            maxLines: AppConstants.diaryPreviewMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _AiQueueCard extends StatelessWidget {
  const _AiQueueCard({
    required this.snapshot,
    required this.onRetry,
  });

  final AiAnalysisQueueSnapshot snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final job = snapshot.currentJob;
    final theme = Theme.of(context);
    final hasRunning = job?.state == AiAnalysisJobState.running;
    final hasFailed = snapshot.failedCount > 0 && !hasRunning;
    final isResuming = job?.state == AiAnalysisJobState.incomplete;
    final title = hasFailed
        ? '有日记整理失败'
        : isResuming
            ? '继续整理记忆'
            : '正在整理记忆';
    final stage = job?.stageLabel ?? '等待继续';
    final waiting = snapshot.waitingCount;
    final totalActive = snapshot.runnableCount +
        (job?.state == AiAnalysisJobState.running ? 1 : 0);
    final batchProgress = job == null || totalActive <= 0
        ? ''
        : '正在整理 ${snapshot.activeOrdinal}/$totalActive 篇';
    final progress =
        job == null ? 0.0 : (job.completedStages.length / 7).clamp(0.0, 1.0);

    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasFailed
                    ? Icons.error_outline
                    : Icons.auto_awesome_motion_outlined,
                color: hasFailed
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              if (hasFailed)
                TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
          const SizedBox(height: 10),
          if (job != null) ...[
            LinearProgressIndicator(value: progress, minHeight: 3),
            const SizedBox(height: 10),
          ],
          if (batchProgress.isNotEmpty) ...[
            Text(batchProgress, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
          ],
          Text(isResuming ? '上次整理被中断，将从已完成阶段继续：$stage' : stage),
          if (job != null && job.completedStages.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '已完成 ${job.completedStages.length}/7 个阶段',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (snapshot.incompleteCount > 0 && !isResuming) ...[
            const SizedBox(height: 4),
            Text('有 ${snapshot.incompleteCount} 篇会从中断处恢复。',
                style: theme.textTheme.bodySmall),
          ],
          if (waiting > 0) ...[
            const SizedBox(height: 4),
            Text('还有 $waiting 篇等待后台串行继续。', style: theme.textTheme.bodySmall),
          ],
          if (job?.lastError != null && job!.lastError!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(job.lastError!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _TodayAnalysisCard extends StatelessWidget {
  const _TodayAnalysisCard({
    required this.entry,
    required this.data,
  });

  final DiaryEntry entry;
  final _AnalysisData? data;

  @override
  Widget build(BuildContext context) {
    final status = data?.status;
    final insight = data?.insight;
    if (status?.state == DiaryAnalysisState.queued ||
        status?.state == DiaryAnalysisState.analyzing ||
        status?.state == DiaryAnalysisState.incomplete) {
      return _AnalysisLoadingCard(message: status?.message);
    }
    if (status?.state == DiaryAnalysisState.failed) {
      return _AnalysisErrorCard(message: status?.message ?? '分析失败');
    }
    if (insight == null) return const _AnalysisEmptyCard();
    return _AnalysisResultCard(insight: insight);
  }
}

class _AnalysisEmptyCard extends StatelessWidget {
  const _AnalysisEmptyCard();

  @override
  Widget build(BuildContext context) {
    return const _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日日记分析',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          SizedBox(height: 10),
          Text('还没有分析结果。退出编辑页后，会开始结合今天日记和历史经历生成分析。'),
        ],
      ),
    );
  }
}

class _AnalysisErrorCard extends StatelessWidget {
  const _AnalysisErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('分析失败',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(message),
        ],
      ),
    );
  }
}

class _AnalysisLoadingCard extends StatefulWidget {
  const _AnalysisLoadingCard({this.message});

  final String? message;

  @override
  State<_AnalysisLoadingCard> createState() => _AnalysisLoadingCardState();
}

class _AnalysisLoadingCardState extends State<_AnalysisLoadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final opacity = 0.45 + _controller.value * 0.35;
          return Opacity(
            opacity: opacity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('正在分析今天',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(widget.message ?? '正在结合今天的日记和曾经的经历，生成分析和建议。'),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AnalysisResultCard extends StatelessWidget {
  const _AnalysisResultCard({required this.insight});

  final DiaryInsight insight;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('今日日记分析',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (insight.reflection.isNotEmpty)
            SimpleMarkdownText(text: insight.reflection),
          if (insight.relatedMemories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('和过去的关联', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final memory in insight.relatedMemories.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                    '· ${memory.title}${memory.reason.isEmpty ? '' : '：${memory.reason}'}'),
              ),
          ],
          if (insight.stoneTitle.isNotEmpty ||
              insight.stoneDescription.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('给我的建议', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (insight.stoneTitle.isNotEmpty)
              Text(insight.stoneTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            if (insight.stoneDescription.isNotEmpty)
              SimpleMarkdownText(text: insight.stoneDescription),
          ],
          const SizedBox(height: 12),
          AiFeedbackBar(entryId: insight.entryId),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      ),
    );
  }
}
