import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/diary_entry.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/models/stone_task.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/repositories/stone_task_repository.dart';

class ShapingStonePage extends StatefulWidget {
  const ShapingStonePage({super.key});

  @override
  State<ShapingStonePage> createState() => _ShapingStonePageState();
}

class _ShapingStonePageState extends State<ShapingStonePage> {
  final _repository = const InsightRepository();
  final _diaryRepository = const DiaryRepository();
  final _taskRepository = const StoneTaskRepository();
  late Future<_StonePageData> _dataFuture = _loadData();

  Future<_StonePageData> _loadData() async {
    final insights = await _repository.listInsights();
    final tasks = await _taskRepository.listTasks();
    final entries = await _diaryRepository.listEntries();
    final taskSourceIds = tasks.map((task) => task.sourceEntryId).toSet();
    final candidates = [
      for (final insight in insights)
        if (insight.stoneTitle.trim().isNotEmpty ||
            insight.stoneDescription.trim().isNotEmpty)
          if (!taskSourceIds.contains(insight.entryId))
            _StoneCandidate(insight: insight),
    ];
    candidates.sort((a, b) => b.date.compareTo(a.date));
    return _StonePageData(
      tasks: tasks,
      candidates: candidates,
      progressHints: {
        for (final task in tasks) task.id: _progressHints(task, entries),
      },
    );
  }

  List<_StoneProgressHint> _progressHints(
    StoneTask task,
    List<DiaryEntry> entries,
  ) {
    if (task.isCompleted) return const [];
    final taskTokens = _tokens([
      task.title,
      task.description,
      ...task.tags,
    ].join(' '));
    if (taskTokens.isEmpty) return const [];
    final hints = <_StoneProgressHint>[];
    for (final entry in entries) {
      if (entry.id == task.sourceEntryId) continue;
      if (entry.date.isBefore(task.createdAt)) continue;
      final entryTokens = _tokens(entry.content);
      final matched = taskTokens.where(entryTokens.contains).take(5).toList();
      if (matched.length < 2) continue;
      hints.add(_StoneProgressHint(
        entry: entry,
        matchedTokens: matched,
      ));
    }
    hints.sort((a, b) => b.entry.date.compareTo(a.entry.date));
    return hints.take(2).toList(growable: false);
  }

  Future<void> _refresh() async {
    setState(() {
      _dataFuture = _loadData();
    });
    await _dataFuture;
  }

