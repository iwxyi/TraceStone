import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiClientService {
  const AiClientService();

  static const _useOfficialKey = 'ai.useOfficial';
  static const _platformKey = 'ai.platform';
  static const _baseUrlKey = 'ai.baseUrl';
  static const _apiKeyKey = 'ai.apiKey';
  static const _modelKey = 'ai.model';

  Future<AiClientConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final useOfficial = prefs.getBool(_useOfficialKey) ?? true;
    final platform = prefs.getString(_platformKey) ?? 'OpenAI';
    final baseUrl = (prefs.getString(_baseUrlKey) ?? '').trim();
    final apiKey = (prefs.getString(_apiKeyKey) ?? '').trim();
    final model = (prefs.getString(_modelKey) ?? '').trim();

    if (useOfficial) {
      throw const AiClientException('当前未开启自定义 AI');
    }
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      throw const AiClientException('请先完成自定义 AI 配置');
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

    final response = await http.post(uri, headers: headers, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiClientException('AI 请求失败：${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = isAnthropic
        ? _extractAnthropicContent(data)
        : _extractOpenAiContent(data);
    final jsonText = _extractJson(content);
    return jsonText;
  }

  String _extractOpenAiContent(Map<String, dynamic> data) {
    final choices = data['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) {
      throw const AiClientException('AI 未返回结果');
    }
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = message?['content']?.toString();
    if (content == null || content.isEmpty) {
      throw const AiClientException('AI 返回内容为空');
    }
    return content;
  }

  String _extractAnthropicContent(Map<String, dynamic> data) {
    final content = data['content'] as List<dynamic>? ?? const [];
    if (content.isEmpty) {
      throw const AiClientException('AI 未返回结果');
    }
    final first = content.first as Map<String, dynamic>;
    final text = first['text']?.toString();
    if (text == null || text.isEmpty) {
      throw const AiClientException('AI 返回内容为空');
    }
    return text;
  }

  String _extractJson(String content) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (match == null) {
      throw const AiClientException('AI 返回格式无法解析');
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

class AiClientException implements Exception {
  const AiClientException(this.message);

  final String message;

  @override
  String toString() => message;
}
