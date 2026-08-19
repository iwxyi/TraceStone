import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiClientService {
  const AiClientService({http.Client? httpClient}) : _httpClient = httpClient;

  final http.Client? _httpClient;

  static DateTime? _requestStartedAt;
  static DateTime? _responseReceivedAt;
  static String? _requestEndpoint;
  static String? _requestOutcome;

  static String get debugRequestState {
    final startedAt = _requestStartedAt;
    if (startedAt == null) return 'idle';
    final responseAt = _responseReceivedAt;
    final elapsed = (responseAt ?? DateTime.now()).difference(startedAt);
    return 'startedAt=${startedAt.toIso8601String()} '
        'elapsed=${elapsed.inSeconds}s '
        'endpoint=${_requestEndpoint ?? 'unknown'} '
        'response=${responseAt == null ? 'waiting' : responseAt.toIso8601String()} '
        'outcome=${_requestOutcome ?? 'waiting'}';
  }

  static const _useOfficialKey = 'ai.useOfficial';
  static const _platformKey = 'ai.platform';
  static const _baseUrlKey = 'ai.baseUrl';
  static const _apiKeyKey = 'ai.apiKey';
  static const _modelKey = 'ai.model';
  static const _requestTimeout = Duration(seconds: 75);

  Future<AiClientConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final useOfficial = _safeGetBool(prefs, _useOfficialKey) ?? true;
    final platform = _safeGetString(prefs, _platformKey) ?? 'OpenAI';
    final baseUrl = (_safeGetString(prefs, _baseUrlKey) ?? '').trim();
    final apiKey = (_safeGetString(prefs, _apiKeyKey) ?? '').trim();
    final model = (_safeGetString(prefs, _modelKey) ?? '').trim();

    if (useOfficial) {
      throw const AiClientException(
        'AI 配置错误：当前未开启自定义 AI',
        retryable: false,
        kind: AiClientErrorKind.configuration,
      );
    }
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      throw const AiClientException(
        'AI 配置错误：请先完成自定义 AI 配置',
        retryable: false,
        kind: AiClientErrorKind.configuration,
      );
    }

    return AiClientConfig(
      platform: platform,
      baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
      apiKey: apiKey,
      model: model,
    );
  }

  Future<String> completeJson({
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    final config = await loadConfig();
    return completeJsonWithConfig(
      config: config,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      maxTokens: maxTokens,
    );
  }

  Future<String> completeJsonWithConfig({
    required AiClientConfig config,
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    final isAnthropic =
        config.platform == 'Claude' || config.baseUrl.contains('anthropic');
    final uri = Uri.parse(isAnthropic
        ? '${config.baseUrl}/messages'
        : '${config.baseUrl}/chat/completions');
    final headers = isAnthropic
        ? {
            'x-api-key': config.apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          }
        : {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          };

    final body = isAnthropic
        ? jsonEncode({
            'model': config.model,
            'max_tokens': maxTokens,
            'system': systemPrompt,
            'messages': [
              {'role': 'user', 'content': userPrompt}
            ]
          })
        : jsonEncode({
            'model': config.model,
            'temperature': 0,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt}
            ]
          });

    late final http.Response response;
    _requestStartedAt = DateTime.now();
    _responseReceivedAt = null;
    _requestEndpoint = uri.replace(query: null, fragment: null).toString();
    _requestOutcome = 'requesting';
    try {
      final request = _httpClient == null
          ? http.post(uri, headers: headers, body: body)
          : _httpClient.post(uri, headers: headers, body: body);
      response = await request.timeout(_requestTimeout);
    } on TimeoutException {
      _requestOutcome = 'timeout';
      throw const AiClientException(
        '无法连接 AI 接口：请求超时（75 秒），请检查网络或服务状态',
        kind: AiClientErrorKind.connection,
      );
    } on Object catch (error) {
      _requestOutcome = 'transportError: $error';
      throw AiClientException(
        '无法连接 AI 接口：$error',
        kind: AiClientErrorKind.connection,
      );
    }
    _responseReceivedAt = DateTime.now();
    _requestOutcome = 'http ${response.statusCode}';
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiClientException(
        'AI 服务端返回错误（HTTP ${response.statusCode}）：${_responseErrorDetail(response.body)}',
        retryable: response.statusCode >= 500,
        kind: AiClientErrorKind.serverResponse,
      );
    }

    late final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } on Object catch (error) {
      throw AiClientException(
        'AI 响应格式错误：返回内容不是有效 JSON：$error',
        kind: AiClientErrorKind.responseFormat,
      );
    }
    final content = isAnthropic
        ? _extractAnthropicContent(data)
        : _extractOpenAiContent(data);
    final jsonText = _extractJson(content);
    return jsonText;
  }

  bool? _safeGetBool(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is bool ? value : null;
    } on Object {
      return null;
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

  String _responseErrorDetail(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '服务端没有提供响应正文';
    return trimmed.length > 1000
        ? '${trimmed.substring(0, 1000)}...（响应已截断）'
        : trimmed;
  }

  String _extractOpenAiContent(Map<String, dynamic> data) {
    final choices = data['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) {
      throw const AiClientException('AI 响应格式错误：AI 未返回结果');
    }
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = message?['content']?.toString();
    if (content == null || content.isEmpty) {
      throw const AiClientException('AI 响应格式错误：AI 返回内容为空');
    }
    return content;
  }

  String _extractAnthropicContent(Map<String, dynamic> data) {
    final content = data['content'] as List<dynamic>? ?? const [];
    if (content.isEmpty) {
      throw const AiClientException('AI 响应格式错误：AI 未返回结果');
    }
    final first = content.first as Map<String, dynamic>;
    final text = first['text']?.toString();
    if (text == null || text.isEmpty) {
      throw const AiClientException('AI 响应格式错误：AI 返回内容为空');
    }
    return text;
  }

  String _extractJson(String content) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (match == null) {
      throw const AiClientException('AI 响应格式错误：返回内容无法解析为 JSON');
    }
    return match.group(0)!;
  }
}

class AiClientConfig {
  const AiClientConfig({
    required this.platform,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String platform;
  final String baseUrl;
  final String apiKey;
  final String model;
}

enum AiClientErrorKind {
  configuration,
  connection,
  serverResponse,
  responseFormat,
}

class AiClientException implements Exception {
  const AiClientException(
    this.message, {
    this.retryable = true,
    this.kind = AiClientErrorKind.serverResponse,
  });

  final String message;
  final bool retryable;
  final AiClientErrorKind kind;

  @override
  String toString() => message;
}
