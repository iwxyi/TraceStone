import 'package:flutter/material.dart';

import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/repositories/insight_repository.dart';
import 'ai_feedback_bar.dart';

class InsightPage extends StatefulWidget {
  const InsightPage({super.key});

  @override
  State<InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends State<InsightPage> {
  final _repository = const InsightRepository();
  late Future<DiaryInsight?> _insightFuture = _repository.getLatestInsight();

  Future<void> _refresh() async {
    setState(() => _insightFuture = _repository.getLatestInsight());
    await _insightFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日洞察')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<DiaryInsight?>(
          future: _insightFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final insight = snapshot.data;
            if (insight == null) return const _EmptyInsight();
            return _InsightBody(insight: insight);
          },
        ),
      ),
    );
  }
}

class _InsightBody extends StatelessWidget {
  const _InsightBody({required this.insight});

  final DiaryInsight insight;

  @override
  Widget build(BuildContext context) {
    final meta = [
      _dateLabel(insight.entryDate),
      if (insight.emotion.isNotEmpty) insight.emotion,
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('今日洞察包', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(meta, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        _SectionCard(
          title: '读后感',
          icon: Icons.auto_awesome_outlined,
          child: SimpleMarkdownText(
            text: insight.reflection,
            emptyText: '洞察生成中。',
          ),
        ),
        if (insight.relatedMemories.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: '它和过去有关',
            icon: Icons.history_edu_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final memory in insight.relatedMemories) ...[
                  Text(memory.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (memory.reason.isNotEmpty) Text(memory.reason),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
        if (insight.stoneTitle.isNotEmpty ||
            insight.stoneDescription.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: '塑石建议',
            icon: Icons.self_improvement_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (insight.stoneTitle.isNotEmpty)
                  Text(insight.stoneTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                if (insight.stoneDescription.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SimpleMarkdownText(text: insight.stoneDescription),
                ],
              ],
            ),
          ),
        ],
        if (insight.keywords.isNotEmpty || insight.people.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: '记忆标签',
            icon: Icons.local_offer_outlined,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in [...insight.keywords, ...insight.people])
                  Chip(label: Text(item)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _SectionCard(
          title: '反馈',
          icon: Icons.rate_review_outlined,
          child: AiFeedbackBar(entryId: insight.entryId),
        ),
      ],
    );
  }

  String _dateLabel(DateTime date) => '${date.year}年${date.month}月${date.day}日';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyInsight extends StatelessWidget {
  const _EmptyInsight();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.auto_awesome_outlined, size: 48),
        SizedBox(height: 16),
        Text(
          '写完并保存日记后，后台会结合今天内容和历史记忆生成洞察。',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
