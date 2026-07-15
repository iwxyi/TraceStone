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

  Future<List<String>> listOutdatedEntryIds({
    required String modelId,
    required String modelVersion,
    int? dimensions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entryIds = <String>{};
    for (final key in _embeddingObjectKeys(prefs)) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) continue;
      final embedding = _embeddingFromRaw(raw);
      if (embedding == null || embedding.entryId.isEmpty) continue;
      if (embedding.modelId != modelId ||
          embedding.modelVersion != modelVersion ||
          (dimensions != null && embedding.dimensions != dimensions)) {
        entryIds.add(embedding.entryId);
      }
    }
    return entryIds.toList()..sort();
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
    final indexedIds =
        _safeGetStringList(prefs, '$_entryIndexPrefix$entryId') ?? [];
    final scannedIds = <String>[];
    for (final key in _embeddingObjectKeys(prefs)) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) continue;
      final embedding = _embeddingFromRaw(raw);
      if (embedding?.entryId == entryId) {
        scannedIds.add(embedding!.id);
      }
    }
    final ids = <String>{...indexedIds, ...scannedIds}.toList();
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

  Future<AiEmbeddingIndexRepairResult> repairIndexes() async {
    final prefs = await SharedPreferences.getInstance();
    final previousEntryIndexes = _readIndexes(prefs, _entryIndexPrefix);
    final previousTypeIndexes = _readIndexes(prefs, _typeIndexPrefix);
    final entryIndexes = <String, List<String>>{};
    final typeIndexes = <String, List<String>>{};
    var objectCount = 0;
    var invalidObjectCount = 0;
    var missingEntryReferences = 0;
    var missingTypeReferences = 0;

    for (final key in _embeddingObjectKeys(prefs)) {
      objectCount++;
      final raw = _safeGetString(prefs, key);
      final embedding = raw == null ? null : _embeddingFromRaw(raw);
      if (embedding == null ||
          embedding.id.isEmpty ||
          embedding.entryId.isEmpty) {
        invalidObjectCount++;
        await prefs.remove(key);
        continue;
      }
      entryIndexes.putIfAbsent(embedding.entryId, () => []).add(embedding.id);
      typeIndexes
          .putIfAbsent(embedding.sourceType.name, () => [])
          .add(embedding.id);
      if (!(previousEntryIndexes[embedding.entryId] ?? const <String>[])
          .contains(embedding.id)) {
        missingEntryReferences++;
      }
      if (!(previousTypeIndexes[embedding.sourceType.name] ?? const <String>[])
          .contains(embedding.id)) {
        missingTypeReferences++;
      }
    }

    final removedIndexReferences = _staleIndexReferenceCount(
          previousEntryIndexes,
          entryIndexes,
        ) +
        _staleIndexReferenceCount(previousTypeIndexes, typeIndexes);
    await _replaceIndexes(prefs, _entryIndexPrefix, entryIndexes);
    await _replaceIndexes(prefs, _typeIndexPrefix, typeIndexes);
    return AiEmbeddingIndexRepairResult(
      objectCount: objectCount,
      validObjectCount: objectCount - invalidObjectCount,
      invalidObjectCount: invalidObjectCount,
      entryIndexCount: entryIndexes.length,
      typeIndexCount: typeIndexes.length,
      missingEntryReferences: missingEntryReferences,
      missingTypeReferences: missingTypeReferences,
      removedIndexReferences: removedIndexReferences,
    );
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

  List<String> _embeddingObjectKeys(SharedPreferences prefs) {
    return prefs
        .getKeys()
        .where((key) =>
            key.startsWith(_prefix) &&
            !key.startsWith(_entryIndexPrefix) &&
            !key.startsWith(_typeIndexPrefix))
        .toList(growable: false)
      ..sort();
  }

  Map<String, List<String>> _readIndexes(
    SharedPreferences prefs,
    String prefix,
  ) {
    final indexes = <String, List<String>>{};
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      indexes[key.substring(prefix.length)] =
          _safeGetStringList(prefs, key) ?? const <String>[];
    }
    return indexes;
  }

  Future<void> _replaceIndexes(
    SharedPreferences prefs,
    String prefix,
    Map<String, List<String>> indexes,
  ) async {
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      await prefs.remove(key);
    }
    for (final entry in indexes.entries) {
      final ids = entry.value.toSet().toList()..sort();
      if (ids.isEmpty) continue;
      await prefs.setStringList('$prefix${entry.key}', ids);
    }
  }

  int _staleIndexReferenceCount(
    Map<String, List<String>> previous,
    Map<String, List<String>> repaired,
  ) {
    var count = 0;
    for (final entry in previous.entries) {
      final validIds = repaired[entry.key]?.toSet() ?? const <String>{};
      count += entry.value.where((id) => !validIds.contains(id)).length;
    }
    return count;
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

class AiEmbeddingIndexRepairResult {
  const AiEmbeddingIndexRepairResult({
    required this.objectCount,
    required this.validObjectCount,
    required this.invalidObjectCount,
    required this.entryIndexCount,
    required this.typeIndexCount,
    required this.missingEntryReferences,
    required this.missingTypeReferences,
    required this.removedIndexReferences,
  });

  final int objectCount;
  final int validObjectCount;
  final int invalidObjectCount;
  final int entryIndexCount;
  final int typeIndexCount;
  final int missingEntryReferences;
  final int missingTypeReferences;
  final int removedIndexReferences;

  int get repairedReferenceCount =>
      missingEntryReferences + missingTypeReferences + removedIndexReferences;

  String get summary =>
      'objects=$objectCount valid=$validObjectCount invalid=$invalidObjectCount '
      'entryIndexes=$entryIndexCount typeIndexes=$typeIndexCount '
      'added=${missingEntryReferences + missingTypeReferences} '
      'removed=$removedIndexReferences';
}
