import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/ai_analysis_job.dart';
import '../../../data/models/diary_entry.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/models/period_summary.dart';
import '../../../data/repositories/ai_analysis_queue_bus.dart';
import '../../../data/repositories/ai_analysis_queue_repository.dart';
import '../../../data/repositories/diary_change_bus.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/repositories/period_summary_repository.dart';
import '../../../data/services/ai_analysis_queue_runner.dart';
import '../../ai_insight/presentation/ai_feedback_bar.dart';

String? _temperatureLabel(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final normalized = trimmed
      .replaceFirst(RegExp(r'\s*(℃|°C|C|°)$', caseSensitive: false), '')
      .trim();
  return normalized.isEmpty ? null : '$normalized℃';
}

bool _isVisibleLocation(String value) {
  final trimmed = value.trim();
  return trimmed.isNotEmpty &&
      trimmed != '未选择地点' &&
      trimmed != '点击选择地点' &&
      trimmed != '定位中';
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final _repository = const DiaryRepository();
  int _selectedIndex = 2;

  @override
  void initState() {
    super.initState();
    DiaryChangeBus.version.addListener(_refreshEntries);
    _loadViewPreference();
    _loadEntries(showLoading: true);
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedIndex = _safeGetInt(prefs, 'review.selectedIndex');
    if (selectedIndex == null || !mounted) return;
    setState(() => _selectedIndex = selectedIndex.clamp(0, 2));
  }

  Future<void> _saveViewPreference(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('review.selectedIndex', index);
  }

  int? _safeGetInt(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is int ? value : null;
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    DiaryChangeBus.version.removeListener(_refreshEntries);
    super.dispose();
  }

  void _refreshEntries() {
    _loadEntries();
  }

  int? _selectedYear;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final Set<String> _selectedIds = <String>{};
  List<DiaryEntry> _entries = const [];
  Object? _entriesError;
  bool _isLoadingEntries = true;
  int _entriesLoadGeneration = 0;

  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    await _repository.moveManyToTrash(_selectedIds);
    setState(() {
      _selectedIds.clear();
    });
    _loadEntries();
  }

  void _openEntry(String id) {
    if (_isSelectionMode) {
      _toggleSelection(id);
      return;
    }
    Navigator.of(context)
        .pushNamed(AppRoutes.diaryEditPath(id), arguments: id)
        .then((_) {
      if (mounted) {
        _loadEntries();
      }
    });
  }

  void _startSelection(String id) => _toggleSelection(id);

  String get _appBarTitle =>
      _isSelectionMode ? '已选择 ${_selectedIds.length} 篇' : '时光';

  Future<void> _loadEntries({bool showLoading = false}) async {
    final generation = ++_entriesLoadGeneration;
    if (showLoading && mounted) {
      setState(() {
        _isLoadingEntries = true;
        _entriesError = null;
      });
    }
    try {
      final entries = await _repository.listEntries();
      if (!mounted || generation != _entriesLoadGeneration) return;
      setState(() {
        _entries = entries;
        _entriesError = null;
        _isLoadingEntries = false;
        if (_selectedIds.isNotEmpty) {
          final ids = entries.map((entry) => entry.id).toSet();
          _selectedIds.removeWhere((id) => !ids.contains(id));
        }
      });
    } catch (error) {
      if (!mounted || generation != _entriesLoadGeneration) return;
      setState(() {
        _entriesError = error;
        _isLoadingEntries = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text(_appBarTitle)
            : Stack(
                alignment: Alignment.center,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('时光'),
                  ),
                  _ReviewViewSwitcher(
                    selectedIndex: _selectedIndex,
                    onChanged: (index) {
                      setState(() => _selectedIndex = index);
                      _saveViewPreference(index);
                    },
                  ),
                ],
              ),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              tooltip: '删除选中日记',
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_outline),
            ),
            IconButton(
              tooltip: '取消选择',
              onPressed: () => setState(() => _selectedIds.clear()),
              icon: const Icon(Icons.close),
            ),
          ] else ...[
            IconButton(
              tooltip: '搜索',
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.search),
              icon: const Icon(Icons.search),
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_entriesError != null && _entries.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: _refreshEntries,
          icon: const Icon(Icons.refresh),
          label: const Text('加载日记失败，点击重试'),
        ),
      );
    }
    if (_isLoadingEntries && _entries.isEmpty) {
      return _ReviewLoadingPlaceholder(selectedIndex: _selectedIndex);
    }
    if (_entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: _EmptyReviewCard(),
      );
    }
    if (_selectedIndex == 2) {
      return _DayTimeline(
        key: const PageStorageKey('review-day-timeline'),
        entries: _entries,
        onOpenEntry: _openEntry,
        onLongSelectEntry: _startSelection,
        selectedIds: _selectedIds,
      );
    }

    final availableYears = _entries.map((e) => e.date.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (_selectedYear == null || !availableYears.contains(_selectedYear)) {
      _selectedYear = availableYears.first;
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          sliver: SliverToBoxAdapter(
            child: _selectedIndex == 0
                ? _YearList(
                    entries: _entries,
                    selectedYear: _selectedYear!,
                    onSelectYear: (year) =>
                        setState(() => _selectedYear = year),
                    onOpenEntry: _openEntry,
                    onLongSelectEntry: _startSelection,
                    selectedIds: _selectedIds,
                  )
                : _MonthCalendar(
                    entries: _entries,
                    selectedMonth: _selectedMonth,
                    selectedDay: _selectedDay,
                    onChangeMonth: (month) => setState(() {
                      _selectedMonth = month;
                      _selectedDay = DateTime(month.year, month.month, 1);
                    }),
                    onSelectDay: (day) => setState(() => _selectedDay = day),
                    onOpenEntry: _openEntry,
                    onLongSelectEntry: _startSelection,
                    selectedIds: _selectedIds,
                  ),
          ),
        ),
      ],
    );
  }
}

class _ReviewViewSwitcher extends StatelessWidget {
  const _ReviewViewSwitcher(
      {required this.selectedIndex, required this.onChanged});

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
      segments: const [
        ButtonSegment(value: 2, label: Text('日')),
        ButtonSegment(value: 1, label: Text('月')),
        ButtonSegment(value: 0, label: Text('年')),
      ],
      selected: {selectedIndex},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _EmptyReviewCard extends StatelessWidget {
  const _EmptyReviewCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Text('还没有保存过日记。'),
      ),
    );
  }
}

class _ReviewLoadingPlaceholder extends StatelessWidget {
  const _ReviewLoadingPlaceholder({required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (selectedIndex == 2) return const _DayTimelineSkeleton();
    return const _CalendarReviewSkeleton();
  }
}

class _DayTimelineSkeleton extends StatelessWidget {
  const _DayTimelineSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      itemCount: 5,
      itemBuilder: (context, index) {
        return const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonDateRail(),
              SizedBox(width: 12),
              Expanded(child: _SkeletonEntryCard()),
            ],
          ),
        );
      },
    );
  }
}

