import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/webdav_config.dart';

class WebDavConfigRepository {
  const WebDavConfigRepository({
    WebDavSecretStore? secretStore,
  }) : _secretStore = secretStore ?? const FlutterWebDavSecretStore();

  final WebDavSecretStore _secretStore;

  static const _configKey = 'webdav.config';
  static const _passwordKey = 'webdav.password';

  Future<WebDavConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final password = await _readPassword();
    final raw = _safeGetString(prefs, _configKey);
    if (raw == null || raw.trim().isEmpty) {
      return WebDavConfig.empty.copyWith(password: password);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return WebDavConfig.empty.copyWith(password: password);
      }
      return WebDavConfig.fromJson(decoded, password: password);
    } on Object {
      return WebDavConfig.empty.copyWith(password: password);
    }
  }

  Future<void> saveConfig(WebDavConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
    if (config.password.trim().isEmpty) {
      await _secretStore.delete(_passwordKey);
    } else {
      await _secretStore.write(_passwordKey, config.password);
    }
  }

  Future<void> saveLastBackupAt(DateTime value) async {
    final config = await loadConfig();
    await saveConfig(config.copyWith(lastBackupAt: value));
  }

  Future<void> saveLastRestoreAt(DateTime value) async {
    final config = await loadConfig();
    await saveConfig(config.copyWith(lastRestoreAt: value));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configKey);
    await _secretStore.delete(_passwordKey);
  }

  Future<String> _readPassword() async {
    try {
      return await _secretStore
              .read(_passwordKey)
              .timeout(const Duration(milliseconds: 600)) ??
          '';
    } on Object {
      return '';
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
}

abstract interface class WebDavSecretStore {
  const WebDavSecretStore();

  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterWebDavSecretStore implements WebDavSecretStore {
  const FlutterWebDavSecretStore();

  static final _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
