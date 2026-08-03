import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../data/services/diary_file_exporter.dart';
import '../../../data/services/diary_import_export_service.dart';

class DiaryImportExportPage extends StatelessWidget {
  const DiaryImportExportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('导入导出'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '导入'),
              Tab(text: '导出'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DiaryImportTab(),
            _DiaryExportTab(),
          ],
        ),
      ),
    );
  }
}

class _DiaryImportTab extends StatefulWidget {
  const _DiaryImportTab();

  @override
  State<_DiaryImportTab> createState() => _DiaryImportTabState();
}

class _DiaryImportTabState extends State<_DiaryImportTab> {
  final _service = const DiaryImportExportService();
  final _patternController = TextEditingController(
    text: DiaryImportExportService.templates.first.pattern,
  );
  final _startYearController = TextEditingController(
    text: DateTime.now().year.toString(),
  );
  DiaryImportMode _mode = DiaryImportMode.text;
  DiaryImportTemplate _template = DiaryImportExportService.templates.first;
  DiaryCsvImportData? _csvData;
  DiaryCsvMapping _csvMapping = const DiaryCsvMapping(
    dateColumn: null,
    contentColumn: null,
    titleColumn: null,
  );
  DiaryImportPreview? _preview;
  String _fileName = '';
  String _rawText = '';
  String _error = '';
  bool _working = false;

