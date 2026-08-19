import 'package:flutter/material.dart';

import '../../../data/models/diary_entry.dart';
import '../../../data/models/webdav_config.dart';
import '../../../data/repositories/webdav_config_repository.dart';
import '../../../data/services/webdav_sync_service.dart';

class WebDavSyncPage extends StatefulWidget {
  const WebDavSyncPage({super.key});

  @override
  State<WebDavSyncPage> createState() => _WebDavSyncPageState();
}

class _WebDavSyncPageState extends State<WebDavSyncPage> {
  final _repository = const WebDavConfigRepository();
  final _service = const WebDavSyncService();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _remoteRootController = TextEditingController(text: '/Shinen');

  WebDavConfig _config = WebDavConfig.empty;
  WebDavSyncProgress? _progress;
  String _status = '';
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remoteRootController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await _repository.loadConfig();
    if (!mounted) return;
    setState(() {
      _config = config;
      _urlController.text = config.url;
      _usernameController.text = config.username;
      _passwordController.text = config.password;
      _remoteRootController.text = config.remoteRoot;
      _loading = false;
    });
  }

  WebDavConfig _currentConfig() {
    return _config.copyWith(
      url: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      remoteRoot: _remoteRootController.text.trim().isEmpty
          ? '/Shinen'
          : _remoteRootController.text.trim(),
    );
  }

  Future<void> _save() async {
    await _run('保存配置', () async {
      final next = _currentConfig();
      await _repository.saveConfig(next);
      setState(() => _config = next);
      return 'WebDAV 配置已保存';
    });
  }

  Future<void> _testConnection() async {
    await _run('测试连接', () async {
      final next = _currentConfig();
      await _repository.saveConfig(next);
      await _service.testConnection(next);
      setState(() => _config = next);
      return '连接成功';
    });
  }

  Future<void> _backup() async {
    await _run('备份', () async {
      await _repository.saveConfig(_currentConfig());
      final result = await _service.backupAll(onProgress: _setProgress);
      await _load();
      return '已备份 ${result.entryCount} 篇日记、${result.mediaCount} 个附件、${result.dataItemCount} 项数据';
    });
  }

  Future<void> _restore() async {
    if (_working) return;
    await _repository.saveConfig(_currentConfig());
    if (!mounted) return;
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WebDavRestorePage()),
    );
    if (restored == true) {
      await _load();
      if (!mounted) return;
      setState(() => _status = '恢复完成');
    }
  }

  void _setProgress(WebDavSyncProgress progress) {
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  Future<void> _run(
    String stage,
    Future<String> Function() action,
  ) async {
    if (_working) return;
    setState(() {
      _working = true;
      _status = '$stage中';
      _progress = null;
    });
    try {
      final message = await action();
      if (!mounted) return;
      setState(() {
        _status = message;
        _progress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '$stage失败：$error';
        _progress = null;
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('WebDAV 备份')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 备份')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _urlController,
                    enabled: !_working,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'https://example.com/dav',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _usernameController,
                    enabled: !_working,
                    decoration: const InputDecoration(
                      labelText: '账号',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    enabled: !_working,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '密码或应用密码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _remoteRootController,
                    enabled: !_working,
                    decoration: const InputDecoration(
                      labelText: '远端目录',
                      hintText: '/Shinen',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _working ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('保存'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _testConnection,
                        icon: const Icon(Icons.cloud_done_outlined),
                        label: const Text('测试'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '日记备份',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                      label: '上次备份', value: _timeLabel(_config.lastBackupAt)),
                  _InfoRow(
                      label: '上次恢复', value: _timeLabel(_config.lastRestoreAt)),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(_status),
                  ],
                  if (_progress != null) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: _progress!.fraction),
                    const SizedBox(height: 6),
                    Text(
                      '${_progress!.stage} ${_progress!.completed}/${_progress!.total}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _working ? null : _backup,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('立即备份'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _restore,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('从备份恢复'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeLabel(DateTime? value) {
    if (value == null) return '从未';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}

class WebDavRestorePage extends StatefulWidget {
  const WebDavRestorePage({super.key});

  @override
  State<WebDavRestorePage> createState() => _WebDavRestorePageState();
}

class _WebDavRestorePageState extends State<WebDavRestorePage> {
  final _service = const WebDavSyncService();
  WebDavRestorePreview? _preview;
  WebDavSyncProgress? _progress;
  Set<String> _selectedRemoteIds = const {};
  Set<String> _selectedLocalOnlyIds = const {};
  String? _error;
  bool _loading = true;
  bool _working = false;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = null;
    });
    try {
      final preview = await _service.previewRestore(onProgress: _setProgress);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _selectedRemoteIds =
            preview.entriesToRestore.map((entry) => entry.id).toSet();
        _selectedLocalOnlyIds =
            preview.localOnlyEntries.map((entry) => entry.id).toSet();
        _loading = false;
        _progress = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
        _progress = null;
      });
    }
  }

  void _setProgress(WebDavSyncProgress progress) {
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  Future<void> _merge() => _restore(overwriteLocal: false);

  Future<void> _overwriteLocal() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('覆盖本地数据？'),
        content: const Text(
          '这会按云端备份重建本地数据，云端没有的本地日记会被彻底删除。建议只在测试还原或明确需要回滚时使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('覆盖本地'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _restore(overwriteLocal: true);
    }
  }

  Future<void> _restore({required bool overwriteLocal}) async {
    final preview = _preview;
    if (preview == null || _working) return;
    setState(() {
      _working = true;
      _progress = null;
      _error = null;
    });
    try {
      final result = await _service.restorePreview(
        preview,
        overwriteLocal: overwriteLocal,
        selectedEntryIds: _selectedRemoteIds,
        selectedLocalOnlyIds: overwriteLocal ? _selectedLocalOnlyIds : const {},
        onProgress: _setProgress,
      );
      if (!mounted) return;
      setState(() {
        _restored = true;
        _working = false;
        _progress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已恢复 ${result.importedCount} 篇、${result.mediaCount} 个附件、${result.dataItemCount} 项数据，跳过 ${result.skippedCount} 篇',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = '$error';
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_working) Navigator.of(context).pop(_restored);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('云端恢复')),
        body: _loading
            ? _LoadingRestore(progress: _progress)
            : _error != null
                ? _RestoreError(message: _error!, onRetry: _loadPreview)
                : _RestorePreviewBody(
                    preview: preview!,
                    selectedRemoteIds: _selectedRemoteIds,
                    selectedLocalOnlyIds: _selectedLocalOnlyIds,
                    onRemoteSelectionChanged: (ids) {
                      setState(() => _selectedRemoteIds = ids);
                    },
                    onLocalOnlySelectionChanged: (ids) {
                      setState(() => _selectedLocalOnlyIds = ids);
                    },
                  ),
        bottomNavigationBar: preview == null || _loading || _error != null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _working || _selectedRemoteIds.isEmpty
                              ? null
                              : _merge,
                          icon: _working
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.merge_outlined),
                          label: const Text('合并'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      PopupMenuButton<String>(
                        enabled: !_working,
                        tooltip: '更多',
                        onSelected: (value) {
                          if (value == 'overwrite') _overwriteLocal();
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'overwrite',
                            child: Text('覆盖本地'),
                          ),
                        ],
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.more_horiz),
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

class _RestorePreviewBody extends StatefulWidget {
  const _RestorePreviewBody({
    required this.preview,
    required this.selectedRemoteIds,
    required this.selectedLocalOnlyIds,
    required this.onRemoteSelectionChanged,
    required this.onLocalOnlySelectionChanged,
  });

  final WebDavRestorePreview preview;
  final Set<String> selectedRemoteIds;
  final Set<String> selectedLocalOnlyIds;
  final ValueChanged<Set<String>> onRemoteSelectionChanged;
  final ValueChanged<Set<String>> onLocalOnlySelectionChanged;

  @override
  State<_RestorePreviewBody> createState() => _RestorePreviewBodyState();
}

class _RestorePreviewBodyState extends State<_RestorePreviewBody> {
  int _tab = 0;
  int _selected = 0;
  bool _showLocalVersion = false;

  List<_RestorePreviewItem> get _items {
    final preview = widget.preview;
    switch (_tab) {
      case 0:
        return [
          for (final entry in preview.importEntries)
            _RestorePreviewItem(entry: entry, type: '新增'),
        ];
      case 1:
        return [
          for (final change in preview.updateEntries)
            _RestorePreviewItem.update(
                remote: change.remote, local: change.local),
        ];
      case 2:
        return [
          for (final entry in preview.skippedEntries)
            _RestorePreviewItem(entry: entry, type: '跳过', detail: '本地已是最新'),
          for (final file in preview.invalidFiles)
            _RestorePreviewItem.invalid(file),
        ];
      case 3:
        return [
          for (final entry in preview.localOnlyEntries)
            _RestorePreviewItem(
              entry: entry,
              type: '本地',
              detail: '云端没有',
            ),
        ];
      default:
        return const [];
    }
  }

  bool get _isSelectableTab => _tab == 0 || _tab == 1;

  Set<String> get _checkedIds =>
      _tab == 3 ? widget.selectedLocalOnlyIds : widget.selectedRemoteIds;

  void _setCheckedIds(Set<String> ids) {
    if (_tab == 3) {
      widget.onLocalOnlySelectionChanged(ids);
    } else {
      widget.onRemoteSelectionChanged(ids);
    }
  }

  void _selectAllVisible() {
    final ids =
        _items.map((item) => item.entry?.id).whereType<String>().toSet();
    _setCheckedIds({..._checkedIds, ...ids});
  }

  void _invertVisible() {
    final visibleIds =
        _items.map((item) => item.entry?.id).whereType<String>().toSet();
    final next = _checkedIds.toSet();
    for (final id in visibleIds) {
      if (!next.remove(id)) next.add(id);
    }
    _setCheckedIds(next);
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final items = _items;
    final selected =
        items.isEmpty ? null : items[_selected.clamp(0, items.length - 1)];
    final detailItem = selected == null
        ? null
        : selected.localEntry != null && _showLocalVersion
            ? selected.localVersion()
            : selected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text('新增 ${preview.importCount}')),
              ButtonSegment(value: 1, label: Text('更新 ${preview.updateCount}')),
              ButtonSegment(
                  value: 2, label: Text('跳过 ${preview.skippedCount}')),
              ButtonSegment(
                value: 3,
                label: Text('本地独有 ${preview.localOnlyCount}'),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (value) {
              setState(() {
                _tab = value.first;
                _selected = 0;
                _showLocalVersion = false;
              });
            },
          ),
          if (_isSelectableTab) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _selectAllVisible,
                  child: const Text('全选'),
                ),
                OutlinedButton(
                  onPressed: _invertVisible,
                  child: const Text('反选'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                if (compact) {
                  return _CompactPreviewList(
                    items: items,
                    selected: selected,
                    detailItem: detailItem,
                    checkedIds: _checkedIds,
                    selectable: _isSelectableTab,
                    onCheckChanged: _setCheckedIds,
                    onSelect: (index) => setState(() {
                      _selected = index;
                      _showLocalVersion = false;
                    }),
                    onSelectVersion: (index, showLocal) => setState(() {
                      _selected = index;
                      _showLocalVersion = showLocal;
                    }),
                  );
                }
                return Row(
                  children: [
                    SizedBox(
                      width: constraints.maxWidth < 860 ? 340 : 420,
                      child: _PreviewList(
                        items: items,
                        selectedIndex: _selected,
                        checkedIds: _checkedIds,
                        selectable: _isSelectableTab,
                        onCheckChanged: _setCheckedIds,
                        onSelect: (index) => setState(() {
                          _selected = index;
                          _showLocalVersion = false;
                        }),
                        onSelectVersion: (index, showLocal) => setState(() {
                          _selected = index;
                          _showLocalVersion = showLocal;
                        }),
                      ),
                    ),
                    const VerticalDivider(width: 24),
                    Expanded(child: _PreviewDetail(item: detailItem)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingRestore extends StatelessWidget {
  const _LoadingRestore({required this.progress});

  final WebDavSyncProgress? progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(progress == null
                ? '正在读取云端备份'
                : '${progress!.stage} ${progress!.completed}/${progress!.total}'),
          ],
        ),
      ),
    );
  }
}

class _RestoreError extends StatelessWidget {
  const _RestoreError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('读取失败：$message', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _CompactPreviewList extends StatelessWidget {
  const _CompactPreviewList({
    required this.items,
    required this.selected,
    required this.detailItem,
    required this.checkedIds,
    required this.selectable,
    required this.onCheckChanged,
    required this.onSelect,
    required this.onSelectVersion,
  });

  final List<_RestorePreviewItem> items;
  final _RestorePreviewItem? selected;
  final _RestorePreviewItem? detailItem;
  final Set<String> checkedIds;
  final bool selectable;
  final ValueChanged<Set<String>> onCheckChanged;
  final ValueChanged<int> onSelect;
  final void Function(int index, bool showLocal) onSelectVersion;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: _PreviewList(
            items: items,
            selectedIndex: selected == null ? 0 : items.indexOf(selected!),
            checkedIds: checkedIds,
            selectable: selectable,
            onCheckChanged: onCheckChanged,
            onSelect: onSelect,
            onSelectVersion: onSelectVersion,
          ),
        ),
        const Divider(height: 18),
        Expanded(child: _PreviewDetail(item: detailItem)),
      ],
    );
  }
}

class _PreviewList extends StatelessWidget {
  const _PreviewList({
    required this.items,
    required this.selectedIndex,
    required this.checkedIds,
    required this.selectable,
    required this.onCheckChanged,
    required this.onSelect,
    required this.onSelectVersion,
  });

  final List<_RestorePreviewItem> items;
  final int selectedIndex;
  final Set<String> checkedIds;
  final bool selectable;
  final ValueChanged<Set<String>> onCheckChanged;
  final ValueChanged<int> onSelect;
  final void Function(int index, bool showLocal) onSelectVersion;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('没有内容'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = index == selectedIndex;
        final id = item.entry?.id;
        final checked = id != null && checkedIds.contains(id);
        if (item.localEntry != null) {
          return _UpdatePreviewTile(
            item: item,
            selected: selected,
            checked: checked,
            onCheckChanged: (value) {
              if (id == null) return;
              final next = checkedIds.toSet();
              if (value == true) {
                next.add(id);
              } else {
                next.remove(id);
              }
              onCheckChanged(next);
            },
            onSelectLocal: () => onSelectVersion(index, true),
            onSelectRemote: () => onSelectVersion(index, false),
          );
        }
        return ListTile(
          selected: selected,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          dense: true,
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: CircleAvatar(
            radius: 15,
            child: selectable && id != null
                ? Checkbox(
                    value: checked,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (value) {
                      final next = checkedIds.toSet();
                      if (value == true) {
                        next.add(id);
                      } else {
                        next.remove(id);
                      }
                      onCheckChanged(next);
                    },
                  )
                : Text(item.type.characters.first),
          ),
          onTap: () {
            onSelect(index);
            if (selectable && id != null) {
              final next = checkedIds.toSet();
              if (!next.remove(id)) next.add(id);
              onCheckChanged(next);
            }
          },
        );
      },
    );
  }
}

