import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_routes.dart';
import '../../../data/models/diary_entry.dart';
import '../../../data/repositories/diary_change_bus.dart';
import '../../../data/repositories/diary_repository.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final _repository = const DiaryRepository();
  int _selectedIndex = 1;

  @override
  void initState() {
    super.initState();
    DiaryChangeBus.version.addListener(_refreshEntries);
    _loadViewPreference();
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedIndex = prefs.getInt('review.selectedIndex');
    if (selectedIndex == null || !mounted) return;
    setState(() => _selectedIndex = selectedIndex.clamp(0, 2));
  }

  Future<void> _saveViewPreference(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('review.selectedIndex', index);
  }

  @override
  void dispose() {
    DiaryChangeBus.version.removeListener(_refreshEntries);
    super.dispose();
  }

  void _refreshEntries() {
    if (!mounted) return;
    setState(() {
      _entriesFuture = _repository.listEntries();
    });
  }

  int? _selectedYear;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final Set<String> _selectedIds = <String>{};
  late Future<List<DiaryEntry>> _entriesFuture = _repository.listEntries();

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
      _entriesFuture = _repository.listEntries();
    });
  }

  void _openEntry(String id) {
    if (_isSelectionMode) {
      _toggleSelection(id);
      return;
    }
    Navigator.of(context)
        .pushNamed(AppRoutes.diaryEdit, arguments: id)
        .then((_) {
      if (mounted) {
        setState(() {
          _entriesFuture = _repository.listEntries();
        });
      }
    });
  }

  void _startSelection(String id) => _toggleSelection(id);

  String get _appBarTitle =>
      _isSelectionMode ? '已选择 ${_selectedIds.length} 篇' : '回顾';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entriesFuture = _repository.listEntries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle),
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('年')),
              ButtonSegment(value: 1, label: Text('月')),
              ButtonSegment(value: 2, label: Text('日')),
            ],
            selected: {_selectedIndex},
            onSelectionChanged: (value) {
              final index = value.first;
              setState(() => _selectedIndex = index);
              _saveViewPreference(index);
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<DiaryEntry>>(
            future: _entriesFuture,
            builder: (context, snapshot) {
              final entries = snapshot.data ?? [];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (entries.isEmpty) {
                return const _EmptyReviewCard();
              }
              final availableYears = entries
                  .map((e) => e.date.year)
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
              _selectedYear ??= availableYears.first;
              return switch (_selectedIndex) {
                0 => _YearList(
                    entries: entries,
                    selectedYear: _selectedYear!,
                    onSelectYear: (year) =>
                        setState(() => _selectedYear = year),
                    onOpenEntry: _openEntry,
                    onLongSelectEntry: _startSelection,
                    selectedIds: _selectedIds,
                  ),
                1 => _MonthCalendar(
                    entries: entries,
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
                _ => _DayTimeline(
                    entries: entries,
                    onOpenEntry: _openEntry,
                    onLongSelectEntry: _startSelection,
                    selectedIds: _selectedIds),
              };
            },
          ),
        ],
      ),
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

class _YearList extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final counts = <int, int>{};
    for (final entry in entries) {
      counts.update(entry.date.year, (value) => value + 1, ifAbsent: () => 1);
    }
    final years = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    final yearEntries = entries
        .where((e) => e.date.year == selectedYear)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

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
                selected: year == selectedYear,
                onSelected: (_) => onSelectYear(year),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final entry in yearEntries) ...[
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onOpenEntry(entry.id),
              onLongPress: () => onLongSelectEntry(entry.id),
              child: ListTile(
                title: Text(
                    entry.title ?? '${entry.date.month}月${entry.date.day}日'),
                subtitle: Text(
                  entry.bodyPreview,
                  maxLines: AppConstants.diaryPreviewMaxLines,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: selectedIds.contains(entry.id),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
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
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onSelectDay(DateTime(
                          selectedMonth.year, selectedMonth.month, day)),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.15)
                                : null,
                            border: count > 0
                                ? Border.all(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    width: 1.5)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(count > 1 ? '$day\n$count' : '$day',
                              textAlign: TextAlign.center),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
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
                Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onOpenEntry(entry.id),
                    onLongPress: () => onLongSelectEntry(entry.id),
                    child: ListTile(
                      title: Text(entry.title ?? entry.bodyPreview),
                      subtitle: entry.title == null
                          ? null
                          : Text(
                              entry.bodyPreview,
                              maxLines: AppConstants.diaryPreviewMaxLines,
                              overflow: TextOverflow.ellipsis,
                            ),
                      selected: selectedIds.contains(entry.id),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
      ],
    );
  }
}

class _DayTimeline extends StatelessWidget {
  const _DayTimeline(
      {required this.entries,
      required this.onOpenEntry,
      required this.onLongSelectEntry,
      required this.selectedIds});

  final List<DiaryEntry> entries;
  final ValueChanged<String> onOpenEntry;
  final ValueChanged<String> onLongSelectEntry;
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<DiaryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.dayKey, () => []).add(entry);
    }
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      children: [
        for (final key in keys)
          _TimelineDayGroup(
            entries: grouped[key]!,
            onOpenEntry: onOpenEntry,
            onLongSelectEntry: onLongSelectEntry,
            selectedIds: selectedIds,
          ),
      ],
    );
  }
}

class _TimelineDayGroup extends StatelessWidget {
  const _TimelineDayGroup(
      {required this.entries,
      required this.onOpenEntry,
      required this.onLongSelectEntry,
      required this.selectedIds});

  final List<DiaryEntry> entries;
  final ValueChanged<String> onOpenEntry;
  final ValueChanged<String> onLongSelectEntry;
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final date = sorted.first.date;
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final title = '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 34, bottom: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (var i = 0; i < sorted.length; i++)
            _TimelineEntry(
              entry: sorted[i],
              isLast: i == sorted.length - 1,
              onOpenEntry: onOpenEntry,
              onLongSelectEntry: onLongSelectEntry,
              selected: selectedIds.contains(sorted[i].id),
            ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry(
      {required this.entry,
      required this.isLast,
      required this.onOpenEntry,
      required this.onLongSelectEntry,
      required this.selected});

  final DiaryEntry entry;
  final bool isLast;
  final ValueChanged<String> onOpenEntry;
  final ValueChanged<String> onLongSelectEntry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (entry.location.trim().isNotEmpty &&
          entry.location != '未选择地点' &&
          entry.location != '点击选择地点')
        entry.location,
      if (entry.weather.trim().isNotEmpty && entry.weather != '天气')
        entry.weather,
      if (entry.temperature?.trim().isNotEmpty ?? false) entry.temperature!,
    ].join(' · ');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary),
                ),
                if (!isLast)
                  Expanded(
                      child: Container(
                          width: 1,
                          color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
          Expanded(
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onOpenEntry(entry.id),
                onLongPress: () => onLongSelectEntry(entry.id),
                child: ListTile(
                  selected: selected,
                  title: Text(entry.title ?? entry.bodyPreview),
                  subtitle: meta.isEmpty
                      ? (entry.title == null
                          ? null
                          : Text(
                              entry.bodyPreview,
                              maxLines: AppConstants.diaryPreviewMaxLines,
                              overflow: TextOverflow.ellipsis,
                            ))
                      : Text(
                          '$meta\n${entry.bodyPreview}',
                          maxLines: AppConstants.diaryPreviewMaxLines + 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  isThreeLine: entry.title != null || meta.isNotEmpty,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
