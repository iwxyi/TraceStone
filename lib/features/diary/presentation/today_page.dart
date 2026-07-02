import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_routes.dart';
import '../../../data/models/diary_entry.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/repositories/diary_change_bus.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/services/diary_analysis_service.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.onDiaryChanged});

  final VoidCallback? onDiaryChanged;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final repository = const DiaryRepository();
  final insightRepository = const InsightRepository();
  final analysisService = const DiaryAnalysisService();
  late Future<List<DiaryEntry>> _entriesFuture =
      repository.getEntriesForDate(DateTime.now());
  String? _analyzingEntryId;
  String? _analysisError;

  @override
  void initState() {
    super.initState();
    DiaryChangeBus.version.addListener(_refreshEntries);
  }

  @override
  void dispose() {
    DiaryChangeBus.version.removeListener(_refreshEntries);
    super.dispose();
  }

  void _refreshEntries() {
    if (!mounted) return;
    setState(() {
      _entriesFuture = repository.getEntriesForDate(DateTime.now());
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
      _analyzeEntry(result);
    }
  }

  Future<void> _analyzeEntry(DiaryEntry entry) async {
    setState(() {
      _analyzingEntryId = entry.id;
      _analysisError = null;
    });
    try {
      await analysisService.analyzeEntry(entry);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _analysisError = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _analyzingEntryId = null;
          _entriesFuture = repository.getEntriesForDate(DateTime.now());
        });
      }
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
                _TodayAnalysisCard(
                  entry: latestEntry,
                  insightRepository: insightRepository,
                  isAnalyzing: _analyzingEntryId == latestEntry.id,
                  error: _analysisError,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
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

class _TodayAnalysisCard extends StatelessWidget {
  const _TodayAnalysisCard({
    required this.entry,
    required this.insightRepository,
    required this.isAnalyzing,
    required this.error,
  });

  final DiaryEntry entry;
  final InsightRepository insightRepository;
  final bool isAnalyzing;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (isAnalyzing) return const _AnalysisLoadingCard();
    if (error != null) return _AnalysisErrorCard(message: error!);
    return FutureBuilder<DiaryInsight?>(
      future: insightRepository.getInsight(entry.id),
      builder: (context, snapshot) {
        final insight = snapshot.data;
        if (insight == null) return const _AnalysisEmptyCard();
        return _AnalysisResultCard(insight: insight);
      },
    );
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
  const _AnalysisLoadingCard();

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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                SizedBox(height: 10),
                Text('正在结合今天的日记和曾经的经历，生成分析和建议。'),
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
          if (insight.reflection.isNotEmpty) Text(insight.reflection),
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
              Text(insight.stoneDescription),
          ],
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