class _UpdatePreviewTile extends StatelessWidget {
  const _UpdatePreviewTile({
    required this.item,
    required this.selected,
    required this.checked,
    required this.onCheckChanged,
    required this.onSelectLocal,
    required this.onSelectRemote,
  });

  final _RestorePreviewItem item;
  final bool selected;
  final bool checked;
  final ValueChanged<bool?> onCheckChanged;
  final VoidCallback onSelectLocal;
  final VoidCallback onSelectRemote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = item.localEntry!;
    final remote = item.entry!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? theme.colorScheme.secondaryContainer : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: onCheckChanged,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _VersionCell(
                label: '本地',
                entry: local,
                onTap: onSelectLocal,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _VersionCell(
                label: '云端',
                entry: remote,
                onTap: onSelectRemote,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionCell extends StatelessWidget {
  const _VersionCell({
    required this.label,
    required this.entry,
    required this.onTap,
  });

  final String label;
  final DiaryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 2),
            Text(
              entry.title ?? entry.excerpt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _timeLabelStatic(entry.updatedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewDetail extends StatelessWidget {
  const _PreviewDetail({required this.item});

  final _RestorePreviewItem? item;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    if (item == null) {
      return const Center(child: Text('选择左侧条目查看详情'));
    }
    if (item.invalidFile != null) {
      return ListView(
        children: [
          Text('无法解析', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Text(item.invalidFile!),
        ],
      );
    }
    final entry = item.entry!;
    return ListView(
      children: [
        Text(entry.title ?? '无标题',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        _InfoRow(label: '日期', value: DiaryEntry.dateKey(entry.date)),
        _InfoRow(label: '操作', value: item.type),
        _InfoRow(
            label: '${item.type}更新', value: _timeLabelStatic(entry.updatedAt)),
        if (item.detail != null) _InfoRow(label: '说明', value: item.detail!),
        _InfoRow(label: '附件', value: '${entry.attachments.length} 个'),
        const SizedBox(height: 12),
        Text(entry.bodyPreview, maxLines: 10, overflow: TextOverflow.fade),
      ],
    );
  }
}

class _RestorePreviewItem {
  const _RestorePreviewItem({
    required this.entry,
    required this.type,
    this.detail,
  })  : localEntry = null,
        invalidFile = null;

  const _RestorePreviewItem.update({
    required DiaryEntry remote,
    required DiaryEntry local,
  })  : entry = remote,
        localEntry = local,
        type = '云端',
        detail = null,
        invalidFile = null;

  const _RestorePreviewItem.invalid(String file)
      : entry = null,
        localEntry = null,
        type = '坏',
        detail = '文件无法解析',
        invalidFile = file;

  final DiaryEntry? entry;
  final DiaryEntry? localEntry;
  final String type;
  final String? detail;
  final String? invalidFile;

  String get title => entry?.title ?? entry?.excerpt ?? invalidFile ?? '未知文件';
  String get subtitle {
    final entry = this.entry;
    if (entry == null) return detail ?? '';
    return '${DiaryEntry.dateKey(entry.date)} · ${entry.attachments.length} 个附件';
  }

  _RestorePreviewItem localVersion() => _RestorePreviewItem(
        entry: localEntry,
        type: '本地',
      );
}

String _timeLabelStatic(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}-$month-$day $hour:$minute';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
