import 'package:flutter/material.dart';

import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import 'ai_feedback_bar.dart';

class InsightPage extends StatefulWidget {
  const InsightPage({super.key});

  @override
  State<InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends State<InsightPage> {
  final _repository = const InsightRepository();
  final _developerSettings = const DeveloperSettingsRepository();
  late Future<DiaryInsight?> _insightFuture = _repository.getLatestInsight();
  late final Future<bool> _developerModeFuture =
      _developerSettings.isDeveloperModeEnabled();

  Future<void> _refresh() async {
    setState(() {
      _insightFuture = _repository.getLatestInsight();
    });
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
            return FutureBuilder<bool>(
              future: _developerModeFuture,
              builder: (context, developerSnapshot) {
                return _InsightBody(
                  insight: insight,
                  developerMode: developerSnapshot.data ?? false,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _InsightBody extends StatelessWidget {
  const _InsightBody({
    required this.insight,
    required this.developerMode,
  });

  final DiaryInsight insight;
  final bool developerMode;

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
        if (insight.facts.isNotEmpty ||
            insight.signals.isNotEmpty ||
            insight.hypotheses.isNotEmpty ||
            insight.suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: '结论分层',
            icon: Icons.account_tree_outlined,
            child: Column(
              children: [
                _ClaimGroup(
                  title: '事实',
                  claims: insight.facts,
                  developerMode: developerMode,
                ),
                _ClaimGroup(
                  title: '信号',
                  claims: insight.signals,
                  developerMode: developerMode,
                ),
                _ClaimGroup(
                  title: '可能性',
                  claims: insight.hypotheses,
                  developerMode: developerMode,
                ),
                _ClaimGroup(
                  title: '建议',
                  claims: insight.suggestions,
                  developerMode: developerMode,
                ),
              ],
            ),
          ),
        ],
        if (developerMode &&
            (insight.profileUpdateCandidates.isNotEmpty ||
                insight.relationshipUpdates.isNotEmpty ||
                insight.contradictions.isNotEmpty)) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: '更新候选',
            icon: Icons.tune_outlined,
            child: _UpdateCandidateList(insight: insight),
          ),
        ],
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

class _UpdateCandidateList extends StatelessWidget {
  const _UpdateCandidateList({required this.insight});

  final DiaryInsight insight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CandidateGroup(
          title: '画像候选',
          lines: [
            for (final candidate in insight.profileUpdateCandidates)
              '${candidate.field}：${candidate.value}${_confidence(candidate.confidence)}',
          ],
        ),
        _CandidateGroup(
          title: '关系候选',
          lines: [
            for (final update in insight.relationshipUpdates)
              [
                if (update.personName.isNotEmpty) update.personName,
                if (update.summary.isNotEmpty) update.summary,
                if (update.pattern?.isNotEmpty ?? false) update.pattern!,
                _confidence(update.confidence),
              ].where((item) => item.isNotEmpty).join('｜'),
          ],
        ),
        _CandidateGroup(
          title: '反证候选',
          lines: [
            for (final contradiction in insight.contradictions)
              [
                if (contradiction.oldMemoryId.isNotEmpty)
                  '旧记忆 ${contradiction.oldMemoryId}',
                if (contradiction.newEvidence.isNotEmpty)
                  contradiction.newEvidence,
                if (contradiction.interpretation.isNotEmpty)
                  contradiction.interpretation,
                _confidence(contradiction.confidence),
              ].where((item) => item.isNotEmpty).join('｜'),
          ],
        ),
      ],
    );
  }

  String _confidence(double? value) =>
      value == null ? '' : '｜置信度 ${value.toStringAsFixed(2)}';
}

class _CandidateGroup extends StatelessWidget {
  const _CandidateGroup({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(title, style: theme.textTheme.titleSmall),
      children: [
        for (final line in lines)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(line),
            ),
          ),
      ],
    );
  }
}

class _ClaimGroup extends StatelessWidget {
  const _ClaimGroup({
    required this.title,
    required this.claims,
    required this.developerMode,
  });

  final String title;
  final List<InsightClaim> claims;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    if (claims.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(title, style: theme.textTheme.titleSmall),
      initiallyExpanded: title == '事实',
      children: [
        for (final claim in claims)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(claim.text),
                if (developerMode && claim.confidence != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '置信度 ${claim.confidence!.toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                if (developerMode && claim.evidence.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final evidence in claim.evidence.take(3))
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(_evidenceLabel(evidence)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _evidenceLabel(InsightEvidence evidence) {
    final id = evidence.id.isEmpty ? '' : ' ${evidence.id}';
    return '${evidence.type}$id'.trim();
  }
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
