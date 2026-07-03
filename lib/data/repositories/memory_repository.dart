import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_embedding.dart';
import '../models/ai_feedback.dart';
import '../models/diary_entry.dart';
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
    final index = prefs.getStringList(_indexKey) ?? [];
    if (!index.contains(memory.id)) {
      index.add(memory.id);
      await prefs.setStringList(_indexKey, index);
    }
    await _saveEmbeddingIfNeeded(memory);
  }

  Future<List<MemoryEntry>> listMemories() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey) ?? [];
    final memories = <MemoryEntry>[];
    for (final id in index) {
      final raw = prefs.getString('$_prefix$id');
      if (raw == null) continue;
      memories
          .add(MemoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    memories.sort((a, b) => b.date.compareTo(a.date));
    return memories;
  }

  Future<void> updateMemory(MemoryEntry memory) async {
    await saveMemory(memory.copyWith(updatedAt: DateTime.now()));
  }

  Future<int> countMemories() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_indexKey) ?? []).length;
  }

  Future<void> deleteMemory(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
    final index = prefs.getStringList(_indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
    await const AiEmbeddingRepository().deleteBySource(
      sourceType: AiEmbeddingSourceType.memory,
      sourceId: id,
    );
  }

  Future<void> deleteForSourceEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey) ?? [];
    final nextIndex = <String>[];
    for (final id in index) {
      final raw = prefs.getString('$_prefix$id');
      if (raw == null) continue;
      final memory =
          MemoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
      final matchedTokens = <String>[];
      final reasons = <String>[];
      for (final token in queryTokens) {
        if (memoryTokens.contains(token)) {
          score += token.length > 1 ? 2 : 1;
          matchedTokens.add(token);
        }
      }
      if (matchedTokens.isNotEmpty) {
        reasons.add('关键词重合：${matchedTokens.take(6).join('、')}');
      }
      final dayDistance = entry.date.difference(memory.date).inDays.abs();
      if (dayDistance <= 14) {
        score += 2;
        reasons.add('时间接近：$dayDistance 天内');
      } else if (dayDistance <= 60) {
        score += 1;
        reasons.add('时间较近：$dayDistance 天内');
      }
      if (memory.people.isNotEmpty) {
        final peopleMatches = memory.people
            .where((person) => entry.content.contains(person))
            .toList();
        if (peopleMatches.isNotEmpty) {
          score += peopleMatches.length * 2;
          reasons.add('人物重合：${peopleMatches.join('、')}');
        }
      }
      final memoryEmbedding = memoryEmbeddings[memory.id];
      if (memoryEmbedding != null) {
        final similarity = const EmbeddingService()
            .cosineSimilarity(queryEmbedding.vector, memoryEmbedding.vector);
        if (similarity > 0.12) {
          final semanticScore = (similarity * 10).round();
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
      if (memory.decay > 0) {
        final penalty = (memory.decay * 4).round();
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
    final raw = prefs.getString('$_prefix$id');
    if (raw == null) return;
    final memory =
        MemoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
    final raw = prefs.getString('$_prefix$id');
    if (raw == null) return;
    final memory =
        MemoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
