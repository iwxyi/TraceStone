import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/ai_context_package.dart';
import '../../../data/models/ai_profile.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/models/memory_retrieval_result.dart';
import '../../../data/models/stone_task.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/services/ai_context_builder.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _contextBuilder = const AiContextBuilder();
  final _developerSettings = const DeveloperSettingsRepository();
  Future<AiContextPackage?>? _searchFuture;
  _SearchSourceFilter _filter = _SearchSourceFilter.all;
  late final Future<bool> _developerModeFuture =
      _developerSettings.isDeveloperModeEnabled();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searchFuture = _contextBuilder.buildForSearch(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语义搜索')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SearchBar(
            controller: _controller,
            hintText: '例如：去年让我感到被支持的时刻',
            leading: const Icon(Icons.search),
            trailing: [
              IconButton(
                tooltip: '搜索',
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_SearchSourceFilter>(
              segments: const [
                ButtonSegment(
                    value: _SearchSourceFilter.all, label: Text('全部')),
                ButtonSegment(
                    value: _SearchSourceFilter.diary, label: Text('日记')),
                ButtonSegment(
                    value: _SearchSourceFilter.memory, label: Text('记忆')),
                ButtonSegment(
                    value: _SearchSourceFilter.relationship, label: Text('关系')),
                ButtonSegment(
                    value: _SearchSourceFilter.profile, label: Text('画像')),
                ButtonSegment(
                    value: _SearchSourceFilter.stone, label: Text('塑石')),
              ],
              selected: {_filter},
              onSelectionChanged: (value) {
                setState(() => _filter = value.first);
              },
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<bool>(
            future: _developerModeFuture,
            builder: (context, developerSnapshot) {
              final developerMode = developerSnapshot.data ?? false;
              return FutureBuilder<AiContextPackage?>(
                future: _searchFuture,
                builder: (context, snapshot) {
                  if (_searchFuture == null) return const _SearchHint();
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final package = snapshot.data;
                  final searchMatches = package?.searchMatches ?? const [];
                  final diaryMatches = searchMatches
                      .where((match) =>
                          !_nonDiarySourceTypes.contains(match.sourceType))
                      .toList(growable: false);
                  final memorySearchMatches = searchMatches
                      .where((match) => match.sourceType == 'memory')
                      .toList(growable: false);
                  final profileSearchMatches = searchMatches
                      .where((match) => match.sourceType == 'profile')
                      .toList(growable: false);
                  final relationshipSearchMatches = searchMatches
                      .where((match) => match.sourceType == 'relationship')
                      .toList(growable: false);
                  final memoryResults = package?.relatedMemories ?? const [];
                  final memorySearchIds = memorySearchMatches
                      .map((match) => match.sourceId)
                      .toSet();
                  final relatedMemoryResults = memoryResults
                      .where((result) =>
                          !memorySearchIds.contains(result.memory.id))
                      .toList(growable: false);
                  final profileFacts = package?.profileFacts ?? const [];
                  final relationshipProfiles =
                      package?.relationshipProfiles ?? const [];
                  final profileFactIds =
                      profileFacts.map((fact) => fact.id).toSet();
                  final relationshipNames = relationshipProfiles
                      .map((profile) => profile.personName)
                      .toSet();
                  final visibleProfileSearchMatches = profileSearchMatches
                      .where(
                          (match) => !profileFactIds.contains(match.sourceId))
                      .toList(growable: false);
                  final visibleRelationshipSearchMatches =
                      relationshipSearchMatches
                          .where((match) =>
                              !relationshipNames.contains(match.sourceId))
                          .toList(growable: false);
                  final stoneTasks = package?.stoneTasks ?? const [];
                  final hasVisibleResults =
                      (_showDiary && diaryMatches.isNotEmpty) ||
                          (_showMemory &&
                              (memorySearchMatches.isNotEmpty ||
                                  relatedMemoryResults.isNotEmpty)) ||
                          (_showProfile &&
                              (visibleProfileSearchMatches.isNotEmpty ||
                                  profileFacts.isNotEmpty)) ||
                          (_showRelationship &&
                              (visibleRelationshipSearchMatches.isNotEmpty ||
                                  relationshipProfiles.isNotEmpty)) ||
                          (_showStone && stoneTasks.isNotEmpty);
                  if (!hasVisibleResults) {
                    return const _EmptyResult();
                  }
                  final visiblePackage = package!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (developerMode) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(visiblePackage.debugSummary,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  _copyDebugContext(visiblePackage),
                              icon: const Icon(Icons.copy),
                              label: const Text('复制上下文'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_showDiary)
                        for (final result in diaryMatches) ...[
                          _SearchMatchCard(
                            result: result,
                            developerMode: developerMode,
                          ),
                          const SizedBox(height: 10),
                        ],
                      if (_showMemory) ...[
                        for (final result in memorySearchMatches) ...[
                          _SearchMatchCard(
                            result: result,
                            developerMode: developerMode,
                          ),
                          const SizedBox(height: 10),
                        ],
                        for (final result in relatedMemoryResults) ...[
                          _MemoryResultCard(
                            result: result,
                            developerMode: developerMode,
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                      if (_showRelationship) ...[
                        for (final result
                            in visibleRelationshipSearchMatches) ...[
                          _SearchMatchCard(
                            result: result,
                            developerMode: developerMode,
                          ),
                          const SizedBox(height: 10),
                        ],
                        for (final profile in relationshipProfiles) ...[
                          _RelationshipResultCard(
                            profile: profile,
                            developerMode: developerMode,
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                      if (_showProfile) ...[
                        for (final result in visibleProfileSearchMatches) ...[
                          _SearchMatchCard(
                            result: result,
                            developerMode: developerMode,
                          ),
                          const SizedBox(height: 10),
                        ],
                        for (final fact in profileFacts) ...[
                          _ProfileResultCard(
                            fact: fact,
                            developerMode: developerMode,
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                      if (_showStone)
                        for (final task in stoneTasks) ...[
                          _StoneResultCard(
                            task: task,
                            developerMode: developerMode,
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  bool get _showDiary =>
      _filter == _SearchSourceFilter.all ||
      _filter == _SearchSourceFilter.diary;

  bool get _showMemory =>
      _filter == _SearchSourceFilter.all ||
      _filter == _SearchSourceFilter.memory;

  bool get _showProfile =>
      _filter == _SearchSourceFilter.all ||
      _filter == _SearchSourceFilter.profile;

  bool get _showRelationship =>
      _filter == _SearchSourceFilter.all ||
      _filter == _SearchSourceFilter.relationship;

  bool get _showStone =>
      _filter == _SearchSourceFilter.all ||
      _filter == _SearchSourceFilter.stone;

  Future<void> _copyDebugContext(AiContextPackage package) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('复制搜索调试上下文？'),
        content: const Text(
          '调试上下文可能包含日记摘要、长期记忆、画像、关系、塑石行动和检索分数。'
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
    if (confirmed != true) return;
    await Clipboard.setData(
      ClipboardData(text: _SearchDebugContextText(package).build()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制搜索调试上下文')),
    );
  }
}

enum _SearchSourceFilter { all, diary, memory, relationship, profile, stone }

const _nonDiarySourceTypes = {
  'memory',
  'profile',
  'relationship',
  'stone',
};

class _SearchDebugContextText {
  const _SearchDebugContextText(this.package);

  final AiContextPackage package;

  String build() {
    return [
      _section('Summary', [
        package.debugSummary,
        if (package.query?.isNotEmpty ?? false) 'query=${package.query}',
      ]),
      _section('Search Matches', [
        for (final match in package.searchMatches)
          '${match.sourceType}:${match.sourceId} entry=${match.entryId} '
              'score=${match.score} ${match.title} | ${match.summary} | '
              '${match.reasons.join('；')}'
              '${match.rerankSignals.isEmpty ? '' : ' | signals=${_signalLine(match.rerankSignals)}'}',
      ]),
      _section('Memories', [
        for (final result in package.relatedMemories)
          '${result.memory.id} score=${result.score} ${result.memory.title} | '
              '${result.memory.summary} | ${result.reasons.join('；')}'
              '${result.rerankSignals.isEmpty ? '' : ' | signals=${_signalLine(result.rerankSignals)}'}',
      ]),
      _section('Profile', [
        for (final fact in package.profileFacts) ...[
          '${fact.id} ${fact.field}=${fact.value} '
              'confidence=${fact.confidence.toStringAsFixed(2)} '
              'evidence=${fact.evidenceCount}',
          for (final evidence in fact.evidence.take(6))
            '  evidence=${_evidenceLine(evidence)}',
        ],
      ]),
      _section('Relationships', [
        for (final profile in package.relationshipProfiles) ...[
          '${profile.personName} relationship=${profile.relationship ?? ''} '
              'confidence=${profile.confidence.toStringAsFixed(2)} '
              'interactions=${profile.interactionCount} '
              '${profile.patterns.take(2).join('；')}',
          for (final evidence in profile.evidence.take(6))
            '  evidence=${_evidenceLine(evidence)}',
          for (final interaction in profile.recentInteractions.take(3))
            '  interaction=${interaction.entryId} '
                '${interaction.date.toIso8601String().split('T').first} '
                '${interaction.summary}',
        ],
      ]),
      _section('Stone', [
        for (final task in package.stoneTasks)
          '${task.id} ${task.title} | ${task.description} | '
              'status=${task.status.name} sourceEntry=${task.sourceEntryId}'
              '${task.checkIns.isEmpty ? '' : ' checkIns=${task.checkIns.length}'}',
        for (final task in package.stoneTasks)
          for (final checkIn in task.checkIns.take(3))
            '  checkIn=${checkIn.id} sourceEntry=${checkIn.sourceEntryId ?? ''} '
                '${checkIn.createdAt.toIso8601String()} ${checkIn.note}',
      ]),
      if (package.retrievalTrace != null)
        _section('Retrieval Trace', [
          'scenario=${package.retrievalTrace!.scenario ?? ''} '
              'sources=${package.retrievalTrace!.sourceCount} '
              'generatedAt=${package.retrievalTrace!.generatedAt.toIso8601String()}',
          for (final item in package.retrievalTrace!.items)
            '${item.sourceType}:${item.sourceId} score=${item.score} '
                '${item.title} | ${item.reasons.join('；')}'
                '${item.rerankSignals.isEmpty ? '' : ' | signals=${_signalLine(item.rerankSignals)}'}',
        ]),
    ].where((section) => section.trim().isNotEmpty).join('\n\n');
  }

  String _signalLine(Map<String, double> signals) {
    return signals.entries
        .map((entry) => '${entry.key}:${entry.value.toStringAsFixed(2)}')
        .join(',');
  }

  String _section(String title, List<String> lines) {
    final visible =
        lines.map((line) => line.trim()).where((line) => line.isNotEmpty);
    if (visible.isEmpty) return '';
    return ['## $title', ...visible].join('\n');
  }

  String _evidenceLine(InsightEvidence evidence) {
    return [
      '${evidence.type}:${evidence.id}',
      if (evidence.date != null)
        evidence.date!.toIso8601String().split('T').first,
      if (evidence.summary?.isNotEmpty ?? false) evidence.summary!,
      if (evidence.quote?.isNotEmpty ?? false) 'quote=${evidence.quote}',
      if (evidence.relevance?.isNotEmpty ?? false)
        'relevance=${evidence.relevance}',
    ].join(' | ');
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.manage_search_outlined, size: 44),
          SizedBox(height: 14),
          Text('可以搜索情绪、关系、事件、地点或一段自然语言。'),
        ],
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.search_off_outlined, size: 44),
          SizedBox(height: 14),
          Text('暂时没有找到相关记录。'),
        ],
      ),
    );
  }
}

class _SearchMatchCard extends StatelessWidget {
  const _SearchMatchCard({
    required this.result,
    required this.developerMode,
  });

  final AiSearchMatch result;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    return _ResultCard(
      icon: _sourceIcon(result.sourceType),
      title: result.title,
      subtitle: _sourceLabel(result.sourceType),
      score: result.score,
      body: result.summary,
      reasons: result.reasons,
      sourceLine: [
        '${result.sourceType}:${result.sourceId}',
        if (result.entryId.isNotEmpty) 'entry=${result.entryId}',
        if (result.matchedTokens.isNotEmpty)
          'matched=${result.matchedTokens.take(8).join(',')}',
        if (result.rerankSignals.isNotEmpty)
          'signals=${_signalLine(result.rerankSignals)}',
      ].join(' | '),
      developerMode: developerMode,
    );
  }

  String _signalLine(Map<String, double> signals) {
    return signals.entries
        .map((entry) => '${entry.key}:${entry.value.toStringAsFixed(2)}')
        .join(',');
  }

  IconData _sourceIcon(String sourceType) {
    switch (sourceType) {
      case 'segment':
        return Icons.notes_outlined;
      case 'memory':
        return Icons.psychology_alt_outlined;
      case 'profile':
        return Icons.badge_outlined;
      case 'relationship':
        return Icons.people_alt_outlined;
      default:
        return Icons.article_outlined;
    }
  }

  String _sourceLabel(String sourceType) {
    switch (sourceType) {
      case 'segment':
        return '日记片段';
      case 'entry_summary':
        return '日记摘要';
      case 'entry':
        return '日记全文预览';
      case 'memory':
        return '长期记忆';
      case 'profile':
        return '画像命中';
      case 'relationship':
        return '关系命中';
      default:
        return '相关记录';
    }
  }
}

class _MemoryResultCard extends StatelessWidget {
  const _MemoryResultCard({
    required this.result,
    required this.developerMode,
  });

  final MemoryRetrievalResult result;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    final memory = result.memory;
    return _ResultCard(
      icon: Icons.psychology_alt_outlined,
      title: memory.title,
      subtitle: memory.emotion.isEmpty ? '长期记忆' : '长期记忆 · ${memory.emotion}',
      score: result.score,
      body: memory.summary,
      reasons: result.reasons,
      sourceLine: [
        'memory:${memory.id}',
        if (memory.sourceEntryId.isNotEmpty)
          'sourceEntry=${memory.sourceEntryId}',
        if (memory.allSourceEntryIds.isNotEmpty)
          'evidence=${memory.allSourceEntryIds.take(6).join(',')}',
        if (result.matchedTokens.isNotEmpty)
          'matched=${result.matchedTokens.take(8).join(',')}',
        if (result.rerankSignals.isNotEmpty)
          'signals=${_signalLine(result.rerankSignals)}',
      ].join(' | '),
      developerMode: developerMode,
    );
  }

  String _signalLine(Map<String, double> signals) {
    return signals.entries
        .map((entry) => '${entry.key}:${entry.value.toStringAsFixed(2)}')
        .join(',');
  }
}

class _ProfileResultCard extends StatelessWidget {
  const _ProfileResultCard({
    required this.fact,
    required this.developerMode,
  });

  final ProfileFact fact;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    return _ResultCard(
      icon: Icons.badge_outlined,
      title: fact.field,
      subtitle:
          fact.userConfirmed ? '画像 · 已确认' : '画像 · ${_statusLabel(fact.status)}',
      score: (fact.confidence * 10).round(),
      body: fact.value,
      reasons: [
        '${fact.evidenceCount} 条证据',
        '${fact.distinctDays} 天',
        if (fact.userConfirmed) '用户确认',
      ],
      sourceLine: [
        'profile:${fact.id}',
        if (fact.evidence.isNotEmpty)
          'evidence=${fact.evidence.take(6).map((item) => '${item.type}:${item.id}').join(',')}',
      ].join(' | '),
      developerMode: developerMode,
    );
  }

  String _statusLabel(ProfileFactStatus status) {
    switch (status) {
      case ProfileFactStatus.stable:
        return '稳定';
      case ProfileFactStatus.emerging:
        return '形成中';
      case ProfileFactStatus.weak:
        return '待确认';
    }
  }
}

class _RelationshipResultCard extends StatelessWidget {
  const _RelationshipResultCard({
    required this.profile,
    required this.developerMode,
  });

  final RelationshipProfile profile;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    final latest = profile.recentInteractions.firstOrNull;
    return _ResultCard(
      icon: Icons.people_alt_outlined,
      title: profile.personName,
      subtitle: [
        '关系',
        if (profile.relationship?.isNotEmpty ?? false) profile.relationship!,
        '${profile.interactionCount} 次互动',
      ].join(' · '),
      score: (profile.confidence * 10).round(),
      body: [
        if (latest?.summary.isNotEmpty ?? false) latest!.summary,
        if (profile.patterns.isNotEmpty) profile.patterns.take(2).join('；'),
      ].where((item) => item.isNotEmpty).join('\n'),
      reasons: [
        '${profile.distinctDays} 天证据',
        if (profile.userConfirmed) '用户确认',
      ],
      sourceLine: [
        'relationship:${profile.personName}',
        if (profile.evidence.isNotEmpty)
          'evidence=${profile.evidence.take(6).map((item) => '${item.type}:${item.id}').join(',')}',
      ].join(' | '),
      developerMode: developerMode,
    );
  }
}

class _StoneResultCard extends StatelessWidget {
  const _StoneResultCard({
    required this.task,
    required this.developerMode,
  });

  final StoneTask task;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    return _ResultCard(
      icon: Icons.self_improvement_outlined,
      title: task.title,
      subtitle: task.isCompleted ? '塑石行动 · 已完成' : '塑石行动 · 进行中',
      score: task.isCompleted ? 3 : 6,
      body: [
        task.description,
        if (task.checkIns.isNotEmpty)
          '最近进展：${task.checkIns.first.note.isEmpty ? '记录了一次进展' : task.checkIns.first.note}',
      ].where((item) => item.isNotEmpty).join('\n'),
      reasons: [
        if (task.tags.isNotEmpty) '标签：${task.tags.take(4).join('、')}',
        if (task.checkIns.isNotEmpty) '进展 ${task.checkIns.length} 次',
      ],
      sourceLine: [
        'stone:${task.id}',
        if (task.sourceEntryId.isNotEmpty) 'sourceEntry=${task.sourceEntryId}',
        if (task.checkIns.isNotEmpty)
          'checkIns=${task.checkIns.take(3).map((item) => item.id).join(',')}',
      ].join(' | '),
      developerMode: developerMode,
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.score,
    required this.body,
    required this.reasons,
    required this.developerMode,
    this.sourceLine = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int score;
  final String body;
  final List<String> reasons;
  final bool developerMode;
  final String sourceLine;

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
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                if (developerMode)
                  Text('score $score',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            if (developerMode && sourceLine.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                sourceLine,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(body),
            if (!developerMode && _visibleCautionReasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in _visibleCautionReasons)
                    Chip(label: Text(reason)),
                ],
              ),
            ],
            if (developerMode && reasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in reasons) Chip(label: Text(reason)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> get _visibleCautionReasons {
    return reasons
        .where((reason) => reason == '已归档记忆' || reason == '低置信记忆')
        .toList(growable: false);
  }
}
