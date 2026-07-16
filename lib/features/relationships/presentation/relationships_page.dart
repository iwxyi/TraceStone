import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/routing/app_route_observer.dart';
import '../../companion/presentation/companion_page.dart';
import '../../../data/models/ai_profile.dart';
import '../../../data/models/ai_profile_preference.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/repositories/ai_analysis_queue_bus.dart';
import '../../../data/repositories/ai_profile_preference_repository.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/diary_change_bus.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/services/ai_profile_decision_service.dart';
import '../../../data/services/profile_projection_service.dart';
import '../../../data/utils/ai_source_formatter.dart';

class RelationshipsPage extends StatefulWidget {
  const RelationshipsPage({super.key});

  @override
  State<RelationshipsPage> createState() => _RelationshipsPageState();
}

class _RelationshipsPageState extends State<RelationshipsPage> with RouteAware {
  final _repository = const InsightRepository();
  final _developerSettings = const DeveloperSettingsRepository();
  final _profilePreferences = const AiProfilePreferenceRepository();
  final _projectionService = const ProfileProjectionService();
  final _decisionService = const AiProfileDecisionService();
  final _filterController = TextEditingController();
  Timer? _refreshDebounce;
  bool _routeSubscribed = false;
  _RelationshipPageData _data = const _RelationshipPageData();
  Future<_RelationshipPageData>? _loadingFuture;
  bool _loadingInitial = true;

  @override
  void initState() {
    super.initState();
    AiAnalysisQueueBus.version.addListener(_scheduleDynamicRefresh);
    DiaryChangeBus.version.addListener(_scheduleDynamicRefresh);
    _refreshNow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didPopNext() {
    _refreshNow();
  }

  void _scheduleDynamicRefresh() {
    if (!mounted) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 350), _refreshNow);
  }

  void _refreshNow() {
    if (!mounted) return;
    final future = _loadData();
    _loadingFuture = future;
    if (_data.isEmpty) setState(() => _loadingInitial = true);
    future.then((data) {
      if (!mounted || _loadingFuture != future) return;
      setState(() {
        _data = data;
        _loadingInitial = false;
      });
    }).catchError((Object _) {
      if (!mounted || _loadingFuture != future) return;
      setState(() => _loadingInitial = false);
    });
  }

  Future<_RelationshipPageData> _loadData() async {
    final insights = await _repository.listInsights();
    final profiles = _projectionService.buildRelationshipProfiles(insights);
    final preferences = await _profilePreferences.listPreferences();
    final mergeHistory =
        await _profilePreferences.listRelationshipMergeHistory();
    final visibleProfiles =
        await _profilePreferences.applyToRelationshipProfiles(profiles);
    final developerMode = await _developerSettings.isDeveloperModeEnabled();
    return _RelationshipPageData(
      profiles: visibleProfiles,
      mergeHistory: mergeHistory,
      developerMode: developerMode,
      decisions: _decisionService.buildRelationshipDecisions(
        profiles: visibleProfiles,
        preferences: preferences,
      ),
    );
  }

  Future<void> _setConfirmed(
    RelationshipProfile profile,
    bool confirmed,
  ) async {
    await _profilePreferences.setConfirmed(
      targetType: AiProfilePreferenceTargetType.relationship,
      targetId: profile.personName,
      confirmed: confirmed,
    );
    await _refresh();
  }

  Future<void> _hideProfile(RelationshipProfile profile) async {
    await _profilePreferences.setHidden(
      targetType: AiProfilePreferenceTargetType.relationship,
      targetId: profile.personName,
      hidden: true,
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已隐藏这位人物的关系记录'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await _profilePreferences.setHidden(
              targetType: AiProfilePreferenceTargetType.relationship,
              targetId: profile.personName,
              hidden: false,
            );
            if (mounted) await _refresh();
          },
        ),
      ),
    );
  }

  Future<void> _correctRelationship(RelationshipProfile profile) async {
    final corrected = await showDialog<String>(
      context: context,
      builder: (context) => _RelationshipCorrectionDialog(profile: profile),
    );
    if (corrected == null) return;
    await _profilePreferences.setCorrectedValue(
      targetType: AiProfilePreferenceTargetType.relationship,
      targetId: profile.personName,
      correctedValue: corrected,
    );
    await _refresh();
  }

  Future<void> _mergeRelationship(
    RelationshipProfile profile,
    List<RelationshipProfile> candidates,
  ) async {
    if (candidates.isEmpty) return;
    final target = await showDialog<RelationshipProfile>(
      context: context,
      builder: (context) => _RelationshipMergeDialog(
        source: profile,
        candidates: candidates,
      ),
    );
    if (target == null) return;
    final previous = await _profilePreferences.getPreference(
      targetType: AiProfilePreferenceTargetType.relationship,
      targetId: profile.personName,
    );
    await _profilePreferences.setMergedRelationship(
      sourcePersonName: profile.personName,
      targetPersonName: target.personName,
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已将 ${profile.personName} 合并到 ${target.personName}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            if (previous == null) {
              await _profilePreferences.deletePreference(
                targetType: AiProfilePreferenceTargetType.relationship,
                targetId: profile.personName,
              );
            } else {
              await _profilePreferences.savePreference(previous);
            }
            await _profilePreferences.recordRelationshipMergeUndo(
              sourcePersonName: profile.personName,
              targetPersonName: target.personName,
            );
            if (mounted) await _refresh();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    AiAnalysisQueueBus.version.removeListener(_scheduleDynamicRefresh);
    DiaryChangeBus.version.removeListener(_scheduleDynamicRefresh);
    if (_routeSubscribed) appRouteObserver.unsubscribe(this);
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _refreshNow();
    await _loadingFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关系')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _RelationshipContent(
          data: _data,
          loadingInitial: _loadingInitial,
          filterController: _filterController,
          visibleProfiles: _visibleProfiles(_data.profiles),
          onFilterChanged: (_) => setState(() {}),
          onConfirmedChanged: _setConfirmed,
          onHide: _hideProfile,
          onCorrect: _correctRelationship,
          onMerge: _mergeRelationship,
          onAsk: _askAboutRelationship,
        ),
      ),
    );
  }

  List<RelationshipProfile> _visibleProfiles(
    List<RelationshipProfile> profiles,
  ) {
    final query = _filterController.text.trim();
    if (query.isEmpty) return profiles;
    return profiles.where((profile) {
      final text = [
        profile.personName,
        ...profile.names,
        profile.relationship ?? '',
        ...profile.emotions,
        ...profile.patterns,
        for (final item in profile.recentInteractions) item.summary,
      ].join(' ');
      return text.contains(query);
    }).toList(growable: false);
  }

  void _askAboutRelationship(RelationshipProfile profile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompanionPage(
          initialQuestion: '我和${profile.personName}最近怎么样？',
        ),
      ),
    );
  }
}