class _CalendarReviewSkeleton extends StatelessWidget {
  const _CalendarReviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        const Row(
          children: [
            _SkeletonBlock(width: 88, height: 30),
            Spacer(),
            _SkeletonBlock(width: 128, height: 30),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 6 * 8) / 7;
            return Wrap(
              spacing: 8,
              runSpacing: 10,
              children: [
                for (var index = 0; index < 35; index++)
                  _SkeletonBlock(width: width, height: 42),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const _SkeletonEntryCard(),
        const SizedBox(height: 12),
        const _SkeletonEntryCard(),
      ],
    );
  }
}

class _SkeletonDateRail extends StatelessWidget {
  const _SkeletonDateRail();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 42,
      height: 104,
      child: Column(
        children: [
          _SkeletonBlock(width: 34, height: 42),
          Expanded(
            child: _SkeletonVerticalLine(),
          ),
        ],
      ),
    );
  }
}

class _SkeletonVerticalLine extends StatelessWidget {
  const _SkeletonVerticalLine();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.58);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color),
          ),
        ),
      ],
    );
  }
}

class _SkeletonEntryCard extends StatelessWidget {
  const _SkeletonEntryCard();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBlock(width: double.infinity, height: 18),
            SizedBox(height: 10),
            _SkeletonBlock(width: double.infinity, height: 12),
            SizedBox(height: 7),
            _SkeletonBlock(width: 180, height: 12),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.58);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height <= 2 ? 0 : 7),
        ),
      ),
    );
  }
}

class _EntryPreviewDialog extends StatefulWidget {
  const _EntryPreviewDialog({required this.entries, required this.onOpenEntry});

  final List<DiaryEntry> entries;
  final ValueChanged<String> onOpenEntry;

  @override
  State<_EntryPreviewDialog> createState() => _EntryPreviewDialogState();
}

class _EntryPreviewDialogState extends State<_EntryPreviewDialog> {
  final _insightRepository = const InsightRepository();
  late final PageController _pageController;
  late final FocusNode _focusNode;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.entries.length - 1);
    if (next == _index) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(screen.width * 0.92, 680.0);
    final height = math.min(screen.height * 0.82, 680.0);
    final hasPrevious = _index > 0;
    final hasNext = _index < widget.entries.length - 1;
    final previousLayerCount = math.min(_index, 3);
    final nextLayerCount = math.min(widget.entries.length - _index - 1, 3);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (hasPrevious)
                _PaperLayers(
                  side: _PaperLayerSide.left,
                  count: previousLayerCount,
                ),
              if (hasNext)
                _PaperLayers(
                  side: _PaperLayerSide.right,
                  count: nextLayerCount,
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.entries.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) {
                      final entry = widget.entries[index];
                      return _EntryPreviewPage(
                        entry: entry,
                        positionLabel: '${index + 1}/${widget.entries.length}',
                        insightFuture: _insightRepository.getInsight(entry.id),
                        hasPrevious: hasPrevious,
                        hasNext: hasNext,
                        onPrevious: () => _go(-1),
                        onNext: () => _go(1),
                        onOpenEntry: () {
                          Navigator.of(context).pop();
                          widget.onOpenEntry(entry.id);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PaperLayerSide { left, right }

class _PaperLayers extends StatelessWidget {
  const _PaperLayers({required this.side, required this.count});

  final _PaperLayerSide side;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (var i = count - 1; i >= 0; i--)
              Positioned(
                top: 18.0 + i * 7,
                bottom: 4.0 + i * 7,
                left: side == _PaperLayerSide.left ? 0.0 + i * 10 : 24.0,
                right: side == _PaperLayerSide.right ? 0.0 + i * 10 : 24.0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.68 - i * 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset:
                            Offset(side == _PaperLayerSide.left ? -2 : 2, 2),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewArrow extends StatelessWidget {
  const _PreviewArrow(
      {required this.icon, required this.onPressed, required this.enabled});

  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _EntryPreviewPage extends StatelessWidget {
  const _EntryPreviewPage(
      {required this.entry,
      required this.positionLabel,
      required this.insightFuture,
      required this.hasPrevious,
      required this.hasNext,
      required this.onPrevious,
      required this.onNext,
      required this.onOpenEntry});

  final DiaryEntry entry;
  final String positionLabel;
  final Future<DiaryInsight?> insightFuture;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final shinen = theme.shinenColors;
    final meta = [
      if (_isVisibleLocation(entry.location)) entry.location,
      if (entry.weather.trim().isNotEmpty && entry.weather != '天气')
        entry.weather,
      if (_temperatureLabel(entry.temperature) != null)
        _temperatureLabel(entry.temperature)!,
    ].join(' · ');

    return Card(
      elevation: shinen.cardStyle == ShinenCardStyle.glass ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: shinen.cardColor(
          colorScheme.surface, theme.brightness == Brightness.dark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shinen.cardRadius),
        side: shinen.cardBorderSide(colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dateLabel(entry.date),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  positionLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                if (meta.isNotEmpty) ...[
                  Text(
                    meta,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                ],
                _EntryMarkdownPreview(text: entry.content),
                const SizedBox(height: 18),
                FutureBuilder<DiaryInsight?>(
                  future: insightFuture,
                  builder: (context, snapshot) {
                    final insight = snapshot.data;
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }
                    if (insight == null) {
                      return _InsightPreviewEmpty(onOpenEntry: onOpenEntry);
                    }
                    return _InsightPreview(insight: insight);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Row(
              children: [
                _PreviewArrow(
                  icon: Icons.chevron_left,
                  enabled: hasPrevious,
                  onPressed: onPrevious,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpenEntry,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('打开完整日记'),
                  ),
                ),
                const SizedBox(width: 10),
                _PreviewArrow(
                  icon: Icons.chevron_right,
                  enabled: hasNext,
                  onPressed: onNext,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dateLabel(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${date.year}年${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
  }
}

class _InsightPreviewEmpty extends StatelessWidget {
  const _InsightPreviewEmpty({required this.onOpenEntry});

  final VoidCallback onOpenEntry;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Text('还没有 AI 分析。打开完整日记后可以生成分析。'),
      ),
    );
  }
}

class _InsightPreview extends StatelessWidget {
  const _InsightPreview({required this.insight});

  final DiaryInsight insight;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI 分析', style: Theme.of(context).textTheme.titleSmall),
            if (insight.reflection.isNotEmpty) ...[
              const SizedBox(height: 8),
              SimpleMarkdownText(text: insight.reflection),
            ],
            if (insight.emotion.isNotEmpty ||
                insight.keywords.isNotEmpty ||
                insight.people.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (insight.emotion.isNotEmpty)
                    Chip(label: Text(insight.emotion)),
                  for (final keyword in insight.keywords.take(4))
                    Chip(label: Text(keyword)),
                  for (final person in insight.people.take(3))
                    Chip(label: Text(person)),
                ],
              ),
            ],
            if (insight.stoneTitle.isNotEmpty ||
                insight.stoneDescription.isNotEmpty) ...[
              const SizedBox(height: 10),
              if (insight.stoneTitle.isNotEmpty)
                SimpleMarkdownText(text: '### ${insight.stoneTitle}'),
              if (insight.stoneDescription.isNotEmpty)
                SimpleMarkdownText(text: insight.stoneDescription),
            ],
            const SizedBox(height: 12),
            AiFeedbackBar(entryId: insight.entryId),
          ],
        ),
      ),
    );
  }
}

class _EntryMarkdownPreview extends StatelessWidget {
  const _EntryMarkdownPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.trim().isEmpty ? ['空白日记'] : text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) _EntryMarkdownLine(line: line),
      ],
    );
  }
}

