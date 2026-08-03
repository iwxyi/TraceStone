import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_lock_settings.dart';

class AppLockRepository {
  const AppLockRepository({
    AppLockSecureStore? secureStore,
  }) : _secureStore = secureStore ?? const FlutterAppLockSecureStore();

  final AppLockSecureStore _secureStore;

  static const _settingsKey = 'app.lock.settings';

  Future<AppLockSettings> loadSettings() async {
    String? raw;
    try {
      raw = await _secureStore.read(_settingsKey);
    } on Object {
      return AppLockSettings.disabled;
    }
    if (raw == null || raw.trim().isEmpty) return AppLockSettings.disabled;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AppLockSettings.fromJson(decoded);
      }
    } on Object {
      await clear();
    }
    return AppLockSettings.disabled;
  }

  Future<void> saveSettings(AppLockSettings settings) async {
    await _secureStore.write(
      _settingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  Future<AppLockSettings> disable() async {
    final current = await loadSettings();
    final next = current.copyWith(
      enabled: false,
      method: AppLockMethod.none,
      updatedAt: DateTime.now(),
    );
    await saveSettings(next);
    return next;
  }

  Future<AppLockSettings> setSystemLock({
    required int requireAfterSeconds,
  }) async {
    final next = AppLockSettings(
      enabled: true,
      method: AppLockMethod.system,
      requireAfterSeconds: requireAfterSeconds,
      updatedAt: DateTime.now(),
    );
    await saveSettings(next);
    return next;
  }

  Future<AppLockSettings> setLocalSecret({
    required AppLockMethod method,
    required String secret,
    required int requireAfterSeconds,
  }) async {
    if (method != AppLockMethod.pin && method != AppLockMethod.password) {
      throw const AppLockException('不支持的锁定方式');
    }
    final normalized = secret.trim();
    if (method == AppLockMethod.pin &&
        !RegExp(r'^\d{4,6}$').hasMatch(normalized)) {
      throw const AppLockException('PIN 需要 4-6 位数字');
    }
    if (method == AppLockMethod.password && normalized.length < 6) {
      throw const AppLockException('密码至少需要 6 位');
    }
    final salt = _salt();
    final next = AppLockSettings(
      enabled: true,
      method: method,
      requireAfterSeconds: requireAfterSeconds,
      secretHash: _hashSecret(normalized, salt),
      secretSalt: salt,
      updatedAt: DateTime.now(),
    );
    await saveSettings(next);
    return next;
  }

  Future<bool> verifySecret(String secret) async {
    final settings = await loadSettings();
    if (!settings.hasLocalSecret) return false;
    return _hashSecret(secret.trim(), settings.secretSalt) ==
        settings.secretHash;
  }

  Future<void> clear() => _secureStore.delete(_settingsKey);

  String _salt() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(values);
  }

  String _hashSecret(String secret, String salt) {
    final bytes = utf8.encode('$salt:$secret');
    return sha256.convert(bytes).toString();
  }
}

abstract interface class AppLockSecureStore {
  const AppLockSecureStore();

  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterAppLockSecureStore implements AppLockSecureStore {
  const FlutterAppLockSecureStore();

  static final _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class AppLockException implements Exception {
  const AppLockException(this.message);

  final String message;

  @override
  String toString() => message;
}
