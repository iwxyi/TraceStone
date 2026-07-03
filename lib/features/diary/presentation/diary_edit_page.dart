import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/diary_entry.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/services/ai_repair_service.dart';
import '../../../data/services/diary_analysis_service.dart';
import '../../../data/services/location_weather_service.dart';
import 'map_picker_page.dart';

class DiaryEditPage extends StatefulWidget {
  const DiaryEditPage({super.key});

  @override
  State<DiaryEditPage> createState() => _DiaryEditPageState();
}

class _DiaryEditPageState extends State<DiaryEditPage> {
  static const _recentLocationsKey = 'diary.recentLocations';

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();
  final _repository = const DiaryRepository();
  final _insightRepository = const InsightRepository();
  final _analysisService = const DiaryAnalysisService();
  final _aiRepairService = const AiRepairService();
  final _locationWeatherService = const LocationWeatherService();
  final _images = <XFile>[];

  bool _routeLoaded = false;
  bool _isEditing = true;
  bool _isPreview = false;
  bool _isAiFixing = false;
  bool _isAnalyzingDiary = false;
  bool _isLoadingLocation = false;
  bool _suppressHistory = false;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  String _lastHistoryValue = '';
  bool _hasManualLocation = false;
  bool _hasManualWeather = false;
  bool _autoSave = true;
  bool _hasUnsavedChanges = false;
  bool _isBootstrapping = true;
  bool _useCustomAiFix = false;
  String _customAiFixRule = '';
  String? _analysisError;
  Future<DiaryInsight?>? _insightFuture;

  String _entryId = const Uuid().v4();
  DateTime _createdAt = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  String _selectedLocation = '定位中';
  String _weather = '';
  String? _temperature;
  Map<String, dynamic> _locationDetails = const {};
  int _headingLevel = 2;
  _ListStyle _listStyle = _ListStyle.unordered;

  late final String _placeholder = _weightedPlaceholder();