class _EntryMarkdownLine extends StatelessWidget {
  const _EntryMarkdownLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final trimmed = line.trimRight();
    if (trimmed.trim().isEmpty) {
      return const SizedBox(height: 8);
    }

    final headingMatch = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(trimmed);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!.length;
      final value = headingMatch.group(2)!.trim();
      final style = switch (level) {
        1 => Theme.of(context).textTheme.headlineSmall,
        2 => Theme.of(context).textTheme.titleLarge,
        _ => Theme.of(context).textTheme.titleMedium,
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _MarkdownInlineText(text: value, style: style),
      );
    }

    if (trimmed.startsWith('> ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _MarkdownInlineText(text: trimmed.substring(2)),
          ),
        ),
      );
    }

    final bullet = RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
    if (bullet != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• '),
            Expanded(child: _MarkdownInlineText(text: bullet.group(1)!)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _MarkdownInlineText(text: trimmed),
    );
  }
}

class _MarkdownInlineText extends StatelessWidget {
  const _MarkdownInlineText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium;
    return RichText(
      text: TextSpan(
        style: baseStyle?.copyWith(
          color: baseStyle.color ?? Theme.of(context).colorScheme.onSurface,
        ),
        children: _spans(context, text),
      ),
    );
  }

  List<TextSpan> _spans(BuildContext context, String value) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ));
      }
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return spans;
  }
}

enum _YearHeatmapMode { months, continuous }

class _YearList extends StatefulWidget {
  const _YearList(
      {required this.entries,
      required this.selectedYear,
      required this.onSelectYear,
      required this.onOpenEntry,
      required this.onLongSelectEntry,
      required this.selectedIds});

  final List<DiaryEntry> entries;
  final int selectedYear;
  final ValueChanged<int> onSelectYear;
  final ValueChanged<String> onOpenEntry;
  final ValueChanged<String> onLongSelectEntry;
  final Set<String> selectedIds;

  @override
  State<_YearList> createState() => _YearListState();
}

class _YearListState extends State<_YearList> {
  _YearHeatmapMode? _mode;

