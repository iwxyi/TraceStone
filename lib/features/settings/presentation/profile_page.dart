import 'package:flutter/material.dart';

import '../../../core/routing/app_routes.dart';
import '../../../data/models/ai_profile.dart';
import '../../../data/models/ai_profile_preference.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/repositories/ai_profile_preference_repository.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/services/ai_profile_decision_service.dart';
import '../../../data/services/profile_projection_service.dart';
import '../../../data/utils/ai_source_formatter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _repository = const InsightRepository();
  final _developerSettings = const DeveloperSettingsRepository();
  final _profilePreferences = const AiProfilePreferenceRepository();
  final _projectionService = const ProfileProjectionService();
  final _decisionService = const AiProfileDecisionService();
  late Future<_ProfilePageData> _dataFuture = _loadData();
  late final Future<bool> _developerModeFuture =
      _developerSettings.isDeveloperModeEnabled();

  Future<_ProfilePageData> _loadData() async {
    final insights = await _repository.listInsights();
    final facts = _projectionService.buildProfileFacts(insights);
    final preferences = await _profilePreferences.listPreferences();
    final conflicts = _projectionService.buildConflictNotes(insights);
    final visibleFacts = await _profilePreferences.applyToProfileFacts(facts);
    return _ProfilePageData(
      facts: visibleFacts,
      conflicts: conflicts,
      decisions: _decisionService.buildProfileFactDecisions(
        facts: visibleFacts,
        preferences: preferences,
        conflicts: conflicts,
      ),
    );
  }

  Future<void> _setConfirmed(ProfileFact fact, bool confirmed) async {
    await _profilePreferences.setConfirmed(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: fact.id,
      confirmed: confirmed,
    );
    await _refresh();
  }

  Future<void> _hideFact(ProfileFact fact) async {
    await _profilePreferences.setHidden(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: fact.id,
      hidden: true,
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已隐藏这条画像'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await _profilePreferences.setHidden(
              targetType: AiProfilePreferenceTargetType.profileFact,
              targetId: fact.id,
              hidden: false,
            );
            if (mounted) await _refresh();
          },
        ),
      ),
    );
  }

  Future<void> _correctFact(ProfileFact fact) async {
    final corrected = await showDialog<String>(
      context: context,
      builder: (context) => _ProfileCorrectionDialog(fact: fact),
    );
    if (corrected == null) return;
    await _profilePreferences.setCorrectedValue(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: fact.id,
      correctedValue: corrected,
    );
    await _refresh();
  }

  Future<void> _mergeFacts(ProfileFact fact, List<ProfileFact> siblings) async {
    if (siblings.isEmpty) return;
    final merged = await showDialog<String>(
      context: context,
      builder: (context) => _ProfileMergeDialog(
        primary: fact,
        siblings: siblings,
      ),
    );
    if (merged == null || merged.trim().isEmpty) return;
    await _profilePreferences.setCorrectedValue(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: fact.id,
      correctedValue: merged,
    );
    for (final sibling in siblings) {
      await _profilePreferences.setHidden(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: sibling.id,
        hidden: true,
      );
    }
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已合并同字段画像候选')),
    );
  }

  Future<void> _adoptConflict(ProfileConflictNote conflict) async {
    final target = await _factForConflict(conflict);
    if (target == null) {
      _showConflictTargetMissing();
      return;
    }
    await _profilePreferences.setCorrectedValue(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: target.id,
      correctedValue: conflict.newEvidence,
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已采纳这条变化并更新画像')),
    );
  }

  Future<void> _keepExistingForConflict(ProfileConflictNote conflict) async {
    final target = await _factForConflict(conflict);
    if (target == null) {
      _showConflictTargetMissing();
      return;
    }
    await _profilePreferences.setConfirmed(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: target.id,
      confirmed: true,
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保留原画像并标记为确认')),
    );
  }

  Future<ProfileFact?> _factForConflict(ProfileConflictNote conflict) async {
    final facts = _projectionService.buildProfileFacts(
      await _repository.listInsights(),
    );
    final target = conflict.targetId.toLowerCase().trim();
    final normalizedField = target.startsWith('profile:')
        ? target.substring('profile:'.length)
        : target;
    for (final fact in facts) {
      final factId = fact.id.toLowerCase();
      final field = fact.field.toLowerCase();
      if (factId == target ||
          field == target ||
          field == normalizedField ||
          target.startsWith('$field:')) {
        return fact;
      }
    }
    return null;
  }

  void _showConflictTargetMissing() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('没有找到可更新的画像目标')),
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
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_ProfilePageData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data ?? const _ProfilePageData();
            final facts = data.facts;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const _ProfileHeader(),
                const SizedBox(height: 16),
                if (snapshot.connectionState != ConnectionState.done)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (facts.isEmpty &&
                    data.conflicts.isEmpty &&
                    data.decisions.isEmpty)
                  const _EmptyProfileCandidates()
                else
                  FutureBuilder<bool>(
                    future: _developerModeFuture,
                    builder: (context, developerSnapshot) {
                      final developerMode = developerSnapshot.data ?? false;
                      return Column(
                        children: [
                          if (data.conflicts.isNotEmpty) ...[
                            _ProfileConflictCard(
                              conflicts: data.conflicts,
                              developerMode: developerMode,
                              onAdopt: _adoptConflict,
                              onKeepExisting: _keepExistingForConflict,
                            ),
                            if (facts.isNotEmpty) const SizedBox(height: 16),
                          ],
                          if (developerMode && data.decisions.isNotEmpty) ...[
                            _ProfileDecisionCard(decisions: data.decisions),
                            if (facts.isNotEmpty) const SizedBox(height: 16),
                          ],
                          if (facts.isNotEmpty)
                            _ProfileSummary(
                              facts: facts,
                              developerMode: developerMode,
                              onConfirmedChanged: _setConfirmed,
                              onHide: _hideFact,
                              onCorrect: _correctFact,
                              onMerge: _mergeFacts,
                            ),
                        ],
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfilePageData {
  const _ProfilePageData({
    this.facts = const [],
    this.conflicts = const [],
    this.decisions = const [],
  });

  final List<ProfileFact> facts;
  final List<ProfileConflictNote> conflicts;
  final List<AiProfileDecision> decisions;
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(radius: 28, child: Text('我')),
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('未登录用户',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('本地记录优先保存'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({
    required this.facts,
    required this.developerMode,
    required this.onConfirmedChanged,
    required this.onHide,
    required this.onCorrect,
    required this.onMerge,
  });

  final List<ProfileFact> facts;
  final bool developerMode;
  final Future<void> Function(ProfileFact fact, bool confirmed)
      onConfirmedChanged;
  final Future<void> Function(ProfileFact fact) onHide;
  final Future<void> Function(ProfileFact fact) onCorrect;
  final Future<void> Function(ProfileFact fact, List<ProfileFact> siblings)
      onMerge;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.psychology_alt_outlined, size: 22),
              const SizedBox(width: 8),
              Text('成长画像', style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: 8),
            Text(
              '多次出现、跨日期的观察会逐渐成为稳定画像，其余先保留为待确认内容。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            for (final fact in facts.take(8)) ...[
              _ProfileFactTile(
                fact: fact,
                mergeSiblings: _mergeSiblings(fact),
                developerMode: developerMode,
                onConfirmedChanged: onConfirmedChanged,
                onHide: onHide,
                onCorrect: onCorrect,
                onMerge: onMerge,
              ),
              if (fact != facts.take(8).last) const Divider(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  List<ProfileFact> _mergeSiblings(ProfileFact fact) {
    return facts
        .where((item) =>
            item.id != fact.id &&
            item.field.toLowerCase() == fact.field.toLowerCase())
        .toList(growable: false);
  }
}

class _ProfileConflictCard extends StatelessWidget {
  const _ProfileConflictCard({
    required this.conflicts,
    required this.developerMode,
    required this.onAdopt,
    required this.onKeepExisting,
  });

  final List<ProfileConflictNote> conflicts;
  final bool developerMode;
  final Future<void> Function(ProfileConflictNote conflict) onAdopt;
  final Future<void> Function(ProfileConflictNote conflict) onKeepExisting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.change_circle_outlined, size: 22),
              const SizedBox(width: 8),
              Text('需要核对的变化', style: theme.textTheme.titleLarge),
            ]),
            const SizedBox(height: 8),
            Text(
              '这些内容可能说明旧记忆需要增加条件或降低权重，不会自动覆盖你的画像。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            for (final conflict in conflicts.take(3)) ...[
              Text(
                conflict.newEvidence,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (conflict.interpretation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(conflict.interpretation),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('来自 ${_dateLabel(conflict.entryDate)}')),
                  Chip(
                    label:
                        Text('可信度 ${conflict.confidence.toStringAsFixed(2)}'),
                  ),
                ],
              ),
              if (developerMode) ...[
                const SizedBox(height: 6),
                Text('target: ${conflict.targetId}',
                    style: theme.textTheme.bodySmall),
                Text('entry: ${conflict.entryId}',
                    style: theme.textTheme.bodySmall),
                for (final evidence in conflict.evidence.take(3))
                  Text(
                    'source: ${formatInsightEvidenceId(evidence)}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => onAdopt(conflict),
                    icon: const Icon(Icons.update_outlined),
                    label: const Text('采纳变化'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onKeepExisting(conflict),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('保持原画像'),
                  ),
                ],
              ),
              if (conflict != conflicts.take(3).last) const Divider(height: 22),
            ],
          ],
        ),
      ),
    );
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';
}

