import 'package:flutter/material.dart';

import '../../../core/routing/app_routes.dart';
import '../../../data/models/ai_profile.dart';
import '../../../data/models/ai_profile_preference.dart';
import '../../../data/repositories/ai_profile_preference_repository.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/services/profile_projection_service.dart';

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
  late Future<List<ProfileFact>> _factsFuture = _loadFacts();
  late final Future<bool> _developerModeFuture =
      _developerSettings.isDeveloperModeEnabled();

  Future<List<ProfileFact>> _loadFacts() async {
    final insights = await _repository.listInsights();
    final facts = _projectionService.buildProfileFacts(insights);
    return _profilePreferences.applyToProfileFacts(facts);
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
        content: const Text('已隐藏这条画像候选'),
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

  Future<void> _refresh() async {
    setState(() {
      _factsFuture = _loadFacts();
    });
    await _factsFuture;
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
        child: FutureBuilder<List<ProfileFact>>(
          future: _factsFuture,
          builder: (context, snapshot) {
            final facts = snapshot.data ?? const <ProfileFact>[];
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
                else if (facts.isEmpty)
                  const _EmptyProfileCandidates()
                else
                  FutureBuilder<bool>(
                    future: _developerModeFuture,
                    builder: (context, developerSnapshot) {
                      return _ProfileSummary(
                        facts: facts,
                        developerMode: developerSnapshot.data ?? false,
                        onConfirmedChanged: _setConfirmed,
                        onHide: _hideFact,
                        onCorrect: _correctFact,
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
  });

  final List<ProfileFact> facts;
  final bool developerMode;
  final Future<void> Function(ProfileFact fact, bool confirmed)
      onConfirmedChanged;
  final Future<void> Function(ProfileFact fact) onHide;
  final Future<void> Function(ProfileFact fact) onCorrect;

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
              Text('画像候选', style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: 8),
            Text(
              '多次出现、跨日期的观察会逐渐成为稳定画像，其余先保留为候选。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            for (final fact in facts.take(8)) ...[
              _ProfileFactTile(
                fact: fact,
                developerMode: developerMode,
                onConfirmedChanged: onConfirmedChanged,
                onHide: onHide,
                onCorrect: onCorrect,
              ),
              if (fact != facts.take(8).last) const Divider(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileFactTile extends StatelessWidget {
  const _ProfileFactTile({
    required this.fact,
    required this.developerMode,
    required this.onConfirmedChanged,
    required this.onHide,
    required this.onCorrect,
  });

  final ProfileFact fact;
  final bool developerMode;
  final Future<void> Function(ProfileFact fact, bool confirmed)
      onConfirmedChanged;
  final Future<void> Function(ProfileFact fact) onHide;
  final Future<void> Function(ProfileFact fact) onCorrect;

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
            Chip(label: Text('${fact.evidenceCount} 条证据')),
            Chip(label: Text('${fact.distinctDays} 天')),
            Chip(label: Text('最近 ${_dateLabel(fact.lastSeenAt)}')),
            if (fact.userConfirmed) const Chip(label: Text('已确认')),
            if (developerMode)
              Chip(label: Text('置信度 ${fact.confidence.toStringAsFixed(2)}')),
          ],
        ),
      ],
    );
  }

  static String _statusText(ProfileFactStatus status) {
    switch (status) {
      case ProfileFactStatus.stable:
        return '稳定画像';
      case ProfileFactStatus.emerging:
        return '形成中';
      case ProfileFactStatus.weak:
        return '候选';
    }
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';
}

enum _ProfileFactAction { confirm, unconfirm, correct, hide }

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
            Text('完成更多 AI 洞察后，这里会显示长期主题、调节方式、压力源等画像候选。'),
          ],
        ),
      ),
    );
  }
}