  Future<void> _openEntryPreview(List<DiaryEntry> entries) async {
    if (entries.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _EntryPreviewDialog(
        entries: entries,
        onOpenEntry: widget.onOpenEntry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{};
    for (final entry in widget.entries) {
      counts.update(entry.date.year, (value) => value + 1, ifAbsent: () => 1);
    }
    final years = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    final yearEntries = widget.entries
        .where((e) => e.date.year == widget.selectedYear)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final dayGroups = <String, List<DiaryEntry>>{};
    for (final entry in yearEntries) {
      dayGroups.putIfAbsent(entry.dayKey, () => []).add(entry);
    }
    for (final dayEntries in dayGroups.values) {
      dayEntries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    final activeDays = dayGroups.length;
    final longestStreak = _longestYearStreak(dayGroups.keys);
    final busiestDay = dayGroups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final busiestLabel = busiestDay.isEmpty
        ? '无'
        : '${DateTime.parse(busiestDay.first.key).month}月${DateTime.parse(busiestDay.first.key).day}日 · ${busiestDay.first.value.length}篇';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final year in years)
              ChoiceChip(
                label: Text('$year · ${counts[year]}篇'),
                selected: year == widget.selectedYear,
                onSelected: (_) => widget.onSelectYear(year),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _YearStats(
          entryCount: yearEntries.length,
          activeDays: activeDays,
          longestStreak: longestStreak,
          busiestLabel: busiestLabel,
        ),
        const SizedBox(height: 16),
        _PeriodSummaryCard(
          summaryKey: PeriodSummaryRepository.yearId(widget.selectedYear),
          type: PeriodSummaryType.year,
          period: DateTime(widget.selectedYear),
          entries: widget.entries,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final effectiveMode = _mode ??
                (constraints.maxWidth >= 720
                    ? _YearHeatmapMode.continuous
                    : _YearHeatmapMode.months);
            final modeSwitcher = Center(
              child: SegmentedButton<_YearHeatmapMode>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                      value: _YearHeatmapMode.months, label: Text('月份')),
                  ButtonSegment(
                      value: _YearHeatmapMode.continuous, label: Text('全年')),
                ],
                selected: {effectiveMode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.first),
              ),
            );

            if (effectiveMode == _YearHeatmapMode.continuous) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  modeSwitcher,
                  const SizedBox(height: 12),
                  _YearContinuousHeatmap(
                    year: widget.selectedYear,
                    dayGroups: dayGroups,
                    selectedIds: widget.selectedIds,
                    onOpenEntries: _openEntryPreview,
                    onLongSelectEntry: widget.onLongSelectEntry,
                  ),
                ],
              );
            }

            final columns = constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 520
                    ? 2
                    : 1;
            final gap = columns == 1 ? 0.0 : 12.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 12,
              children: [
                SizedBox(width: constraints.maxWidth, child: modeSwitcher),
                for (var month = 1; month <= 12; month++)
                  SizedBox(
                    width: width,
                    child: _YearMonthHeatmap(
                      year: widget.selectedYear,
                      month: month,
                      dayGroups: dayGroups,
                      selectedIds: widget.selectedIds,
                      onOpenEntries: _openEntryPreview,
                      onLongSelectEntry: widget.onLongSelectEntry,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  int _longestYearStreak(Iterable<String> dayKeys) {
    final days = dayKeys.map(DateTime.parse).toList()
      ..sort((a, b) => a.compareTo(b));
    var longest = 0;
    var current = 0;
    DateTime? previous;
    for (final day in days) {
      if (previous == null || day.difference(previous).inDays == 1) {
        current += 1;
      } else {
        current = 1;
      }
      if (current > longest) longest = current;
      previous = day;
    }
    return longest;
  }
}

class _YearStats extends StatelessWidget {
  const _YearStats(
      {required this.entryCount,
      required this.activeDays,
      required this.longestStreak,
      required this.busiestLabel});

  final int entryCount;
  final int activeDays;
  final int longestStreak;
  final String busiestLabel;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('总篇数', '$entryCount'),
      ('记录天数', '$activeDays'),
      ('最长连续', '$longestStreak天'),
      ('最密集', busiestLabel),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _YearMonthHeatmap extends StatelessWidget {
  const _YearMonthHeatmap(
      {required this.year,
      required this.month,
      required this.dayGroups,
      required this.selectedIds,
      required this.onOpenEntries,
      required this.onLongSelectEntry});

  final int year;
  final int month;
  final Map<String, List<DiaryEntry>> dayGroups;
  final Set<String> selectedIds;
  final ValueChanged<List<DiaryEntry>> onOpenEntries;
  final ValueChanged<String> onLongSelectEntry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metrics = _MonthHeatmapMetrics(year: year, month: month);
    final monthEntryCount = [
      for (var day = 1; day <= metrics.daysInMonth; day++)
        ...dayGroups[DiaryEntry.dateKey(DateTime(year, month, day))] ??
            const <DiaryEntry>[],
    ].length;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$month月', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  '$monthEntryCount篇',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final size = metrics.sizeForWidth(constraints.maxWidth);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final day = metrics.dayAt(details.localPosition, size);
                    if (day == null) return;
                    final entries = dayGroups[
                        DiaryEntry.dateKey(DateTime(year, month, day))];
                    if (entries == null || entries.isEmpty) return;
                    onOpenEntries(entries);
                  },
                  onLongPressStart: (details) {
                    final day = metrics.dayAt(details.localPosition, size);
                    if (day == null) return;
                    final entries = dayGroups[
                        DiaryEntry.dateKey(DateTime(year, month, day))];
                    if (entries == null || entries.isEmpty) return;
                    onLongSelectEntry(entries.first.id);
                  },
                  child: CustomPaint(
                    size: size,
                    painter: _MonthHeatmapPainter(
                      metrics: metrics,
                      dayGroups: dayGroups,
                      selectedIds: selectedIds,
                      colorScheme: colorScheme,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _YearContinuousHeatmap extends StatelessWidget {
  const _YearContinuousHeatmap(
      {required this.year,
      required this.dayGroups,
      required this.selectedIds,
      required this.onOpenEntries,
      required this.onLongSelectEntry});

  final int year;
  final Map<String, List<DiaryEntry>> dayGroups;
  final Set<String> selectedIds;
  final ValueChanged<List<DiaryEntry>> onOpenEntries;
  final ValueChanged<String> onLongSelectEntry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metrics = _ContinuousHeatmapMetrics(year: year);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final paintWidth = math.max(constraints.maxWidth, 760.0);
            final size = metrics.sizeForWidth(paintWidth);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final date = metrics.dateAt(details.localPosition, size);
                  if (date == null) return;
                  final entries = dayGroups[DiaryEntry.dateKey(date)];
                  if (entries == null || entries.isEmpty) return;
                  onOpenEntries(entries);
                },
                onLongPressStart: (details) {
                  final date = metrics.dateAt(details.localPosition, size);
                  if (date == null) return;
                  final entries = dayGroups[DiaryEntry.dateKey(date)];
                  if (entries == null || entries.isEmpty) return;
                  onLongSelectEntry(entries.first.id);
                },
                child: CustomPaint(
                  size: size,
                  painter: _ContinuousHeatmapPainter(
                    metrics: metrics,
                    dayGroups: dayGroups,
                    selectedIds: selectedIds,
                    colorScheme: colorScheme,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MonthHeatmapMetrics {
  const _MonthHeatmapMetrics({required this.year, required this.month});

  final int year;
  final int month;
  static const gap = 5.0;

  int get leading => DateTime(year, month).weekday - 1;
  int get daysInMonth => DateTime(year, month + 1, 0).day;
  int get rows => ((leading + daysInMonth + 6) / 7).floor();

  Size sizeForWidth(double width) {
    final cell = (width - gap * 6) / 7;
    return Size(width, rows * cell + (rows - 1) * gap);
  }

  Rect rectForDay(int day, Size size) {
    final cell = (size.width - gap * 6) / 7;
    final index = leading + day - 1;
    final row = index ~/ 7;
    final col = index % 7;
    return Rect.fromLTWH(
      col * (cell + gap),
      row * (cell + gap),
      cell,
      cell,
    );
  }

  int? dayAt(Offset position, Size size) {
    final cell = (size.width - gap * 6) / 7;
    final col = position.dx ~/ (cell + gap);
    final row = position.dy ~/ (cell + gap);
    if (col < 0 || col > 6 || row < 0 || row >= rows) return null;
    final dx = position.dx - col * (cell + gap);
    final dy = position.dy - row * (cell + gap);
    if (dx > cell || dy > cell) return null;
    final day = row * 7 + col - leading + 1;
    if (day < 1 || day > daysInMonth) return null;
    return day;
  }
}

class _ContinuousHeatmapMetrics {
  const _ContinuousHeatmapMetrics({required this.year});

  final int year;
  static const gap = 4.0;
  static const monthLabelHeight = 18.0;

  int get leading => DateTime(year).weekday - 1;
  int get daysInYear => DateTime(year + 1).difference(DateTime(year)).inDays;
  int get columns => ((leading + daysInYear + 6) / 7).floor();

  Size sizeForWidth(double width) {
    final cell = (width - gap * (columns - 1)) / columns;
    return Size(width, monthLabelHeight + 7 * cell + 6 * gap);
  }

  Rect rectForDate(DateTime date, Size size) {
    final cell = (size.width - gap * (columns - 1)) / columns;
    final dayIndex = date.difference(DateTime(year)).inDays;
    final index = leading + dayIndex;
    final col = index ~/ 7;
    final row = index % 7;
    return Rect.fromLTWH(
      col * (cell + gap),
      monthLabelHeight + row * (cell + gap),
      cell,
      cell,
    );
  }

  DateTime? dateAt(Offset position, Size size) {
    if (position.dy < monthLabelHeight) return null;
    final cell = (size.width - gap * (columns - 1)) / columns;
    final col = position.dx ~/ (cell + gap);
    final row = (position.dy - monthLabelHeight) ~/ (cell + gap);
    if (col < 0 || col >= columns || row < 0 || row > 6) return null;
    final dx = position.dx - col * (cell + gap);
    final dy = position.dy - monthLabelHeight - row * (cell + gap);
    if (dx > cell || dy > cell) return null;
    final dayIndex = col * 7 + row - leading;
    if (dayIndex < 0 || dayIndex >= daysInYear) return null;
    return DateTime(year).add(Duration(days: dayIndex));
  }
}

class _MonthHeatmapPainter extends CustomPainter {
  const _MonthHeatmapPainter(
      {required this.metrics,
      required this.dayGroups,
      required this.selectedIds,
      required this.colorScheme});

  final _MonthHeatmapMetrics metrics;
  final Map<String, List<DiaryEntry>> dayGroups;
  final Set<String> selectedIds;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    for (var day = 1; day <= metrics.daysInMonth; day++) {
      final date = DateTime(metrics.year, metrics.month, day);
      final entries =
          dayGroups[DiaryEntry.dateKey(date)] ?? const <DiaryEntry>[];
      final selected = entries.any((entry) => selectedIds.contains(entry.id));
      _paintHeatmapCell(
        canvas: canvas,
        rect: metrics.rectForDay(day, size),
        count: entries.length,
        selected: selected,
        colorScheme: colorScheme,
        label: '$day',
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MonthHeatmapPainter oldDelegate) {
    return oldDelegate.dayGroups != dayGroups ||
        oldDelegate.selectedIds != selectedIds ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _ContinuousHeatmapPainter extends CustomPainter {
  const _ContinuousHeatmapPainter(
      {required this.metrics,
      required this.dayGroups,
      required this.selectedIds,
      required this.colorScheme});

  final _ContinuousHeatmapMetrics metrics;
  final Map<String, List<DiaryEntry>> dayGroups;
  final Set<String> selectedIds;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );
    for (var month = 1; month <= 12; month++) {
      final rect = metrics.rectForDate(DateTime(metrics.year, month), size);
      textPainter.text = TextSpan(
        text: '$month月',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 10,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(rect.left, 0));
    }

    for (var i = 0; i < metrics.daysInYear; i++) {
      final date = DateTime(metrics.year).add(Duration(days: i));
      final entries =
          dayGroups[DiaryEntry.dateKey(date)] ?? const <DiaryEntry>[];
      final selected = entries.any((entry) => selectedIds.contains(entry.id));
      _paintHeatmapCell(
        canvas: canvas,
        rect: metrics.rectForDate(date, size),
        count: entries.length,
        selected: selected,
        colorScheme: colorScheme,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ContinuousHeatmapPainter oldDelegate) {
    return oldDelegate.dayGroups != dayGroups ||
        oldDelegate.selectedIds != selectedIds ||
        oldDelegate.colorScheme != colorScheme;
  }
}

void _paintHeatmapCell({
  required Canvas canvas,
  required Rect rect,
  required int count,
  required bool selected,
  required ColorScheme colorScheme,
  String? label,
}) {
  final alpha = switch (count) {
    0 => 0.0,
    1 => 0.18,
    2 => 0.32,
    3 || 4 => 0.48,
    _ => 0.66,
  };
  final fill = count == 0
      ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
      : colorScheme.primary.withValues(alpha: alpha);
  final radius = Radius.circular(rect.width < 12 ? 3 : 5);
  final rrect = RRect.fromRectAndRadius(rect, radius);
  canvas.drawRRect(rrect, Paint()..color = fill);
  if (selected) {
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = colorScheme.primary,
    );
  }
  if (label == null || rect.width < 18) return;
  final textPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color:
            count == 0 ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
        fontSize: rect.width < 28 ? 9 : 10,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: rect.width);
  textPainter.paint(
    canvas,
    Offset(
      rect.left + (rect.width - textPainter.width) / 2,
      rect.top + (rect.height - textPainter.height) / 2,
    ),
  );
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar(
      {required this.entries,
      required this.selectedMonth,
      required this.selectedDay,
      required this.onChangeMonth,
      required this.onSelectDay,
      required this.onOpenEntry,
      required this.onLongSelectEntry,
      required this.selectedIds});

  final List<DiaryEntry> entries;
  final DateTime selectedMonth;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onChangeMonth;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<String> onOpenEntry;
  final ValueChanged<String> onLongSelectEntry;
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(selectedMonth.year, selectedMonth.month);
    final daysInMonth =
        DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
    final leading = firstDay.weekday - 1;
    final entriesInMonth = entries
        .where((e) =>
            e.date.year == selectedMonth.year &&
            e.date.month == selectedMonth.month)
        .toList();
    final counts = <int, int>{};
    for (final entry in entriesInMonth) {
      counts.update(entry.date.day, (value) => value + 1, ifAbsent: () => 1);
    }
    final dayEntries = entries
        .where((e) =>
            DiaryEntry.dateKey(e.date) == DiaryEntry.dateKey(selectedDay))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => onChangeMonth(DateTime(
                          selectedMonth.year, selectedMonth.month - 1)),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('${selectedMonth.year}年${selectedMonth.month}月',
                        style: Theme.of(context).textTheme.titleMedium),
                    IconButton(
                      onPressed: () => onChangeMonth(DateTime(
                          selectedMonth.year, selectedMonth.month + 1)),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('一'),
                    Text('二'),
                    Text('三'),
                    Text('四'),
                    Text('五'),
                    Text('六'),
                    Text('日')
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: leading + daysInMonth,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7),
                  itemBuilder: (context, index) {
                    if (index < leading) return const SizedBox.shrink();
                    final day = index - leading + 1;
                    final count = counts[day] ?? 0;
                    final isSelected = selectedDay.year == selectedMonth.year &&
                        selectedDay.month == selectedMonth.month &&
                        selectedDay.day == day;
                    return _MonthDayCell(
                      day: day,
                      count: count,
                      selected: isSelected,
                      onTap: () => onSelectDay(DateTime(
                          selectedMonth.year, selectedMonth.month, day)),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _PeriodSummaryCard(
          summaryKey: PeriodSummaryRepository.monthId(selectedMonth),
          type: PeriodSummaryType.month,
          period: selectedMonth,
          entries: entries,
        ),
        const SizedBox(height: 16),
        if (dayEntries.isEmpty)
          const Card(
              elevation: 0,
              child:
                  Padding(padding: EdgeInsets.all(18), child: Text('当天没有日记。')))
        else
          Column(
            children: [
              for (final entry in dayEntries) ...[
                _ReviewEntryCard(
                  entry: entry,
                  selected: selectedIds.contains(entry.id),
                  onTap: () => onOpenEntry(entry.id),
                  onLongPress: () => onLongSelectEntry(entry.id),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
      ],
    );
  }
}

class _ReviewEntryCard extends StatelessWidget {
  const _ReviewEntryCard({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final DiaryEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title ?? entry.bodyPreview,
                      maxLines: entry.title == null ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        height: 1.28,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (entry.title != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        entry.bodyPreview,
                        maxLines: AppConstants.diaryPreviewMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: selected
                    ? Padding(
                        key: const ValueKey('selected'),
                        padding: const EdgeInsets.only(left: 10, top: 2),
                        child: Icon(Icons.check_circle,
                            size: 18, color: colorScheme.primary),
                      )
                    : const SizedBox.shrink(key: ValueKey('unselected')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell(
      {required this.day,
      required this.count,
      required this.selected,
      required this.onTap});

  final int day;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dotCount = count.clamp(0, 3);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                maxLines: 1,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1,
                    ),
              ),
              if (dotCount > 0) ...[
                const SizedBox(height: 3),
                SizedBox(
                  height: 4,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < dotCount; i++) ...[
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary,
                          ),
                        ),
                        if (i != dotCount - 1) const SizedBox(width: 2),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodSummaryCard extends StatefulWidget {
  const _PeriodSummaryCard({
    required this.summaryKey,
    required this.type,
    required this.period,
    required this.entries,
    DeveloperSettingsRepository? developerSettings,
  }) : _developerSettings =
            developerSettings ?? const DeveloperSettingsRepository();

  final String summaryKey;
  final PeriodSummaryType type;
  final DateTime period;
  final List<DiaryEntry> entries;
  final DeveloperSettingsRepository _developerSettings;

  @override
  State<_PeriodSummaryCard> createState() => _PeriodSummaryCardState();
}

class _PeriodSummaryCardState extends State<_PeriodSummaryCard> {
  final _repository = const PeriodSummaryRepository();
  final _queueRepository = const AiAnalysisQueueRepository();
  final _runner = const AiAnalysisQueueRunner();
  late Future<_PeriodSummaryCardData> _future;
  bool _isRegenerating = false;
  bool _autoQueued = false;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    AiAnalysisQueueBus.version.addListener(_refreshFromQueue);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_enqueueIfMissing());
    });
  }

  @override
  void dispose() {
    AiAnalysisQueueBus.version.removeListener(_refreshFromQueue);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PeriodSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summaryKey != widget.summaryKey) {
      _future = _load();
      _isRegenerating = false;
      _autoQueued = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_enqueueIfMissing());
      });
    }
  }

  Future<_PeriodSummaryCardData> _load() async {
    final summary = await _repository.getSummary(widget.summaryKey);
    final status = await _repository.getStatus(widget.summaryKey);
    final job = await _queueRepository.getJob(widget.summaryKey);
    return _PeriodSummaryCardData(
      summary: summary,
      status: status,
      job: job,
    );
  }

  void _refreshFromQueue() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Future<void> _enqueueIfMissing() async {
    if (_autoQueued) return;
    final data = await _load();
    if (data.isActive) return;
    final shouldAutoUpdate =
        data.summary == null || (data.status?.shouldAutoUpdate() ?? false);
    if (!shouldAutoUpdate) return;
    _autoQueued = true;
    await _enqueue(regenerate: false);
  }

  Future<void> _regenerate() async {
    setState(() {
      _isRegenerating = true;
    });
    try {
      await _enqueue(regenerate: true);
      if (!mounted) return;
      final title = widget.type == PeriodSummaryType.month ? '月度总结' : '年度总结';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入后台重新生成：$title')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRegenerating = false);
      }
    }
  }

  Future<void> _enqueue({required bool regenerate}) async {
    final version = _periodVersion(widget.entries, widget.type, widget.period);
    if (widget.type == PeriodSummaryType.month) {
      await _queueRepository.enqueueMonthSummary(
        widget.period,
        pipelineVersion:
            regenerate ? DateTime.now().microsecondsSinceEpoch : version,
      );
    } else {
      await _queueRepository.enqueueYearSummary(
        widget.period.year,
        pipelineVersion:
            regenerate ? DateTime.now().microsecondsSinceEpoch : version,
      );
    }
    setState(() {
      _future = _load();
    });
    await _runner.processUntilIdle(
        maxJobs: widget.type == PeriodSummaryType.year ? 14 : 1);
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  int _periodVersion(
    List<DiaryEntry> entries,
    PeriodSummaryType type,
    DateTime period,
  ) {
    final scoped = type == PeriodSummaryType.year
        ? entries.where((entry) => entry.date.year == period.year)
        : entries.where((entry) =>
            entry.date.year == period.year && entry.date.month == period.month);
    var version = 0;
    for (final entry in scoped) {
      final value = entry.updatedAt.microsecondsSinceEpoch;
      if (value > version) version = value;
    }
    return version == 0 ? DateTime.now().microsecondsSinceEpoch : version;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PeriodSummaryCardData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final summary = data?.summary;
        if (summary == null) {
          final title =
              widget.type == PeriodSummaryType.month ? '月度总结' : '年度总结';
          final message = data?.status?.message ??
              (data?.isActive ?? false ? '已加入后台整理' : '等待生成$title');
          return Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(message)),
                  IconButton(
                    tooltip: '重新生成$title',
                    onPressed: _isRegenerating ? null : _regenerate,
                    style: _quietIconButtonStyle(context),
                    icon: const Icon(Icons.refresh_outlined),
                  ),
                ],
              ),
            ),
          );
        }
        final title = summary.type == PeriodSummaryType.month ? '月度总结' : '年度总结';
        final updateMessage = data?.status?.needsUpdate ?? false
            ? _updateMessage(data!.status!)
            : '';
        return FutureBuilder<bool>(
          future: widget._developerSettings.isDeveloperModeEnabled(),
          builder: (context, developerSnapshot) {
            final developerMode = developerSnapshot.data ?? false;
            return Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.insights_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text(title,
                            style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        Text('${summary.entryCount}篇',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (data?.isActive ?? false) ...[
                          const SizedBox(width: 8),
                          Text(
                            data?.status?.message ?? '队列中',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: '重新生成$title',
                          style: _quietIconButtonStyle(context),
                          icon: _isRegenerating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_outlined),
                          onPressed: _isRegenerating ? null : _regenerate,
                        ),
                        IconButton(
                          tooltip: _collapsed ? '展开$title' : '折叠$title',
                          style: _quietIconButtonStyle(context),
                          icon: AnimatedRotation(
                            turns: _collapsed ? -0.25 : 0.25,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: const Icon(Icons.chevron_right),
                          ),
                          onPressed: () =>
                              setState(() => _collapsed = !_collapsed),
                        ),
                      ],
                    ),
                    if (!_collapsed) ...[
                      const SizedBox(height: 12),
                      Text(summary.brief),
                      if (updateMessage.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          updateMessage,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                      if (summary.themes.isNotEmpty ||
                          summary.emotions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final theme in summary.themes.take(6))
                              Chip(label: Text(theme)),
                            for (final emotion in summary.emotions.take(3))
                              Chip(
                                avatar:
                                    const Icon(Icons.mood_outlined, size: 16),
                                label: Text(emotion),
                              ),
                          ],
                        ),
                      ],
                      if (summary.relationshipHighlights.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('关系变化',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        for (final line
                            in summary.relationshipHighlights.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(line),
                          ),
                      ],
                      if (summary.growthHighlights.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('成长线索',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        for (final line in summary.growthHighlights.take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(line),
                          ),
                      ],
                      if (summary.notableChanges.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('值得注意的变化',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        for (final line in summary.notableChanges.take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(line),
                          ),
                      ],
                      if (summary.stoneHighlights.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('成长线索',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        for (final line in summary.stoneHighlights.take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(line),
                          ),
                      ],
                      if (summary.outlook.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('接下来',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text(summary.outlook),
                      ],
                      if (developerMode &&
                          (summary.contextDebugSummary.isNotEmpty ||
                              summary.contextSourceLines.isNotEmpty)) ...[
                        const SizedBox(height: 12),
                        _PeriodSummaryDebugSources(summary: summary),
                      ],
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _updateMessage(PeriodSummaryStatus status) {
    final percent = (status.changeRatio * 100).round();
    if (status.shouldAutoUpdate()) {
      return '日记变化较多，正在排队更新这个总结。';
    }
    return '有 ${status.changedEntryIds.length} 篇日记变化，约占 $percent%，暂不自动更新。';
  }

  ButtonStyle _quietIconButtonStyle(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton.styleFrom(
      foregroundColor: color.withValues(alpha: 0.72),
      disabledForegroundColor: color.withValues(alpha: 0.32),
      backgroundColor: Colors.transparent,
      hoverColor: color.withValues(alpha: 0.08),
      focusColor: color.withValues(alpha: 0.08),
      highlightColor: color.withValues(alpha: 0.08),
    );
  }
}

class _PeriodSummaryCardData {
  const _PeriodSummaryCardData({
    this.summary,
    this.status,
    this.job,
  });

  final PeriodSummary? summary;
  final PeriodSummaryStatus? status;
  final AiAnalysisJob? job;

  bool get isActive =>
      job != null &&
      (job!.state == AiAnalysisJobState.pending ||
          job!.state == AiAnalysisJobState.running ||
          job!.state == AiAnalysisJobState.incomplete);
}

class _PeriodSummaryDebugSources extends StatelessWidget {
  const _PeriodSummaryDebugSources({required this.summary});

  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      title: Text('开发者来源', style: Theme.of(context).textTheme.titleSmall),
      children: [
        if (summary.contextDebugSummary.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText('context: ${summary.contextDebugSummary}'),
            ),
          ),
        for (final line in summary.contextSourceLines.take(8))
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText('source: $line'),
            ),
          ),
      ],
    );
  }
}

class _DayTimeline extends StatefulWidget {
  const _DayTimeline(
      {super.key,
      required this.entries,
      required this.onOpenEntry,
      required this.onLongSelectEntry,
      required this.selectedIds});

  final List<DiaryEntry> entries;
  final ValueChanged<String> onOpenEntry;
  final ValueChanged<String> onLongSelectEntry;
  final Set<String> selectedIds;

  @override
  State<_DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<_DayTimeline> {
  static const _initialMonthCount = 4;
  static const _monthPageSize = 3;
  static const _loadAheadExtent = 900.0;

  final Set<int> _collapsedYears = <int>{};
  final Set<String> _collapsedMonths = <String>{};
  final ScrollController _scrollController = ScrollController();
  int _visibleMonthCount = _initialMonthCount;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFilled());
  }

  @override
  void didUpdateWidget(covariant _DayTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      final bucketCount = _monthBuckets.length;
      _visibleMonthCount = math.min(
          math.max(_visibleMonthCount, _initialMonthCount), bucketCount);
      final buckets = _monthBuckets;
      final monthKeys = buckets.map((bucket) => bucket.key).toSet();
      _collapsedMonths.removeWhere((key) => !monthKeys.contains(key));
      final years = buckets.map((bucket) => bucket.year).toSet();
      _collapsedYears.removeWhere((year) => !years.contains(year));
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFilled());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < _loadAheadExtent) {
      _loadMoreMonths();
    }
  }

  void _loadMoreMonths() {
    final bucketCount = _monthBuckets.length;
    if (_visibleMonthCount >= bucketCount) return;
    setState(() {
      _visibleMonthCount =
          (_visibleMonthCount + _monthPageSize).clamp(0, bucketCount);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFilled());
  }

  void _ensureFilled() {
    if (!mounted) return;
    final bucketCount = _monthBuckets.length;
    if (bucketCount == 0 || _visibleMonthCount >= bucketCount) return;

    final canPreload = !_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions ||
        _scrollController.position.extentAfter < _loadAheadExtent;
    final needsMoreVisibleContent =
        _loadedBuckets.every((bucket) => _collapsedYears.contains(bucket.year));
    if (needsMoreVisibleContent || canPreload) {
      _loadMoreMonths();
    }
  }

  List<_TimelineMonthBucket> get _monthBuckets {
    final sorted = [...widget.entries]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return b.createdAt.compareTo(a.createdAt);
      });

    final months = <String, List<DiaryEntry>>{};
    for (final entry in sorted) {
      final key = _monthKey(entry.date);
      months.putIfAbsent(key, () => []).add(entry);
    }

    return [
      for (final monthEntries in months.values)
        _TimelineMonthBucket(monthEntries),
    ];
  }

  List<_TimelineMonthBucket> get _loadedBuckets {
    final buckets = _monthBuckets;
    return buckets.take(_visibleMonthCount.clamp(0, buckets.length)).toList();
  }

  void _toggleYear(int year) {
    setState(() {
      if (!_collapsedYears.remove(year)) {
        _collapsedYears.add(year);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFilled());
  }

  void _toggleMonth(String monthKey) {
    setState(() {
      if (!_collapsedMonths.remove(monthKey)) {
        _collapsedMonths.add(monthKey);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFilled());
  }

  @override
  Widget build(BuildContext context) {
    final buckets = _monthBuckets;
    final loadedBuckets = buckets.take(_visibleMonthCount).toList();
    final hasMore = _visibleMonthCount < buckets.length;
    var lastYear = -1;
    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];

    for (final bucket in loadedBuckets) {
      final startsNewYear = bucket.year != lastYear;
      if (!_collapsedYears.contains(bucket.year)) {
        final monthCollapsed = _collapsedMonths.contains(bucket.key);
        final groupSlivers = <Widget>[
          _TimelineStickyHeaderSliver(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _TimelineMonthHeader(
                yearLabel: '${bucket.year}年',
                monthLabel: bucket.monthLabel,
                entryCount: bucket.entryCount,
                yearCollapsed: false,
                monthCollapsed: monthCollapsed,
                indentLeft: false,
                onToggleYear: () => _toggleYear(bucket.year),
                onToggleMonth: () => _toggleMonth(bucket.key),
              ),
            ),
          ),
        ];
        if (!monthCollapsed) {
          groupSlivers.add(SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final day = bucket.dayGroups[index];
                  return _TimelineDayGroup(
                    day: day,
                    hasLineBefore: index == 0 && !startsNewYear,
                    hasLineAfter: index < bucket.dayGroups.length - 1,
                    onOpenEntry: widget.onOpenEntry,
                    onLongSelectEntry: widget.onLongSelectEntry,
                    selectedIds: widget.selectedIds,
                  );
                },
                childCount: bucket.dayGroups.length,
              ),
            ),
          ));
        }
        slivers.add(SliverMainAxisGroup(slivers: groupSlivers));
      } else if (startsNewYear) {
        slivers.add(SliverMainAxisGroup(slivers: [
          _TimelineStickyHeaderSliver(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _TimelineMonthHeader(
                yearLabel: '${bucket.year}年',
                monthLabel: null,
                entryCount: buckets
                    .where((item) => item.year == bucket.year)
                    .fold<int>(0, (total, item) => total + item.entryCount),
                yearCollapsed: true,
                monthCollapsed: true,
                indentLeft: false,
                onToggleYear: () => _toggleYear(bucket.year),
                onToggleMonth: () => _toggleYear(bucket.year),
              ),
            ),
          ),
        ]));
      }
      lastYear = bucket.year;
    }

    if (hasMore) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 20)));

    return CustomScrollView(
      key: const PageStorageKey('review-day-timeline-scroll'),
      controller: _scrollController,
      slivers: slivers,
    );
  }
}