class _RelationshipContent extends StatelessWidget {
  const _RelationshipContent({
    required this.data,
    required this.loadingInitial,
    required this.filterController,
    required this.visibleProfiles,
    required this.onFilterChanged,
    required this.onConfirmedChanged,
    required this.onHide,
    required this.onCorrect,
    required this.onMerge,
    required this.onAsk,
  });

  final _RelationshipPageData data;
  final bool loadingInitial;
  final TextEditingController filterController;
  final List<RelationshipProfile> visibleProfiles;
  final ValueChanged<String> onFilterChanged;
  final Future<void> Function(RelationshipProfile profile, bool confirmed)
      onConfirmedChanged;
  final Future<void> Function(RelationshipProfile profile) onHide;
  final Future<void> Function(RelationshipProfile profile) onCorrect;
  final Future<void> Function(
    RelationshipProfile profile,
    List<RelationshipProfile> candidates,
  ) onMerge;
  final ValueChanged<RelationshipProfile> onAsk;

  @override
  Widget build(BuildContext context) {
    if (loadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (data.profiles.isEmpty) return const _EmptyRelationships();
    final showDeveloperCard = data.developerMode &&
        (data.decisions.isNotEmpty || data.mergeHistory.isNotEmpty);
    final itemOffset = showDeveloperCard ? 2 : 1;
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: visibleProfiles.length + itemOffset,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _RelationshipFilter(
            controller: filterController,
            resultCount: visibleProfiles.length,
            onChanged: onFilterChanged,
          );
        }
        if (showDeveloperCard && index == 1) {
          return _RelationshipDecisionCard(
            decisions: data.decisions,
            mergeHistory: data.mergeHistory,
          );
        }
        final profile = visibleProfiles[index - itemOffset];
        return _RelationshipCard(
          profile: profile,
          mergeCandidates: visibleProfiles
              .where((item) => item.personName != profile.personName)
              .toList(growable: false),
          developerMode: data.developerMode,
          onConfirmedChanged: onConfirmedChanged,
          onHide: onHide,
          onCorrect: onCorrect,
          onMerge: onMerge,
          onAsk: onAsk,
        );
      },
    );
  }
}

