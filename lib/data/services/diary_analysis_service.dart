import 'dart:convert';

import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../models/diary_insight.dart';
import '../models/diary_segment.dart';
import '../models/memory_entry.dart';
import '../models/ai_embedding.dart';
import '../models/ai_context_package.dart';
import '../models/memory_retrieval_result.dart';
import '../models/ai_prompt_trace.dart';
import '../repositories/ai_embedding_repository.dart';
import '../repositories/ai_prompt_trace_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/memory_repository.dart';
import 'ai_client_service.dart';
import 'ai_context_builder.dart';
import 'embedding_service.dart';

class DiaryAnalysisService {
  const DiaryAnalysisService({
    AiClientService? client,
    AiEmbeddingRepository? embeddingRepository,
    AiPromptTraceRepository? promptTraceRepository,
    AiContextBuilder? contextBuilder,
    MemoryRepository? memoryRepository,
    InsightRepository? insightRepository,
    EmbeddingService? embeddingService,
  })  : _client = client ?? const AiClientService(),
        _embeddingRepository =
            embeddingRepository ?? const AiEmbeddingRepository(),
        _promptTraceRepository =
            promptTraceRepository ?? const AiPromptTraceRepository(),
        _contextBuilder = contextBuilder ?? const AiContextBuilder(),
        _memoryRepository = memoryRepository ?? const MemoryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _embeddingService = embeddingService ?? const EmbeddingService();

  final AiClientService _client;
  final AiEmbeddingRepository _embeddingRepository;
  final AiPromptTraceRepository _promptTraceRepository;
  final AiContextBuilder _contextBuilder;
  final MemoryRepository _memoryRepository;
  final InsightRepository _insightRepository;
  final EmbeddingService _embeddingService;

  Future<DiaryInsight> analyzeEntry(DiaryEntry entry) async {
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: entry.id,
      state: DiaryAnalysisState.analyzing,
      updatedAt: DateTime.now(),
    ));
    final context = await _contextBuilder.buildForTodayInsight(entry);
    const systemPrompt =
        '你是溯石的日记洞察助手。你必须结合今天的日记、最近日记和历史记忆分析，不做空洞说教，不虚构事实。输出必须是 JSON。';
    final userPrompt = _buildPrompt(context);
    await _savePromptTrace(
      id: entry.id,
      scenario: context.scenario.name,
      contextSummary: context.debugSummary,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
    );
    final jsonText = await _client.completeJson(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      maxTokens: 1600,
    );
    final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
    final insight = _parseInsight(entry, parsed);
    await _insightRepository.saveInsight(insight);
    final memory = _memoryFromInsight(insight);
    await _memoryRepository.saveMemory(memory);
    await _saveMemoryEmbedding(memory);
    return insight;
  }

  String _buildPrompt(AiContextPackage context) {
    final entry = context.currentEntry!;
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

本地摘要包：
${context.currentSummary == null ? '无' : _summaryBlock(context)}

本地分段：
${context.currentSegments.isEmpty ? '无' : context.currentSegments.map(_segmentLine).join('\n')}

最近日记摘要：
${context.recentEntries.isEmpty ? '无' : context.recentEntries.map(_entryLine).join('\n')}

相关历史记忆：
${context.relatedMemories.isEmpty ? '无' : context.relatedMemories.map(_memoryLine).join('\n')}

要求：
1. related_memories 只能来自“最近日记摘要”或“相关历史记忆”；
2. 如果历史材料不足，就诚实少引用，不要编造；
3. stone_suggestion 必须微小、具体、明天可完成；
4. 如果今天日记包含多个事件，请先分别理解，再给整体读后感；
5. memory_update.summary 不超过 80 字。''';
  }

  String _summaryBlock(AiContextPackage context) {
    final summary = context.currentSummary!;
    return [
      'context：${context.debugSummary}',
      'brief：${summary.brief}',
      if (summary.keyPoints.isNotEmpty)
        'keyPoints：${summary.keyPoints.join('；')}',
      if (summary.topics.isNotEmpty) 'topics：${summary.topics.join('、')}',
    ].join('\n');
  }

  String _segmentLine(DiarySegment segment) =>
      '- s${segment.index + 1}｜${segment.summary}｜${segment.topics.join('、')}';

  String _entryLine(DiaryEntry entry) =>
      '- ${_dateLabel(entry.date)}｜${entry.title ?? entry.excerpt}｜${entry.excerpt}';

  String _memoryLine(MemoryRetrievalResult result) {
    final memory = result.memory;
    return '- ${_dateLabel(memory.date)}｜score ${result.score}｜${memory.title}｜${memory.summary}｜${memory.emotion}｜${[
      ...memory.keywords,
      ...memory.people,
      ...memory.tags
    ].join('、')}｜原因：${result.reasons.join('；')}';
  }

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

  Future<void> _saveMemoryEmbedding(MemoryEntry memory) async {
    final result = _embeddingService.embed([
      memory.summary,
      memory.emotion,
      ...memory.keywords,
      ...memory.people,
      ...memory.tags,
    ].join('\n'));
    await _embeddingRepository.saveEmbedding(AiEmbedding(
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

  Future<void> _savePromptTrace({
    required String id,
    required String scenario,
    required String contextSummary,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    await _promptTraceRepository.saveTrace(AiPromptTrace(
      id: id,
      scenario: scenario,
      createdAt: DateTime.now(),
      contextSummary: contextSummary,
      systemPromptPreview: _preview(systemPrompt),
      userPromptPreview: _preview(userPrompt),
      systemPromptLength: systemPrompt.length,
      userPromptLength: userPrompt.length,
    ));
  }

  String _preview(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 600
        ? normalized
        : '${normalized.substring(0, 600)}…';
  }

  List<String> _stringList(Object? value) => (value as List<dynamic>? ?? [])
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