  Future<void> _addCandidate(_StoneCandidate candidate) async {
    final insight = candidate.insight;
    final now = DateTime.now();
    await _taskRepository.saveTask(StoneTask(
      id: 'stone:${insight.entryId}',
      sourceEntryId: insight.entryId,
      title: insight.stoneTitle.isEmpty ? '未命名行动' : insight.stoneTitle,
      description: insight.stoneDescription,
      createdAt: now,
      updatedAt: now,
      dueDate: DateTime(now.year, now.month, now.day + 1),
      tags: [
        ...insight.keywords.take(4),
        if (insight.emotion.isNotEmpty) insight.emotion,
      ],
    ));
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已收藏这一步')),
    );
  }

  Future<void> _setCompleted(StoneTask task, bool completed) async {
    await _taskRepository.setCompleted(task.id, completed);
    await _refresh();
  }

  Future<void> _addCheckIn(StoneTask task) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => const _StoneCheckInDialog(),
    );
    if (note == null) return;
    await _taskRepository.addCheckIn(task.id, note: note);
    await _refresh();
  }

  Future<void> _editTask(StoneTask task) async {
    final updated = await showDialog<StoneTask>(
      context: context,
      builder: (context) => _StoneTaskEditDialog(task: task),
    );
    if (updated == null) return;
    await _taskRepository.saveTask(updated);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('成长线索')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_StonePageData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data ?? const _StonePageData();
            if (data.tasks.isEmpty && data.candidates.isEmpty) {
              return const _EmptyStoneState();
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const _StoneHeader(),
                if (data.tasks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionTitle(
                      title: '收藏的一小步', subtitle: '${data.tasks.length} 条'),
                  const SizedBox(height: 8),
                  for (final task in data.tasks) ...[
                    _StoneTaskCard(
                      task: task,
                      progressHints: data.progressHints[task.id] ?? const [],
                      onCompletedChanged: (value) => _setCompleted(task, value),
                      onEdit: () => _editTask(task),
                      onCheckIn: () => _addCheckIn(task),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                if (data.candidates.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _SectionTitle(
                      title: '可以轻轻尝试', subtitle: '${data.candidates.length} 条'),
                  const SizedBox(height: 8),
                  for (final candidate in data.candidates) ...[
                    _StoneCandidateCard(
                      candidate: candidate,
                      onAdd: () => _addCandidate(candidate),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _StoneTaskCard extends StatelessWidget {
  const _StoneTaskCard({
    required this.task,
    required this.progressHints,
    required this.onCompletedChanged,
    required this.onEdit,
    required this.onCheckIn,
  });

  final StoneTask task;
  final List<_StoneProgressHint> progressHints;
  final ValueChanged<bool> onCompletedChanged;
  final VoidCallback onEdit;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: theme.cardTheme.elevation ?? 0,
      color: theme.cardTheme.color,
      shape: theme.cardTheme.shape,
      child: CheckboxListTile(
        value: task.isCompleted,
        onChanged: (value) => onCompletedChanged(value ?? false),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              SimpleMarkdownText(text: task.description),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (task.dueDate != null)
                  Chip(label: Text('建议 ${_dateLabel(task.dueDate!)}')),
                if (task.checkIns.isNotEmpty)
                  Chip(label: Text('进展 ${task.checkIns.length} 次')),
                for (final tag in task.tags.take(4)) Chip(label: Text(tag)),
              ],
            ),
            if (task.checkIns.isNotEmpty) ...[
              const SizedBox(height: 8),
              _StoneCheckInPreview(checkIn: task.checkIns.first),
            ],
            if (progressHints.isNotEmpty) ...[
              const SizedBox(height: 10),
              _StoneProgressHintBox(
                hints: progressHints,
                onCompleted: () => onCompletedChanged(true),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: task.isCompleted ? null : onCheckIn,
                    icon: const Icon(Icons.add_task_outlined),
                    label: const Text('写下变化'),
                  ),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                ],
              ),
            ),
          ],
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }
}

class _StoneCheckInDialog extends StatefulWidget {
  const _StoneCheckInDialog();

  @override
  State<_StoneCheckInDialog> createState() => _StoneCheckInDialogState();
}

class _StoneCheckInDialogState extends State<_StoneCheckInDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('记录一点进展'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: '例如：今天晚饭后散步了 8 分钟，状态轻了一点。',
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

class _StoneCheckInPreview extends StatelessWidget {
  const _StoneCheckInPreview({required this.checkIn});

  final StoneTaskCheckIn checkIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shinen = theme.shinenColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: shinen.cardColor(
          theme.colorScheme.surfaceContainerHighest,
          theme.brightness == Brightness.dark,
        ),
        borderRadius: BorderRadius.circular(shinen.cardRadius - 2),
        border: Border.all(
            color:
                shinen.cardBorderSide(theme.colorScheme.outlineVariant).color),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.flag_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_dateLabel(checkIn.createdAt)}｜${checkIn.note.isEmpty ? '记录了一次进展' : checkIn.note}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoneTaskEditDialog extends StatefulWidget {
  const _StoneTaskEditDialog({required this.task});

  final StoneTask task;

  @override
  State<_StoneTaskEditDialog> createState() => _StoneTaskEditDialogState();
}

class _StoneTaskEditDialogState extends State<_StoneTaskEditDialog> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.task.title);
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.task.description);
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _dueDate = widget.task.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() => _dueDate = picked);
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(widget.task.copyWith(
      title: title,
      description: _descriptionController.text.trim(),
      dueDate: _dueDate,
      updatedAt: DateTime.now(),
      clearDueDate: _dueDate == null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑这一小步'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '标题'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: '描述'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(_dueDate == null
                      ? '未设置建议日期'
                      : '建议 ${_dateLabel(_dueDate!)}'),
                ),
                IconButton(
                  tooltip: '选择日期',
                  onPressed: _pickDueDate,
                  icon: const Icon(Icons.event_outlined),
                ),
                IconButton(
                  tooltip: '清除日期',
                  onPressed: _dueDate == null
                      ? null
                      : () => setState(() => _dueDate = null),
                  icon: const Icon(Icons.event_busy_outlined),
                ),
              ],
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
}

