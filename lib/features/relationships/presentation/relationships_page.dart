import 'package:flutter/material.dart';

import '../../companion/presentation/companion_page.dart';
import '../../../data/models/ai_profile.dart';
import '../../../data/models/ai_profile_preference.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/repositories/ai_profile_preference_repository.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/services/profile_projection_service.dart';
import '../../../data/utils/ai_source_formatter.dart';

class RelationshipsPage extends StatefulWidget {
  const RelationshipsPage({super.key});

  @override
  State<RelationshipsPage> createState() => _RelationshipsPageState();
}

class _RelationshipsPageState extends State<RelationshipsPage> {
  final _repository = const InsightRepository();
  final _developerSettings = const DeveloperSettingsRepository();
  final _profilePreferences = const AiProfilePreferenceRepository();
  final _projectionService = const ProfileProjectionService();
  final _filterController = TextEditingController();
  late Future<List<RelationshipProfile>> _profilesFuture = _loadProfiles();
  late final Future<bool> _developerModeFuture =
      _developerSettings.isDeveloperModeEnabled();

  Future<List<RelationshipProfile>> _loadProfiles() async {
    final insights = await _repository.listInsights();
    final profiles = _projectionService.buildRelationshipProfiles(insights);
    return _profilePreferences.applyToRelationshipProfiles(profiles);
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

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _profilesFuture = _loadProfiles();
    });
    await _profilesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关系')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RelationshipProfile>>(
          future: _profilesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final profiles = snapshot.data ?? const <RelationshipProfile>[];
            if (profiles.isEmpty) return const _EmptyRelationships();
            return FutureBuilder<bool>(
              future: _developerModeFuture,
              builder: (context, developerSnapshot) {
                final developerMode = developerSnapshot.data ?? false;
                return ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _visibleProfiles(profiles).length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final visibleProfiles = _visibleProfiles(profiles);
                    if (index == 0) {
                      return _RelationshipFilter(
                        controller: _filterController,
                        resultCount: visibleProfiles.length,
                        onChanged: (_) => setState(() {}),
                      );
                    }
                    final profile = visibleProfiles[index - 1];
                    return _RelationshipCard(
                      profile: profile,
                      developerMode: developerMode,
                      onConfirmedChanged: _setConfirmed,
                      onHide: _hideProfile,
                      onCorrect: _correctRelationship,
                      onAsk: _askAboutRelationship,
                    );
                  },
                );
              },
            );
          },
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

class _RelationshipCard extends StatelessWidget {
  const _RelationshipCard({
    required this.profile,
    required this.developerMode,
    required this.onConfirmedChanged,
    required this.onHide,
    required this.onCorrect,
    required this.onAsk,
  });

  final RelationshipProfile profile;
  final bool developerMode;
  final Future<void> Function(RelationshipProfile profile, bool confirmed)
      onConfirmedChanged;
  final Future<void> Function(RelationshipProfile profile) onHide;
  final Future<void> Function(RelationshipProfile profile) onCorrect;
  final ValueChanged<RelationshipProfile> onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = profile.recentInteractions.firstOrNull;

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
                if (profile.userConfirmed) const Chip(label: Text('已确认')),
                if (developerMode)
                  Chip(
                    label: Text('置信度 ${profile.confidence.toStringAsFixed(2)}'),
                  ),
              ],
            ),
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

enum _RelationshipAction { confirm, unconfirm, correct, hide }

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
