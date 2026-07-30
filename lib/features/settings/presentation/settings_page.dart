import 'package:flutter/material.dart';

import '../../../app/theme_controller.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/app_auth_repository.dart';
import '../../../data/repositories/developer_settings_repository.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = ['日记锁', 'WebDAV 备份', '提醒通知', '导出数据', '会员中心'];

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _ThemeModeSection(),
          const SizedBox(height: 18),
          const _PaletteSection(),
          const SizedBox(height: 18),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('自定义 AI'),
                  subtitle: const Text('官方 AI / OpenAI 兼容接口'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.customAi),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('回收站'),
              subtitle: const Text('删除的日记保留 90 天'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.recycleBin),
            ),
          ),
          const SizedBox(height: 18),
          const _DeveloperModeSection(),
          const SizedBox(height: 18),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => Opacity(
                opacity: 0.45,
                child: ListTile(
                  enabled: false,
                  title: Text(items[index]),
                  subtitle: const Text('即将推出'),
                  trailing: const Icon(Icons.lock_outline),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperModeSection extends StatefulWidget {
  const _DeveloperModeSection();

  @override
  State<_DeveloperModeSection> createState() => _DeveloperModeSectionState();
}

class _DeveloperModeSectionState extends State<_DeveloperModeSection> {
  final _repository = const DeveloperSettingsRepository();
  final _authRepository = const AppAuthRepository();
  late Future<bool> _enabledFuture = _repository.isDeveloperModeEnabled();
  late Future<String> _backendBaseUrlFuture = _authRepository.loadBaseUrl();

  Future<void> _setEnabled(bool value) async {
    await _repository.setDeveloperModeEnabled(value);
    if (!mounted) return;
    setState(() {
      _enabledFuture = Future.value(value);
    });
  }

  Future<void> _editBackendBaseUrl() async {
    final current = await _authRepository.loadBaseUrl();
    if (!mounted) return;
    final controller = TextEditingController(text: current);
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('后端地址'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: AppAuthRepository.defaultBaseUrl,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.of(context).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(AppAuthRepository.defaultBaseUrl),
              child: const Text('恢复默认'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (value == null) return;
      await _authRepository.saveBaseUrl(value);
      if (!mounted) return;
      setState(() {
        _backendBaseUrlFuture = _authRepository.loadBaseUrl();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('后端地址已保存')),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _enabledFuture,
      builder: (context, snapshot) {
        final enabled = snapshot.data ?? false;
        return Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.bug_report_outlined),
                title: const Text('开发者模式'),
                subtitle: const Text('显示 AI 后台进度、来源、错误和调试信息'),
                value: enabled,
                onChanged: _setEnabled,
              ),
              if (enabled) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_motion_outlined),
                  title: const Text('AI 调试'),
                  subtitle: const Text('查看后台进度、阶段日志和失败原因'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.aiDebug),
                ),
                const Divider(height: 1),
                FutureBuilder<String>(
                  future: _backendBaseUrlFuture,
                  builder: (context, snapshot) {
                    return ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('后端地址'),
                      subtitle: Text(
                        snapshot.data ?? AppAuthRepository.defaultBaseUrl,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _editBackendBaseUrl,
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ThemeModeSection extends StatelessWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('日夜间',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('跟随')),
                    ButtonSegment(value: ThemeMode.light, label: Text('日间')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('夜间')),
                  ],
                  selected: {themeController.themeMode},
                  onSelectionChanged: (value) =>
                      themeController.setThemeMode(value.first),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PaletteSection extends StatefulWidget {
  const _PaletteSection();

  @override
  State<_PaletteSection> createState() => _PaletteSectionState();
}

class _PaletteSectionState extends State<_PaletteSection> {
  static const _defaultVisibleCount = 3;

  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final palettes = _showAll
            ? AppTheme.palettes
            : AppTheme.palettes.take(_defaultVisibleCount);
        final hiddenCount = AppTheme.palettes.length - _defaultVisibleCount;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('配色主题',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _ThemePreview(palette: themeController.palette),
                const SizedBox(height: 14),
                for (final palette in palettes)
                  _PaletteTile(
                    palette: palette,
                    selected: palette.name == themeController.palette.name,
                  ),
                if (hiddenCount > 0) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      icon: Icon(
                          _showAll ? Icons.expand_less : Icons.expand_more),
                      label: Text(_showAll ? '收起更多主题' : '展开更多主题'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.palette});

  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shinen = theme.shinenColors;
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: shinen.cardColor(colors.surface, isDark),
        borderRadius: BorderRadius.circular(shinen.cardRadius + 4),
        border: Border.all(
          color: shinen.cardBorderSide(colors.outlineVariant).color,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    palette.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _PreviewPill(label: '日'),
                const SizedBox(width: 6),
                _PreviewPill(label: '夜'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '今晚整理了几段旧事，也看见了一点新的节奏。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                Chip(label: Text('时光')),
                Chip(label: Text('关系')),
                Chip(label: Text('变化')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              enabled: false,
              decoration: const InputDecoration(
                hintText: '写下一句今天想留下的话',
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(
                    alpha: isDark ? 0.62 : 0.82,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(shinen.cardRadius + 6),
                    topRight: Radius.circular(shinen.cardRadius + 6),
                    bottomLeft: Radius.circular(shinen.cardRadius + 6),
                    bottomRight: const Radius.circular(8),
                  ),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.16),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Text(
                    '慢慢写就好',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({required this.palette, required this.selected});

  final ThemePalette palette;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ColorDot(color: palette.lightBackground),
              _ColorDot(color: palette.seed),
              _ColorDot(color: palette.accent),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ColorDot(color: palette.darkBackground),
              _ColorDot(color: palette.darkPrimary),
              _ColorDot(color: palette.darkAccent),
            ],
          ),
        ],
      ),
      title: Text(palette.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(palette.description),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StyleTag(label: '卡片 ${_cardStyleLabel(palette.cardStyle)}'),
              _StyleTag(label: 'Chip ${_chipStyleLabel(palette.chipStyle)}'),
              _StyleTag(label: '输入 ${_inputStyleLabel(palette.inputStyle)}'),
            ],
          ),
        ],
      ),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: () => themeController.setPalette(palette),
    );
  }

  String _cardStyleLabel(ShinenCardStyle style) {
    return switch (style) {
      ShinenCardStyle.paper => '纯白卡片',
      ShinenCardStyle.clean => '清透卡片',
      ShinenCardStyle.archive => '纸感卡片',
      ShinenCardStyle.glass => '玻璃卡片',
      ShinenCardStyle.outline => '边框卡片',
      ShinenCardStyle.letter => '信笺卡片',
    };
  }

  String _chipStyleLabel(ShinenChipStyle style) {
    return switch (style) {
      ShinenChipStyle.softFill => '柔和底色',
      ShinenChipStyle.tinted => '强调底色',
      ShinenChipStyle.outline => '空心边框',
      ShinenChipStyle.ghost => '透明气泡',
    };
  }

  String _inputStyleLabel(ShinenInputStyle style) {
    return switch (style) {
      ShinenInputStyle.paper => '纸页输入',
      ShinenInputStyle.filled => '浅底输入',
      ShinenInputStyle.underlined => '下划线',
      ShinenInputStyle.glow => '发光边框',
      ShinenInputStyle.outline => '纯边框',
    };
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

class _StyleTag extends StatelessWidget {
  const _StyleTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }
}
