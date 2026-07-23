import 'package:flutter/material.dart';

import '../../../data/repositories/diary_repository.dart';
import '../../../data/services/ai_analysis_queue_runner.dart';

class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  final _repository = const DiaryRepository();
  final _queueRunner = const AiAnalysisQueueRunner();
  List<DiaryTrashItem> _items = const [];
  Object? _loadError;
  bool _loadingInitial = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadItems(showLoading: true);
  }

  Future<void> _loadItems({bool showLoading = false}) async {
    final generation = ++_loadGeneration;
    if (showLoading) {
      setState(() {
        _loadingInitial = true;
        _loadError = null;
      });
    }
    try {
      final items = await _repository.listTrashEntries();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _items = items;
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

  Future<void> _restore(DiaryTrashItem item) async {
    await _repository.restoreFromTrash(item.entry.id);
    await _queueRunner.enqueue(item.entry, start: false);
    if (!mounted) return;
    setState(() {
      _items = _items
          .where((trashItem) => trashItem.entry.id != item.entry.id)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已恢复日记')));
  }

  Future<void> _deletePermanently(DiaryTrashItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除这篇日记？'),
        content: const Text('永久删除后无法从回收站恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.permanentlyDeleteFromTrash(item.entry.id);
    if (!mounted) return;
    setState(() {
      _items = _items
          .where((trashItem) => trashItem.entry.id != item.entry.id)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已永久删除')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingInitial && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _items.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _loadItems(showLoading: true),
          icon: const Icon(Icons.refresh),
          label: const Text('加载失败，点击重试'),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('回收站是空的'));
    }
    return RefreshIndicator(
      onRefresh: _loadItems,
      child: ListView.separated(
        key: const PageStorageKey('recycle-bin-list'),
        padding: const EdgeInsets.all(20),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _items[index];
          return _TrashEntryCard(
            item: item,
            onRestore: () => _restore(item),
            onDelete: () => _deletePermanently(item),
          );
        },
      ),
    );
  }
}

class _TrashEntryCard extends StatelessWidget {
  const _TrashEntryCard({
    required this.item,
    required this.onRestore,
    required this.onDelete,
  });

  final DiaryTrashItem item;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final title = entry.title ?? '${entry.date.month}月${entry.date.day}日';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                Text('剩余 ${item.daysRemaining} 天',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entry.bodyPreview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('永久删除'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore),
                  label: const Text('恢复'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