class _TimelineMonthBucket {
  _TimelineMonthBucket(List<DiaryEntry> entries)
      : entries = [...entries],
        year = entries.first.date.year,
        month = entries.first.date.month,
        key = _monthKey(entries.first.date) {
    final grouped = <String, List<DiaryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.dayKey, () => []).add(entry);
    }
    dayGroups = grouped.entries
        .map((entry) => _TimelineDayBucket(entry.value))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  final List<DiaryEntry> entries;
  final int year;
  final int month;
  final String key;
  late final List<_TimelineDayBucket> dayGroups;

  int get entryCount => entries.length;
  String get label => '$year年$month月';
  String get yearMonthLabel => '$year年 · $month月';
  String get monthLabel => '$month月';
  String get contextLabel => '$year · $month月';
}

class _TimelineDayBucket {
  _TimelineDayBucket(List<DiaryEntry> entries)
      : entries =
            ([...entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt))),
        date = entries.first.date,
        key = entries.first.dayKey;

  final List<DiaryEntry> entries;
  final DateTime date;
  final String key;
}

String _monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

class _TimelineStickyHeaderSliver extends StatelessWidget {
  const _TimelineStickyHeaderSliver({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TimelineStickyHeaderDelegate(child: child),
    );
  }
}

class _TimelineStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TimelineStickyHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => _TimelineMonthHeader.height;

  @override
  double get maxExtent => _TimelineMonthHeader.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor.withValues(alpha: 0.965),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: overlapsContent
                  ? theme.colorScheme.outlineVariant.withValues(alpha: 0.52)
                  : Colors.transparent,
            ),
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TimelineStickyHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}