  @override
  void dispose() {
    _patternController.dispose();
    _startYearController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _working = true;
      _error = '';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'md', 'markdown', 'json', 'csv'],
        withReadStream: true,
        withData: false,
      );
      final file = result?.files.single;
      if (file == null) return;
      final text = await _readFileText(file);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _rawText = text;
        _csvData =
            _mode == DiaryImportMode.csv ? _service.inspectCsv(text) : null;
        if (_csvData != null) {
          _csvMapping = _csvData!.mapping;
        }
      });
      _buildPreview();
    } on Object catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String> _readFileText(PlatformFile file) async {
    final stream = file.readStream;
    if (stream != null) {
      final buffer = StringBuffer();
      await for (final chunk in utf8.decoder.bind(stream)) {
        buffer.write(chunk);
      }
      final text = buffer.toString();
      if (text.isEmpty) {
        throw const DiaryImportException('文件为空或无法读取');
      }
      return text;
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const DiaryImportException('文件为空或无法读取');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  void _buildPreview() {
    if (_rawText.trim().isEmpty) {
      setState(() {
        _preview = null;
        _error = '';
      });
      return;
    }
    try {
      final preview = switch (_mode) {
        DiaryImportMode.text => _previewText(),
        DiaryImportMode.json => _service.previewJson(_rawText),
        DiaryImportMode.csv => _previewCsv(),
      };
      setState(() {
        _preview = preview;
        _error = '';
      });
    } on Object catch (error) {
      _showError(error);
    }
  }

  DiaryImportPreview _previewText() {
    final startYear = _template.requiresStartYear
        ? int.tryParse(_startYearController.text.trim())
        : null;
    if (_template.requiresStartYear && startYear == null) {
      throw const DiaryImportException('请填写起始年份');
    }
    return _service.previewText(
      text: _rawText,
      pattern: _patternController.text.trim(),
      startYear: startYear,
    );
  }

  DiaryImportPreview _previewCsv() {
    final data = _csvData ??= _service.inspectCsv(_rawText);
    return _service.previewCsv(data, _csvMapping);
  }

  Future<void> _confirmImport() async {
    final drafts = _preview?.drafts ?? const <DiaryImportDraft>[];
    if (drafts.isEmpty || _working) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认导入？'),
        content: Text('将导入 ${drafts.length} 篇日记，并加入 AI 整理队列。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() => _working = true);
    try {
      final result = await _service.importDrafts(drafts);
      if (!mounted) return;
      setState(() {
        _preview = null;
        _rawText = '';
        _fileName = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${result.importedCount} 篇日记')),
      );
    } on Object catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _setTemplate(DiaryImportTemplate template) {
    setState(() {
      _template = template;
      _patternController.text = template.pattern;
      _preview = null;
      _error = '';
    });
    _buildPreview();
  }

  void _setMode(DiaryImportMode mode) {
    setState(() {
      _mode = mode;
      _preview = null;
      _error = '';
      _csvData = mode == DiaryImportMode.csv && _rawText.isNotEmpty
          ? _service.inspectCsv(_rawText)
          : null;
      if (_csvData != null) _csvMapping = _csvData!.mapping;
    });
    if (_rawText.isNotEmpty) _buildPreview();
  }

  void _setCsvMapping(DiaryCsvMapping mapping) {
    setState(() {
      _csvMapping = mapping;
    });
    _buildPreview();
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _error = '$error');
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<DiaryImportMode>(
                  segments: const [
                    ButtonSegment(
                      value: DiaryImportMode.text,
                      label: Text('文本'),
                      icon: Icon(Icons.notes_outlined),
                    ),
                    ButtonSegment(
                      value: DiaryImportMode.json,
                      label: Text('JSON'),
                      icon: Icon(Icons.data_object_outlined),
                    ),
                    ButtonSegment(
                      value: DiaryImportMode.csv,
                      label: Text('CSV'),
                      icon: Icon(Icons.table_chart_outlined),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged:
                      _working ? null : (value) => _setMode(value.first),
                ),
                const SizedBox(height: 16),
                if (_mode == DiaryImportMode.text) ...[
                  _TextImportControls(
                    template: _template,
                    patternController: _patternController,
                    startYearController: _startYearController,
                    working: _working,
                    onTemplateChanged: _setTemplate,
                    onPatternChanged: (_) => _buildPreview(),
                    onStartYearChanged: (_) => _buildPreview(),
                  ),
                ] else if (_mode == DiaryImportMode.json) ...[
                  const _StructuredImportHint(
                    title: 'JSON 结构化导入',
                    description: '支持数组，或包含 entries / data / items 的对象。',
                    example:
                        '{"date":"2026-01-01","title":"新年","content":"今天开始记录。"}',
                  ),
                ] else ...[
                  _CsvMappingControls(
                    data: _csvData,
                    mapping: _csvMapping,
                    onChanged: _setCsvMapping,
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _working ? null : _pickFile,
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(_fileName.isEmpty ? '选择文件' : _fileName),
                ),
              ],
            ),
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: _error),
        ],
        if (preview != null) ...[
          const SizedBox(height: 16),
          _ImportPreviewCard(
            preview: preview,
            onOpen: _openDraft,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _working ? null : _confirmImport,
            icon: const Icon(Icons.check_outlined),
            label: Text('确认导入 ${preview.drafts.length} 篇'),
          ),
        ],
      ],
    );
  }

  Future<void> _openDraft(DiaryImportDraft draft) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(draft.dateLabel),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(draft.content),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _TextImportControls extends StatelessWidget {
  const _TextImportControls({
    required this.template,
    required this.patternController,
    required this.startYearController,
    required this.working,
    required this.onTemplateChanged,
    required this.onPatternChanged,
    required this.onStartYearChanged,
  });

  final DiaryImportTemplate template;
  final TextEditingController patternController;
  final TextEditingController startYearController;
  final bool working;
  final ValueChanged<DiaryImportTemplate> onTemplateChanged;
  final ValueChanged<String> onPatternChanged;
  final ValueChanged<String> onStartYearChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: '格式模板',
            border: OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<DiaryImportTemplate>(
              value: template,
              isExpanded: true,
              items: [
                for (final item in DiaryImportExportService.templates)
                  DropdownMenuItem(
                    value: item,
                    child: Text(item.label),
                  ),
              ],
              onChanged: working
                  ? null
                  : (value) {
                      if (value != null) onTemplateChanged(value);
                    },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _TemplateExample(template: template),
        const SizedBox(height: 12),
        TextFormField(
          controller: patternController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '正则表达式',
            helperText: '需要命名分组 month/day，可选 year/title；可按文件实际格式修改',
            border: OutlineInputBorder(),
          ),
          onChanged: onPatternChanged,
        ),
        if (template.requiresStartYear) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: startYearController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '起始年份',
              helperText: '无年份日期会从这里开始，月份变小则自动进入下一年',
              border: OutlineInputBorder(),
            ),
            onChanged: onStartYearChanged,
          ),
        ],
      ],
    );
  }
}

class _StructuredImportHint extends StatelessWidget {
  const _StructuredImportHint({
    required this.title,
    required this.description,
    required this.example,
  });

