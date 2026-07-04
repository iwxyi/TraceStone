import 'package:shared_preferences/shared_preferences.dart';

class AiDataInventoryService {
  const AiDataInventoryService();

  Future<AiDataInventory> buildInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final sections = [
      _section(keys, '日记摘要', [
        'ai.entrySummaries.',
        'ai.entrySegments.',
      ]),
      _section(keys, '向量索引', [
        'ai.embeddings.',
      ]),
      _section(keys, '今日洞察', [
        'diary.insights.',
      ]),
      _section(keys, '长期记忆', [
        'memory.entries.',
      ]),
      _section(keys, '画像偏好', [
        'ai.profilePreferences.',
      ]),
      _section(keys, '后台队列', [
        'ai.analysis.jobs.',
      ]),
      _section(keys, '调试记录', [
        'ai.promptTraces.',
        'ai.retrievalTraces.',
        'ai.feedback.',
      ]),
      _section(keys, '周期总结', [
        'period.summaries.',
      ]),
      _section(keys, '纪念日', [
        'calendar.memories.',
      ]),
      _section(keys, '塑石行动', [
        'stone.tasks.',
      ]),
    ];
    return AiDataInventory(sections: sections);
  }

  AiDataInventorySection _section(
    Set<String> keys,
    String label,
    List<String> prefixes,
  ) {
    final matched = keys
        .where((key) => prefixes.any(key.startsWith))
        .toList(growable: false)
      ..sort();
    return AiDataInventorySection(
      label: label,
      count: matched.length,
      prefixes: prefixes,
      sampleKeys: matched.take(5).toList(growable: false),
    );
  }
}

class AiDataInventory {
  const AiDataInventory({required this.sections});

  final List<AiDataInventorySection> sections;

  int get totalCount =>
      sections.fold(0, (total, section) => total + section.count);

  String toDebugText() {
    return [
      '## TraceStone AI Data Inventory',
      'total=$totalCount',
      'policy=AI 衍生数据默认视为日记数据的一部分，应随日记一起备份、删除和保护。',
      '',
      for (final section in sections) ...[
        '### ${section.label}',
        'count=${section.count}',
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
    required this.sampleKeys,
  });

  final String label;
  final int count;
  final List<String> prefixes;
  final List<String> sampleKeys;
}
