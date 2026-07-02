import 'dart:convert';

import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../models/diary_insight.dart';
import '../models/memory_entry.dart';
import '../repositories/diary_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/memory_repository.dart';
import 'ai_client_service.dart';

class DiaryAnalysisService {
  const DiaryAnalysisService({
    AiClientService? client,
    DiaryRepository? diaryRepository,
    MemoryRepository? memoryRepository,
    InsightRepository? insightRepository,
  })  : _client = client ?? const AiClientService(),
        _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _memoryRepository = memoryRepository ?? const MemoryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository();

  final AiClientService _client;
  final DiaryRepository _diaryRepository;
  final MemoryRepository _memoryRepository;
  final InsightRepository _insightRepository;

  Future<DiaryInsight> analyzeEntry(DiaryEntry entry) async {
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: entry.id,
      state: DiaryAnalysisState.analyzing,
      updatedAt: DateTime.now(),
    ));
    final recentEntries = await _recentEntries(entry);
    final relatedMemories = await _memoryRepository.findRelated(entry: entry);
    final jsonText = await _client.completeJson(
      systemPrompt:
          '你是溯石的日记洞察助手。你必须结合今天的日记、最近日记和历史记忆分析，不做空洞说教，不虚构事实。输出必须是 JSON。',
      userPrompt: _buildPrompt(entry, recentEntries, relatedMemories),
      maxTokens: 1600,
    );
    final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
    final insight = _parseInsight(entry, parsed);
    await _insightRepository.saveInsight(insight);
    await _memoryRepository.saveMemory(_memoryFromInsight(insight));
    return insight;
  }

  Future<List<DiaryEntry>> _recentEntries(DiaryEntry entry) async {
    final entries = await _diaryRepository.listEntries();
    return entries
        .where((item) => item.id != entry.id)
        .take(5)
        .toList(growable: false);
  }

  String _buildPrompt(
    DiaryEntry entry,
    List<DiaryEntry> recentEntries,
    List<MemoryEntry> relatedMemories,
  ) {
    return '''请分析用户刚写完的日记。分析必须优先尊重原文，只能引用已给出的历史材料。

输出 JSON 格式：
{
  "reflection": "200字以内，温和、具体、能呼应过往经历的读后感",
  "related_memories": [{"title": "过往经历标题", "reason": "为什么和今天有关"}],
  "emotion": "主要情绪",
  "keywords": ["关键词"],
  "people": ["人物名"],
  "stone_suggestion": {"title": "明天就能做的微小行动", "description": "一步即可执行"},
  "memory_update": {"summary": "这篇日记值得长期记住的摘要", "tags": ["长期标签"]}
}

今天日记：
日期：${_dateLabel(entry.date)}
地点天气：${entry.location} ${entry.weather} ${entry.temperature ?? ''}
内容：
${entry.content}

最近日记摘要：
${recentEntries.isEmpty ? '无' : recentEntries.map(_entryLine).join('\n')}

相关历史记忆：
${relatedMemories.isEmpty ? '无' : relatedMemories.map(_memoryLine).join('\n')}

要求：
1. related_memories 只能来自“最近日记摘要”或“相关历史记忆”；
2. 如果历史材料不足，就诚实少引用，不要编造；
3. stone_suggestion 必须微小、具体、明天可完成；
4. memory_update.summary 不超过 80 字。''';
  }

  String _entryLine(DiaryEntry entry) =>
      '- ${_dateLabel(entry.date)}｜${entry.title ?? entry.excerpt}｜${entry.excerpt}';

  String _memoryLine(MemoryEntry memory) =>
      '- ${_dateLabel(memory.date)}｜${memory.title}｜${memory.summary}｜${memory.emotion}｜${[
        ...memory.keywords,
        ...memory.people,
        ...memory.tags
      ].join('、')}';

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  DiaryInsight _parseInsight(DiaryEntry entry, Map<String, dynamic> parsed) {
    final stone =
        parsed['stone_suggestion'] as Map<String, dynamic>? ?? const {};
    final memory = parsed['memory_update'] as Map<String, dynamic>? ?? const {};
    return DiaryInsight(
      entryId: entry.id,
      entryDate: entry.date,
      generatedAt: DateTime.now(),
      reflection: (parsed['reflection'] as String? ?? '').trim(),
      relatedMemories: (parsed['related_memories'] as List<dynamic>? ?? [])
          .map((item) => RelatedMemoryInsight.fromJson(
              item as Map<String, dynamic>? ?? const {}))
          .where((item) => item.title.isNotEmpty || item.reason.isNotEmpty)
          .toList(),
      emotion: (parsed['emotion'] as String? ?? '').trim(),
      keywords: _stringList(parsed['keywords']),
      people: _stringList(parsed['people']),
      stoneTitle: (stone['title'] as String? ?? '').trim(),
      stoneDescription: (stone['description'] as String? ?? '').trim(),
      memorySummary: (memory['summary'] as String? ?? '').trim(),
      memoryTags: _stringList(memory['tags']),
    );
  }

  MemoryEntry _memoryFromInsight(DiaryInsight insight) {
    return MemoryEntry(
      id: insight.entryId,
      sourceEntryId: insight.entryId,
      date: insight.entryDate,
      createdAt: insight.generatedAt,
      summary: insight.memorySummary.isEmpty
          ? insight.reflection
          : insight.memorySummary,
      keywords: insight.keywords,
      emotion: insight.emotion,
      people: insight.people,
      tags: insight.memoryTags,
    );
  }

  List<String> _stringList(Object? value) => (value as List<dynamic>? ?? [])
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
