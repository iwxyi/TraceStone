import 'package:flutter/material.dart';

import '../../../data/models/calendar_memory.dart';
import '../../../data/repositories/calendar_memory_repository.dart';

class CalendarMemoryPage extends StatefulWidget {
  const CalendarMemoryPage({super.key});

  @override
  State<CalendarMemoryPage> createState() => _CalendarMemoryPageState();
}

class _CalendarMemoryPageState extends State<CalendarMemoryPage> {
  final _repository = const CalendarMemoryRepository();
  List<CalendarMemory> _memories = const [];
  Object? _loadError;
  bool _loadingInitial = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadMemories(showLoading: true);
  }

  Future<void> _loadMemories({bool showLoading = false}) async {
    final generation = ++_loadGeneration;
    if (showLoading) {
      setState(() {
        _loadingInitial = true;
        _loadError = null;
      });
    }
    try {
      final memories = await _repository.listMemories();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _memories = memories;
        _loadError = null;
        _loadingInitial = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loadingInitial = false;
      });
    }
  }

  Future<void> _edit([CalendarMemory? memory]) async {
    final updated = await showDialog<CalendarMemory>(
      context: context,
      builder: (context) => _CalendarMemoryDialog(memory: memory),
    );
    if (updated == null) return;
    await _repository.saveMemory(updated);
    await _loadMemories();
  }

  Future<void> _setEnabled(CalendarMemory memory, bool enabled) async {
    await _repository.saveMemory(memory.copyWith(
      enabled: enabled,
      updatedAt: DateTime.now(),
    ));
    await _loadMemories();
  }

  Future<void> _delete(CalendarMemory memory) async {
    await _repository.deleteMemory(memory.id);
    if (!mounted) return;
    setState(() {
      _memories = _memories
          .where((item) => item.id != memory.id)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已删除纪念日'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await _repository.saveMemory(memory);
            if (mounted) await _loadMemories();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('纪念日')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('新增'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMemories,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingInitial && _memories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _memories.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _loadMemories(showLoading: true),
          icon: const Icon(Icons.refresh),
          label: const Text('加载失败，点击重试'),
        ),
      );
    }
    if (_memories.isEmpty) {
      return const _EmptyCalendarMemoryState();
    }
    return ListView.separated(
      key: const PageStorageKey('calendar-memory-list'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      itemCount: _memories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final memory = _memories[index];
        return _CalendarMemoryCard(
          memory: memory,
          onEnabledChanged: (value) => _setEnabled(memory, value),
          onEdit: () => _edit(memory),
          onDelete: () => _delete(memory),
        );
      },
    );
  }
}

class _CalendarMemoryCard extends StatelessWidget {
  const _CalendarMemoryCard({
    required this.memory,
    required this.onEnabledChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final CalendarMemory memory;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
                Icon(
                  Icons.event_available_outlined,
                  color: memory.enabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    memory.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Switch(
                  value: memory.enabled,
                  onChanged: onEnabledChanged,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${memory.type == CalendarMemoryType.lunar ? '农历' : '阳历'} '
              '${memory.month}月${memory.day}日',
            ),
            if (memory.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(memory.note),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarMemoryDialog extends StatefulWidget {
  const _CalendarMemoryDialog({this.memory});

  final CalendarMemory? memory;

  @override
  State<_CalendarMemoryDialog> createState() => _CalendarMemoryDialogState();
}

class _CalendarMemoryDialogState extends State<_CalendarMemoryDialog> {
  late final _titleController =
      TextEditingController(text: widget.memory?.title ?? '');
  late final _noteController =
      TextEditingController(text: widget.memory?.note ?? '');
  late int _month = widget.memory?.month ?? DateTime.now().month;
  late int _day = widget.memory?.day ?? DateTime.now().day;
  late CalendarMemoryType _type =
      widget.memory?.type ?? CalendarMemoryType.solar;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final now = DateTime.now();
    Navigator.of(context).pop(CalendarMemory(
      id: widget.memory?.id ?? 'calendar:${now.microsecondsSinceEpoch}',
      title: title,
      month: _month,
      day: _day,
      createdAt: widget.memory?.createdAt ?? now,
      updatedAt: now,
      type: _type,
      note: _noteController.text.trim(),
      enabled: widget.memory?.enabled ?? true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final maxDay = _maxDay;
    if (_day > maxDay) _day = maxDay;
    return AlertDialog(
      title: Text(widget.memory == null ? '新增纪念日' : '编辑纪念日'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<CalendarMemoryType>(
              segments: const [
                ButtonSegment(
                  value: CalendarMemoryType.solar,
                  label: Text('阳历'),
                  icon: Icon(Icons.wb_sunny_outlined),
                ),
                ButtonSegment(
                  value: CalendarMemoryType.lunar,
                  label: Text('农历'),
                  icon: Icon(Icons.nightlight_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (values) {
                final selected = values.first;
                setState(() {
                  _type = selected;
                  if (_day > _maxDay) _day = _maxDay;
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    decoration: const InputDecoration(labelText: '月'),
                    items: [
                      for (var value = 1; value <= 12; value++)
                        DropdownMenuItem(value: value, child: Text('$value 月')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _month = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _day,
                    decoration: const InputDecoration(labelText: '日'),
                    items: [
                      for (var value = 1; value <= maxDay; value++)
                        DropdownMenuItem(value: value, child: Text('$value 日')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _day = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '例如：每年这天和外婆有关',
              ),
            ),
          ],
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

  int _daysInMonth(int month) {
    const days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return days[month - 1];
  }

  int get _maxDay =>
      _type == CalendarMemoryType.lunar ? 30 : _daysInMonth(_month);
}

class _EmptyCalendarMemoryState extends StatelessWidget {
  const _EmptyCalendarMemoryState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.event_note_outlined, size: 48),
        SizedBox(height: 16),
        Text(
          '添加重要纪念日后，AI 在“多年今日”里会优先关联这些日期。',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
