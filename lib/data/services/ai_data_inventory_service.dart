import 'package:shared_preferences/shared_preferences.dart';

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
      ),
      _section(
        keys,
        label: '塑石行动',
        prefixes: const ['stone.tasks.'],
        sensitivity: 'high',
        backupPolicy: '随日记和行动记录备份',
        deletePolicy: '用户删除行动或来源删除时清理引用',
        exportPolicy: '可随行动记录导出',
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
