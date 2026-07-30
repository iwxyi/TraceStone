import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_auth_session.dart';
import '../repositories/app_auth_repository.dart';

class AppAuthService {
  const AppAuthService({
    AppAuthRepository? repository,
    http.Client? client,
  })  : _repository = repository ?? const AppAuthRepository(),
        _client = client;

  final AppAuthRepository _repository;
  final http.Client? _client;

  Future<SendCodeResult> sendCode(String mobile) async {
    final normalizedMobile = mobile.trim();
    if (normalizedMobile.isEmpty) {
      throw const AppAuthException('请输入手机号');
    }
    final data = await _post(
      '/api/auth/send-code',
      {
        'appId': AppAuthRepository.appId,
        'mobile': normalizedMobile,
      },
    );
    return SendCodeResult.fromJson(data);
  }

  Future<AppAuthSession> login({
    required String mobile,
    required String code,
  }) async {
    final normalizedMobile = mobile.trim();
    final normalizedCode = code.trim();
    if (normalizedMobile.isEmpty) {
      throw const AppAuthException('请输入手机号');
    }
    if (normalizedCode.isEmpty) {
      throw const AppAuthException('请输入验证码');
    }
    final data = await _post(
      '/api/auth/login',
      {
        'appId': AppAuthRepository.appId,
        'mobile': normalizedMobile,
        'code': normalizedCode,
      },
    );
    final session = AppAuthSession.fromJson(data);
    if (session == null) {
      throw const AppAuthException('登录响应缺少账号信息');
    }
    await _repository.saveSession(session);
    return session;
  }

  Future<AppAuthSession> passwordLogin({
    required String account,
    required String password,
  }) async {
    final normalizedAccount = account.trim();
    if (normalizedAccount.isEmpty) {
      throw const AppAuthException('请输入手机号');
    }
    if (password.isEmpty) {
      throw const AppAuthException('请输入密码');
    }
    final data = await _post(
      '/api/auth/password-login',
      {
        'appId': AppAuthRepository.appId,
        'account': normalizedAccount,
        'password': password,
      },
    );
    final session = AppAuthSession.fromJson(data);
    if (session == null) {
      throw const AppAuthException('登录响应缺少账号信息');
    }
    await _repository.saveSession(session);
    return session;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final client = _client ?? http.Client();
    final shouldCloseClient = _client == null;
    try {
      final baseUrl = await _repository.loadBaseUrl();
      final response = await client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = _decodeResponse(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppAuthException(_responseMessage(decoded, response.statusCode));
      }
      final code = decoded['code'];
      final success = code == null || code == 0 || code == 200;
      if (!success) {
        throw AppAuthException(_responseMessage(decoded, response.statusCode));
      }
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      return const {};
    } on AppAuthException {
      rethrow;
    } on http.ClientException catch (error) {
      if (kIsWeb) {
        throw AppAuthException(
          '网络请求失败：浏览器无法访问后端，请检查后端 CORS 配置和地址。$error',
        );
      }
      throw AppAuthException('网络请求失败：$error');
    } on Object catch (error) {
      throw AppAuthException('网络请求失败：$error');
    } finally {
      if (shouldCloseClient) client.close();
    }
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on Object {
      // Fall through to a generic error below.
    }
    throw const AppAuthException('后端响应格式异常');
  }

  String _responseMessage(Map<String, dynamic> body, int statusCode) {
    final message = body['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    return '请求失败：$statusCode';
  }
}

class SendCodeResult {
  const SendCodeResult({
    required this.sent,
    required this.expireSeconds,
    this.debugCode = '',
  });

  final bool sent;
  final int expireSeconds;
  final String debugCode;

  static SendCodeResult fromJson(Map<String, dynamic> json) {
    return SendCodeResult(
      sent: json['sent'] is bool ? json['sent'] as bool : true,
      expireSeconds: _intValue(json['expireSeconds'], fallback: 60),
      debugCode: json['debugCode'] is String ? json['debugCode'] as String : '',
    );
  }

  static int _intValue(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class AppAuthException implements Exception {
  const AppAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
