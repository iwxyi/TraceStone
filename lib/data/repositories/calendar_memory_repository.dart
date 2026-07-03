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
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    final memories = <CalendarMemory>[];
    for (final id in index) {
      final memory = await _getMemory(prefs, id);
      if (memory == null) continue;
      if (memory.id.isNotEmpty && memory.title.trim().isNotEmpty) {
        memories.add(memory);
      }
    }
    await prefs.setStringList(
        _indexKey, memories.map((memory) => memory.id).toList());
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
    final index = _safeGetStringList(prefs, _indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
  }

  Future<CalendarMemory?> _getMemory(
    SharedPreferences prefs,
    String id,
  ) async {
    final key = '$_prefix$id';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      return CalendarMemory.fromJson(decoded);
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
}
