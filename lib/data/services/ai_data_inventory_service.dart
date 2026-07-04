import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_memory.dart';
import '../models/entry_summary.dart';
import '../models/stone_task.dart';

class AiDataInventoryService {
  const AiDataInventoryService();

  Future<AiDataInventory> buildInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final sections = [
      _section(
        keys,
        label: '日记摘要',
        prefixes: const [
          'ai.entrySummaries.',
          'ai.entrySummaryRevisions.',
          'ai.entrySegments.',
        ],
        sensitivity: 'high',
        backupPolicy: '随日记备份',
        deletePolicy: '日记永久删除时清理',
        exportPolicy: '可随日记导出，需提示包含 AI 摘要和片段',
        details: _summaryQualityDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '向量索引',
        prefixes: const ['ai.embeddings.'],
        sensitivity: 'high',
        backupPolicy: '可随日记备份，也可恢复后重建',
        deletePolicy: '来源删除或重建时清理',
        exportPolicy: '默认不展示原始向量，开发者模式可导出元数据',
        details: _embeddingIndexDetails(keys),
      ),
      _section(
        keys,
        label: '今日洞察',
        prefixes: const ['diary.insights.'],
        sensitivity: 'high',
        backupPolicy: '随日记备份',
        deletePolicy: '日记永久删除时清理',
        exportPolicy: '可随洞察导出，需保留来源提示',
      ),
      _section(
        keys,
        label: '长期记忆',
        prefixes: const ['memory.entries.'],
        sensitivity: 'high',
        backupPolicy: '随 AI 记忆备份',
        deletePolicy: '用户删除记忆或来源不足时清理',
        exportPolicy: '普通导出仅摘要，开发者导出含来源链',
      ),
      _section(
        keys,
        label: '画像偏好',
        prefixes: const ['ai.profilePreferences.'],
        sensitivity: 'medium',
        backupPolicy: '随 AI 设置备份',
        deletePolicy: '目标不存在时清理',
        exportPolicy: '开发者导出含确认、隐藏、修正和合并状态',
      ),
      _section(
        keys,
        label: '关系合并历史',
        prefixes: const ['ai.relationshipMergeHistory.'],
        sensitivity: 'medium',
        backupPolicy: '随 AI 设置备份',
        deletePolicy: '保留审计历史，清除 AI 数据时清理',
        exportPolicy: '仅开发者导出',
      ),
      _section(
        keys,
        label: '后台队列',
        prefixes: const ['ai.analysis.jobs.'],
        sensitivity: 'medium',
        backupPolicy: '不要求跨设备恢复，可本地保留',
        deletePolicy: '任务完成、重建或来源删除时清理',
        exportPolicy: '开发者导出任务状态和错误摘要',
      ),
      _section(
        keys,
        label: '调试记录',
        prefixes: const [
          'ai.promptTraces.',
          'ai.retrievalTraces.',
          'ai.feedback.',
        ],
        sensitivity: 'critical',
        backupPolicy: '默认不建议云备份，除非用户明确启用开发者备份',
        deletePolicy: '用户清除调试记录或来源删除时清理',
        exportPolicy: '复制前必须确认，可能包含 prompt、上下文和原始响应',
      ),
      _section(
        keys,
        label: '周期总结',
        prefixes: const ['period.summaries.'],
        sensitivity: 'high',
        backupPolicy: '随日记备份',
        deletePolicy: '来源日记变更或删除时失效清理',
        exportPolicy: '可随月/年总结导出，开发者模式含来源',
      ),
      _section(
        keys,
        label: '纪念日',
        prefixes: const ['calendar.memories.'],
        sensitivity: 'medium',
        backupPolicy: '随用户设置备份',
        deletePolicy: '用户删除纪念日时清理',
        exportPolicy: '普通导出可展示名称和日期',
        details: _calendarMemoryDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '塑石行动',
        prefixes: const ['stone.tasks.'],
        sensitivity: 'high',
        backupPolicy: '随日记和行动记录备份',
        deletePolicy: '用户删除行动或来源删除时清理引用',
        exportPolicy: '可随行动记录导出',
        details: _stoneTaskDetails(prefs, keys),
      ),
    ];
    return AiDataInventory(sections: sections);
  }

  AiDataInventorySection _section(
    Set<String> keys, {
    required String label,
    required List<String> prefixes,
    required String sensitivity,
    required String backupPolicy,
    required String deletePolicy,
    required String exportPolicy,
    List<String> details = const [],
  }) {
    final matched = keys
        .where((key) => prefixes.any(key.startsWith))
        .toList(growable: false)
      ..sort();
    return AiDataInventorySection(
      label: label,
      count: matched.length,
      prefixes: prefixes,
      sensitivity: sensitivity,
      backupPolicy: backupPolicy,
      deletePolicy: deletePolicy,
      exportPolicy: exportPolicy,
      details: details,
      sampleKeys: matched.take(5).toList(growable: false),
    );
  }

  List<String> _embeddingIndexDetails(Set<String> keys) {
    const objectPrefix = 'ai.embeddings.';
    const entryIndexPrefix = 'ai.embeddings.entryIndex.';
    const typeIndexPrefix = 'ai.embeddings.typeIndex.';
    final objectKeys = keys
        .where((key) =>
            key.startsWith(objectPrefix) &&
            !key.startsWith(entryIndexPrefix) &&
            !key.startsWith(typeIndexPrefix))
        .toList(growable: false);
    final entryIndexCount =
        keys.where((key) => key.startsWith(entryIndexPrefix)).length;
    final typeIndexCount =
        keys.where((key) => key.startsWith(typeIndexPrefix)).length;
    final details = <String>[
      'objects=${objectKeys.length}',
      'entryIndexes=$entryIndexCount',
      'typeIndexes=$typeIndexCount',
    ];
    if (objectKeys.isNotEmpty &&
        (entryIndexCount == 0 || typeIndexCount == 0)) {
      details.add('warning=存在缺少 entry/type 索引的向量对象');
    }
    return details;
  }

  List<String> _summaryQualityDetails(
    SharedPreferences prefs,
    Set<String> keys,
  ) {
    const summaryPrefix = 'ai.entrySummaries.';
    final summaryKeys = keys
        .where((key) => key.startsWith(summaryPrefix))
        .toList(growable: false)
      ..sort();
    if (summaryKeys.isEmpty) return const [];

    final summaries = <_SummaryQualityRecord>[];
    final warningCounts = <String, int>{};
    var malformed = 0;
    for (final key in summaryKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformed += 1;
          continue;
        }
        final summary = EntrySummary.fromJson(decoded);
        final entryId = summary.entryId.isEmpty
            ? key.substring(summaryPrefix.length)
            : summary.entryId;
        summaries.add(_SummaryQualityRecord(
          id: entryId.isEmpty ? 'unknown' : entryId,
          qualityScore: summary.qualityScore,
          qualityWarnings: summary.qualityWarnings,
        ));
        for (final warning in summary.qualityWarnings) {
          warningCounts.update(warning, (value) => value + 1,
              ifAbsent: () => 1);
        }
        if (entryId.isEmpty) malformed += 1;
      } on Object {
        malformed += 1;
      }
    }
    if (summaries.isEmpty) {
      return [
        'summaryObjects=0',
        if (malformed > 0) 'malformed=$malformed',
      ];
    }

    final lowQuality =
        summaries.where((summary) => summary.qualityScore < 0.55).length;
    final warningSummaries =
        summaries.where((summary) => summary.qualityWarnings.isNotEmpty).length;
    final averageQuality = summaries
            .map((summary) => summary.qualityScore)
            .reduce((a, b) => a + b) /
        summaries.length;
    final sortedByQuality = [...summaries]..sort((a, b) {
        final byQuality = a.qualityScore.compareTo(b.qualityScore);
        if (byQuality != 0) return byQuality;
        return a.id.compareTo(b.id);
      });
    final warningSummary = warningCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return [
      'summaryObjects=${summaries.length}',
      'averageQuality=${averageQuality.toStringAsFixed(2)}',
      'lowQuality=$lowQuality',
      'warningSummaries=$warningSummaries',
      if (malformed > 0) 'malformed=$malformed',
      'worst=${sortedByQuality.first.id}:${sortedByQuality.first.qualityScore.toStringAsFixed(2)}',
      if (warningSummary.isNotEmpty)
        'warnings=${warningSummary.take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
    ];
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }
}

