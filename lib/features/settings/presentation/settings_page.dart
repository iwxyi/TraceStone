import 'package:flutter/material.dart';

import '../../../app/theme_controller.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_theme.dart';

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
            child: ListTile(
              title: const Text('自定义 AI'),
              subtitle: const Text('官方 AI / OpenAI 兼容接口'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.customAi),
            ),
          ),
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

class _PaletteSection extends StatelessWidget {
  const _PaletteSection();

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
                const Text('配色主题',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                for (final palette in AppTheme.palettes)
                  _PaletteTile(
                    palette: palette,
                    selected: palette.name == themeController.palette.name,
                  ),
              ],
            ),
          ),
        );
      },
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
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ColorDot(color: palette.lightBackground),
          _ColorDot(color: palette.seed),
          _ColorDot(color: palette.accent),
        ],
      ),
      title: Text(palette.name),
      subtitle: Text(palette.description),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: () => themeController.setPalette(palette),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}