class _TimelineMonthHeader extends StatelessWidget {
  const _TimelineMonthHeader(
      {required this.yearLabel,
      this.monthLabel,
      required this.entryCount,
      required this.yearCollapsed,
      required this.monthCollapsed,
      required this.indentLeft,
      required this.onToggleYear,
      required this.onToggleMonth});

  static const height = 46.0;
  static const _contentHeight = 34.0;

  final String? yearLabel;
  final String? monthLabel;
  final int entryCount;
  final bool yearCollapsed;
  final bool monthCollapsed;
  final bool indentLeft;
  final VoidCallback onToggleYear;
  final VoidCallback onToggleMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final shinen = theme.shinenColors;
    return Padding(
      padding: EdgeInsets.only(left: indentLeft ? 56 : 0),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: SizedBox(
            height: _contentHeight,
            child: Row(
              children: [
                if (yearLabel != null) ...[
                  _TimelineHeaderButton(
                    label: yearLabel!,
                    collapsed: yearCollapsed,
                    onTap: onToggleYear,
                    iconSize: 17,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      '/',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
                if (monthLabel != null) ...[
                  _TimelineHeaderButton(
                    label: monthLabel!,
                    collapsed: monthCollapsed,
                    onTap: onToggleMonth,
                    iconSize: 20,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const Spacer(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: switch (shinen.chipStyle) {
                      ShinenChipStyle.outline ||
                      ShinenChipStyle.ghost =>
                        Colors.transparent,
                      ShinenChipStyle.softFill => colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.44),
                      ShinenChipStyle.tinted =>
                        colorScheme.primary.withValues(alpha: 0.1),
                    },
                    borderRadius: BorderRadius.circular(
                      shinen.chipStyle == ShinenChipStyle.softFill ? 8 : 999,
                    ),
                    border: Border.all(
                      color: shinen.chipStyle == ShinenChipStyle.ghost
                          ? Colors.transparent
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text(
                      '$entryCount篇',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineHeaderButton extends StatelessWidget {
  const _TimelineHeaderButton({
    required this.label,
    required this.collapsed,
    required this.onTap,
    required this.style,
    required this.iconSize,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onTap;
  final TextStyle? style;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 5, 5, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              child: Icon(Icons.keyboard_arrow_down, size: iconSize),
            ),
            const SizedBox(width: 2),
            Text(label, style: style),
          ],
        ),
      ),
    );
  }
}

class _TimelineDayGroup extends StatelessWidget {
  const _TimelineDayGroup(
      {required this.day,
      required this.hasLineBefore,
      required this.hasLineAfter,
      required this.onOpenEntry,
      required this.onLongSelectEntry,
      required this.selectedIds});

  final _TimelineDayBucket day;
  final bool hasLineBefore;
  final bool hasLineAfter;
  final ValueChanged<String> onOpenEntry;
  final ValueChanged<String> onLongSelectEntry;
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final date = day.date;
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekday = weekdays[date.weekday - 1];

    final colorScheme = Theme.of(context).colorScheme;
    final railColor = colorScheme.primary;
    final lineColor = railColor.withValues(alpha: 0.28);

    return Stack(
      children: [
        if (hasLineBefore)
          Positioned(
            left: 21,
            top: 0,
            height: _TimelineDateBadge.height / 2,
            child: _TimelineRailLine(color: lineColor),
          ),
        if (hasLineAfter)
          Positioned(
            left: 21,
            top: _TimelineDateBadge.height,
            bottom: 0,
            child: _TimelineRailLine(color: lineColor),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42,
              child: Align(
                alignment: Alignment.topCenter,
                child: _TimelineDateBadge(
                  day: date.day,
                  weekday: weekday,
                  selected: true,
                  railColor: railColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < day.entries.length; index++) ...[
                    _TimelineEntry(
                      entry: day.entries[index],
                      onOpenEntry: onOpenEntry,
                      onLongSelectEntry: onLongSelectEntry,
                      selected: selectedIds.contains(day.entries[index].id),
                    ),
                    SizedBox(
                      height: index == day.entries.length - 1 ? 6 : 8,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimelineRailLine extends StatelessWidget {
  const _TimelineRailLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: 1,
      color: color,
    );
  }
}

class _TimelineDateBadge extends StatelessWidget {
  const _TimelineDateBadge({
    required this.day,
    required this.weekday,
    required this.selected,
    required this.railColor,
  });

  static const height = 46.0;

  final int day;
  final String weekday;
  final bool selected;
  final Color railColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 34,
      height: height,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: railColor.withValues(alpha: 0.28)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$day',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 19,
                    height: 1.05,
                    color:
                        selected ? colorScheme.primary : colorScheme.onSurface,
                  ),
            ),
            Text(
              weekday,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.05,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry(
      {required this.entry,
      required this.onOpenEntry,
      required this.onLongSelectEntry,
      required this.selected});

  final DiaryEntry entry;
  final ValueChanged<String> onOpenEntry;
  final ValueChanged<String> onLongSelectEntry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (_isVisibleLocation(entry.location)) entry.location,
      if (entry.weather.trim().isNotEmpty && entry.weather != '天气')
        entry.weather,
      if (_temperatureLabel(entry.temperature) != null)
        _temperatureLabel(entry.temperature)!,
    ].join(' · ');

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final shinen = theme.shinenColors;
    final radius = shinen.cardRadius;
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: isDark ? 0.1 : 0.055)
            : shinen.cardColor(colorScheme.surface, isDark),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: isDark ? 0.46 : 0.34)
              : shinen
                  .cardBorderSide(colorScheme.outlineVariant)
                  .color
                  .withValues(alpha: 0.72),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: () => onOpenEntry(entry.id),
        onLongPress: () => onLongSelectEntry(entry.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(14, 13, 13, 13),
          color: Colors.transparent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title ?? entry.bodyPreview,
                      maxLines: entry.title == null ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w400,
                            height: 1.25,
                          ),
                    ),
                    if (entry.title != null || meta.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      if (meta.isNotEmpty) ...[
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.78),
                                  ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        entry.bodyPreview,
                        maxLines: AppConstants.diaryPreviewMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.42,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: selected
                    ? Padding(
                        key: const ValueKey('selected'),
                        padding: const EdgeInsets.only(left: 10, top: 1),
                        child: Icon(Icons.check_circle,
                            size: 18, color: colorScheme.primary),
                      )
                    : const SizedBox.shrink(key: ValueKey('unselected')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