class _ProfileDecisionCard extends StatelessWidget {
  const _ProfileDecisionCard({required this.decisions});

  final List<AiProfileDecision> decisions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.rule_outlined, size: 22),
              const SizedBox(width: 8),
              Text('画像决策', style: theme.textTheme.titleLarge),
            ]),
            const SizedBox(height: 8),
            Text(
              '开发者视图：用于核对候选是否应确认、合并、隐藏或继续观察。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            for (final decision in decisions.take(5)) ...[
              _DecisionLine(decision: decision),
              if (decision != decisions.take(5).last) const Divider(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _DecisionLine extends StatelessWidget {
  const _DecisionLine({required this.decision});

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

class _ProfileFactTile extends StatelessWidget {
  const _ProfileFactTile({
    required this.fact,
    required this.mergeSiblings,
    required this.developerMode,
    required this.onConfirmedChanged,
    required this.onHide,
    required this.onCorrect,
    required this.onMerge,
  });

  final ProfileFact fact;
  final List<ProfileFact> mergeSiblings;
  final bool developerMode;
  final Future<void> Function(ProfileFact fact, bool confirmed)
      onConfirmedChanged;
  final Future<void> Function(ProfileFact fact) onHide;
  final Future<void> Function(ProfileFact fact) onCorrect;
  final Future<void> Function(ProfileFact fact, List<ProfileFact> siblings)
      onMerge;

  @override
  Widget build(BuildContext context) {
    final status = _statusText(fact.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(fact.field,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              status,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            PopupMenuButton<_ProfileFactAction>(
              tooltip: '画像操作',
              onSelected: (action) {
                switch (action) {
                  case _ProfileFactAction.confirm:
                    onConfirmedChanged(fact, true);
                  case _ProfileFactAction.unconfirm:
                    onConfirmedChanged(fact, false);
                  case _ProfileFactAction.correct:
                    onCorrect(fact);
                  case _ProfileFactAction.merge:
                    onMerge(fact, mergeSiblings);
                  case _ProfileFactAction.hide:
                    onHide(fact);
                }
              },
              itemBuilder: (context) => [
                if (fact.userConfirmed)
                  const PopupMenuItem(
                    value: _ProfileFactAction.unconfirm,
                    child: Text('取消确认'),
                  )
                else
                  const PopupMenuItem(
                    value: _ProfileFactAction.confirm,
                    child: Text('确认准确'),
                  ),
                const PopupMenuItem(
                  value: _ProfileFactAction.correct,
                  child: Text('修正'),
                ),
                if (mergeSiblings.isNotEmpty)
                  const PopupMenuItem(
                    value: _ProfileFactAction.merge,
                    child: Text('合并同类画像'),
                  ),
                const PopupMenuItem(
                  value: _ProfileFactAction.hide,
                  child: Text('隐藏'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(fact.value),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('来自 ${fact.evidenceCount} 条记录')),
            Chip(label: Text('${fact.distinctDays} 天')),
            Chip(label: Text('最近 ${_dateLabel(fact.lastSeenAt)}')),
            if (mergeSiblings.isNotEmpty)
              Chip(label: Text('同字段 ${mergeSiblings.length + 1} 条')),
            if (fact.userConfirmed) const Chip(label: Text('已确认')),
            if (developerMode)
              Chip(label: Text('置信度 ${fact.confidence.toStringAsFixed(2)}')),
          ],
        ),
        if (developerMode && fact.evidence.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('证据来源', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final evidence in fact.evidence.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                _evidenceLine(evidence),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }

  String _evidenceLine(InsightEvidence evidence) {
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

  static String _statusText(ProfileFactStatus status) {
    switch (status) {
      case ProfileFactStatus.stable:
        return '稳定画像';
      case ProfileFactStatus.emerging:
        return '形成中';
      case ProfileFactStatus.weak:
        return '待确认';
    }
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';
}

enum _ProfileFactAction { confirm, unconfirm, correct, merge, hide }

class _ProfileCorrectionDialog extends StatefulWidget {
  const _ProfileCorrectionDialog({required this.fact});

  final ProfileFact fact;

  @override
  State<_ProfileCorrectionDialog> createState() =>
      _ProfileCorrectionDialogState();
}

class _ProfileCorrectionDialogState extends State<_ProfileCorrectionDialog> {
  late final _controller = TextEditingController(text: widget.fact.value);

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
      title: const Text('修正画像'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: '更准确的说法',
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

class _ProfileMergeDialog extends StatefulWidget {
  const _ProfileMergeDialog({
    required this.primary,
    required this.siblings,
  });

  final ProfileFact primary;
  final List<ProfileFact> siblings;

  @override
  State<_ProfileMergeDialog> createState() => _ProfileMergeDialogState();
}

class _ProfileMergeDialogState extends State<_ProfileMergeDialog> {
  late final _controller = TextEditingController(text: _initialValue());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _initialValue() {
    final values = <String>{
      widget.primary.value.trim(),
      for (final sibling in widget.siblings) sibling.value.trim(),
    }..remove('');
    return values.join('；');
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('合并同类画像'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.primary.field} 下有 ${widget.siblings.length + 1} 条候选。'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '合并后的画像',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('合并'),
        ),
      ],
    );
  }
}

class _EmptyProfileCandidates extends StatelessWidget {
  const _EmptyProfileCandidates();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('个人成长概要',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(height: 10),
            Text('完成更多 AI 洞察后，这里会显示长期主题、调节方式、压力源等成长画像。'),
          ],
        ),
      ),
    );
  }
}
