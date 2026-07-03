import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_embedding.dart';
import '../models/ai_feedback.dart';
import '../models/diary_entry.dart';
import '../models/diary_insight.dart';
import '../models/memory_entry.dart';
import '../models/memory_retrieval_result.dart';
import '../services/embedding_service.dart';
import 'ai_embedding_repository.dart';

class MemoryRepository {
  const MemoryRepository();

  static const _indexKey = 'memory.entries.index';
  static const _prefix = 'memory.entries.';

  Future<void> saveMemory(MemoryEntry memory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix${memory.id}', jsonEncode(memory.toJson()));
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    if (!index.contains(memory.id)) {
      index.add(memory.id);
      await prefs.setStringList(_indexKey, index);
    }
    await _saveEmbeddingIfNeeded(memory);
  }

  Future<void> saveGeneratedMemory(MemoryEntry memory) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await _getMemory(prefs, memory.id);
    if (existing == null) {
      await saveMemory(memory);
      return;
    }
    await saveMemory(MemoryEntry(
      id: memory.id,
      sourceEntryId: memory.sourceEntryId,
      date: memory.date,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
      lastReferencedAt: existing.lastReferencedAt,
      summary: memory.summary,
      keywords: memory.keywords,
      emotion: memory.emotion,
      people: memory.people,
      tags: memory.tags,
      evidenceEntryIds: {
        ...existing.allSourceEntryIds,
        ...memory.allSourceEntryIds,
      }.toList(growable: false),
      importance: existing.importance,
      confidence: existing.confidence,
      referenceCount: existing.referenceCount,
      decay: existing.decay,
      archived: existing.archived,
    ));
  }

  Future<List<MemoryEntry>> listMemories() async {
    final prefs = await SharedPreferences.getInstance();
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    final memories = <MemoryEntry>[];
    for (final id in index) {
      final memory = await _getMemory(prefs, id);
      if (memory != null) memories.add(memory);
    }
    await prefs.setStringList(
        _indexKey, memories.map((memory) => memory.id).toList());
    memories.sort((a, b) => b.date.compareTo(a.date));
    return memories;
  }

  Future<void> updateMemory(MemoryEntry memory) async {
    await saveMemory(memory.copyWith(updatedAt: DateTime.now()));
  }

  Future<int> countMemories() async {
    return (await listMemories()).length;
  }

  Future<void> deleteMemory(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
    await const AiEmbeddingRepository().deleteBySource(
      sourceType: AiEmbeddingSourceType.memory,
      sourceId: id,
    );
  }

  Future<void> deleteForSourceEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    final nextIndex = <String>[];
    for (final id in index) {
      final memory = await _getMemory(prefs, id);
      if (memory == null) continue;
      if (memory.allSourceEntryIds.contains(entryId)) {
        final remainingSources = memory.allSourceEntryIds
            .where((sourceId) => sourceId != entryId)
            .toList(growable: false);
        if (remainingSources.isNotEmpty) {
          final updated = memory.copyWith(
            sourceEntryId: memory.sourceEntryId == entryId
                ? remainingSources.first
                : memory.sourceEntryId,
            evidenceEntryIds: remainingSources,
            confidence: (memory.confidence - 0.08).clamp(0, 1).toDouble(),
            updatedAt: DateTime.now(),
          );
          await prefs.setString('$_prefix$id', jsonEncode(updated.toJson()));
          nextIndex.add(id);
          await _saveEmbeddingIfNeeded(updated);
          continue;
        }
        await prefs.remove('$_prefix$id');
        await const AiEmbeddingRepository().deleteBySource(
          sourceType: AiEmbeddingSourceType.memory,
          sourceId: id,
        );
      } else {
        nextIndex.add(id);
      }
    }
    await prefs.setStringList(_indexKey, nextIndex);
  }

  Future<List<MemoryEntry>> findRelated({
    required DiaryEntry entry,
    int limit = 8,
  }) async {
    final results = await findRelatedWithReasons(entry: entry, limit: limit);
    return results.map((result) => result.memory).toList();
  }

  Future<List<MemoryRetrievalResult>> findRelatedWithReasons({
    required DiaryEntry entry,
    int limit = 8,
  }) async {
    final memories = await listMemories();
    final queryEmbedding = const EmbeddingService().embed(
      '${entry.content} ${entry.location} ${entry.weather}',
    );
    final memoryEmbeddings = {
      for (final embedding in await const AiEmbeddingRepository()
          .listByType(AiEmbeddingSourceType.memory))
        embedding.sourceId: embedding,
    };
    final queryTokens =
        _tokens('${entry.content} ${entry.location} ${entry.weather}');
    final scored = <MemoryRetrievalResult>[];

    for (final memory in memories) {
      if (memory.allSourceEntryIds.contains(entry.id)) continue;
      if (memory.archived || memory.confidence < 0.2) continue;
      final memoryText = [
        memory.summary,
        memory.emotion,
        ...memory.keywords,
        ...memory.people,
        ...memory.tags,
      ].join(' ');
      final memoryTokens = _tokens(memoryText);
      var score = 0;
      var keywordScore = 0;
      final matchedTokens = <String>[];
      final reasons = <String>[];
      for (final token in queryTokens) {
        if (memoryTokens.contains(token)) {
          final tokenScore = token.length > 1 ? 2 : 1;
          keywordScore += tokenScore;
          score += tokenScore;
          matchedTokens.add(token);
        }
      }
      if (matchedTokens.isNotEmpty) {
        reasons.add('关键词重合：${matchedTokens.take(6).join('、')}');
      }
      final dayDistance = entry.date.difference(memory.date).inDays.abs();
      var timeScore = 0;
      if (dayDistance <= 14) {
        timeScore = 2;
        score += timeScore;
        reasons.add('时间接近：$dayDistance 天内');
      } else if (dayDistance <= 60) {
        timeScore = 1;
        score += timeScore;
        reasons.add('时间较近：$dayDistance 天内');
      }
      var peopleScore = 0;
      if (memory.people.isNotEmpty) {
        final peopleMatches = memory.people
            .where((person) => entry.content.contains(person))
            .toList();
        if (peopleMatches.isNotEmpty) {
          peopleScore = peopleMatches.length * 2;
          score += peopleScore;
          reasons.add('人物重合：${peopleMatches.join('、')}');
        }
      }
      var semanticSimilarity = 0.0;
      var semanticScore = 0;
      final memoryEmbedding = memoryEmbeddings[memory.id];
      if (memoryEmbedding != null) {
        final similarity = const EmbeddingService()
            .cosineSimilarity(queryEmbedding.vector, memoryEmbedding.vector);
        if (similarity > 0.12) {
          semanticSimilarity = similarity;
          semanticScore = (similarity * 10).round();
          score += semanticScore;
          reasons.add('语义相似：${similarity.toStringAsFixed(2)}');
        }
      }
      final lifecycleScore = _lifecycleScore(memory, entry.date);
      if (lifecycleScore > 0) {
        score += lifecycleScore;
        reasons.add(
            '记忆权重：重要度 ${memory.importance.toStringAsFixed(2)}，置信度 ${memory.confidence.toStringAsFixed(2)}');
      }
      if (memory.referenceCount > 0) {
        score += memory.referenceCount.clamp(0, 3);
      }
      final referenceScore = memory.referenceCount.clamp(0, 3);
      var decayPenalty = 0;
      if (memory.decay > 0) {
        final penalty = (memory.decay * 4).round();
        decayPenalty = penalty;
        score -= penalty;
        if (penalty > 0) {
          reasons.add('长期未引用降权：-$penalty');
        }
      }
      if (score > 0) {
        scored.add(MemoryRetrievalResult(
          memory: memory,
          score: score,
          reasons: reasons,
          matchedTokens: matchedTokens.take(12).toList(),
          rerankSignals: {
            if (keywordScore > 0) 'keyword': keywordScore.toDouble(),
            if (timeScore > 0) 'time': timeScore.toDouble(),
            if (peopleScore > 0) 'people': peopleScore.toDouble(),
            if (semanticScore > 0) 'semantic': semanticSimilarity,
            if (lifecycleScore > 0) 'lifecycle': lifecycleScore.toDouble(),
            if (referenceScore > 0) 'reference': referenceScore.toDouble(),
            if (decayPenalty > 0) 'decay': -decayPenalty.toDouble(),
          },
        ));
      }
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.memory.date.compareTo(a.memory.date);
    });
    final results = scored.take(limit).toList();
    await _markReferenced(results.map((result) => result.memory));
    return results;
  }

  Future<void> archiveMemory(String id, {required bool archived}) async {
    final prefs = await SharedPreferences.getInstance();
    final memory = await _getMemory(prefs, id);
    if (memory == null) return;
    await saveMemory(memory.copyWith(
      archived: archived,
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> correctSummary({
    required String id,
    required String summary,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final memory = await _getMemory(prefs, id);
    if (memory == null) return;
    final value = summary.trim();
    if (value.isEmpty) return;
    await saveMemory(memory.copyWith(
      summary: value,
      confidence: (memory.confidence + 0.12).clamp(0, 1).toDouble(),
      archived: false,
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> applyFeedback({
    required String sourceEntryId,
    required AiFeedbackValue value,
  }) async {
    final memories = await listMemories();
    final related = memories
        .where((memory) => memory.allSourceEntryIds.contains(sourceEntryId));
    for (final memory in related) {
      switch (value) {
        case AiFeedbackValue.helpful:
          await saveMemory(memory.copyWith(
            importance: (memory.importance + 0.08).clamp(0, 1).toDouble(),
            confidence: (memory.confidence + 0.08).clamp(0, 1).toDouble(),
            decay: (memory.decay * 0.7).clamp(0, 1).toDouble(),
            archived: false,
            updatedAt: DateTime.now(),
          ));
        case AiFeedbackValue.inaccurate:
          final confidence = (memory.confidence - 0.18).clamp(0, 1).toDouble();
          await saveMemory(memory.copyWith(
            importance: (memory.importance - 0.12).clamp(0, 1).toDouble(),
            confidence: confidence,
            decay: (memory.decay + 0.22).clamp(0, 1).toDouble(),
            archived: confidence < 0.25,
            updatedAt: DateTime.now(),
          ));
        case AiFeedbackValue.unclear:
          await saveMemory(memory.copyWith(
            confidence: (memory.confidence - 0.05).clamp(0, 1).toDouble(),
            decay: (memory.decay + 0.08).clamp(0, 1).toDouble(),
            updatedAt: DateTime.now(),
          ));
      }
    }
  }

  Future<void> applyContradictions({
    required Iterable<InsightContradiction> contradictions,
  }) async {
    final meaningful = contradictions
        .where((item) => item.oldMemoryId.trim().isNotEmpty)
        .toList(growable: false);
    if (meaningful.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final contradiction in meaningful) {
      final memory = await _getMemory(prefs, contradiction.oldMemoryId);
      if (memory == null) continue;
      final confidence = (contradiction.confidence ?? 0.55).clamp(0, 1);
      final confidencePenalty = (0.06 + confidence * 0.12).clamp(0, 0.18);
      final importancePenalty = (0.04 + confidence * 0.08).clamp(0, 0.12);
      final decayIncrease = (0.08 + confidence * 0.14).clamp(0, 0.22);
      final nextConfidence =
          (memory.confidence - confidencePenalty).clamp(0, 1).toDouble();
      await saveMemory(memory.copyWith(
        confidence: nextConfidence,
        importance:
            (memory.importance - importancePenalty).clamp(0, 1).toDouble(),
        decay: (memory.decay + decayIncrease).clamp(0, 1).toDouble(),
        archived: nextConfidence < 0.25,
        updatedAt: DateTime.now(),
      ));
    }
  }

  int _lifecycleScore(MemoryEntry memory, DateTime referenceDate) {
    final base = (memory.importance.clamp(0, 1) * 4) +
        (memory.confidence.clamp(0, 1) * 4);
    final daysSinceReferenced =
        referenceDate.difference(memory.lastReferencedAt).inDays.abs();
    final recencyBonus = daysSinceReferenced <= 30
        ? 1.5
        : daysSinceReferenced <= 180
            ? 0.8
            : 0;
    return (base + recencyBonus).round();
  }

  Future<void> _markReferenced(Iterable<MemoryEntry> memories) async {
    final now = DateTime.now();
    for (final memory in memories) {
      await saveMemory(memory.copyWith(
        lastReferencedAt: now,
        referenceCount: memory.referenceCount + 1,
        decay: (memory.decay * 0.7).clamp(0, 1).toDouble(),
        updatedAt: now,
      ));
    }
  }

  Future<void> _saveEmbeddingIfNeeded(MemoryEntry memory) async {
    final text = [
      memory.summary,
      memory.emotion,
      ...memory.keywords,
      ...memory.people,
      ...memory.tags,
    ].join('\n');
    final result = const EmbeddingService().embed(text);
    final existing = await const AiEmbeddingRepository().getBySource(
      sourceType: AiEmbeddingSourceType.memory,
      sourceId: memory.id,
    );
    if (existing?.textHash == result.textHash &&
        existing?.modelId == result.modelId &&
        existing?.modelVersion == result.modelVersion) {
      return;
    }
    await const AiEmbeddingRepository().saveEmbedding(AiEmbedding(
      id: '${AiEmbeddingSourceType.memory.name}:${memory.id}',
      sourceType: AiEmbeddingSourceType.memory,
      sourceId: memory.id,
      entryId: memory.sourceEntryId,
      modelId: result.modelId,
      modelVersion: result.modelVersion,
      dimensions: result.dimensions,
      vector: result.vector,
      generatedAt: DateTime.now(),
      textHash: result.textHash,
    ));
  }

  Future<MemoryEntry?> _getMemory(SharedPreferences prefs, String id) async {
    final key = '$_prefix$id';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      final memory = MemoryEntry.fromJson(decoded);
      return memory.id.isEmpty ? null : memory;
    } on Object {
      await prefs.remove(key);
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
}
