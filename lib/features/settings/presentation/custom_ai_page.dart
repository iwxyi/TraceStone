import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/ai_analysis_queue_runner.dart';

class CustomAiPage extends StatefulWidget {
  const CustomAiPage({super.key});

  @override
  State<CustomAiPage> createState() => _CustomAiPageState();
}

class _CustomAiPrivacyNotice extends StatelessWidget {
  const _CustomAiPrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.privacy_tip_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '自定义 AI 会把当前日记、相关历史摘要、长期记忆、画像、关系档案和行动记录发送到你配置的服务。'
                '秘钥只保存在本机，但第三方服务的数据处理规则由服务方决定。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomAiPageState extends State<CustomAiPage> {
  static const _useOfficialKey = 'ai.useOfficial';
  static const _platformKey = 'ai.platform';
  static const _baseUrlKey = 'ai.baseUrl';
  static const _apiKeyKey = 'ai.apiKey';
  static const _modelKey = 'ai.model';
  static const _embeddingUseChatConfigKey = 'ai.embeddingUseChatConfig';
  static const _embeddingPlatformKey = 'ai.embeddingPlatform';
  static const _embeddingBaseUrlKey = 'ai.embeddingBaseUrl';
  static const _embeddingApiKeyKey = 'ai.embeddingApiKey';
  static const _embeddingModelKey = 'ai.embeddingModel';
  static const _privacyAcceptedKey = 'ai.customPrivacyAccepted';

  final _baseUrlController =
      TextEditingController(text: 'https://api.openai.com/v1');
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _embeddingBaseUrlController =
      TextEditingController(text: 'https://api.openai.com/v1');
  final _embeddingApiKeyController = TextEditingController();
  final _embeddingModelController =
      TextEditingController(text: 'text-embedding-3-small');

  bool _useOfficialAi = true;
  bool _embeddingUseChatConfig = true;
  bool _isLoadingModels = false;
  bool _isTestingConfig = false;
  bool _modelsFetchedOnline = false;
  bool _privacyAccepted = false;
  String _selectedPlatform = 'OpenAI';
  String _selectedEmbeddingPlatform = 'OpenAI';
  String? _modelFetchHint;
  String? _lastFetchUrl;
  Timer? _modelFetchDebounce;
  List<String> _models = const [];

  static const _platforms = [
    ('OpenAI', 'https://api.openai.com/v1'),
    ('Claude', 'https://api.anthropic.com/v1'),
    ('DeepSeek', 'https://api.deepseek.com/v1'),
    ('OpenRouter', 'https://openrouter.ai/api/v1'),
  ];

  static const _defaultModels = {
    'OpenAI': 'gpt-4.1-mini',
    'Claude': 'claude-sonnet-4-5',
    'DeepSeek': 'deepseek-chat',
    'OpenRouter': 'openai/gpt-4.1-mini',
  };

  static const _defaultEmbeddingModels = {
    'OpenAI': 'text-embedding-3-small',
    'DeepSeek': 'text-embedding-3-small',
    'OpenRouter': 'openai/text-embedding-3-small',
  };