class _StoneProgressHintBox extends StatelessWidget {
  const _StoneProgressHintBox({
    required this.hints,
    required this.onCompleted,
  });

  final List<_StoneProgressHint> hints;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shinen = theme.shinenColors;
    final latest = hints.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(
          alpha: shinen.chipStyle == ShinenChipStyle.ghost ? 0.2 : 0.45,
        ),
        borderRadius: BorderRadius.circular(shinen.controlRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.task_alt_outlined,
                    size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '最近日记可能提到了这一步',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_dateLabel(latest.entry.date)}｜${latest.entry.excerpt}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final token in latest.matchedTokens)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(token),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCompleted,
                icon: const Icon(Icons.check),
                label: const Text('记为有变化'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoneHeader extends StatelessWidget {
  const _StoneHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('把变化留在日常里',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('这里收藏 AI 从日记中整理出的温和建议。它们不是任务，也不需要打卡，只是在合适的时候提醒你：有些小变化已经在发生。'),
        ],
      ),
    );
  }
}

class _StoneCandidateCard extends StatelessWidget {
  const _StoneCandidateCard({required this.candidate, required this.onAdd});

  final _StoneCandidate candidate;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final insight = candidate.insight;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.self_improvement_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    insight.stoneTitle.isEmpty ? '未命名行动' : insight.stoneTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(_dateLabel(candidate.date),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (insight.stoneDescription.isNotEmpty) ...[
              const SizedBox(height: 10),
              SimpleMarkdownText(text: insight.stoneDescription),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (insight.emotion.isNotEmpty)
                  Chip(label: Text(insight.emotion)),
                for (final keyword in insight.keywords.take(4))
                  Chip(label: Text(keyword)),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('收藏这一步'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';
}

class _EmptyStoneState extends StatelessWidget {
  const _EmptyStoneState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.self_improvement_outlined, size: 48),
        SizedBox(height: 16),
        Text(
          '完成 AI 洞察后，这里会出现可以轻轻尝试的一小步。没有任务，也不需要打卡。',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StoneCandidate {
  const _StoneCandidate({required this.insight});

  final DiaryInsight insight;

  DateTime get date => insight.entryDate;
}

class _StonePageData {
  const _StonePageData({
    this.tasks = const [],
    this.candidates = const [],
    this.progressHints = const {},
  });

  final List<StoneTask> tasks;
  final List<_StoneCandidate> candidates;
  final Map<String, List<_StoneProgressHint>> progressHints;
}

String _dateLabel(DateTime date) => '${date.year}年${date.month}月${date.day}日';

class _StoneProgressHint {
  const _StoneProgressHint({
    required this.entry,
    required this.matchedTokens,
  });

  final DiaryEntry entry;
  final List<String> matchedTokens;
}

Set<String> _tokens(String text) {
  final cleaned = text
      .replaceAll(
          RegExp(r'[\s\n\r\t，。！？；：、“”‘’（）《》【】,.!?;:#>*_`\[\](){}/\\-]+'), ' ')
      .trim();
  final tokens = <String>{};
  for (final part in cleaned.split(' ')) {
    final value = part.trim();
    if (value.length >= 2) tokens.add(value);
    if (value.length >= 4) {
      for (var i = 0; i <= value.length - 2; i++) {
        tokens.add(value.substring(i, i + 2));
      }
    }
  }
  return tokens;
}
