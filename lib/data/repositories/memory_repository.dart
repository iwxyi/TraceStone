import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';
import '../models/memory_entry.dart';

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
      memories.add(MemoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    memories.sort((a, b) => b.date.compareTo(a.date));
    return memories;
  }

  Future<List<MemoryEntry>> findRelated({
    required DiaryEntry entry,
    int limit = 8,
  }) async {
    final memories = await listMemories();
    final queryTokens = _tokens('${entry.content} ${entry.location} ${entry.weather}');
    final scored = <({MemoryEntry memory, int score})>[];

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
      for (final token in queryTokens) {
        if (memoryTokens.contains(token)) score += token.length > 1 ? 2 : 1;
      }
      final dayDistance = entry.date.difference(memory.date).inDays.abs();
      if (dayDistance <= 14) score += 2;
      if (dayDistance <= 60) score += 1;
      if (score > 0) scored.add((memory: memory, score: score));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.memory.date.compareTo(a.memory.date);
    });
    return scored.take(limit).map((item) => item.memory).toList();
  }

  Set<String> _tokens(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'[\s\n\r\t，。！？；：、“”‘’（）《》【】,.!?;:#>*_`\[\](){}/\\-]+'), ' ')
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
