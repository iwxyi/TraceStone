import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_auth_session.dart';
import '../repositories/app_auth_repository.dart';

class AppBackendClient {
  const AppBackendClient({
    AppAuthRepository? repository,
    http.Client? client,
  })  : _repository = repository ?? const AppAuthRepository(),
        _client = client;

  final AppAuthRepository _repository;
  final http.Client? _client;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, Object?> query = const {},
    bool authenticated = false,
  }) async {
    return _request(
      'GET',
      path,
      query: query,
      authenticated: authenticated,
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, Object?> body = const {},
    bool authenticated = false,
  }) async {
    return _request(
      'POST',
      path,
      body: body,
      authenticated: authenticated,
    );
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, Object?> body = const {},
    bool authenticated = false,
  }) async {
    return _request(
      'PUT',
      path,
      body: body,
      authenticated: authenticated,
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?> body = const {},
    bool authenticated = false,
  }) async {
    final client = _client ?? http.Client();
    final shouldCloseClient = _client == null;
    try {
      final baseUrl = await _repository.loadBaseUrl();
      final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: _queryParameters(query),
      );
      final session = authenticated ? await _repository.requireSession() : null;
      final headers = _headers(session);
      final response = await _send(
        client,
        method,
        uri,
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 15));
      final decoded = _decodeResponse(response.body);
      if (response.statusCode == 401) {
        await _repository.clearSession();
        throw const AppBackendException('登录已过期，请重新登录');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppBackendException(
            _responseMessage(decoded, response.statusCode));
      }
      final code = decoded['code'];
      final success = code == null || code == 0 || code == 200;
      if (!success) {
        throw AppBackendException(
            _responseMessage(decoded, response.statusCode));
      }
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      return const {};
    } on AppBackendException {
      rethrow;
    } on AppAuthRequiredException catch (error) {
      throw AppBackendException(error.message);
    } on FormatException {
      rethrow;
    } on http.ClientException catch (error) {
      if (kIsWeb) {
        throw AppBackendException(
          '网络请求失败：浏览器无法访问后端，请检查后端 CORS 配置和地址。$error',
        );
      }
      throw AppBackendException('网络请求失败：$error');
    } on Object catch (error) {
      throw AppBackendException('网络请求失败：$error');
    } finally {
      if (shouldCloseClient) client.close();
    }
  }

  Future<http.Response> _send(
    http.Client client,
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) {
    switch (method) {
      case 'GET':
        return client.get(uri, headers: headers);
      case 'POST':
        return client.post(uri, headers: headers, body: jsonEncode(body));
      case 'PUT':
        return client.put(uri, headers: headers, body: jsonEncode(body));
      default:
        throw AppBackendException('不支持的请求方法：$method');
    }
  }

  Map<String, String> _headers(AppAuthSession? session) {
    return {
      'Content-Type': 'application/json',
      if (session != null) 'Authorization': 'Bearer ${session.token}',
    };
  }

  Map<String, String>? _queryParameters(Map<String, Object?> query) {
    final values = <String, String>{};
    for (final entry in query.entries) {
      final value = entry.value;
      if (value == null) continue;
      final text = value.toString();
      if (text.isEmpty) continue;
      values[entry.key] = text;
    }
    return values.isEmpty ? null : values;
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on Object {
      // Fall through to a generic error below.
    }
    throw const AppBackendException('后端响应格式异常');
  }

  String _responseMessage(Map<String, dynamic> body, int statusCode) {
    final message = body['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    return '请求失败：$statusCode';
  }
}

class AppBackendException implements Exception {
  const AppBackendException(this.message);

  final String message;

  @override
  String toString() => message;
}
