import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_routes.dart';
import '../../../data/models/diary_entry.dart';
import '../../../data/repositories/diary_change_bus.dart';
import '../../../data/repositories/diary_repository.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.onDiaryChanged});

  final VoidCallback? onDiaryChanged;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final repository = const DiaryRepository();
  late Future<List<DiaryEntry>> _entriesFuture =
      repository.getEntriesForDate(DateTime.now());

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
    await Navigator.of(context)
        .pushNamed(AppRoutes.diaryEditPath(entryId), arguments: entryId);
    if (mounted) {
      setState(() {
        _entriesFuture = repository.getEntriesForDate(DateTime.now());
      });
      widget.onDiaryChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DiaryEntry>>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? [];
        final String? diaryInsight = null;
        final String? advice = null;

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
              if (diaryInsight != null) ...[
                const SizedBox(height: 16),
                _InsightCard(text: diaryInsight),
              ],
              if (advice != null) ...[
                const SizedBox(height: 16),
                _AdviceCard(text: advice),
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

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('今日日记分析',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(text),
        ],
      ),
    );
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('给我的建议',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(text),
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
