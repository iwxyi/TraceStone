import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_memory.dart';

class CalendarMemoryRepository {
  const CalendarMemoryRepository();

  static const _indexKey = 'calendar.memories.index';
  static const _prefix = 'calendar.memories.';

  Future<void> saveMemory(CalendarMemory memory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix${memory.id}', jsonEncode(memory.toJson()));
    final index = prefs.getStringList(_indexKey) ?? [];
    if (!index.contains(memory.id)) {
      index.add(memory.id);
      await prefs.setStringList(_indexKey, index);
    }
  }

  Future<List<CalendarMemory>> listMemories() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey) ?? [];
    final memories = <CalendarMemory>[];
    for (final id in index) {
      final raw = prefs.getString('$_prefix$id');
      if (raw == null) continue;
      final memory =
          CalendarMemory.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (memory.id.isNotEmpty && memory.title.trim().isNotEmpty) {
        memories.add(memory);
      }
    }
    memories.sort((a, b) {
      final byMonth = a.month.compareTo(b.month);
      if (byMonth != 0) return byMonth;
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      return a.title.compareTo(b.title);
    });
    return memories;
  }

  Future<void> deleteMemory(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
    final index = prefs.getStringList(_indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
  }
}