List<String> _calendarMemoryDetails(
  SharedPreferences prefs,
  Set<String> keys,
) {
  const prefix = 'calendar.memories.';
  const indexKey = 'calendar.memories.index';
  final objectKeys = keys
      .where((key) => key.startsWith(prefix) && key != indexKey)
      .toList(growable: false)
    ..sort();
  if (objectKeys.isEmpty && !keys.contains(indexKey)) return const [];

  var solar = 0;
  var lunar = 0;
  var disabled = 0;
  var invalidRequired = 0;
  var malformed = 0;
  final monthBuckets = <String, int>{};

  for (final key in objectKeys) {
    final raw = _safeGetInventoryString(prefs, key);
    if (raw == null) {
      malformed += 1;
      continue;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        malformed += 1;
        continue;
      }
      final memory = CalendarMemory.fromJson(decoded);
      switch (memory.type) {
        case CalendarMemoryType.solar:
          solar += 1;
        case CalendarMemoryType.lunar:
          lunar += 1;
      }
      if (!memory.enabled) disabled += 1;
      if (memory.id.trim().isEmpty || memory.title.trim().isEmpty) {
        invalidRequired += 1;
      }
      final monthKey = '${memory.type.name}-${memory.month}';
      monthBuckets.update(monthKey, (value) => value + 1, ifAbsent: () => 1);
    } on Object {
      malformed += 1;
    }
  }

  final densestMonths = monthBuckets.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  final indexed = _safeGetInventoryStringList(prefs, indexKey)?.length ?? 0;
  return [
    'objects=${objectKeys.length}',
    'indexed=$indexed',
    'solar=$solar',
    'lunar=$lunar',
    if (disabled > 0) 'disabled=$disabled',
    if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
    if (malformed > 0) 'malformed=$malformed',
    if (densestMonths.isNotEmpty)
      'topMonths=${densestMonths.take(3).map((entry) => '${entry.key}:${entry.value}').join(',')}',
  ];
}

