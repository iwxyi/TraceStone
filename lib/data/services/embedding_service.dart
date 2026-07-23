import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_embedding.dart';
import 'ai_client_service.dart';

class EmbeddingService {
  const EmbeddingService();

  static const modelId = 'local-hashing-embedding';
  static const modelVersion = 'v1';
  static const dimensions = 128;
  static const _useOfficialKey = 'ai.useOfficial';
  static const _platformKey = 'ai.platform';
  static const _baseUrlKey = 'ai.baseUrl';
  static const _apiKeyKey = 'ai.apiKey';
  static const _embeddingUseChatConfigKey = 'ai.embeddingUseChatConfig';
  static const _embeddingPlatformKey = 'ai.embeddingPlatform';
  static const _embeddingBaseUrlKey = 'ai.embeddingBaseUrl';
  static const _embeddingApiKeyKey = 'ai.embeddingApiKey';
  static const _embeddingModelKey = 'ai.embeddingModel';
  static const _embeddingRemoteAvailableKey = 'ai.embeddingRemoteAvailable';
  static const _defaultEmbeddingModel = 'text-embedding-3-small';

  Future<EmbeddingModelSignature> currentTargetSignature() async {
    final prefs = await SharedPreferences.getInstance();
    final useOfficial = _safeGetBool(prefs, _useOfficialKey) ?? true;
    if (useOfficial) return localSignature;
    final remoteAvailable = _safeGetBool(prefs, _embeddingRemoteAvailableKey);
    if (remoteAvailable == false) return localSignature;
    final useChatConfig =
        _safeGetBool(prefs, _embeddingUseChatConfigKey) ?? true;
    final platform = useChatConfig
        ? _safeGetString(prefs, _platformKey) ?? 'OpenAI'
        : _safeGetString(prefs, _embeddingPlatformKey) ?? 'OpenAI';
    final baseUrlValue = useChatConfig
        ? _safeGetString(prefs, _baseUrlKey)
        : _safeGetString(prefs, _embeddingBaseUrlKey) ??
            _safeGetString(prefs, _baseUrlKey);
    final apiKeyValue = useChatConfig
        ? _safeGetString(prefs, _apiKeyKey)
        : _safeGetString(prefs, _embeddingApiKeyKey) ??
            _safeGetString(prefs, _apiKeyKey);
    final baseUrl = (baseUrlValue ?? '').trim();
    final apiKey = (apiKeyValue ?? '').trim();
    final model =
        (_safeGetString(prefs, _embeddingModelKey) ?? _defaultEmbeddingModel)
            .trim();
    if (_platformDoesNotSupportEmbeddings(platform, baseUrl)) {
      await prefs.setBool(_embeddingRemoteAvailableKey, false);
      return localSignature;
    }
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      return localSignature;
    }
    return EmbeddingModelSignature(
      modelId: model,
      modelVersion: 'remote',
    );
  }

  static const localSignature = EmbeddingModelSignature(
    modelId: modelId,
    modelVersion: modelVersion,
    dimensions: dimensions,
  );

  Future<AiEmbeddingResult> embedForAi(String text) async {
    final signature = await currentTargetSignature();
    if (signature.modelId == modelId &&
        signature.modelVersion == modelVersion &&
        signature.dimensions == dimensions) {
      return embed(text);
    }
    try {
      final result = await _embedRemote(text);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_embeddingRemoteAvailableKey, true);
      return result;
    } on AiClientException catch (error) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_embeddingRemoteAvailableKey, false);
      throw AiClientException(
        '向量生成失败：${error.message}',
        retryable: error.retryable,
      );
    } on Object catch (error) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_embeddingRemoteAvailableKey, false);
      throw AiClientException('向量生成失败：$error');
    }
  }

  AiEmbeddingResult embed(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final vector = List<double>.filled(dimensions, 0);
    final tokens = _tokens(normalized);
    for (final token in tokens) {
      final hash = _hash(token);
      final index = hash.abs() % dimensions;
      final sign = hash.isEven ? 1.0 : -1.0;
      final weight = token.length >= 4 ? 1.4 : 1.0;
      vector[index] += sign * weight;
    }
    _normalize(vector);
    return AiEmbeddingResult(
      modelId: modelId,
      modelVersion: modelVersion,
      dimensions: dimensions,
      vector: vector,
      textHash: _hash(normalized).toRadixString(16),
    );
  }

  Future<AiEmbeddingResult> _embedRemote(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final useOfficial = _safeGetBool(prefs, _useOfficialKey) ?? true;
    if (useOfficial) {
      throw const AiClientException('当前未开启自定义 AI', retryable: false);
    }
    final useChatConfig =
        _safeGetBool(prefs, _embeddingUseChatConfigKey) ?? true;
    final platform = useChatConfig
        ? _safeGetString(prefs, _platformKey) ?? 'OpenAI'
        : _safeGetString(prefs, _embeddingPlatformKey) ?? 'OpenAI';
    final baseUrlValue = useChatConfig
        ? _safeGetString(prefs, _baseUrlKey)
        : _safeGetString(prefs, _embeddingBaseUrlKey) ??
            _safeGetString(prefs, _baseUrlKey);
    final apiKeyValue = useChatConfig
        ? _safeGetString(prefs, _apiKeyKey)
        : _safeGetString(prefs, _embeddingApiKeyKey) ??
            _safeGetString(prefs, _apiKeyKey);
    final baseUrl = (baseUrlValue ?? '').trim();
    final apiKey = (apiKeyValue ?? '').trim();
    final model =
        (_safeGetString(prefs, _embeddingModelKey) ?? _defaultEmbeddingModel)
            .trim();
    if (_platformDoesNotSupportEmbeddings(platform, baseUrl)) {
      throw const AiClientException('当前平台不支持 OpenAI embeddings');
    }
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      throw const AiClientException('请先完成自定义 AI 向量配置', retryable: false);
    }
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final uri =
        Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/embeddings');
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'input': normalized,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiClientException('向量请求失败：${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const AiClientException('向量响应格式异常');
    }
    final items = data['data'];
    if (items is! List || items.isEmpty) {
      throw const AiClientException('向量响应为空');
    }
    final first = items.first;
    if (first is! Map<String, dynamic>) {
      throw const AiClientException('向量响应格式异常');
    }
    final rawVector = first['embedding'];
    if (rawVector is! List || rawVector.isEmpty) {
      throw const AiClientException('向量结果为空');
    }
    final vector = rawVector
        .map((value) => value is num ? value.toDouble() : null)
        .whereType<double>()
        .toList();
    if (vector.isEmpty) {
      throw const AiClientException('向量结果为空');
    }
    _normalize(vector);
    return AiEmbeddingResult(
      modelId: model,
      modelVersion: 'remote',
      dimensions: vector.length,
      vector: vector,
      textHash: _hash(normalized).toRadixString(16),
    );
  }

  bool? _safeGetBool(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is bool ? value : null;
    } on Object {
      return null;
    }
  }

  bool _platformDoesNotSupportEmbeddings(String platform, String baseUrl) {
    final normalizedPlatform = platform.toLowerCase();
    final normalizedUrl = baseUrl.toLowerCase();
    return normalizedPlatform == 'claude' ||
        normalizedPlatform == 'deepseek' ||
        normalizedUrl.contains('anthropic') ||
        normalizedUrl.contains('deepseek');
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    final length = min(a.length, b.length);
    if (length == 0) return 0;
    var dot = 0.0;
    var aNorm = 0.0;
    var bNorm = 0.0;
    for (var index = 0; index < length; index++) {
      dot += a[index] * b[index];
      aNorm += a[index] * a[index];
      bNorm += b[index] * b[index];
    }
    if (aNorm == 0 || bNorm == 0) return 0;
    return dot / (sqrt(aNorm) * sqrt(bNorm));
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

  void _normalize(List<double> vector) {
    var norm = 0.0;
    for (final value in vector) {
      norm += value * value;
    }
    if (norm == 0) return;
    final divisor = sqrt(norm);
    for (var index = 0; index < vector.length; index++) {
      vector[index] = vector[index] / divisor;
    }
  }

  int _hash(String text) {
    var hash = 0x811c9dc5;
    for (final codeUnit in text.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

class EmbeddingModelSignature {
  const EmbeddingModelSignature({
    required this.modelId,
    required this.modelVersion,
    this.dimensions,
  });

  final String modelId;
  final String modelVersion;
  final int? dimensions;

  bool matches(AiEmbedding embedding) {
    return embedding.modelId == modelId &&
        embedding.modelVersion == modelVersion &&
        (dimensions == null || embedding.dimensions == dimensions);
  }

  String get label => dimensions == null
      ? '$modelId/$modelVersion'
      : '$modelId/$modelVersion/${dimensions}d';
}
