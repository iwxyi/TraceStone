import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/models/entry_summary.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/entry_summary_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/utils/ai_source_formatter.dart';
import '../../../data/utils/profile_display_formatter.dart';
import 'ai_feedback_bar.dart';

class InsightPage extends StatefulWidget {
  const InsightPage({super.key});

  @override
  State<InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends State<InsightPage> {
  final _repository = const InsightRepository();
  final _summaryRepository = const EntrySummaryRepository();
  final _developerSettings = const DeveloperSettingsRepository();
  late Future<_InsightPageData?> _dataFuture = _loadData();
  late final Future<bool> _developerModeFuture =
      _developerSettings.isDeveloperModeEnabled();

  Future<_InsightPageData?> _loadData() async {
    final insight = await _repository.getLatestInsight();
    if (insight == null) return null;
    return _InsightPageData(
      insight: insight,
      summary: await _summaryRepository.getSummary(insight.entryId),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _dataFuture = _loadData();
    });
    await _dataFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日分析')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_InsightPageData?>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data;
            if (data == null) return const _EmptyInsight();
            return FutureBuilder<bool>(
              future: _developerModeFuture,
              builder: (context, developerSnapshot) {
                return _InsightBody(
                  data: data,
                  developerMode: developerSnapshot.data ?? false,
                  onSummaryChanged: _refresh,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _InsightPageData {
  const _InsightPageData({
    required this.insight,
    required this.summary,
  });

  final DiaryInsight insight;
  final EntrySummary? summary;
}

class _InsightBody extends StatelessWidget {
  const _InsightBody({
    required this.data,
    required this.developerMode,
    required this.onSummaryChanged,
  });

  final _InsightPageData data;
  final bool developerMode;
  final Future<void> Function() onSummaryChanged;

  @override
  Widget build(BuildContext context) {
    final insight = data.insight;
    final meta = [
      _dateLabel(insight.entryDate),
      if (insight.emotion.isNotEmpty) insight.emotion,
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('今日分析', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(meta, style: Theme.of(context).textTheme.bodySmall),
        if (data.summary != null) ...[
          const SizedBox(height: 16),
          _EntrySummaryCard(
            summary: data.summary!,
            onChanged: onSummaryChanged,
            developerMode: developerMode,
          ),
        ],
        const SizedBox(height: 16),
        _SectionCard(
          title: '读后感',
          icon: Icons.auto_awesome_outlined,
          child: SimpleMarkdownText(
            text: insight.reflection,
            emptyText: '分析生成中。',
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
        if (developerMode) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: '开发者导出',
            icon: Icons.ios_share_outlined,
            child: _InsightExportButton(insight: insight),
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
                  if (developerMode && (memory.entryId?.isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '来源 entry=${memory.entryId}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  if (developerMode && !(memory.entryId?.isNotEmpty ?? false))
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: _DeveloperWarningText('来源未验证：AI 未返回有效 entryId'),
                    ),
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
            title: '可以轻轻尝试',
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

class _EntrySummaryCard extends StatefulWidget {
  const _EntrySummaryCard({
    required this.summary,
    required this.onChanged,
    required this.developerMode,
  });

  final EntrySummary summary;
  final Future<void> Function() onChanged;
  final bool developerMode;

  @override
  State<_EntrySummaryCard> createState() => _EntrySummaryCardState();
}

class _EntrySummaryCardState extends State<_EntrySummaryCard> {
  late Future<List<EntrySummaryRevision>> _revisionsFuture = _loadRevisions();

  @override
  void didUpdateWidget(covariant _EntrySummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.entryId != widget.summary.entryId ||
        oldWidget.summary.revision != widget.summary.revision ||
        oldWidget.developerMode != widget.developerMode) {
      _revisionsFuture = _loadRevisions();
    }
  }

  Future<List<EntrySummaryRevision>> _loadRevisions() {
    if (!widget.developerMode) return Future.value(const []);
    return const EntrySummaryRepository()
        .listSummaryRevisions(widget.summary.entryId);
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final title = summary.title.trim();
    return _SectionCard(
      title: '日记摘要',
      icon: Icons.summarize_outlined,
      trailing: IconButton(
        tooltip: '修正摘要',
        onPressed: () => _editSummary(context),
        icon: const Icon(Icons.edit_note_outlined),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
          ],
          SimpleMarkdownText(
            text: summary.brief,
            emptyText: '还没有摘要。',
          ),
          if (summary.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final point in summary.keyPoints.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $point'),
              ),
          ],
          if (summary.importantQuotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final quote in summary.importantQuotes.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('“$quote”'),
              ),
          ],
          if (widget.developerMode) ...[
            const SizedBox(height: 8),
            Text(
              'generator=${summary.generator} revision=${summary.revision}'
              ' quality=${summary.qualityScore.toStringAsFixed(2)}'
              '${summary.correctedAt == null ? '' : ' correctedAt=${summary.correctedAt!.toIso8601String()}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (summary.qualityWarnings.isNotEmpty)
              Text(
                'qualityWarnings=${summary.qualityWarnings.join('、')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            FutureBuilder<List<EntrySummaryRevision>>(
              future: _revisionsFuture,
              builder: (context, snapshot) {
                final revisions = snapshot.data ?? const [];
                if (revisions.isEmpty) return const SizedBox.shrink();
                return _SummaryRevisionAudit(
                  revisions: revisions,
                  summary: summary,
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editSummary(BuildContext context) async {
    final edited = await showDialog<_SummaryEditResult>(
      context: context,
      builder: (context) => _SummaryEditDialog(summary: widget.summary),
    );
    if (edited == null || edited.brief.isEmpty) return;
    final updated = await const EntrySummaryRepository().correctSummaryPackage(
      entryId: widget.summary.entryId,
      title: edited.title,
      brief: edited.brief,
      keyPoints: edited.keyPoints,
      importantQuotes: edited.importantQuotes,
    );
    if (!context.mounted) return;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('摘要不存在，无法修正')),
      );
      return;
    }
    await widget.onChanged();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已修正摘要并刷新向量')),
    );
  }
}

class _SummaryRevisionAudit extends StatelessWidget {
  const _SummaryRevisionAudit({
    required this.revisions,
    required this.summary,
  });

  final List<EntrySummaryRevision> revisions;
  final EntrySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '修订历史 ${revisions.length}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('复制修订'),
              ),
            ],
          ),
          for (final revision in revisions.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'r${revision.revision} ${revision.previousQualityScore.toStringAsFixed(2)} -> '
                '${revision.updatedQualityScore.toStringAsFixed(2)}｜'
                '${_compact(revision.previousBrief)} => ${_compact(revision.updatedBrief)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final text = [
      '## Entry Summary Revision Audit',
      'entryId=${summary.entryId}',
      'currentRevision=${summary.revision}',
      'currentQuality=${summary.qualityScore.toStringAsFixed(2)}',
      'generator=${summary.generator}',
      if (summary.correctedAt != null)
        'correctedAt=${summary.correctedAt!.toIso8601String()}',
      '',
      for (final revision in revisions) ...[
        '### r${revision.revision}',
        'createdAt=${revision.createdAt.toIso8601String()}',
        'reason=${revision.reason}',
        'quality=${revision.previousQualityScore.toStringAsFixed(2)} -> ${revision.updatedQualityScore.toStringAsFixed(2)}',
        if (revision.previousTitle != revision.updatedTitle)
          'title=${revision.previousTitle} => ${revision.updatedTitle}',
        'previousBrief=${revision.previousBrief}',
        'updatedBrief=${revision.updatedBrief}',
        '',
      ],
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制摘要修订审计')),
    );
  }

  static String _compact(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 48) return normalized;
    return '${normalized.substring(0, 48)}...';
  }
}

class _SummaryEditResult {
  const _SummaryEditResult({
    required this.title,
    required this.brief,
    required this.keyPoints,
    required this.importantQuotes,
  });

  final String title;
  final String brief;
  final List<String> keyPoints;
  final List<String> importantQuotes;
}

class _SummaryEditDialog extends StatefulWidget {
  const _SummaryEditDialog({required this.summary});

  final EntrySummary summary;

  @override
  State<_SummaryEditDialog> createState() => _SummaryEditDialogState();
}

class _SummaryEditDialogState extends State<_SummaryEditDialog> {
  late final _titleController =
      TextEditingController(text: widget.summary.title);
  late final _briefController =
      TextEditingController(text: widget.summary.brief);
  late final _keyPointsController =
      TextEditingController(text: widget.summary.keyPoints.join('\n'));
  late final _quotesController =
      TextEditingController(text: widget.summary.importantQuotes.join('\n'));

  @override
  void dispose() {
    _titleController.dispose();
    _briefController.dispose();
    _keyPointsController.dispose();
    _quotesController.dispose();
    super.dispose();
  }

  void _save() {
    final brief = _briefController.text.trim();
    if (brief.isEmpty) return;
    Navigator.of(context).pop(_SummaryEditResult(
      title: _titleController.text.trim(),
      brief: brief,
      keyPoints: _lines(_keyPointsController.text),
      importantQuotes: _lines(_quotesController.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修正摘要'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '摘要标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _briefController,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '更准确的日记摘要',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keyPointsController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '关键要点，每行一条',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _quotesController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '重要原文，每行一条',
                  border: OutlineInputBorder(),
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
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  List<String> _lines(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

class _InsightExportButton extends StatelessWidget {
  const _InsightExportButton({required this.insight});

  final DiaryInsight insight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => _copyInsight(context),
        icon: const Icon(Icons.copy),
        label: const Text('复制分析包'),
      ),
    );
  }

  Future<void> _copyInsight(BuildContext context) async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('复制分析包？'),
        content: const Text(
          '分析包可能包含日记摘要、证据来源、画像候选和关系候选。'
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
    await Clipboard.setData(ClipboardData(text: _debugText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制分析包')),
    );
  }

  String _debugText() {
    const encoder = JsonEncoder.withIndent('  ');
    return [
      '## Diary Insight',
      'entryId=${insight.entryId}',
      'entryDate=${insight.entryDate.toIso8601String()}',
      'generatedAt=${insight.generatedAt.toIso8601String()}',
      'emotion=${insight.emotion}',
      'keywords=${insight.keywords.join(',')}',
      'people=${insight.people.join(',')}',
      'facts=${insight.facts.length}',
      'signals=${insight.signals.length}',
      'hypotheses=${insight.hypotheses.length}',
      'suggestions=${insight.suggestions.length}',
      'profileCandidates=${insight.profileUpdateCandidates.length}',
      'relationshipUpdates=${insight.relationshipUpdates.length}',
      'contradictions=${insight.contradictions.length}',
      '',
      '## Reflection',
      insight.reflection,
      '',
      '## Raw JSON',
      encoder.convert(insight.toJson()),
    ].join('\n');
  }
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
          items: [
            for (final candidate in insight.profileUpdateCandidates)
              _CandidateDebugItem(
                line:
                    '${profileFieldLabel(candidate.field)}：${candidate.value}${_confidence(candidate.confidence)}',
                evidence: candidate.evidence,
              ),
          ],
        ),
        _CandidateGroup(
          title: '关系候选',
          items: [
            for (final update in insight.relationshipUpdates)
              _CandidateDebugItem(
                line: [
                  if (update.personName.isNotEmpty) update.personName,
                  if (update.summary.isNotEmpty) update.summary,
                  if (update.pattern?.isNotEmpty ?? false) update.pattern!,
                  _confidence(update.confidence),
                ].where((item) => item.isNotEmpty).join('｜'),
                evidence: update.evidence,
              ),
          ],
        ),
        _CandidateGroup(
          title: '反证候选',
          items: [
            for (final contradiction in insight.contradictions)
              _CandidateDebugItem(
                line: [
                  if (contradiction.oldMemoryId.isNotEmpty)
                    '旧记忆 ${contradiction.oldMemoryId}',
                  if (contradiction.newEvidence.isNotEmpty)
                    contradiction.newEvidence,
                  if (contradiction.interpretation.isNotEmpty)
                    contradiction.interpretation,
                  _confidence(contradiction.confidence),
                ].where((item) => item.isNotEmpty).join('｜'),
                evidence: contradiction.evidence,
              ),
          ],
        ),
      ],
    );
  }

  String _confidence(double? value) =>
      value == null ? '' : '｜置信度 ${value.toStringAsFixed(2)}';
}

class _CandidateDebugItem {
  const _CandidateDebugItem({
    required this.line,
    required this.evidence,
  });

  final String line;
  final List<InsightEvidence> evidence;
}

class _CandidateGroup extends StatelessWidget {
  const _CandidateGroup({required this.title, required this.items});

  final String title;
  final List<_CandidateDebugItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(title, style: theme.textTheme.titleSmall),
      children: [
        for (final item in items)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.line),
                  if (item.evidence.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _EvidenceList(evidence: item.evidence),
                  ] else ...[
                    const SizedBox(height: 4),
                    const _DeveloperWarningText('证据缺失：候选没有有效来源'),
                  ],
                ],
              ),
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
                  _EvidenceList(evidence: claim.evidence),
                ] else if (developerMode) ...[
                  const SizedBox(height: 4),
                  const _DeveloperWarningText('证据缺失：结论没有有效来源'),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DeveloperWarningText extends StatelessWidget {
  const _DeveloperWarningText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.error,
      ),
    );
  }
}

class _EvidenceList extends StatelessWidget {
  const _EvidenceList({required this.evidence});

  final List<InsightEvidence> evidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '证据来源',
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
        const SizedBox(height: 4),
        for (final item in evidence.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _evidenceLine(item),
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
      ],
    );
  }

  String _evidenceLine(InsightEvidence evidence) {
    final parts = [
      formatInsightEvidenceId(evidence),
      if (evidence.date != null) _dateLabel(evidence.date!),
      if (evidence.summary?.isNotEmpty ?? false) evidence.summary!,
      if (evidence.quote?.isNotEmpty ?? false) '“${evidence.quote}”',
      if (evidence.relevance?.isNotEmpty ?? false) evidence.relevance!,
    ].where((item) => item.isNotEmpty).toList();
    return parts.join('｜');
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${_two(date.month)}-${_two(date.day)}';

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shinen = theme.shinenColors;
    final iconRadius = shinen.shapeScale == ShinenShapeScale.large ? 12.0 : 8.0;
    return Card(
      elevation: theme.cardTheme.elevation ?? 0,
      color: theme.cardTheme.color,
      shape: theme.cardTheme.shape,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: switch (shinen.chipStyle) {
                      ShinenChipStyle.outline ||
                      ShinenChipStyle.ghost =>
                        Colors.transparent,
                      ShinenChipStyle.softFill =>
                        colors.primary.withValues(alpha: 0.08),
                      ShinenChipStyle.tinted =>
                        colors.primary.withValues(alpha: 0.14),
                    },
                    borderRadius: BorderRadius.circular(iconRadius),
                    border: Border.all(
                      color: shinen.chipStyle == ShinenChipStyle.ghost
                          ? Colors.transparent
                          : colors.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(icon, size: 18, color: colors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) trailing!,
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
          '暂无分析',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
