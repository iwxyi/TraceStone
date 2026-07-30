import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_auth_session.dart';

class AppAuthRepository {
  const AppAuthRepository({
    AppSecureSessionStore? secureStore,
  }) : _secureStore = secureStore ?? const FlutterSecureSessionStore();

  final AppSecureSessionStore _secureStore;

  static const appId = '1003';
  static const _sessionKey = 'app.auth.session';
  static const _secureSessionKey = 'app.auth.secureSession';
  static const _baseUrlKey = 'app.backend.baseUrl';
  static const defaultBaseUrl = 'http://localhost:8888';

  Future<AppAuthSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await _readSessionJson(prefs);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await _deleteSessionJson(prefs);
        return null;
      }
      final session = AppAuthSession.fromJson(decoded);
      if (session == null || session.isExpired) {
        await _deleteSessionJson(prefs);
        return null;
      }
      return session;
    } on Object {
      await _deleteSessionJson(prefs);
      return null;
    }
  }

  Future<AppAuthSession> requireSession() async {
    final session = await loadSession();
    if (session == null || !session.isValid) {
      if (session?.isExpired ?? false) await clearSession();
      throw const AppAuthRequiredException('请先登录');
    }
    return session;
  }

  Future<void> saveSession(AppAuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeSessionJson(prefs, jsonEncode(session.toJson()));
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await _deleteSessionJson(prefs);
  }

  Future<String> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = (_safeGetString(prefs, _baseUrlKey) ?? defaultBaseUrl).trim();
    return value.isEmpty
        ? defaultBaseUrl
        : value.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> saveBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty || normalized == defaultBaseUrl) {
      await prefs.remove(_baseUrlKey);
      return;
    }
    await prefs.setString(_baseUrlKey, normalized);
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }

  Future<String?> _readSessionJson(SharedPreferences prefs) async {
    final legacyRaw = _safeGetString(prefs, _sessionKey);
    if (legacyRaw != null && legacyRaw.trim().isNotEmpty) {
      if (_secureStore is! FlutterSecureSessionStore) {
        await _writeSessionJson(prefs, legacyRaw);
      }
      return legacyRaw;
    }
    String? secureRaw;
    try {
      secureRaw = await _secureStore
          .read(_secureSessionKey)
          .timeout(const Duration(milliseconds: 600));
    } on Object {
      secureRaw = null;
    }
    if (secureRaw != null && secureRaw.trim().isNotEmpty) return secureRaw;
    return null;
  }

  Future<void> _writeSessionJson(SharedPreferences prefs, String value) async {
    try {
      await _secureStore
          .write(_secureSessionKey, value)
          .timeout(const Duration(milliseconds: 600));
      await prefs.remove(_sessionKey);
    } on Object {
      await prefs.setString(_sessionKey, value);
    }
  }

  Future<void> _deleteSessionJson(SharedPreferences prefs) async {
    try {
      await _secureStore
          .delete(_secureSessionKey)
          .timeout(const Duration(milliseconds: 600));
    } on Object {
      // Also clear the legacy fallback below.
    }
    await prefs.remove(_sessionKey);
  }
}

abstract interface class AppSecureSessionStore {
  const AppSecureSessionStore();

  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureSessionStore implements AppSecureSessionStore {
  const FlutterSecureSessionStore();

  static final _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class AppAuthRequiredException implements Exception {
  const AppAuthRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}