  final String title;
  final String description;
  final String example;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            SelectableText(
              example,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CsvMappingControls extends StatelessWidget {
  const _CsvMappingControls({
    required this.data,
    required this.mapping,
    required this.onChanged,
  });

  final DiaryCsvImportData? data;
  final DiaryCsvMapping mapping;
  final ValueChanged<DiaryCsvMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    final headers = data?.headers ?? const <String>[];
    if (headers.isEmpty) {
      return const _StructuredImportHint(
        title: 'CSV 表格导入',
        description: '选择文件后会自动识别表头，并可手动映射日期、标题和正文列。',
        example: 'date,title,content\n2026-01-01,新年,今天开始记录。',
      );
    }
    return Column(
      children: [
        _ColumnPicker(
          label: '日期列',
          value: mapping.dateColumn,
          headers: headers,
          onChanged: (value) => onChanged(DiaryCsvMapping(
            dateColumn: value,
            contentColumn: mapping.contentColumn,
            titleColumn: mapping.titleColumn,
          )),
        ),
        const SizedBox(height: 12),
        _ColumnPicker(
          label: '正文列',
          value: mapping.contentColumn,
          headers: headers,
          onChanged: (value) => onChanged(DiaryCsvMapping(
            dateColumn: mapping.dateColumn,
            contentColumn: value,
            titleColumn: mapping.titleColumn,
          )),
        ),
        const SizedBox(height: 12),
        _ColumnPicker(
          label: '标题列',
          value: mapping.titleColumn,
          headers: headers,
          allowEmpty: true,
          onChanged: (value) => onChanged(DiaryCsvMapping(
            dateColumn: mapping.dateColumn,
            contentColumn: mapping.contentColumn,
            titleColumn: value,
          )),
        ),
      ],
    );
  }
}

class _ColumnPicker extends StatelessWidget {
  const _ColumnPicker({
    required this.label,
    required this.value,
    required this.headers,
    required this.onChanged,
    this.allowEmpty = false,
  });

  final String label;
  final String? value;
  final List<String> headers;
  final ValueChanged<String?> onChanged;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          items: [
            if (allowEmpty)
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('不使用'),
              ),
            for (final header in headers)
              DropdownMenuItem<String?>(
                value: header,
                child: Text(header),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TemplateExample extends StatelessWidget {
  const _TemplateExample({required this.template});

  final DiaryImportTemplate template;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(template.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            SelectableText(
              template.example,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportPreviewCard extends StatelessWidget {
  const _ImportPreviewCard({
    required this.preview,
    required this.onOpen,
  });

  final DiaryImportPreview preview;
  final ValueChanged<DiaryImportDraft> onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.list_alt_outlined),
            title: Text('预览 ${preview.drafts.length} 篇日记'),
            subtitle: const Text('点开可查看完整内容'),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 420,
            child: Scrollbar(
              child: ListView.builder(
                itemCount: preview.drafts.length,
                itemBuilder: (context, index) {
                  final draft = preview.drafts[index];
                  return ListTile(
                    title: Text(
                      draft.title.isEmpty ? draft.dateLabel : draft.title,
                    ),
                    subtitle: Text(
                      '${draft.dateLabel} · ${draft.content.replaceAll('\n', ' ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.open_in_new_outlined),
                    onTap: () => onOpen(draft),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaryExportTab extends StatefulWidget {
  const _DiaryExportTab();

  @override
  State<_DiaryExportTab> createState() => _DiaryExportTabState();
}

class _DiaryExportTabState extends State<_DiaryExportTab> {
  final _service = const DiaryImportExportService();
  final _exporter = createDiaryFileExporter();
  DiaryExportFormat _format = DiaryExportFormat.shinenText;
  bool _working = false;
  String _error = '';

  Future<void> _export() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = '';
    });
    try {
      final payload = await _service.buildExport(_format);
      final saved = await _exporter.save(
        fileName: payload.fileName,
        extension: payload.extension,
        bytes: payload.bytes,
      );
      if (!mounted) return;
      if (!saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导出完成')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<DiaryExportFormat>(
                  segments: const [
                    ButtonSegment(
                      value: DiaryExportFormat.shinenText,
                      label: Text('拾年文本'),
                      icon: Icon(Icons.article_outlined),
                    ),
                    ButtonSegment(
                      value: DiaryExportFormat.json,
                      label: Text('JSON'),
                      icon: Icon(Icons.data_object_outlined),
                    ),
                  ],
                  selected: {_format},
                  onSelectionChanged: _working
                      ? null
                      : (value) => setState(() => _format = value.first),
                ),
                const SizedBox(height: 10),
                Text(
                  _format == DiaryExportFormat.shinenText
                      ? '适合阅读、迁移和再次导入'
                      : '保留完整字段，适合备份和开发调试',
                ),
              ],
            ),
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: _error),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _working ? null : _export,
          icon: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          label: const Text('导出'),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: ListTile(
        leading: Icon(Icons.error_outline, color: colors.onErrorContainer),
        title: Text(
          message,
          style: TextStyle(color: colors.onErrorContainer),
        ),
      ),
    );
  }
}
