import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/routing/app_route_observer.dart';
import '../../../core/routing/app_routes.dart';
import '../../../data/repositories/ai_analysis_queue_bus.dart';
import '../../../data/repositories/ai_analysis_queue_repository.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/diary_change_bus.dart';
import '../../../data/services/ai_analysis_queue_runner.dart';
import '../../../data/services/ai_user_profile_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with RouteAware {
  final _developerSettings = const DeveloperSettingsRepository();
  final _userProfileService = const AiUserProfileService();
  final _queueRepository = const AiAnalysisQueueRepository();
  final _queueRunner = const AiAnalysisQueueRunner();
  Timer? _refreshDebounce;
  bool _routeSubscribed = false;
  _ProfilePageData _data = const _ProfilePageData();
  Future<_ProfilePageData>? _loadingFuture;
  bool _loadingInitial = true;
  bool _rebuildingProfile = false;

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
  void dispose() {
    _refreshDebounce?.cancel();
    AiAnalysisQueueBus.version.removeListener(_scheduleDynamicRefresh);
    DiaryChangeBus.version.removeListener(_scheduleDynamicRefresh);
    if (_routeSubscribed) appRouteObserver.unsubscribe(this);
    super.dispose();
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

  Future<_ProfilePageData> _loadData() async {
    return _ProfilePageData(
      profileState: await _userProfileService.currentState(),
      developerMode: await _developerSettings.isDeveloperModeEnabled(),
    );
  }

  Future<void> _refresh() async {
    _refreshNow();
    await _loadingFuture;
  }

  Future<void> _rebuildUserProfile() async {
    if (_rebuildingProfile) return;
    setState(() => _rebuildingProfile = true);
    try {
      await _queueRepository.enqueueUserProfile();
      unawaited(_queueRunner.processNext());
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用户画像已加入 AI 队列')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成用户画像失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _rebuildingProfile = false);
    }
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
        child: _ProfileContent(
          data: _data,
          loadingInitial: _loadingInitial,
          rebuildingProfile: _rebuildingProfile,
          onRebuildProfile: _rebuildUserProfile,
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.data,
    required this.loadingInitial,
    required this.rebuildingProfile,
    required this.onRebuildProfile,
  });

  final _ProfilePageData data;
  final bool loadingInitial;
  final bool rebuildingProfile;
  final VoidCallback onRebuildProfile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _ProfileHeader(),
        const SizedBox(height: 16),
        const _ProfileAiToolsCard(),
        const SizedBox(height: 16),
        if (loadingInitial)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else
          _UserProfileCard(
            profileState: data.profileState,
            developerMode: data.developerMode,
            rebuildingProfile: rebuildingProfile,
            onRebuildProfile: onRebuildProfile,
          ),
      ],
    );
  }
}

class _ProfilePageData {
  const _ProfilePageData({this.profileState, this.developerMode = false});

  final AiUserProfileState? profileState;
  final bool developerMode;

  bool get isEmpty => profileState == null;
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

class _ProfileAiToolsCard extends StatelessWidget {
  const _ProfileAiToolsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.auto_awesome_motion_outlined),
            title: const Text('AI 整理进度'),
            subtitle: const Text('查看日记分析、月度总结和年度总结的后台进度'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.aiTaskQueue),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.psychology_alt_outlined),
            title: const Text('AI 记忆'),
            subtitle: const Text('查看、修正或删除 AI 记住的长期信息'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.memoryManagement),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('纪念日'),
            subtitle: const Text('用于多年今日、农历节日和特殊日期关联'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.calendarMemory),
          ),
        ],
      ),
    );
  }
}

class _UserProfileCard extends StatelessWidget {
  const _UserProfileCard({
    required this.profileState,
    required this.developerMode,
    required this.rebuildingProfile,
    required this.onRebuildProfile,
  });

  final AiUserProfileState? profileState;
  final bool developerMode;
  final bool rebuildingProfile;
  final VoidCallback onRebuildProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = profileState;
    final profile = state?.profile;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_alt_outlined, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('用户画像', style: theme.textTheme.titleLarge),
                ),
                FilledButton.tonalIcon(
                  onPressed: rebuildingProfile ? null : onRebuildProfile,
                  icon: rebuildingProfile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined),
                  label: Text(rebuildingProfile ? '生成中' : '重新生成'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '由大模型综合日记摘要、长期记忆和历史洞察生成，用于让后续总结、洞察和建议更贴合你。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            if (state != null) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(state.label)),
                  Chip(
                    label: Text(
                      '覆盖 ${state.sourceEntryCount}/${state.totalEntryCount} 篇',
                    ),
                  ),
                  if (state.changedEntryCount > 0)
                    Chip(label: Text('变化 ${state.changedEntryCount} 篇')),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (profile == null)
              Text(
                '还没有生成用户画像。完成一些日记整理后，可以手动生成。',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              for (final paragraph in profile.summary
                  .split(RegExp(r'\n\s*\n'))
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)) ...[
                Text(paragraph),
                const SizedBox(height: 10),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('来源 ${profile.allSourceEntryIds.length} 条')),
                  Chip(
                      label:
                          Text('可信度 ${profile.confidence.toStringAsFixed(2)}')),
                  Chip(label: Text('更新 ${_dateLabel(profile.updatedAt)}')),
                ],
              ),
              if (developerMode) ...[
                const SizedBox(height: 8),
                Text('memoryId: ${profile.id}',
                    style: theme.textTheme.bodySmall),
                Text('tags: ${profile.tags.join(', ')}',
                    style: theme.textTheme.bodySmall),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';
}
