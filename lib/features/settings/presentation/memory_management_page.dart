import 'package:flutter/material.dart';

import '../../../data/models/memory_entry.dart';
import '../../../data/repositories/memory_repository.dart';

class MemoryManagementPage extends StatefulWidget {
  const MemoryManagementPage({super.key});

  @override
  State<MemoryManagementPage> createState() => _MemoryManagementPageState();
}

class _MemoryManagementPageState extends State<MemoryManagementPage> {
  final _repository = const MemoryRepository();
  late Future<List<MemoryEntry>> _memoriesFuture = _repository.listMemories();

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
                  onDelete: () => _delete(memory),
                );
              },
            ),
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
    required this.onDelete,
  });

  final MemoryEntry memory;
  final VoidCallback onDelete;

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
                IconButton(
                  tooltip: '删除记忆',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(memory.summary),
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
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) => '${date.year}年${date.month}月${date.day}日';
}
