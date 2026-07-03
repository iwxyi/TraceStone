import 'package:flutter/material.dart';

import '../../../data/models/memory_entry.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/memory_repository.dart';
import '../../../data/utils/ai_source_formatter.dart';

class MemoryManagementPage extends StatefulWidget {
  const MemoryManagementPage({super.key});

  @override
  State<MemoryManagementPage> createState() => _MemoryManagementPageState();
}

class _MemoryManagementPageState extends State<MemoryManagementPage> {
  final _repository = const MemoryRepository();
  final _developerSettings = const DeveloperSettingsRepository();
  late Future<List<MemoryEntry>> _memoriesFuture = _repository.listMemories();
  late final Future<bool> _developerModeFuture =
      _developerSettings.isDeveloperModeEnabled();

  void _refresh() {
    setState(() {
      _memoriesFuture = _repository.listMemories();
    });
  }

  Future<void> _delete(MemoryEntry memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记忆？'),
        content: const Text('删除后，AI 后续不会再主动引用这条长期记忆。原始日记不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deleteMemory(memory.id);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已删除记忆')));
  }

  Future<void> _toggleArchive(MemoryEntry memory) async {
    await _repository.archiveMemory(memory.id, archived: !memory.archived);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(memory.archived ? '已恢复记忆' : '已归档记忆'),
    ));
  }

  Future<void> _correct(MemoryEntry memory) async {
    final corrected = await showDialog<String>(
      context: context,
      builder: (context) => _MemoryCorrectionDialog(memory: memory),
    );
    if (corrected == null) return;
    await _repository.correctSummary(id: memory.id, summary: corrected);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已修正记忆')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 记忆')),
      body: FutureBuilder<List<MemoryEntry>>(
        future: _memoriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final memories = snapshot.data ?? const <MemoryEntry>[];
          if (memories.isEmpty) return const _EmptyMemoryState();
          return FutureBuilder<bool>(
            future: _developerModeFuture,
            builder: (context, developerSnapshot) {
              final developerMode = developerSnapshot.data ?? false;
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: memories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final memory = memories[index];
                    return _MemoryCard(
                      memory: memory,
                      developerMode: developerMode,
                      onDelete: () => _delete(memory),
                      onToggleArchive: () => _toggleArchive(memory),
                      onCorrect: () => _correct(memory),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyMemoryState extends StatelessWidget {
  const _EmptyMemoryState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_alt_outlined, size: 48),
            SizedBox(height: 16),
            Text('还没有长期记忆'),
            SizedBox(height: 8),
            Text('保存日记并完成 AI 整理后，这里会显示 AI 记住的内容。'),
          ],
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.memory,
    required this.developerMode,
    required this.onDelete,
    required this.onToggleArchive,
    required this.onCorrect,
  });

  final MemoryEntry memory;
  final bool developerMode;
  final VoidCallback onDelete;
  final VoidCallback onToggleArchive;
  final VoidCallback onCorrect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = [
      if (memory.emotion.isNotEmpty) memory.emotion,
      ...memory.keywords,
      ...memory.people,
      ...memory.tags,
    ];

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(memory.title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(_dateLabel(memory.date),
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                PopupMenuButton<_MemoryAction>(
                  tooltip: '记忆操作',
                  onSelected: (action) {
                    switch (action) {
                      case _MemoryAction.archive:
                        onToggleArchive();
                      case _MemoryAction.correct:
                        onCorrect();
                      case _MemoryAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _MemoryAction.archive,
                      child: Text(memory.archived ? '恢复引用' : '归档'),
                    ),
                    const PopupMenuItem(
                      value: _MemoryAction.correct,
                      child: Text('修正'),
                    ),
                    const PopupMenuItem(
                      value: _MemoryAction.delete,
                      child: Text('删除'),
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(memory.summary),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: developerMode
                  ? _developerMetricChips(memory)
                  : _userStatusChips(memory),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final chip in chips.take(12)) Chip(label: Text(chip)),
                ],
              ),
            ],
            if (developerMode) ...[
              const SizedBox(height: 12),
              Text('调试信息', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(formatAiSourceId('memory', memory.id),
                  style: theme.textTheme.bodySmall),
              Text('sourceEntry:${memory.sourceEntryId}',
                  style: theme.textTheme.bodySmall),
              Text('updatedAt:${memory.updatedAt.toIso8601String()}',
                  style: theme.textTheme.bodySmall),
              Text(
                  'lastReferencedAt:${memory.lastReferencedAt.toIso8601String()}',
                  style: theme.textTheme.bodySmall),
              if (memory.allSourceEntryIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('证据来源', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                for (final id in memory.allSourceEntryIds.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('entry:$id', style: theme.textTheme.bodySmall),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) => '${date.year}年${date.month}月${date.day}日';

  List<Widget> _userStatusChips(MemoryEntry memory) {
    return [
      _MetricChip(label: '来自 ${memory.allSourceEntryIds.length} 篇日记'),
      if (memory.archived)
        const _MetricChip(label: '已归档')
      else if (memory.confidence < 0.2)
        const _MetricChip(label: '低置信')
      else if (memory.confidence >= 0.7)
        const _MetricChip(label: '较稳定')
      else
        const _MetricChip(label: '形成中'),
    ];
  }

  List<Widget> _developerMetricChips(MemoryEntry memory) {
    return [
      _MetricChip(label: '重要度 ${memory.importance.toStringAsFixed(2)}'),
      _MetricChip(label: '置信度 ${memory.confidence.toStringAsFixed(2)}'),
      _MetricChip(label: '证据 ${memory.allSourceEntryIds.length} 篇'),
      _MetricChip(label: '引用 ${memory.referenceCount}'),
      if (memory.decay > 0)
        _MetricChip(label: '衰减 ${memory.decay.toStringAsFixed(2)}'),
      if (memory.archived) const _MetricChip(label: '已归档'),
    ];
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
    );
  }
}

class _MemoryCorrectionDialog extends StatefulWidget {
  const _MemoryCorrectionDialog({required this.memory});

  final MemoryEntry memory;

  @override
  State<_MemoryCorrectionDialog> createState() =>
      _MemoryCorrectionDialogState();
}

class _MemoryCorrectionDialogState extends State<_MemoryCorrectionDialog> {
  late final _controller = TextEditingController(text: widget.memory.summary);

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
      title: const Text('修正记忆'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        decoration: const InputDecoration(
          labelText: '更准确的记忆摘要',
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

enum _MemoryAction { archive, correct, delete }