  bool get _isExistingEntry =>
      ModalRoute.of(context)?.settings.arguments != null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadEditorPreferences();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeLoaded) return;
    _routeLoaded = true;
    final routeId = ModalRoute.of(context)?.settings.arguments as String?;
    final urlId = Uri.base.queryParameters['id'];
    final id = routeId ?? urlId;
    if (id == null) {
      _isEditing = true;
      _loadNewEntryState();
    } else {
      _isEditing = false;
      _loadExistingEntryState(id);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadEditorPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _headingLevel = (prefs.getInt('diary.headingLevel') ?? 2).clamp(1, 6);
      final listIndex = (prefs.getInt('diary.listStyle') ?? 0)
          .clamp(0, _ListStyle.values.length - 1);
      _listStyle = _ListStyle.values[listIndex];
      _autoSave = prefs.getBool('diary.autoSave') ?? true;
      _useCustomAiFix = prefs.getBool('diary.aiFix.useCustom') ?? false;
      _customAiFixRule = prefs.getString('diary.aiFix.customRule') ?? '';
    });
  }

  Future<void> _loadNewEntryState() async {
    if (!mounted) return;
    _controller.removeListener(_onTextChanged);
    _controller.clear();
    _controller.addListener(_onTextChanged);
    setState(() {
      _entryId = const Uuid().v4();
      _createdAt = DateTime.now();
      _selectedDate = DateTime.now();
      _selectedLocation = '定位中';
      _weather = '';
      _temperature = null;
      _locationDetails = const {};
      _hasManualLocation = false;
      _hasManualWeather = false;
      _hasUnsavedChanges = false;
      _undoStack.clear();
      _redoStack.clear();
      _lastHistoryValue = '';
      _isBootstrapping = false;
    });
    _restoreFocus();
    await _loadCurrentLocationWeather();
  }

  Future<void> _loadExistingEntryState(String id) async {
    DiaryEntry? entry = await _repository.getEntryById(id);
    entry ??= await _repository.getRecoverySnapshot(id);
    if (entry == null) {
      final entries = await _repository.listEntries();
      entry = entries.where((e) => e.id == id).firstOrNull;
    }
    if (!mounted) return;
    if (entry == null) {
      setState(() => _isBootstrapping = false);
      return;
    }
    final resolvedEntry = entry;
    _controller.removeListener(_onTextChanged);
    _controller.text = resolvedEntry.content;
    _controller.addListener(_onTextChanged);
    setState(() {
      _entryId = resolvedEntry.id;
      _createdAt = resolvedEntry.createdAt;
      _selectedDate = resolvedEntry.date;
      _selectedLocation = resolvedEntry.location;
      _weather = resolvedEntry.weather;
      _temperature = resolvedEntry.temperature;
      _locationDetails = resolvedEntry.locationDetails;
      _hasManualLocation = resolvedEntry.location.trim().isNotEmpty &&
          resolvedEntry.location != '未选择地点' &&
          resolvedEntry.location != '点击选择地点';
      _hasManualWeather = resolvedEntry.weather.trim().isNotEmpty &&
          resolvedEntry.weather != '天气';
      _hasUnsavedChanges = false;
      _undoStack.clear();
      _redoStack.clear();
      _lastHistoryValue = resolvedEntry.content;
      _isBootstrapping = false;
    });
    _loadOrAnalyzeInsight(resolvedEntry);
  }

  DiaryEntry _currentEntry() {
    return DiaryEntry(
      id: _entryId,
      date: _selectedDate,
      createdAt: _createdAt,
      content: _controller.text,
      location: _selectedLocation,
      weather: _weather,
      temperature: _temperature,
      updatedAt: DateTime.now(),
      locationDetails: _locationDetails,
    );
  }

  Future<void> _saveEntry() async {
    final entry = _currentEntry();
    if (entry.content.trim().isEmpty) return;
    await _repository.saveEntry(entry);
  }

  Future<void> _loadOrAnalyzeInsight(DiaryEntry entry) async {
    setState(() {
      _analysisError = null;
      _insightFuture = _insightRepository.getInsight(entry.id);
    });
    final existing = await _insightFuture;
    if (!mounted || existing != null) return;
    await _refreshInsight(entry);
  }

  Future<void> _refreshInsight([DiaryEntry? source]) async {
    final entry = source ?? _currentEntry();
    if (entry.content.trim().isEmpty || _isAnalyzingDiary) return;
    setState(() {
      _isAnalyzingDiary = true;
      _analysisError = null;
    });
    try {
      final insight = await _analysisService.analyzeEntry(entry);
      if (!mounted) return;
      setState(() {
        _insightFuture = Future.value(insight);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _analysisError = error.toString());
    } finally {
      if (mounted) setState(() => _isAnalyzingDiary = false);
    }
  }

  void _onTextChanged() {
    if (_isBootstrapping || !_isEditing) return;
    if (!_suppressHistory && _controller.text != _lastHistoryValue) {
      _undoStack.add(_lastHistoryValue);
      _lastHistoryValue = _controller.text;
      _redoStack.clear();
    }
    if (_autoSave) {
      _saveEntry();
    } else if (mounted) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  void _restoreText(String value) {
    _suppressHistory = true;
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _lastHistoryValue = value;
    _suppressHistory = false;
    _restoreFocus();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_controller.text);
    _restoreText(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_controller.text);
    _restoreText(_redoStack.removeLast());
  }

  Future<void> _runAiFix() async {
    if (_controller.text.trim().isEmpty || _isAiFixing) return;
    setState(() => _isAiFixing = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('AI 正在修复日记内容…')),
          ],
        ),
      ),
    );

    try {
      final before = _controller.text;
      final result = await _aiRepairService.repair(
        before,
        customRule: _useCustomAiFix ? _customAiFixRule : null,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final hasTextChange = result.correctedText != before;
      final shouldApplyResult = result.applied &&
          (_useCustomAiFix ? hasTextChange : result.totalFixes > 0);

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      if (!shouldApplyResult) {
        messenger.showSnackBar(const SnackBar(
          content: Text('无需优化'),
          duration: Duration(seconds: 2),
        ));
      } else {
        _undoStack.add(before);
        _redoStack.clear();
        _restoreText(result.correctedText);
        await _saveEntry();
        if (!mounted) return;
        final message = _useCustomAiFix
            ? '已完成自定义修复'
            : '已修复 ${result.typoCount} 个错别字，${result.grammarCount} 个语法问题，${result.punctuationCount} 个标点问题';
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(label: '撤回', onPressed: _undo),
          ),
        );
      }
      if (result.warnings.isNotEmpty && mounted) {
        final title = result.applied ? 'AI 修复提醒' : 'AI 修复未自动应用';
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(result.warnings.join('\n')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } on AiRepairException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _isAiFixing = false);
    }
  }

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;
  bool get _canAiFix => !_isAiFixing && _controller.text.trim().isNotEmpty;

  Future<void> _openAiFixMenu([Offset? position]) async {
    if (!context.mounted) return;
    final action = await showMenu<_AiFixMenuAction>(
      context: context,
      position: _menuPosition(position),
      items: [
        CheckedPopupMenuItem(
          value: _AiFixMenuAction.toggleCustom,
          checked: _useCustomAiFix,
          child: const Text('启用自定义修复'),
        ),
        PopupMenuItem(
          value: _AiFixMenuAction.custom,
          enabled: _useCustomAiFix,
          child: const Text('自定义修复'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == _AiFixMenuAction.toggleCustom) {
      await _setAiFixMode(!_useCustomAiFix);
      return;
    }
    if (action == _AiFixMenuAction.custom) {
      final controller = TextEditingController(text: _customAiFixRule);
      if (!context.mounted) return;
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('自定义修复'),
          content: TextField(
            controller: controller,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '例如：\n只修复错别字\n统一标题和列表格式\n轻微润色，但保留原意',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('保存并启用'),
            ),
          ],
        ),
      );
      if (result == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('diary.aiFix.customRule', result);
      await prefs.setBool('diary.aiFix.useCustom', true);
      setState(() {
        _customAiFixRule = result;
        _useCustomAiFix = true;
      });
    }
  }

  Future<void> _chooseListStyle([Offset? position]) async {
    final style = await showMenu<_ListStyle>(
      context: context,
      position: _menuPosition(position),
      items: const [
        PopupMenuItem(value: _ListStyle.unordered, child: Text('无序列表  - 列表项')),
        PopupMenuItem(value: _ListStyle.ordered, child: Text('有序列表  1. 列表项')),
        PopupMenuItem(
            value: _ListStyle.checkbox, child: Text('复选框  - [ ] 待办项')),
      ],
    );
    if (style == null) return;
    setState(() => _listStyle = style);
    await _saveListStyle(style);
    _restoreFocus();
  }

  RelativeRect _menuPosition(Offset? position) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final offset = position ?? overlay.size.center(Offset.zero);
    return RelativeRect.fromRect(
      Rect.fromCircle(center: offset, radius: 1),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _chooseHeadingLevel([Offset? position]) async {
    final level = await showMenu<int>(
      context: context,
      position: _menuPosition(position),
      items: [
        for (var level = 1; level <= 6; level++)
          PopupMenuItem(
              value: level, child: Text('H$level  ${'#' * level} 标题')),
      ],
    );
    if (level == null) return;
    setState(() => _headingLevel = level);
    await _saveHeadingLevel(level);
    _restoreFocus();
  }

  Future<void> _saveHeadingLevel(int level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('diary.headingLevel', level);
  }

  Future<void> _saveListStyle(_ListStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('diary.listStyle', style.index);
  }

  Future<void> _setAutoSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('diary.autoSave', value);
    setState(() => _autoSave = value);
    if (value) await _saveEntry();
  }

  Future<void> _setAiFixMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('diary.aiFix.useCustom', value);
    setState(() => _useCustomAiFix = value);
  }

  Future<void> _editCustomAiFixRule() async {
    final controller = TextEditingController(text: _customAiFixRule);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义修复'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '例如：\n只修复错别字\n统一 Markdown 标题和列表格式\n轻微润色，但保留原意',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存并启用'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('diary.aiFix.customRule', result);
    await prefs.setBool('diary.aiFix.useCustom', true);
    setState(() {
      _customAiFixRule = result;
      _useCustomAiFix = true;
    });
  }

  Future<void> _finishEditing() async {
    final entry = _currentEntry();
    if (entry.content.trim().isNotEmpty) {
      await _repository.saveEntry(entry);
    }
    if (mounted) {
      Navigator.of(context).pop(entry.content.trim().isEmpty ? true : entry);
    }
  }

  void _enterEditMode() {
    setState(() => _isEditing = true);
    _restoreFocus();
  }

  Future<void> _closeEditor() async {
    if (!_isEditing) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_autoSave) {
      await _finishEditing();
      return;
    }
    final action = await _confirmLeave();
    if (!mounted || action == _LeaveAction.cancel) return;
    if (action == _LeaveAction.discard) {
      Navigator.of(context).pop(true);
      return;
    }
    await _finishEditing();
  }

  Future<void> _discardAndClose() async {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteEntry() async {
    await _repository.moveToTrash(_entryId);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _openEditorMenu() async {
    final action = await showMenu<_EditorMenuAction>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 64, 12, 0),
      items: [
        PopupMenuItem(
          value: _EditorMenuAction.togglePreview,
          child: Row(
            children: [
              Icon(
                  _isPreview ? Icons.edit_outlined : Icons.visibility_outlined),
              const SizedBox(width: 8),
              Text(_isPreview ? '编辑' : '预览'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _EditorMenuAction.saveNow,
          child: Row(
            children: [
              Icon(Icons.save_outlined),
              SizedBox(width: 8),
              Text('保存'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _EditorMenuAction.toggleAutoSave,
          child: Row(
            children: [
              Icon(_autoSave ? Icons.toggle_on : Icons.toggle_off),
              const SizedBox(width: 8),
              Text(_autoSave ? '关闭自动保存' : '开启自动保存'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _EditorMenuAction.toggleAiFixMode,
          child: Row(
            children: [
              Icon(_useCustomAiFix ? Icons.tune : Icons.auto_fix_high),
              const SizedBox(width: 8),
              Text(_useCustomAiFix ? '切换到标准修复' : '切换到自定义修复'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _EditorMenuAction.customAiFix,
          child: Row(
            children: [
              Icon(Icons.edit_note_outlined),
              SizedBox(width: 8),
              Text('编辑自定义修复'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _EditorMenuAction.discard,
          child: Row(
            children: [
              Icon(Icons.undo_outlined),
              SizedBox(width: 8),
              Text('舍弃编辑'),
            ],
          ),
        ),
        if (_isExistingEntry) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _EditorMenuAction.delete,
            child: Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('删除这篇日记', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ],
    );
    if (action == null) return;
    switch (action) {
      case _EditorMenuAction.togglePreview:
        setState(() => _isPreview = !_isPreview);
      case _EditorMenuAction.saveNow:
        await _saveEntry();
      case _EditorMenuAction.toggleAutoSave:
        await _setAutoSave(!_autoSave);
      case _EditorMenuAction.toggleAiFixMode:
        await _setAiFixMode(!_useCustomAiFix);
      case _EditorMenuAction.customAiFix:
        await _editCustomAiFixRule();
      case _EditorMenuAction.discard:
        await _discardAndClose();
      case _EditorMenuAction.delete:
        await _deleteEntry();
    }
  }

  Future<_LeaveAction> _confirmLeave() async {
    if (_autoSave || !_hasUnsavedChanges) return _LeaveAction.save;
    final action = await showDialog<_LeaveAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存这次编辑吗？'),
        content: const Text('关闭自动保存后，返回前需要确认是否保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LeaveAction.discard),
            child: const Text('不保存'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LeaveAction.cancel),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_LeaveAction.save),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    switch (action) {
      case _LeaveAction.save:
        await _saveEntry();
        return _LeaveAction.save;
      case _LeaveAction.discard:
        return _LeaveAction.discard;
      case _LeaveAction.cancel:
      case null:
        return _LeaveAction.cancel;
    }
  }

  void _toggleHeading() {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final lineStart = text.lastIndexOf('\n', start - 1);
    final actualStart = lineStart == -1 ? 0 : lineStart + 1;
    final lineEndIndex = text.indexOf('\n', start);
    final actualEnd = lineEndIndex == -1 ? text.length : lineEndIndex;
    final line = text.substring(actualStart, actualEnd);
    final atxPattern = RegExp(r'^#{1,6}\s+');

    final nextLine = atxPattern.hasMatch(line)
        ? line.replaceFirst(atxPattern, '')
        : '${'#' * _headingLevel} $line';

    _controller.value = TextEditingValue(
      text: text.replaceRange(actualStart, actualEnd, nextLine),
      selection: TextSelection.collapsed(offset: actualStart + nextLine.length),
    );
    _restoreFocus();
  }

  void _toggleLinePrefix(String prefix, {List<String> alternates = const []}) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final lineStart = text.lastIndexOf('\n', start - 1);
    final actualStart = lineStart == -1 ? 0 : lineStart + 1;
    final lineEndIndex = text.indexOf('\n', start);
    final actualEnd = lineEndIndex == -1 ? text.length : lineEndIndex;
    final line = text.substring(actualStart, actualEnd);

    String nextLine = line;
    if (line.startsWith(prefix)) {
      nextLine = line.substring(prefix.length);
    } else {
      final alternate = alternates.where(line.startsWith).firstOrNull;
      if (alternate != null) {
        nextLine = '$prefix${line.substring(alternate.length)}';
      } else {
        nextLine = '$prefix$line';
      }
    }

    _controller.value = TextEditingValue(
      text: text.replaceRange(actualStart, actualEnd, nextLine),
      selection: TextSelection.collapsed(offset: actualStart + nextLine.length),
    );
    _restoreFocus();
  }

  void _toggleQuote() => _toggleLinePrefix('> ');

  void _insertList() {
    switch (_listStyle) {
      case _ListStyle.unordered:
        _toggleLinePrefix('- ', alternates: ['1. ', '- [ ] ']);
      case _ListStyle.ordered:
        _toggleLinePrefix('1. ', alternates: ['- ', '- [ ] ']);
      case _ListStyle.checkbox:
        _toggleLinePrefix('- [ ] ', alternates: ['- ', '1. ']);
    }
  }

  void _insertDivider() {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final before = text.substring(0, start);
    final after = text.substring(start);

    final needsLeadingBreaks = before.isEmpty
        ? 0
        : before.endsWith('\n\n')
            ? 0
            : before.endsWith('\n')
                ? 1
                : 2;
    final needsTrailingBreaks = after.isEmpty
        ? 0
        : after.startsWith('\n\n\n')
            ? 0
            : after.startsWith('\n\n')
                ? 1
                : 2;

    final insert =
        '${'\n' * needsLeadingBreaks}---${'\n' * needsTrailingBreaks}';
    final nextText = text.replaceRange(start, start, insert);
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    _restoreFocus();
  }

  void _insertImageMarkdown(XFile image) {
    final name = image.name.isEmpty ? 'image' : image.name;
    _insertMarkdown('\n![$name](${image.path})\n');
  }

  Future<void> _loadCurrentLocationWeather() async {
    setState(() => _isLoadingLocation = true);
    try {
      final value = await _locationWeatherService.getCurrent();
      if (!mounted) return;
      setState(() {
        if (!_hasManualLocation) {
          _selectedLocation =
              value.locationName.isEmpty ? '当前位置' : value.locationName;
          _locationDetails = value.details;
        }
        if (!_hasManualWeather) {
          _weather = value.weather;
          _temperature = value.temperature;
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        if (!_hasManualLocation) {
          _selectedLocation = '未选择地点';
        }
      });
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 82);
    if (picked.isEmpty) return;
    setState(() => _images.addAll(picked));
  }

  Future<void> _openLocationMenu() async {
    final recentLocations = await _recentLocations();
    if (!mounted) return;
    final value = await showModalBottomSheet<LocationWeather>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _LocationSheet(
        recentLocations: recentLocations,
        currentLocation: _selectedLocation,
        weather: _weather,
        temperature: _temperature,
      ),
    );
    if (value == null) return;
    await _rememberLocation(value);
    setState(() {
      _selectedLocation = value.locationName;
      _weather = value.weather;
      _temperature = value.temperature;
      _locationDetails = value.details;
      _hasManualLocation = true;
      _hasManualWeather = true;
    });
  }

  Future<List<LocationWeather>> _recentLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_recentLocationsKey) ?? [];
    return saved.map(_locationFromStorage).take(5).toList();
  }

  Future<void> _rememberLocation(LocationWeather value) async {
    final location = value.locationName.trim();
    if (location.isEmpty || location == '未选择地点' || location == '点击选择地点') {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_recentLocationsKey) ?? [];
    final next = <String>[_locationToStorage(value)];
    for (final item in current) {
      final stored = _locationFromStorage(item);
      if (stored.locationName == location) continue;
      next.add(item);
      if (next.length >= 10) break;
    }
    await prefs.setStringList(_recentLocationsKey, next);
  }

  String _locationToStorage(LocationWeather value) => [
        value.locationName,
        value.weather,
        value.temperature,
        value.latitude.toString(),
        value.longitude.toString(),
        jsonEncode(value.details),
      ].join('');

  LocationWeather _locationFromStorage(String value) {
    final parts = value.split('');
    return LocationWeather(
      latitude: parts.length > 3 ? double.tryParse(parts[3]) ?? 0 : 0,
      longitude: parts.length > 4 ? double.tryParse(parts[4]) ?? 0 : 0,
      locationName: parts.isNotEmpty ? parts[0] : '',
      weather: parts.length > 1 ? parts[1] : _weather,
      temperature: parts.length > 2 ? parts[2] : (_temperature ?? ''),
      details: parts.length > 5
          ? (jsonDecode(parts[5]) as Map<String, dynamic>? ?? const {})
          : const {},
    );
  }

  Future<void> _openDatePicker() async {
    final values = await showCalendarDatePicker2Dialog(
      context: context,
      config: CalendarDatePicker2WithActionButtonsConfig(
        calendarType: CalendarDatePicker2Type.single,
        firstDate: DateTime(1970),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
        selectedDayHighlightColor: Theme.of(context).colorScheme.primary,
      ),
      dialogSize: const Size(360, 420),
      value: [_selectedDate],
    );
    final date = values?.firstOrNull;
    if (date == null) return;

    if (_isExistingEntry) {
      final source = await _repository.getEntryById(_entryId);
      if (!mounted) return;
      setState(() {
        _selectedDate = date;
        if (source != null) {
          _selectedLocation = source.location;
          _weather = source.weather;
          _temperature = source.temperature;
        }
      });
      return;
    }

    setState(() {
      _selectedDate = date;
      _entryId = const Uuid().v4();
      _createdAt = DateTime.now();
      _controller.clear();
      _selectedLocation = '定位中';
      _weather = '';
      _temperature = null;
      _locationDetails = const {};
      _hasManualLocation = false;
      _hasManualWeather = false;
      _hasUnsavedChanges = false;
    });
    await _loadCurrentLocationWeather();
  }

  Future<void> _openWeatherMenu() async {
    final result = await showModalBottomSheet<_WeatherEditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _WeatherSheet(
        weather: _weather,
        temperature: _temperature,
      ),
    );
    if (result == null) return;
    setState(() {
      _weather = result.weather;
      _temperature = result.temperature;
      _hasManualWeather = true;
    });
  }

  void _restoreFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _insertMarkdown(String before, [String after = '']) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final selected = text.substring(start, end);
    final nextText = text.replaceRange(start, end, '$before$selected$after');
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(
          offset: start + before.length + selected.length),
    );
    _restoreFocus();
  }

  void _toggleMarkdown(String marker) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    if (start >= marker.length &&
        end + marker.length <= text.length &&
        text.substring(start - marker.length, start) == marker &&
        text.substring(end, end + marker.length) == marker) {
      final nextText = text
          .replaceRange(end, end + marker.length, '')
          .replaceRange(start - marker.length, start, '');
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection(
            baseOffset: start - marker.length,
            extentOffset: end - marker.length),
      );
    } else {
      final selected = text.substring(start, end);
      final nextText = text.replaceRange(start, end, '$marker$selected$marker');
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection(
            baseOffset: start + marker.length,
            extentOffset: end + marker.length),
      );
    }
    _restoreFocus();
  }

  String get _dateLabel {
    final date = _selectedDate;
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
  }

  String _weightedPlaceholder() {
    final now = DateTime.now();
    final seed = (now.microsecondsSinceEpoch % 100).abs();
    final pool = switch (seed) {
      < 40 => _DiaryPlaceholders.gentle,
      < 65 => _DiaryPlaceholders.emotional,
      < 80 => _DiaryPlaceholders.perspective,
      _ => _DiaryPlaceholders.review,
    };
    return pool[now.millisecond % pool.length];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _closeEditor();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回',
            onPressed: _closeEditor,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(_isEditing ? '写日记' : '日记'),
          actions: [
            if (_isEditing)
              IconButton(
                tooltip: '更多',
                onPressed: _openEditorMenu,
                icon: const Icon(Icons.more_vert),
              ),
          ],
        ),
        resizeToAvoidBottomInset: true,
        floatingActionButton: _isEditing
            ? null
            : FloatingActionButton(
                onPressed: _enterEditMode,
                child: const Icon(Icons.edit_outlined),
              ),
        body: Column(
          children: [
            _DiaryMetaBar(
              dateLabel: _dateLabel,
              location: _selectedLocation,
              weather: _weather,
              temperature: _temperature,
              isLoadingLocation: _isLoadingLocation,
              onOpenDate: _isEditing ? _openDatePicker : null,
              onOpenLocation: _isEditing ? _openLocationMenu : null,
              onOpenWeather: _isEditing ? _openWeatherMenu : null,
            ),
            Expanded(
              child: _isEditing
                  ? (_isPreview
                      ? _MarkdownPreview(text: _controller.text)
                      : TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          keyboardType: TextInputType.multiline,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            contentPadding:
                                const EdgeInsets.fromLTRB(24, 20, 24, 20),
                            border: InputBorder.none,
                            hintText: _placeholder,
                          ),
                        ))
                  : _DiaryReadView(
                      text: _controller.text,
                      isAnalyzing: _isAnalyzingDiary,
                      insightFuture: _insightFuture,
                      error: _analysisError,
                      onRefresh: () => _refreshInsight(),
                    ),
            ),
            if (_isEditing && _images.isNotEmpty)
              _ImageStrip(
                images: _images,
                onInsert: _insertImageMarkdown,
                onRemove: (image) => setState(() => _images.remove(image)),
              ),
            if (_isEditing)
              SafeArea(
                top: false,
                child: _EditorAccessoryBar(
                  headingLevel: _headingLevel,
                  onHeading: _toggleHeading,
                  onHeadingLongPress: _chooseHeadingLevel,
                  onBold: () => _toggleMarkdown('**'),
                  onItalic: () => _toggleMarkdown('*'),
                  onQuote: _toggleQuote,
                  onList: _insertList,
                  onListLongPress: _chooseListStyle,
                  onDivider: _insertDivider,
                  onImage: _pickImages,
                  onUndo: _undo,
                  onRedo: _redo,
                  onAiFix: _runAiFix,
                  onAiFixLongPress: _openAiFixMenu,
                  canUndo: _canUndo,
                  canRedo: _canRedo,
                  canAiFix: _canAiFix,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiaryMetaBar extends StatelessWidget {
  const _DiaryMetaBar({
    required this.dateLabel,
    required this.location,
    required this.weather,
    required this.temperature,
    required this.isLoadingLocation,
    required this.onOpenDate,
    required this.onOpenLocation,
    required this.onOpenWeather,
  });

  final String dateLabel;
  final String location;
  final String weather;
  final String? temperature;
  final bool isLoadingLocation;
  final VoidCallback? onOpenDate;
  final VoidCallback? onOpenLocation;
  final VoidCallback? onOpenWeather;

  @override
  Widget build(BuildContext context) {
    final baseWeather = weather.trim().isEmpty ? '天气' : weather;
    final weatherLabel = temperature == null || temperature!.isEmpty
        ? baseWeather
        : '$baseWeather ${temperature!.replaceAll('℃', '°')}';

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Wrap(
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _HoverChip(
                onTap: onOpenDate,
                child: Text(dateLabel,
                    style: Theme.of(context).textTheme.bodySmall)),
            Text(' · ', style: Theme.of(context).textTheme.bodySmall),
            _HoverChip(
              onTap: isLoadingLocation ? null : onOpenLocation,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoadingLocation) ...[
                    const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.4)),
                    const SizedBox(width: 4),
                  ],
                  Text(location, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (weatherLabel.trim().isNotEmpty) ...[
              Text(' · ', style: Theme.of(context).textTheme.bodySmall),
              _HoverChip(
                onTap: onOpenWeather,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_weatherIcon(weather),
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(weatherLabel,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _weatherIcon(String weather) {
    if (weather.contains('雨')) return '🌧';
    if (weather.contains('雪')) return '❄️';
    if (weather.contains('云')) return '⛅';
    if (weather.contains('雾')) return '🌫';
    if (weather.contains('雷')) return '⛈';
    if (weather.contains('晴')) return '☀️';
    return '';
  }
}

class _HoverChip extends StatelessWidget {
  const _HoverChip({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: child,
      ),
    );
  }
}

class _EditorAccessoryBar extends StatelessWidget {
  const _EditorAccessoryBar({
    required this.headingLevel,
    required this.onHeading,
    required this.onHeadingLongPress,
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onList,
    required this.onListLongPress,
    required this.onDivider,
    required this.onImage,
    required this.onUndo,
    required this.onRedo,
    required this.onAiFix,
    required this.onAiFixLongPress,
    required this.canUndo,
    required this.canRedo,
    required this.canAiFix,
  });

  final int headingLevel;
  final VoidCallback onHeading;
  final Future<void> Function([Offset? position]) onHeadingLongPress;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onList;
  final Future<void> Function([Offset? position]) onListLongPress;
  final VoidCallback onDivider;
  final VoidCallback onImage;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onAiFix;
  final Future<void> Function([Offset? position]) onAiFixLongPress;
  final bool canUndo;
  final bool canRedo;
  final bool canAiFix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onSecondaryTapDown: (details) =>
                        onHeadingLongPress(details.globalPosition),
                    onLongPressStart: (details) =>
                        onHeadingLongPress(details.globalPosition),
                    child: IconButton(
                      tooltip: '小标题',
                      visualDensity: VisualDensity.compact,
                      onPressed: onHeading,
                      icon: Text('H$headingLevel',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  IconButton(
                    tooltip: '加粗',
                    visualDensity: VisualDensity.compact,
                    onPressed: onBold,
                    icon: const Icon(Icons.format_bold),
                  ),
                  IconButton(
                    tooltip: '斜体',
                    visualDensity: VisualDensity.compact,
                    onPressed: onItalic,
                    icon: const Icon(Icons.format_italic),
                  ),
                  IconButton(
                    tooltip: '引用',
                    visualDensity: VisualDensity.compact,
                    onPressed: onQuote,
                    icon: const Icon(Icons.format_quote),
                  ),
                  GestureDetector(
                    onSecondaryTapDown: (details) =>
                        onListLongPress(details.globalPosition),
                    onLongPressStart: (details) =>
                        onListLongPress(details.globalPosition),
                    child: IconButton(
                      tooltip: '列表',
                      visualDensity: VisualDensity.compact,
                      onPressed: onList,
                      icon: const Icon(Icons.format_list_bulleted),
                    ),
                  ),
                  IconButton(
                    tooltip: '分割线',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDivider,
                    icon: const Icon(Icons.horizontal_rule),
                  ),
                  IconButton(
                    tooltip: '图片',
                    visualDensity: VisualDensity.compact,
                    onPressed: onImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '撤销',
                visualDensity: VisualDensity.compact,
                onPressed: canUndo ? onUndo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: '重做',
                visualDensity: VisualDensity.compact,
                onPressed: canRedo ? onRedo : null,
                icon: const Icon(Icons.redo),
              ),
              GestureDetector(
                onSecondaryTapDown: (details) =>
                    onAiFixLongPress(details.globalPosition),
                onLongPressStart: (details) =>
                    onAiFixLongPress(details.globalPosition),
                child: IconButton(
                  tooltip: 'AI修复',
                  visualDensity: VisualDensity.compact,
                  onPressed: canAiFix ? onAiFix : null,
                  icon: const Icon(Icons.auto_fix_high),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _EditorMenuAction {
  togglePreview,
  saveNow,
  toggleAutoSave,
  toggleAiFixMode,
  customAiFix,
  discard,
  delete
}

enum _AiFixMenuAction { toggleCustom, custom }

enum _ListStyle { unordered, ordered, checkbox }

enum _LeaveAction { save, discard, cancel }

class _DiaryPlaceholders {
  const _DiaryPlaceholders._();
  static const gentle = [
    '今天有什么一闪而过的小事？',
    '一句也行。趁它还没消失。',
    '随便写点什么，不一定要有意义。',
    '今天哪一刻，你差点忘了，但还是想记下来？',
    '不用很长。一句话的真实，胜过千言万语。',
    '哪怕只是“今天吃了很好吃的面”。',
    '有什么微小到不好意思发朋友圈的事？',
    '今天有没有哪一秒，世界突然安静了？'
  ];
  static const emotional = [
    '你此刻的感受，值得被看见。',
    '没有别人的目光，只有你自己的。',
    '今天，有什么不想忘掉的？',
    '那个不被理解的瞬间，是什么？',
    '如果没人问你今天过得好不好，这里会。',
    '今天有没有一句话，让你忍住了没说？',
    '所有的情绪，在这里都是被允许的。',
    '今天，你对自己温柔了吗？'
  ];
  static const perspective = [
    '今天学到的最小的一件事是什么？',
    '如果今天是一部电影，最精彩的那一幕是？',
    '今天，你和谁说了最多的话？',
    '今天的哪个决定，可能会影响明天？',
    '有没有一个瞬间，让你觉得“活着真好”？',
    '今天的你，和昨天的你，有什么不同？',
    '如果今天是一首歌，歌名会是什么？',
    '今天，什么让你多停留了几秒？'
  ];
  static const review = [
    '今天有什么事情，让你觉得有点难？',
    '有没有一件事，你处理得比上次更好了？',
    '今天有没有什么，是你想停下来的？',
    '如果明天可以重来，今天你会改变什么？',
    '今天有什么，是你想感谢自己的？',
    '那个小小的进步，你注意到了吗？',
    '今天有没有什么，让你觉得离想要的自己更近了？',
    '如果给今天的自己一个拥抱，因为什么？'
  ];
}

class _WeatherSheet extends StatefulWidget {
  const _WeatherSheet({required this.weather, required this.temperature});

  final String weather;
  final String? temperature;

  @override
  State<_WeatherSheet> createState() => _WeatherSheetState();
}

class _WeatherSheetState extends State<_WeatherSheet> {
  late String _weather = widget.weather;
  late final TextEditingController _temperatureController =
      TextEditingController(
          text: widget.temperature?.replaceAll('℃', '') ?? '');
  bool _showTemperature = true;

  static const _weatherOptions = [
    ('☀️', '晴'),
    ('⛅', '多云'),
    ('🌧️', '雨'),
    ('❄️', '雪'),
    ('🌫️', '雾'),
    ('⛈️', '雷雨')
  ];

  @override
  void initState() {
    super.initState();
    _showTemperature =
        widget.temperature != null && widget.temperature!.isNotEmpty;
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    super.dispose();
  }

  void _submit({String? weather}) {
    final value = _temperatureController.text.trim();
    Navigator.of(context).pop(_WeatherEditResult(
        weather: weather ?? _weather,
        temperature: _showTemperature && value.isNotEmpty ? '$value℃' : null));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('天气温度',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _weatherOptions)
                  ChoiceChip(
                    label: Text('${option.$1} ${option.$2}'),
                    selected: _weather == option.$2,
                    onSelected: (_) => setState(() => _weather = option.$2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _temperatureController,
              enabled: _showTemperature,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: '温度', suffixText: '℃'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示温度'),
              value: _showTemperature,
              onChanged: (value) => setState(() => _showTemperature = value),
            ),
            Row(
              children: [
                TextButton(
                    onPressed: () => _submit(weather: '昨日'),
                    child: const Text('改为昨日')),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _submit, child: const Text('保存')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherEditResult {
  const _WeatherEditResult({required this.weather, required this.temperature});

  final String weather;
  final String? temperature;
}

class _LocationSheet extends StatefulWidget {
  const _LocationSheet({
    required this.recentLocations,
    required this.currentLocation,
    required this.weather,
    required this.temperature,
  });

  final List<LocationWeather> recentLocations;
  final String currentLocation;
  final String weather;
  final String? temperature;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  String get _initialLocation =>
      widget.currentLocation == '未选择地点' || widget.currentLocation == '点击选择地点'
          ? ''
          : widget.currentLocation;

  Future<void> _openMapPicker() async {
    final result = await Navigator.of(context).push<LocationWeather>(
      MaterialPageRoute(
        builder: (_) => MapPickerPage(
          weather: widget.weather,
          temperature: widget.temperature,
        ),
      ),
    );
    if (result == null || !mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('选择地点',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.my_location_outlined),
              title: Text(
                  '当前（${_initialLocation.isEmpty ? '未选择地点' : _initialLocation}）'),
              subtitle: Text([
                widget.weather,
                if (widget.temperature?.isNotEmpty ?? false)
                  widget.temperature!,
              ].join(' · ')),
              onTap: _initialLocation.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(LocationWeather(
                        latitude: 0,
                        longitude: 0,
                        locationName: _initialLocation,
                        weather: widget.weather,
                        temperature: widget.temperature ?? '',
                      )),
            ),
            const Divider(height: 28),
            Text('最近使用', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (widget.recentLocations.isEmpty)
              Text('无最近使用的地点',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(context).disabledColor))
            else
              for (final item in widget.recentLocations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(item.locationName),
                  subtitle: Text([
                    item.weather,
                    if (item.temperature.isNotEmpty) item.temperature,
                  ].join(' · ')),
                  onTap: () => Navigator.of(context).pop(item),
                ),
            const Divider(height: 28),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.map_outlined),
              title: const Text('地图选点'),
              subtitle: const Text('打开地图页面搜索或定位'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openMapPicker,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip(
      {required this.images, required this.onInsert, required this.onRemove});

  final List<XFile> images;
  final ValueChanged<XFile> onInsert;
  final ValueChanged<XFile> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final image = images[index];
          return Stack(
            children: [
              InkWell(
                onTap: () => onInsert(image),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: kIsWeb
                      ? Image.network(image.path,
                          width: 88, height: 88, fit: BoxFit.cover)
                      : Image.file(File(image.path),
                          width: 88, height: 88, fit: BoxFit.cover),
                ),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onRemove(image),
                  icon: const Icon(Icons.close, size: 16),
                ),
              ),
            ],
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: images.length,
      ),
    );
  }
}

class _DiaryReadView extends StatelessWidget {
  const _DiaryReadView({
    required this.text,
    required this.isAnalyzing,
    required this.insightFuture,
    required this.error,
    required this.onRefresh,
  });

  final String text;
  final bool isAnalyzing;
  final Future<DiaryInsight?>? insightFuture;
  final String? error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final lines = text.isEmpty ? ['还没有内容。'] : text.split('\n');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      children: [
        for (final line in lines) _PreviewLine(line: line),
        const SizedBox(height: 22),
        Center(
          child: Container(
            width: 56,
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        const SizedBox(height: 22),
        _ReadInsightSection(
          isAnalyzing: isAnalyzing,
          insightFuture: insightFuture,
          error: error,
        ),
        const SizedBox(height: 28),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'END · 仅供参考',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              IconButton(
                tooltip: '重新分析',
                visualDensity: VisualDensity.compact,
                onPressed: isAnalyzing ? null : onRefresh,
                icon: Icon(Icons.refresh,
                    size: 16, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadInsightSection extends StatelessWidget {
  const _ReadInsightSection({
    required this.isAnalyzing,
    required this.insightFuture,
    required this.error,
  });

  final bool isAnalyzing;
  final Future<DiaryInsight?>? insightFuture;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (isAnalyzing) return const _InsightLoadingBlock();
    if (error != null) return _InsightErrorBlock(message: error!);
    return FutureBuilder<DiaryInsight?>(
      future: insightFuture,
      builder: (context, snapshot) {
        final insight = snapshot.data;
        if (insight == null) return const _InsightLoadingBlock();
        return _InsightResultBlock(insight: insight);
      },
    );
  }
}

class _InsightLoadingBlock extends StatefulWidget {
  const _InsightLoadingBlock();

  @override
  State<_InsightLoadingBlock> createState() => _InsightLoadingBlockState();
}

class _InsightLoadingBlockState extends State<_InsightLoadingBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Opacity(
        opacity: 0.45 + _controller.value * 0.35,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('正在分析这篇日记',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            SizedBox(height: 10),
            Text('正在结合历史记录与相关日记生成分析。'),
          ],
        ),
      ),
    );
  }
}

class _InsightErrorBlock extends StatelessWidget {
  const _InsightErrorBlock({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('分析失败',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text(message),
      ],
    );
  }
}

class _InsightResultBlock extends StatelessWidget {
  const _InsightResultBlock({required this.insight});

  final DiaryInsight insight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('日记 AI 分析',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (insight.reflection.isNotEmpty) Text(insight.reflection),
        if (insight.relatedMemories.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('关联日记', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final memory in insight.relatedMemories)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                  '· ${memory.title}${memory.reason.isEmpty ? '' : '：${memory.reason}'}'),
            ),
        ],
        if (insight.stoneTitle.isNotEmpty ||
            insight.stoneDescription.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('建议', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          if (insight.stoneTitle.isNotEmpty)
            Text(insight.stoneTitle,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          if (insight.stoneDescription.isNotEmpty)
            Text(insight.stoneDescription),
        ],
      ],
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.isEmpty ? ['还没有内容。'] : text.split('\n');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [for (final line in lines) _PreviewLine(line: line)],
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(line.substring(2),
            style: Theme.of(context).textTheme.headlineSmall),
      );
    }
    if (line.startsWith('> ')) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(line.substring(2)),
        ),
      );
    }
    if (line.startsWith('![')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(line, style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(line),
    );
  }
}