class _RelationshipPageData {
  const _RelationshipPageData({
    this.profiles = const [],
    this.decisions = const [],
    this.mergeHistory = const [],
    this.developerMode = false,
  });

  final List<RelationshipProfile> profiles;
  final List<AiProfileDecision> decisions;
  final List<AiRelationshipMergeEvent> mergeHistory;
  final bool developerMode;

  bool get isEmpty =>
      profiles.isEmpty &&
      (!developerMode || (decisions.isEmpty && mergeHistory.isEmpty));
}

class _RelationshipFilter extends StatelessWidget {
  const _RelationshipFilter({
    required this.controller,
    required this.resultCount,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int resultCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchBar(
          controller: controller,
          hintText: '筛选人物、关系或互动',
          leading: const Icon(Icons.search),
          trailing: [
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: '清除',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close),
              ),
          ],
          onChanged: onChanged,
        ),
        if (controller.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            resultCount == 0 ? '没有匹配的关系记录' : '找到 $resultCount 位相关人物',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _RelationshipDecisionCard extends StatefulWidget {
  const _RelationshipDecisionCard({
    required this.decisions,
    required this.mergeHistory,
  });

  final List<AiProfileDecision> decisions;
  final List<AiRelationshipMergeEvent> mergeHistory;

  @override
  State<_RelationshipDecisionCard> createState() =>
      _RelationshipDecisionCardState();
}

class _RelationshipDecisionCardState extends State<_RelationshipDecisionCard> {
  AiProfileDecisionKind? _filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleDecisions = _filter == null
        ? widget.decisions
        : widget.decisions
            .where((decision) => decision.kind == _filter)
            .toList(growable: false);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.rule_outlined, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('关系决策', style: theme.textTheme.titleLarge),
                ),
                TextButton.icon(
                  onPressed: () => _copyAudit(context),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('复制审计'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '开发者视图：核对关系候选是否应确认、修正或继续观察。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text('全部 ${widget.decisions.length}'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final kind in _decisionKinds(widget.decisions))
                  ChoiceChip(
                    label: Text(
                      '${_relationshipDecisionKindLabel(kind)} ${_kindCount(kind)}',
                    ),
                    selected: _filter == kind,
                    onSelected: (_) => setState(() => _filter = kind),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (visibleDecisions.isEmpty)
              Text('没有符合筛选的关系决策', style: theme.textTheme.bodySmall)
            else
              Text(
                  '显示 ${visibleDecisions.take(8).length}/${visibleDecisions.length}',
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final decision in visibleDecisions.take(8)) ...[
              _RelationshipDecisionLine(decision: decision),
              if (decision != visibleDecisions.take(8).last)
                const Divider(height: 18),
            ],
            if (widget.mergeHistory.isNotEmpty) ...[
              const Divider(height: 24),
              Row(children: [
                const Icon(Icons.history_outlined, size: 18),
                const SizedBox(width: 6),
                Text('合并历史', style: theme.textTheme.titleSmall),
              ]),
              const SizedBox(height: 8),
              for (final event in widget.mergeHistory.take(5)) ...[
                _RelationshipMergeHistoryLine(event: event),
                if (event != widget.mergeHistory.take(5).last)
                  const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<AiProfileDecisionKind> _decisionKinds(
    List<AiProfileDecision> decisions,
  ) {
    return {
      for (final decision in decisions) decision.kind,
    }.toList(growable: false)
      ..sort((a, b) => _relationshipDecisionKindLabel(a)
          .compareTo(_relationshipDecisionKindLabel(b)));
  }

  int _kindCount(AiProfileDecisionKind kind) =>
      widget.decisions.where((decision) => decision.kind == kind).length;

  Future<void> _copyAudit(BuildContext context) async {
    final text = [
      '## Relationship Decision Audit',
      'total=${widget.decisions.length}',
      'mergeHistory=${widget.mergeHistory.length}',
      if (_filter != null) 'filter=${_filter!.name}',
      '',
      for (final decision in widget.decisions) ...[
        '- kind=${decision.kind.name}',
        '  targetType=${decision.targetType.name}',
        '  targetId=${decision.targetId}',
        '  title=${decision.title}',
        '  action=${decision.actionLabel}',
        '  reason=${decision.reason}',
        if (decision.debugLine.isNotEmpty) '  debug=${decision.debugLine}',
      ],
      if (widget.mergeHistory.isNotEmpty) ...[
        '',
        '### Merge History',
        for (final event in widget.mergeHistory)
          '- action=${event.action.name} source=${event.sourcePersonName} target=${event.targetPersonName} createdAt=${event.createdAt.toIso8601String()} id=${event.id}',
      ],
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制关系决策审计')),
    );
  }
}

String _relationshipDecisionKindLabel(AiProfileDecisionKind kind) {
  switch (kind) {
    case AiProfileDecisionKind.confirmed:
      return '已确认';
    case AiProfileDecisionKind.corrected:
      return '已修正';
    case AiProfileDecisionKind.hidden:
      return '已隐藏';
    case AiProfileDecisionKind.conflict:
      return '冲突';
    case AiProfileDecisionKind.merged:
      return '已合并';
    case AiProfileDecisionKind.mergeCandidate:
      return '合并候选';
    case AiProfileDecisionKind.observe:
      return '观察';
  }
}

class _RelationshipMergeHistoryLine extends StatelessWidget {
  const _RelationshipMergeHistoryLine({required this.event});

  final AiRelationshipMergeEvent event;

  @override
  Widget build(BuildContext context) {
    final action = switch (event.action) {
      AiRelationshipMergeEventAction.merge => '合并',
      AiRelationshipMergeEventAction.undo => '撤销合并',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '$action：${event.sourcePersonName} -> ${event.targetPersonName} · ${_RelationshipCard._dateLabel(event.createdAt)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _RelationshipDecisionLine extends StatelessWidget {
  const _RelationshipDecisionLine({required this.decision});

  final AiProfileDecision decision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(label: Text(decision.actionLabel)),
            Text(decision.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Text(decision.reason),
        if (decision.debugLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(decision.debugLine, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _RelationshipCard extends StatelessWidget {
  const _RelationshipCard({
    required this.profile,
    required this.mergeCandidates,
    required this.developerMode,
    required this.onConfirmedChanged,
    required this.onHide,
    required this.onCorrect,
    required this.onMerge,
    required this.onAsk,
  });

  final RelationshipProfile profile;
  final List<RelationshipProfile> mergeCandidates;
  final bool developerMode;
  final Future<void> Function(RelationshipProfile profile, bool confirmed)
      onConfirmedChanged;
  final Future<void> Function(RelationshipProfile profile) onHide;
  final Future<void> Function(RelationshipProfile profile) onCorrect;
  final Future<void> Function(
    RelationshipProfile profile,
    List<RelationshipProfile> candidates,
  ) onMerge;
  final ValueChanged<RelationshipProfile> onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = profile.recentInteractions.firstOrNull;
    final aliasNames = _aliasNames(profile);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(profile.personName.characters.first),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.personName,
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${_statusText(profile.status)} · ${profile.interactionCount} 次互动 · 最近 ${_dateLabel(profile.lastInteractionAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_RelationshipAction>(
                  tooltip: '关系操作',
                  onSelected: (action) {
                    switch (action) {
                      case _RelationshipAction.confirm:
                        onConfirmedChanged(profile, true);
                      case _RelationshipAction.unconfirm:
                        onConfirmedChanged(profile, false);
                      case _RelationshipAction.correct:
                        onCorrect(profile);
                      case _RelationshipAction.merge:
                        onMerge(profile, mergeCandidates);
                      case _RelationshipAction.hide:
                        onHide(profile);
                    }
                  },
                  itemBuilder: (context) => [
                    if (profile.userConfirmed)
                      const PopupMenuItem(
                        value: _RelationshipAction.unconfirm,
                        child: Text('取消确认'),
                      )
                    else
                      const PopupMenuItem(
                        value: _RelationshipAction.confirm,
                        child: Text('确认准确'),
                      ),
                    const PopupMenuItem(
                      value: _RelationshipAction.correct,
                      child: Text('修正关系'),
                    ),
                    if (mergeCandidates.isNotEmpty)
                      const PopupMenuItem(
                        value: _RelationshipAction.merge,
                        child: Text('合并人物'),
                      ),
                    const PopupMenuItem(
                      value: _RelationshipAction.hide,
                      child: Text('隐藏'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (latest != null && latest.summary.isNotEmpty)
              Text(latest.summary),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (profile.relationship?.isNotEmpty ?? false)
                  Chip(label: Text(profile.relationship!)),
                Chip(label: Text('来自 ${profile.distinctDays} 天记录')),
                if (profile.names.length > 1)
                  Chip(label: Text('别名 ${profile.names.length} 个')),
                if (profile.userConfirmed) const Chip(label: Text('已确认')),
                if (developerMode)
                  Chip(
                    label: Text('置信度 ${profile.confidence.toStringAsFixed(2)}'),
                  ),
              ],
            ),
            if (aliasNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '也包括：${aliasNames.join('、')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (profile.patterns.isNotEmpty || profile.emotions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final emotion in profile.emotions)
                    Chip(
                      avatar: const Icon(Icons.mood_outlined, size: 16),
                      label: Text(emotion),
                    ),
                  for (final pattern in profile.patterns)
                    Chip(label: Text(pattern)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onAsk(profile),
                icon: const Icon(Icons.forum_outlined),
                label: const Text('询问这段关系'),
              ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('最近互动'),
              children: [
                for (final item in profile.recentInteractions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        [
                          _dateLabel(item.date),
                          if (item.emotion?.isNotEmpty ?? false) item.emotion!,
                          if (item.summary.isNotEmpty) item.summary,
                          if (developerMode && item.confidence != null)
                            '置信度 ${item.confidence!.toStringAsFixed(2)}',
                        ].join('｜'),
                      ),
                    ),
                  ),
                if (developerMode && profile.evidence.isNotEmpty) ...[
                  const Divider(),
                  if (aliasNames.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('合并依据',
                          style: Theme.of(context).textTheme.labelLarge),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        [
                          'aliases=${profile.names.join(', ')}',
                          'interactions=${profile.interactionCount}',
                          'days=${profile.distinctDays}',
                          'evidence=${profile.evidence.length}',
                        ].join(' | '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('证据来源',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                  const SizedBox(height: 6),
                  for (final evidence in profile.evidence.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _evidenceLine(evidence),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';

  static List<String> _aliasNames(RelationshipProfile profile) {
    final primary = profile.personName.trim().toLowerCase();
    return profile.names
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && name.toLowerCase() != primary)
        .toSet()
        .toList(growable: false);
  }

  static String _statusText(ProfileFactStatus status) {
    switch (status) {
      case ProfileFactStatus.stable:
        return '稳定档案';
      case ProfileFactStatus.emerging:
        return '形成中';
      case ProfileFactStatus.weak:
        return '待确认';
    }
  }

  static String _evidenceLine(InsightEvidence evidence) {
    final summary = evidence.summary ?? '';
    final quote = evidence.quote ?? '';
    final relevance = evidence.relevance ?? '';
    return [
      formatInsightEvidenceId(evidence),
      if (summary.isNotEmpty) summary,
      if (quote.isNotEmpty) quote,
      if (relevance.isNotEmpty) relevance,
    ].join(' | ');
  }
}

enum _RelationshipAction { confirm, unconfirm, correct, merge, hide }

class _RelationshipCorrectionDialog extends StatefulWidget {
  const _RelationshipCorrectionDialog({required this.profile});

  final RelationshipProfile profile;

  @override
  State<_RelationshipCorrectionDialog> createState() =>
      _RelationshipCorrectionDialogState();
}

class _RelationshipCorrectionDialogState
    extends State<_RelationshipCorrectionDialog> {
  late final _controller =
      TextEditingController(text: widget.profile.relationship ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('修正和${widget.profile.personName}的关系'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '关系类型',
          hintText: '例如：家人、朋友、同事、医生、重要的人',
          border: OutlineInputBorder(),
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
}

class _RelationshipMergeDialog extends StatefulWidget {
  const _RelationshipMergeDialog({
    required this.source,
    required this.candidates,
  });

  final RelationshipProfile source;
  final List<RelationshipProfile> candidates;

  @override
  State<_RelationshipMergeDialog> createState() =>
      _RelationshipMergeDialogState();
}

class _RelationshipMergeDialogState extends State<_RelationshipMergeDialog> {
  late RelationshipProfile _selected = widget.candidates.first;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('合并人物'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('将 ${widget.source.personName} 合并到：'),
          const SizedBox(height: 12),
          DropdownButtonFormField<RelationshipProfile>(
            initialValue: _selected,
            decoration: const InputDecoration(
              labelText: '目标人物',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final candidate in widget.candidates)
                DropdownMenuItem(
                  value: candidate,
                  child: Text(candidate.personName),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selected = value);
            },
          ),
          const SizedBox(height: 10),
          Text(
            '合并后会保留两边的互动、情绪、模式和证据来源。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('合并'),
        ),
      ],
    );
  }
}

class _EmptyRelationships extends StatelessWidget {
  const _EmptyRelationships();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.people_alt_outlined, size: 48),
        SizedBox(height: 16),
        Text(
          '还没有关系记录。完成 AI 洞察后，这里会按人物聚合互动摘要和关系变化。',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
