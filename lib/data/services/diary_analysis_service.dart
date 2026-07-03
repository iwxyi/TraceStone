import 'dart:convert';

import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../models/diary_insight.dart';
import '../models/diary_segment.dart';
import '../models/memory_entry.dart';
import '../models/ai_context_package.dart';
import '../models/ai_profile.dart';
import '../models/memory_retrieval_result.dart';
import '../models/ai_prompt_trace.dart';
import '../models/stone_task.dart';
import '../repositories/ai_prompt_trace_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/memory_repository.dart';
import 'ai_client_service.dart';
import 'ai_context_builder.dart';

class DiaryAnalysisService {
  const DiaryAnalysisService({
    AiClientService? client,
    AiPromptTraceRepository? promptTraceRepository,
    AiContextBuilder? contextBuilder,
    MemoryRepository? memoryRepository,
    InsightRepository? insightRepository,
  })  : _client = client ?? const AiClientService(),
        _promptTraceRepository =
            promptTraceRepository ?? const AiPromptTraceRepository(),
        _contextBuilder = contextBuilder ?? const AiContextBuilder(),
        _memoryRepository = memoryRepository ?? const MemoryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository();

  final AiClientService _client;
  final AiPromptTraceRepository _promptTraceRepository;
  final AiContextBuilder _contextBuilder;
  final MemoryRepository _memoryRepository;
  final InsightRepository _insightRepository;

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
    return insight;
  }

  String _buildPrompt(AiContextPackage context) {
    final entry = context.currentEntry!;
    return '''请分析用户刚写完的日记。分析必须优先尊重原文，只能引用已给出的历史材料。

输出 JSON 格式：
{
  "reflection": "200字以内，温和、具体、能呼应过往经历的读后感",
  "related_memories": [{"title": "过往经历标题", "reason": "为什么和今天有关"}],
  "facts": [{"text": "明确发生的事实", "evidence": [{"type": "current_entry", "id": "entryId#s1"}]}],
  "signals": [{"text": "较稳妥的情绪或主题信号", "evidence": [{"type": "current_entry", "id": "entryId#s1"}]}],
  "hypotheses": [{"text": "谨慎表达的模式推测", "confidence": 0.6, "evidence": [{"type": "memory", "id": "memoryId"}]}],
  "suggestions": [{"text": "可执行建议", "evidence": [{"type": "current_entry", "id": "entryId"}]}],
  "emotion": "主要情绪",
  "keywords": ["关键词"],
  "people": ["人物名"],
  "stone_suggestion": {"title": "明天就能做的微小行动", "description": "一步即可执行"},
  "memory_update": {"summary": "这篇日记值得长期记住的摘要", "tags": ["长期标签"]},
  "profile_update_candidates": [{"field": "self_regulation", "value": "运动可能帮助用户恢复状态", "confidence": 0.58, "action": "candidate", "evidence": [{"type": "current_entry", "id": "entryId#s1"}]}],
  "relationship_updates": [{"person": "人物名", "relationship": "朋友/家人/同事/未知", "summary": "本次互动摘要", "emotion": "互动情绪", "pattern": "谨慎的互动模式候选", "confidence": 0.55, "evidence": [{"type": "current_entry", "id": "entryId#s1"}]}],
  "contradictions": [{"old_memory_id": "memoryId", "new_evidence": "新日记中的反证", "interpretation": "旧记忆可能需要降权或增加条件", "confidence": 0.55, "evidence": [{"type": "current_entry", "id": "entryId#s1"}]}]
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

多年今日：
${context.calendarMatches.isEmpty ? '无' : context.calendarMatches.map(_calendarLine).join('\n')}

稳定画像候选：
${context.profileFacts.isEmpty ? '无' : context.profileFacts.map(_profileLine).join('\n')}

关系档案：
${context.relationshipProfiles.isEmpty ? '无' : context.relationshipProfiles.map(_relationshipLine).join('\n')}

进行中的塑石行动：
${context.stoneTasks.isEmpty ? '无' : context.stoneTasks.map(_stoneLine).join('\n')}

要求：
1. related_memories 只能来自“最近日记摘要”或“相关历史记忆”；
2. 如果历史材料不足，就诚实少引用，不要编造；
3. stone_suggestion 必须微小、具体、明天可完成；
4. 如果今天日记包含多个事件，请先分别理解，再给整体读后感；
5. facts 只能写当前日记或历史材料明确给出的事实；
6. signals 写稳妥的情绪/主题观察；
7. hypotheses 必须用“可能/看起来/也许”等谨慎措辞，并给 confidence；
8. suggestions 必须可执行；
9. 每条重要结论尽量带 evidence；
10. profile_update_candidates 只能输出候选，不要直接改写用户画像；
11. relationship_updates 只记录本次互动或谨慎模式候选，不给关系下绝对结论；
12. 多年今日可以作为成长对照，但只能引用上方列出的日记，不要编造农历节日；
13. contradictions 只在新材料明显不同于历史记忆时输出；
14. 稳定画像、关系档案和塑石行动只能作为辅助背景，不能替代今天日记；
15. 如果今天提到正在推进的塑石行动，可以温和指出进展，不要批评未完成；
16. memory_update.summary 不超过 80 字。''';
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

  String _calendarLine(AiCalendarMatch match) =>
      '- ${_dateLabel(match.entry.date)}｜${match.reason}${match.label == null ? '' : '｜${match.calendarType}:${match.label}'}｜${match.entry.title ?? match.entry.excerpt}｜${match.entry.excerpt}';

  String _profileLine(ProfileFact profile) =>
      '- ${profile.field}｜${profile.value}｜${profile.evidenceCount} 条证据｜置信度 ${profile.confidence.toStringAsFixed(2)}';

  String _relationshipLine(RelationshipProfile profile) =>
      '- ${profile.personName}｜${profile.relationship ?? '未知关系'}｜${profile.interactionCount} 次互动｜${[
        ...profile.emotions.take(2),
        ...profile.patterns.take(2),
      ].join('、')}';

  String _stoneLine(StoneTask task) =>
      '- ${task.title}｜${task.description}｜${task.tags.join('、')}';

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
      facts: _claimList(parsed['facts']),
      signals: _claimList(parsed['signals']),
      hypotheses: _claimList(parsed['hypotheses']),
      suggestions: _claimList(parsed['suggestions']).isNotEmpty
          ? _claimList(parsed['suggestions'])
          : _fallbackSuggestion(stone, entry),
      profileUpdateCandidates:
          _profileUpdateList(parsed['profile_update_candidates']),
      relationshipUpdates: _relationshipUpdateList(
        parsed['relationship_updates'],
      ),
      contradictions: _contradictionList(parsed['contradictions']),
    );
  }

  List<InsightClaim> _claimList(Object? value) {
    return (value as List<dynamic>? ?? [])
        .map((item) =>
            InsightClaim.fromJson(item as Map<String, dynamic>? ?? const {}))
        .where((item) => item.text.isNotEmpty)
        .toList();
  }

  List<ProfileUpdateCandidate> _profileUpdateList(Object? value) {
    return (value as List<dynamic>? ?? [])
        .map((item) => ProfileUpdateCandidate.fromJson(
            item as Map<String, dynamic>? ?? const {}))
        .where((item) => item.field.isNotEmpty && item.value.isNotEmpty)
        .toList();
  }

  List<RelationshipUpdateCandidate> _relationshipUpdateList(Object? value) {
    return (value as List<dynamic>? ?? [])
        .map((item) => RelationshipUpdateCandidate.fromJson(
            item as Map<String, dynamic>? ?? const {}))
        .where((item) => item.personName.isNotEmpty || item.summary.isNotEmpty)
        .toList();
  }

  List<InsightContradiction> _contradictionList(Object? value) {
    return (value as List<dynamic>? ?? [])
        .map((item) => InsightContradiction.fromJson(
            item as Map<String, dynamic>? ?? const {}))
        .where((item) =>
            item.oldMemoryId.isNotEmpty || item.newEvidence.isNotEmpty)
        .toList();
  }

  List<InsightClaim> _fallbackSuggestion(
    Map<String, dynamic> stone,
    DiaryEntry entry,
  ) {
    final title = (stone['title'] as String? ?? '').trim();
    final description = (stone['description'] as String? ?? '').trim();
    final text =
        [title, description].where((item) => item.isNotEmpty).join('：');
    if (text.isEmpty) return const [];
    return [
      InsightClaim(
        text: text,
        evidence: [
          InsightEvidence(type: 'current_entry', id: entry.id),
        ],
      ),
    ];
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
      evidenceEntryIds: [insight.entryId],
      importance: insight.memorySummary.isEmpty ? 0.5 : 0.64,
      confidence: 0.58,
    );
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
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
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
