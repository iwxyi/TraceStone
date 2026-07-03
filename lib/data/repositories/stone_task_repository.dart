import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/stone_task.dart';

class StoneTaskRepository {
  const StoneTaskRepository();

  static const _indexKey = 'stone.tasks.index';
  static const _prefix = 'stone.tasks.';

  Future<void> saveTask(StoneTask task) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix${task.id}', jsonEncode(task.toJson()));
    final index = prefs.getStringList(_indexKey) ?? [];
    if (!index.contains(task.id)) {
      index.add(task.id);
      await prefs.setStringList(_indexKey, index);
    }
  }

  Future<StoneTask?> getTask(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$id');
    if (raw == null) return null;
    return StoneTask.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<List<StoneTask>> listTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey) ?? [];
    final tasks = <StoneTask>[];
    for (final id in index) {
      final raw = prefs.getString('$_prefix$id');
      if (raw == null) continue;
      tasks.add(StoneTask.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    tasks.sort((a, b) {
      final byStatus =
          _statusPriority(a.status).compareTo(_statusPriority(b.status));
      if (byStatus != 0) return byStatus;
      return b.createdAt.compareTo(a.createdAt);
    });
    return tasks;
  }

  Future<void> deleteTask(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
    final index = prefs.getStringList(_indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
  }

  Future<void> setCompleted(String id, bool completed) async {
    final task = await getTask(id);
    if (task == null) return;
    final now = DateTime.now();
    await saveTask(task.copyWith(
      status: completed ? StoneTaskStatus.completed : StoneTaskStatus.active,
      completedAt: completed ? now : null,
      updatedAt: now,
      clearCompletedAt: !completed,
    ));
  }

  Future<void> addCheckIn(
    String id, {
    required String note,
    String? sourceEntryId,
  }) async {
    final task = await getTask(id);
    if (task == null) return;
    final now = DateTime.now();
    final checkIn = StoneTaskCheckIn(
      id: 'checkin:${now.microsecondsSinceEpoch}',
      createdAt: now,
      note: note.trim(),
      sourceEntryId: sourceEntryId,
    );
    await saveTask(task.copyWith(
      updatedAt: now,
      checkIns: [checkIn, ...task.checkIns],
    ));
  }

  int _statusPriority(StoneTaskStatus status) {
    switch (status) {
      case StoneTaskStatus.active:
        return 0;
      case StoneTaskStatus.completed:
        return 1;
      case StoneTaskStatus.archived:
        return 2;
    }
  }
}
