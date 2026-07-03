import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_embedding.dart';

class AiEmbeddingRepository {
  const AiEmbeddingRepository();

  static const _entryIndexPrefix = 'ai.embeddings.entryIndex.';
  static const _typeIndexPrefix = 'ai.embeddings.typeIndex.';
  static const _prefix = 'ai.embeddings.';

  Future<void> saveEmbedding(AiEmbedding embedding) async {
    final prefs = await SharedPreferences.getInstance();
    final existingRaw = _safeGetString(prefs, '$_prefix${embedding.id}');
    final existing =
        existingRaw == null ? null : _embeddingFromRaw(existingRaw);
    if (existing != null && existing.entryId != embedding.entryId) {
      final oldEntryKey = '$_entryIndexPrefix${existing.entryId}';
      final oldEntryIds = _safeGetStringList(prefs, oldEntryKey) ?? [];
      oldEntryIds.remove(embedding.id);
      await prefs.setStringList(oldEntryKey, oldEntryIds);
    }
    await prefs.setString(
        '$_prefix${embedding.id}', jsonEncode(embedding.toJson()));
    await _addToIndex(
        prefs, '$_entryIndexPrefix${embedding.entryId}', embedding.id);
    await _addToIndex(
        prefs, '$_typeIndexPrefix${embedding.sourceType.name}', embedding.id);
  }

  Future<List<AiEmbedding>> listForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_entryIndexPrefix$entryId';
    final ids = _safeGetStringList(prefs, key) ?? [];
    return _loadMany(prefs, ids, indexKey: key);
  }

  Future<List<AiEmbedding>> listByType(AiEmbeddingSourceType type) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_typeIndexPrefix${type.name}';
    final ids = _safeGetStringList(prefs, key) ?? [];
    return _loadMany(prefs, ids, indexKey: key);
  }

  Future<AiEmbedding?> getBySource({
    required AiEmbeddingSourceType sourceType,
    required String sourceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix${sourceType.name}:$sourceId';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      return AiEmbedding.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> deleteBySource({
    required AiEmbeddingSourceType sourceType,
    required String sourceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final id = '${sourceType.name}:$sourceId';
    final raw = _safeGetString(prefs, '$_prefix$id');
    if (raw != null) {
      final embedding = _embeddingFromRaw(raw);
      if (embedding != null) {
        final entryKey = '$_entryIndexPrefix${embedding.entryId}';
        final entryIds = _safeGetStringList(prefs, entryKey) ?? [];
        entryIds.remove(id);
        await prefs.setStringList(entryKey, entryIds);
      }
    }
    final typeKey = '$_typeIndexPrefix${sourceType.name}';
    final typeIds = _safeGetStringList(prefs, typeKey) ?? [];
    typeIds.remove(id);
    await prefs.setStringList(typeKey, typeIds);
    await prefs.remove('$_prefix$id');
  }

  Future<void> deleteForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = _safeGetStringList(prefs, '$_entryIndexPrefix$entryId') ?? [];
    for (final id in ids) {
      final raw = _safeGetString(prefs, '$_prefix$id');
      if (raw != null) {
        final embedding = _embeddingFromRaw(raw);
        if (embedding != null) {
          final typeKey = '$_typeIndexPrefix${embedding.sourceType.name}';
          final typeIds = _safeGetStringList(prefs, typeKey) ?? [];
          typeIds.remove(id);
          await prefs.setStringList(typeKey, typeIds);
        }
      }
      await prefs.remove('$_prefix$id');
    }
    await prefs.remove('$_entryIndexPrefix$entryId');
  }

  Future<List<AiEmbedding>> _loadMany(SharedPreferences prefs, List<String> ids,
      {String? indexKey}) async {
    final embeddings = <AiEmbedding>[];
    for (final id in ids) {
      final key = '$_prefix$id';
      final raw = _safeGetString(prefs, key);
      if (raw == null) continue;
      final embedding = _embeddingFromRaw(raw);
      if (embedding == null) {
        await prefs.remove(key);
        continue;
      }
      embeddings.add(embedding);
    }
    embeddings.sort((a, b) => a.sourceId.compareTo(b.sourceId));
    if (indexKey != null) {
      await prefs.setStringList(indexKey, embeddings.map((e) => e.id).toList());
    }
    return embeddings;
  }

  Future<void> _addToIndex(
    SharedPreferences prefs,
    String key,
    String id,
  ) async {
    final ids = _safeGetStringList(prefs, key) ?? [];
    if (!ids.contains(id)) {
      ids.add(id);
      await prefs.setStringList(key, ids);
    }
  }

  AiEmbedding? _embeddingFromRaw(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AiEmbedding.fromJson(decoded);
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

  List<String>? _safeGetStringList(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      if (value is List<String>) return List<String>.from(value);
      if (value is List) return value.whereType<String>().toList();
      return null;
    } on Object {
      return null;
    }
  }
}
