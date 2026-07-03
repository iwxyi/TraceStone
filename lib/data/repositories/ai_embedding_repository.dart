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
    await prefs.setString(
        '$_prefix${embedding.id}', jsonEncode(embedding.toJson()));
    await _addToIndex(
        prefs, '$_entryIndexPrefix${embedding.entryId}', embedding.id);
    await _addToIndex(
        prefs, '$_typeIndexPrefix${embedding.sourceType.name}', embedding.id);
  }

  Future<List<AiEmbedding>> listForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('$_entryIndexPrefix$entryId') ?? [];
    return _loadMany(prefs, ids);
  }

  Future<List<AiEmbedding>> listByType(AiEmbeddingSourceType type) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('$_typeIndexPrefix${type.name}') ?? [];
    return _loadMany(prefs, ids);
  }

  Future<void> deleteBySource({
    required AiEmbeddingSourceType sourceType,
    required String sourceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final id = '${sourceType.name}:$sourceId';
    final raw = prefs.getString('$_prefix$id');
    if (raw != null) {
      final embedding =
          AiEmbedding.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final entryKey = '$_entryIndexPrefix${embedding.entryId}';
      final entryIds = prefs.getStringList(entryKey) ?? [];
      entryIds.remove(id);
      await prefs.setStringList(entryKey, entryIds);
    }
    final typeKey = '$_typeIndexPrefix${sourceType.name}';
    final typeIds = prefs.getStringList(typeKey) ?? [];
    typeIds.remove(id);
    await prefs.setStringList(typeKey, typeIds);
    await prefs.remove('$_prefix$id');
  }

  Future<void> deleteForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('$_entryIndexPrefix$entryId') ?? [];
    for (final id in ids) {
      final raw = prefs.getString('$_prefix$id');
      if (raw != null) {
        final embedding =
            AiEmbedding.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final typeKey = '$_typeIndexPrefix${embedding.sourceType.name}';
        final typeIds = prefs.getStringList(typeKey) ?? [];
        typeIds.remove(id);
        await prefs.setStringList(typeKey, typeIds);
      }
      await prefs.remove('$_prefix$id');
    }
    await prefs.remove('$_entryIndexPrefix$entryId');
  }

  Future<List<AiEmbedding>> _loadMany(
    SharedPreferences prefs,
    List<String> ids,
  ) async {
    final embeddings = <AiEmbedding>[];
    for (final id in ids) {
      final raw = prefs.getString('$_prefix$id');
      if (raw == null) continue;
      embeddings
          .add(AiEmbedding.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    embeddings.sort((a, b) => a.sourceId.compareTo(b.sourceId));
    return embeddings;
  }

  Future<void> _addToIndex(
    SharedPreferences prefs,
    String key,
    String id,
  ) async {
    final ids = prefs.getStringList(key) ?? [];
    if (!ids.contains(id)) {
      ids.add(id);
      await prefs.setStringList(key, ids);
    }
  }
}
