import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_embedding.dart';
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
      if (memory.sourceEntryId == entryId) {
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
      if (memory.sourceEntryId == entry.id) continue;
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
    return scored.take(limit).toList();
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