  bool get _canAutoFetch =>
      !_useOfficialAi &&
      _apiKeyController.text.trim().isNotEmpty &&
      _baseUrlController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _baseUrlController.addListener(_scheduleModelFetch);
    _apiKeyController.addListener(_scheduleModelFetch);
    _loadSettings();
  }

  @override
  void dispose() {
    _modelFetchDebounce?.cancel();
    _baseUrlController.removeListener(_scheduleModelFetch);
    _apiKeyController.removeListener(_scheduleModelFetch);
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _embeddingBaseUrlController.dispose();
    _embeddingApiKeyController.dispose();
    _embeddingModelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useOfficialAi = _safeGetBool(prefs, _useOfficialKey) ?? true;
      _selectedPlatform =
          _safeGetString(prefs, _platformKey) ?? _selectedPlatform;
      _baseUrlController.text =
          _safeGetString(prefs, _baseUrlKey) ?? _baseUrlController.text;
      _apiKeyController.text = _safeGetString(prefs, _apiKeyKey) ?? '';
      _modelController.text = _safeGetString(prefs, _modelKey) ??
          (_defaultModels[_selectedPlatform] ?? '');
      _embeddingUseChatConfig =
          _safeGetBool(prefs, _embeddingUseChatConfigKey) ?? true;
      _selectedEmbeddingPlatform =
          _safeGetString(prefs, _embeddingPlatformKey) ?? 'OpenAI';
      _embeddingBaseUrlController.text =
          _safeGetString(prefs, _embeddingBaseUrlKey) ??
              _platforms
                  .firstWhere((item) => item.$1 == _selectedEmbeddingPlatform,
                      orElse: () => _platforms.first)
                  .$2;
      _embeddingApiKeyController.text =
          _safeGetString(prefs, _embeddingApiKeyKey) ?? '';
      _embeddingModelController.text =
          _safeGetString(prefs, _embeddingModelKey) ??
              (_defaultEmbeddingModels[_selectedEmbeddingPlatform] ??
                  'text-embedding-3-small');
      _privacyAccepted = _safeGetBool(prefs, _privacyAcceptedKey) ?? false;
    });
    if (_canAutoFetch) {
      await _fetchModels();
    }
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }

  bool? _safeGetBool(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is bool ? value : null;
    } on Object {
      return null;
    }
  }

  Future<void> _saveSettings() async {
    if (!_useOfficialAi && !_privacyAccepted) {
      final accepted = await _confirmCustomAiPrivacy();
      if (accepted != true) return;
      _privacyAccepted = true;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useOfficialKey, _useOfficialAi);
    await prefs.setString(_platformKey, _selectedPlatform);
    await prefs.setString(_baseUrlKey, _baseUrlController.text.trim());
    await prefs.setString(_apiKeyKey, _apiKeyController.text.trim());
    await prefs.setString(_modelKey, _modelController.text.trim());
    await prefs.setBool(_embeddingUseChatConfigKey, _embeddingUseChatConfig);
    await prefs.setString(_embeddingPlatformKey, _selectedEmbeddingPlatform);
    await prefs.setString(
        _embeddingBaseUrlKey, _embeddingBaseUrlController.text.trim());
    await prefs.setString(
        _embeddingApiKeyKey, _embeddingApiKeyController.text.trim());
    await prefs.setString(
        _embeddingModelKey, _embeddingModelController.text.trim());
    await prefs.setBool(_privacyAcceptedKey, _privacyAccepted);
    if (!_useOfficialAi &&
        _baseUrlController.text.trim().isNotEmpty &&
        _apiKeyController.text.trim().isNotEmpty &&
        _modelController.text.trim().isNotEmpty) {
      unawaited(const AiAnalysisQueueRunner().processUntilIdle(maxJobs: 1));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存 AI 设置')));
  }

  Future<bool?> _confirmCustomAiPrivacy() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用第三方 AI？'),
        content: const Text(
          '启用自定义接口后，日记原文、摘要、相关记忆、画像、关系和塑石行动等上下文会发送到你配置的模型服务。'
          '请确认该服务可信，并理解 TraceStone 无法控制第三方如何处理这些数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('我理解并继续'),
          ),
        ],
      ),
    );
  }

  Future<void> _testConfiguration() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先填写接口、秘钥和模型')));
      return;
    }

    setState(() => _isTestingConfig = true);
    try {
      final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final isAnthropic =
          _selectedPlatform == 'Claude' || normalized.contains('anthropic');
      final uri = Uri.parse(isAnthropic
          ? '$normalized/messages'
          : '$normalized/chat/completions');
      final headers = isAnthropic
          ? {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            }
          : {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            };
      final body = jsonEncode({
        'model': model,
        'max_tokens': 16,
        'messages': [
          {'role': 'user', 'content': 'Reply with OK'}
        ]
      });
      final response = await http.post(uri, headers: headers, body: body);
      if (!mounted) return;
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      final embeddingResult = await _testEmbeddingConfiguration();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? embeddingResult == null
                ? '模型配置可用，向量配置可用'
                : '模型配置可用；向量不可用，将回退本地：$embeddingResult'
            : '模型配置不可用：${response.statusCode}'),
      ));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('测试失败：$error')));
    } finally {
      if (mounted) setState(() => _isTestingConfig = false);
    }
  }

  void _handlePlatformChanged(String? value) {
    if (value == null) return;
    final preset = _platforms.firstWhere((item) => item.$1 == value);
    setState(() {
      _selectedPlatform = preset.$1;
      _baseUrlController.text = preset.$2;
      _models = const [];
      _modelsFetchedOnline = false;
      _modelFetchHint = null;
      _lastFetchUrl = null;
      _modelController.text = _defaultModels[value] ?? '';
      _embeddingModelController.text =
          _defaultEmbeddingModels[value] ?? 'text-embedding-3-small';
    });
    _fetchModels();
  }

  void _handleEmbeddingPlatformChanged(String? value) {
    if (value == null) return;
    final preset = _platforms.firstWhere((item) => item.$1 == value);
    setState(() {
      _selectedEmbeddingPlatform = preset.$1;
      _embeddingBaseUrlController.text = preset.$2;
      _embeddingModelController.text =
          _defaultEmbeddingModels[value] ?? 'text-embedding-3-small';
    });
  }

  Future<String?> _testEmbeddingConfiguration() async {
    final platform = _embeddingUseChatConfig
        ? _selectedPlatform
        : _selectedEmbeddingPlatform;
    final baseUrl = (_embeddingUseChatConfig
            ? _baseUrlController.text
            : _embeddingBaseUrlController.text)
        .trim();
    final apiKey = (_embeddingUseChatConfig
            ? _apiKeyController.text
            : _embeddingApiKeyController.text)
        .trim();
    final model = _embeddingModelController.text.trim();
    if (platform == 'Claude' || baseUrl.contains('anthropic')) {
      return '当前平台不支持 OpenAI embeddings';
    }
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      return '向量接口、秘钥或模型为空';
    }
    try {
      final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final response = await http.post(
        Uri.parse('$normalized/embeddings'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'input': 'TraceStone embedding test',
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return '${response.statusCode}';
      }
      final data = jsonDecode(response.body);
      final items = data is Map<String, dynamic> ? data['data'] : null;
      if (items is! List || items.isEmpty) return '响应为空';
      return null;
    } on Object catch (error) {
      return error.toString();
    }
  }

  void _scheduleModelFetch() {
    _modelFetchDebounce?.cancel();
    if (!_canAutoFetch) {
      setState(() {
        _isLoadingModels = false;
        _models = const [];
      });
      return;
    }
    _modelFetchDebounce =
        Timer(const Duration(milliseconds: 400), _fetchModels);
  }

  Future<void> _fetchModels() async {
    if (!_canAutoFetch) {
      setState(() => _modelFetchHint = 'URL 或秘钥为空，未发起请求');
      return;
    }
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    setState(() => _isLoadingModels = true);
    try {
      final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final isAnthropic =
          _selectedPlatform == 'Claude' || normalized.contains('anthropic');
      if (isAnthropic) {
        setState(() {
          _models = const [];
          _modelsFetchedOnline = false;
          _lastFetchUrl = '$normalized/models';
          _modelFetchHint = '该平台暂不支持统一的在线模型枚举，请手动填写模型名';
        });
        return;
      }

      final uri = Uri.parse('$normalized/models');
      setState(() => _lastFetchUrl = uri.toString());
      final response =
          await http.get(uri, headers: {'Authorization': 'Bearer $apiKey'});
      if (!mounted) return;

      if (response.statusCode == 404 || response.statusCode == 405) {
        setState(() {
          _models = const [];
          _modelsFetchedOnline = false;
          _modelFetchHint = '当前接口未提供模型列表接口，请手动填写模型名';
        });
        return;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        setState(() {
          _models = const [];
          _modelsFetchedOnline = false;
          _modelFetchHint = '秘钥无效或无权限获取模型列表';
        });
        return;
      }
      if (response.statusCode != 200) {
        throw Exception('模型拉取失败：${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['data'] as List<dynamic>? ?? [])
          .map((item) => (item as Map<String, dynamic>)['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      setState(() {
        _models = list;
        _modelsFetchedOnline = list.isNotEmpty;
        _modelFetchHint = list.isEmpty ? '接口已响应，但未返回模型列表' : null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _models = const [];
        _modelsFetchedOnline = false;
        _modelFetchHint = '模型自动拉取失败：$error';
      });
    } finally {
      if (mounted) setState(() => _isLoadingModels = false);
    }
  }

  Future<void> _handleModelButtonTap() async {
    if (_models.isEmpty) {
      await _fetchModels();
      return;
    }
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final model in _models)
            ListTile(
              title: Text(model, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(context).pop(model),
            ),
        ],
      ),
    );
    if (value == null) return;
    setState(() => _modelController.text = value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _useOfficialAi;

    return Scaffold(
      appBar: AppBar(title: const Text('自定义 AI')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.cloud_outlined),
              title: const Text('使用官方 AI'),
              subtitle: Text(
                _useOfficialAi ? '由应用内置服务处理 AI 请求' : '使用下方自定义接口，数据会发送到你配置的服务',
              ),
              value: _useOfficialAi,
              onChanged: (value) {
                setState(() => _useOfficialAi = value);
              },
            ),
          ),
          if (!_useOfficialAi) ...[
            const SizedBox(height: 16),
            const _CustomAiPrivacyNotice(),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AbsorbPointer(
                absorbing: disabled,
                child: Opacity(
                  opacity: disabled ? 0.45 : 1,
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _selectedPlatform,
                        decoration: const InputDecoration(labelText: '平台'),
                        items: [
                          for (final item in _platforms)
                            DropdownMenuItem(
                                value: item.$1, child: Text(item.$1)),
                        ],
                        onChanged: _handlePlatformChanged,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _baseUrlController,
                        decoration: const InputDecoration(labelText: '接口 URL'),
                        onChanged: (_) => _scheduleModelFetch(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiKeyController,
                        decoration: const InputDecoration(labelText: '秘钥'),
                        obscureText: true,
                        onChanged: (_) => _scheduleModelFetch(),
                        onSubmitted: (_) => _fetchModels(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _modelController,
                        decoration: InputDecoration(
                          labelText: '模型',
                          helperText: _modelFetchHint,
                          suffixIcon: InkWell(
                            onTap: _handleModelButtonTap,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isLoadingModels)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.8),
                                    )
                                  else
                                    Icon(_modelsFetchedOnline
                                        ? Icons.arrow_drop_down
                                        : Icons.sync_problem),
                                ],
                              ),
                            ),
                          ),
                        ),
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('向量复用当前 AI 配置'),
                        subtitle: const Text('同一服务同时支持聊天和 embeddings 时开启'),
                        value: _embeddingUseChatConfig,
                        onChanged: (value) =>
                            setState(() => _embeddingUseChatConfig = value),
                      ),
                      if (!_embeddingUseChatConfig) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedEmbeddingPlatform,
                          decoration: const InputDecoration(labelText: '向量平台'),
                          items: [
                            for (final item in _platforms)
                              DropdownMenuItem(
                                  value: item.$1, child: Text(item.$1)),
                          ],
                          onChanged: _handleEmbeddingPlatformChanged,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _embeddingBaseUrlController,
                          decoration:
                              const InputDecoration(labelText: '向量接口 URL'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _embeddingApiKeyController,
                          decoration: const InputDecoration(labelText: '向量秘钥'),
                          obscureText: true,
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _embeddingModelController,
                        decoration: const InputDecoration(
                          labelText: '向量模型',
                          helperText: '用于历史相似度检索，OpenAI 兼容接口默认可用',
                        ),
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      ),
                      if (_lastFetchUrl != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '请求地址：$_lastFetchUrl',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isTestingConfig ? null : _testConfiguration,
                  icon: _isTestingConfig
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      : const Icon(Icons.bolt_outlined),
                  label: const Text('测试'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存设置'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