String? _safeGetInventoryString(SharedPreferences prefs, String key) {
  try {
    final value = prefs.get(key);
    return value is String ? value : null;
  } on Object {
    return null;
  }
}

List<String>? _safeGetInventoryStringList(SharedPreferences prefs, String key) {
  try {
    final value = prefs.get(key);
    if (value is List<String>) return List<String>.from(value);
    if (value is List) return value.whereType<String>().toList();
    return null;
  } on Object {
    return null;
  }
}

List<String> _stoneTaskDetails(
  SharedPreferences prefs,
  Set<String> keys,
) {
  const prefix = 'stone.tasks.';
  const indexKey = 'stone.tasks.index';
  final objectKeys = keys
      .where((key) => key.startsWith(prefix) && key != indexKey)
      .toList(growable: false)
    ..sort();
  if (objectKeys.isEmpty && !keys.contains(indexKey)) return const [];

  final statusCounts = <StoneTaskStatus, int>{
    for (final status in StoneTaskStatus.values) status: 0,
  };
  var checkIns = 0;
  var sourcedTasks = 0;
  var sourcedCheckIns = 0;
  var missingSource = 0;
  var invalidRequired = 0;
  var malformed = 0;
  final tagCounts = <String, int>{};

  for (final key in objectKeys) {
    final raw = _safeGetInventoryString(prefs, key);
    if (raw == null) {
      malformed += 1;
      continue;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        malformed += 1;
        continue;
      }
      final task = StoneTask.fromJson(decoded);
      statusCounts.update(task.status, (value) => value + 1);
      checkIns += task.checkIns.length;
      if (task.sourceEntryId.trim().isEmpty) {
        missingSource += 1;
      } else {
        sourcedTasks += 1;
      }
      sourcedCheckIns += task.checkIns
          .where((item) => (item.sourceEntryId ?? '').trim().isNotEmpty)
          .length;
      if (task.id.trim().isEmpty || task.title.trim().isEmpty) {
        invalidRequired += 1;
      }
      for (final tag in task.tags) {
        tagCounts.update(tag, (value) => value + 1, ifAbsent: () => 1);
      }
    } on Object {
      malformed += 1;
    }
  }

  final topTags = tagCounts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  final indexed = _safeGetInventoryStringList(prefs, indexKey)?.length ?? 0;
  return [
    'objects=${objectKeys.length}',
    'indexed=$indexed',
    'active=${statusCounts[StoneTaskStatus.active] ?? 0}',
    'completed=${statusCounts[StoneTaskStatus.completed] ?? 0}',
    'archived=${statusCounts[StoneTaskStatus.archived] ?? 0}',
    'checkIns=$checkIns',
    'sourcedTasks=$sourcedTasks',
    'sourcedCheckIns=$sourcedCheckIns',
    if (missingSource > 0) 'missingSource=$missingSource',
    if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
    if (malformed > 0) 'malformed=$malformed',
    if (topTags.isNotEmpty)
      'topTags=${topTags.take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
  ];
}

class _SummaryQualityRecord {
  const _SummaryQualityRecord({
    required this.id,
    required this.qualityScore,
    required this.qualityWarnings,
  });

  final String id;
  final double qualityScore;
  final List<String> qualityWarnings;
}

class AiDataInventory {
  const AiDataInventory({required this.sections});

  final List<AiDataInventorySection> sections;

  int get totalCount =>
      sections.fold(0, (total, section) => total + section.count);

  int get highSensitivitySectionCount => sections
      .where((section) =>
          section.count > 0 &&
          (section.sensitivity == 'high' || section.sensitivity == 'critical'))
      .length;

  String toDebugText() {
    return [
      '## TraceStone AI Data Inventory',
      'total=$totalCount',
      'policy=AI 衍生数据默认视为日记数据的一部分，应随日记一起备份、删除和保护。',
      '',
      for (final section in sections) ...[
        '### ${section.label}',
        'count=${section.count}',
        'sensitivity=${section.sensitivity}',
        'backupPolicy=${section.backupPolicy}',
        'deletePolicy=${section.deletePolicy}',
        'exportPolicy=${section.exportPolicy}',
        if (section.details.isNotEmpty) 'details=${section.details.join(';')}',
        'prefixes=${section.prefixes.join(',')}',
        if (section.sampleKeys.isNotEmpty)
          'sampleKeys=${section.sampleKeys.join(',')}',
        '',
      ],
    ].join('\n');
  }
}

class AiDataInventorySection {
  const AiDataInventorySection({
    required this.label,
    required this.count,
    required this.prefixes,
    required this.sensitivity,
    required this.backupPolicy,
    required this.deletePolicy,
    required this.exportPolicy,
    this.details = const [],
    required this.sampleKeys,
  });

  final String label;
  final int count;
  final List<String> prefixes;
  final String sensitivity;
  final String backupPolicy;
  final String deletePolicy;
  final String exportPolicy;
  final List<String> details;
  final List<String> sampleKeys;
}
