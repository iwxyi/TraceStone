import 'dart:convert';

import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../models/diary_insight.dart';
import '../models/diary_segment.dart';
import '../models/ai_feedback.dart';
import '../models/memory_entry.dart';
import '../models/ai_context_package.dart';
import '../models/ai_profile.dart';
import '../models/memory_retrieval_result.dart';
import '../models/ai_prompt_trace.dart';
import '../models/stone_task.dart';
import '../repositories/ai_prompt_trace_repository.dart';
import '../repositories/ai_feedback_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/memory_repository.dart';
import 'ai_client_service.dart';
import 'ai_context_builder.dart';

class DiaryAnalysisService {
  const DiaryAnalysisService({
    AiClientService? client,
    AiPromptTraceRepository? promptTraceRepository,
    AiFeedbackRepository? feedbackRepository,
    AiContextBuilder? contextBuilder,
    MemoryRepository? memoryRepository,
    InsightRepository? insightRepository,
  })  : _client = client ?? const AiClientService(),
        _promptTraceRepository =
            promptTraceRepository ?? const AiPromptTraceRepository(),
        _feedbackRepository =
            feedbackRepository ?? const AiFeedbackRepository(),
        _contextBuilder = contextBuilder ?? const AiContextBuilder(),
        _memoryRepository = memoryRepository ?? const MemoryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository();

  final AiClientService _client;
  final AiPromptTraceRepository _promptTraceRepository;
  final AiFeedbackRepository _feedbackRepository;
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
    final feedback = await _feedbackRepository.getFeedback(entry.id);
    const systemPrompt =
        '你是溯石的日记洞察助手。你必须结合今天的日记、最近日记和历史记忆分析，不做空洞说教，不虚构事实。输出必须是 JSON。';
    final userPrompt = _buildPrompt(context, feedback: feedback);
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
    await _savePromptTrace(
      id: entry.id,
      scenario: context.scenario.name,
      contextSummary: context.debugSummary,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      rawResponse: jsonText,
    );
    final decoded = jsonDecode(jsonText);
    final parsed = _mapValue(decoded);
    final evidenceStats = _EvidenceFilterStats();
    final insight = _parseInsight(entry, parsed, context, evidenceStats);
    if (evidenceStats.hasFilteredSources) {
      await _savePromptTrace(
        id: entry.id,
        scenario: context.scenario.name,
        contextSummary: '${context.debugSummary} ${evidenceStats.debugSummary}',
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        rawResponse: jsonText,
      );
    }
    await _insightRepository.saveInsight(insight);
    await _memoryRepository.applyContradictions(
      contradictions: insight.contradictions,
    );
    final memory = _memoryFromInsight(insight);
    if (memory != null) {
      await _memoryRepository.saveGeneratedMemory(memory);
    }
    return insight;
  }

  String _buildPrompt(AiContextPackage context, {AiFeedback? feedback}) {
    final entry = context.currentEntry!;
    final feedbackBlock = _feedbackBlock(feedback);
    return '''请分析用户刚写完的日记。分析必须优先尊重原文，只能引用已给出的历史材料。

输出 JSON 格式：
{
  "reflection": "200字以内，温和、具体、能呼应过往经历的读后感",
  "related_memories": [{"title": "过往经历标题", "reason": "为什么和今天有关", "entry_id": "必须来自上方 entry/sourceEntry/evidenceEntries 中的一个 ID"}],
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
${context.profileFacts.isEmpty ? '无' : context.profileFacts.asMap().entries.map((entry) => _profileLine(entry.key, entry.value)).join('\n')}

关系档案：
${context.relationshipProfiles.isEmpty ? '无' : context.relationshipProfiles.asMap().entries.map((entry) => _relationshipLine(entry.key, entry.value)).join('\n')}

进行中的塑石行动：
${context.stoneTasks.isEmpty ? '无' : context.stoneTasks.map(_stoneLine).join('\n')}

用户反馈：
$feedbackBlock

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
16. memory_update.summary 不超过 80 字；
17. 如果“用户反馈”指出了上次洞察不准确，本次必须避开该错误，并优先重新核对当前日记原文和证据。''';
  }

  String _feedbackBlock(AiFeedback? feedback) {
    if (feedback == null || feedback.value != AiFeedbackValue.inaccurate) {
      return '无';
    }
    final note = feedback.note?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (note == null || note.isEmpty) {
      return '用户曾标记上一版洞察不准确，但没有填写具体原因。请重新核对原文和证据。';
    }
    return [
      '上一版洞察被用户标记为不准确。',
      '用户指出：${note.length <= 240 ? note : '${note.substring(0, 240)}...'}',
      '请不要机械重复上一版判断，尤其要核对用户指出的问题。',
    ].join('\n');
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
      '- segment:${segment.id}｜entry:${segment.entryId}｜s${segment.index + 1}｜${segment.summary}｜${segment.topics.join('、')}';

  String _entryLine(DiaryEntry entry) =>
      '- entry:${entry.id}｜${_dateLabel(entry.date)}｜${entry.title ?? entry.excerpt}｜${entry.excerpt}';

  String _memoryLine(MemoryRetrievalResult result) {
    final memory = result.memory;
    return '- memory:${memory.id}｜sourceEntry:${memory.sourceEntryId}｜evidenceEntries:${memory.allSourceEntryIds.join(',')}｜${_dateLabel(memory.date)}｜score ${result.score}｜${memory.title}｜${memory.summary}｜${memory.emotion}｜${[
      ...memory.keywords,
      ...memory.people,
      ...memory.tags
    ].join('、')}｜原因：${result.reasons.join('；')}${result.rerankSignals.isEmpty ? '' : '｜signals:${_signalLine(result.rerankSignals)}'}';
  }

  String _calendarLine(AiCalendarMatch match) =>
      '- calendar:${match.calendarType}:${match.label ?? _dateLabel(match.entry.date)}｜entry:${match.entry.id}｜${_dateLabel(match.entry.date)}｜${match.reason}${match.label == null ? '' : '｜${match.calendarType}:${match.label}'}｜${match.contextTitle}｜${match.contextSummary}';

  String _profileLine(int index, ProfileFact profile) =>
      '- ${_profilePromptId(index)}｜${profile.field}｜${profile.value}｜${profile.evidenceCount} 条证据｜证据来源：${_evidenceRefs(profile.evidence)}｜置信度 ${profile.confidence.toStringAsFixed(2)}';

  String _relationshipLine(int index, RelationshipProfile profile) =>
      '- ${_relationshipPromptId(index)}｜${profile.personName}｜${profile.relationship ?? '未知关系'}｜${profile.interactionCount} 次互动｜证据来源：${_evidenceRefs(profile.evidence)}｜${[
        ...profile.emotions.take(2),
        ...profile.patterns.take(2),
      ].join('、')}';

  String _stoneLine(StoneTask task) =>
      '- stone:${task.id}｜sourceEntry:${task.sourceEntryId}｜${task.title}｜${task.description}｜${task.tags.join('、')}';

  String _evidenceRefs(List<InsightEvidence> evidence) {
    if (evidence.isEmpty) return '无';
    return evidence
        .take(4)
        .map((item) =>
            [item.type, item.id].where((value) => value.isNotEmpty).join(':'))
        .where((value) => value.isNotEmpty)
        .join('、');
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _signalLine(Map<String, double> signals) {
    return signals.entries
        .map((entry) => '${entry.key}:${entry.value.toStringAsFixed(2)}')
        .join(',');
  }

  DiaryInsight _parseInsight(
    DiaryEntry entry,
    Map<String, dynamic> parsed,
    AiContextPackage context,
    _EvidenceFilterStats evidenceStats,
  ) {
    final stone = _mapValue(parsed['stone_suggestion']);
    final memory = _mapValue(parsed['memory_update']);
    final allowedSourceIds = _allowedSourceIds(context);
    final suggestions =
        _claimList(parsed['suggestions'], allowedSourceIds, evidenceStats);
    return DiaryInsight(
      entryId: entry.id,
      entryDate: entry.date,
      generatedAt: DateTime.now(),
      reflection: _stringValue(parsed['reflection']).trim(),
      relatedMemories: _listValue(parsed['related_memories'])
          .map((item) => RelatedMemoryInsight.fromJson(_mapValue(item)))
          .map((item) => _sanitizeRelatedMemory(
                item,
                allowedSourceIds,
                evidenceStats,
              ))
          .where((item) => item.title.isNotEmpty || item.reason.isNotEmpty)
          .toList(),
      emotion: _stringValue(parsed['emotion']).trim(),
      keywords: _stringList(parsed['keywords']),
      people: _stringList(parsed['people']),
      stoneTitle: _stringValue(stone['title']).trim(),
      stoneDescription: _stringValue(stone['description']).trim(),
      memorySummary: _stringValue(memory['summary']).trim(),
      memoryTags: _stringList(memory['tags']),
      facts: _claimList(parsed['facts'], allowedSourceIds, evidenceStats),
      signals: _claimList(parsed['signals'], allowedSourceIds, evidenceStats),
      hypotheses:
          _claimList(parsed['hypotheses'], allowedSourceIds, evidenceStats),
      suggestions: suggestions.isNotEmpty
          ? suggestions
          : _fallbackSuggestion(stone, entry),
      profileUpdateCandidates: _profileUpdateList(
        parsed['profile_update_candidates'],
        allowedSourceIds,
        evidenceStats,
      ),
      relationshipUpdates: _relationshipUpdateList(
        parsed['relationship_updates'],
        allowedSourceIds,
        evidenceStats,
      ),
      contradictions: _contradictionList(
        parsed['contradictions'],
        allowedSourceIds,
        evidenceStats,
      ),
    );
  }

  List<InsightClaim> _claimList(
    Object? value,
    Set<String> allowedSourceIds,
    _EvidenceFilterStats evidenceStats,
  ) {
    return _listValue(value)
        .map((item) => InsightClaim.fromJson(_mapValue(item)))
        .map((item) => InsightClaim(
              text: item.text,
              confidence: item.confidence,
              evidence: _validEvidence(
                item.evidence,
                allowedSourceIds,
                evidenceStats,
              ),
            ))
        .where((item) => item.text.isNotEmpty)
        .toList();
  }

  List<ProfileUpdateCandidate> _profileUpdateList(
    Object? value,
    Set<String> allowedSourceIds,
    _EvidenceFilterStats evidenceStats,
  ) {
    return _listValue(value)
        .map((item) => ProfileUpdateCandidate.fromJson(_mapValue(item)))
        .map((item) => ProfileUpdateCandidate(
              field: item.field,
              value: item.value,
              action: item.action,
              confidence: item.confidence,
              evidence: _validEvidence(
                item.evidence,
                allowedSourceIds,
                evidenceStats,
              ),
            ))
        .where((item) => item.field.isNotEmpty && item.value.isNotEmpty)
        .toList();
  }

  List<RelationshipUpdateCandidate> _relationshipUpdateList(
    Object? value,
    Set<String> allowedSourceIds,
    _EvidenceFilterStats evidenceStats,
  ) {
    return _listValue(value)
        .map((item) => RelationshipUpdateCandidate.fromJson(_mapValue(item)))
        .map((item) => RelationshipUpdateCandidate(
              personName: item.personName,
              summary: item.summary,
              relationship: item.relationship,
              emotion: item.emotion,
              pattern: item.pattern,
              confidence: item.confidence,
              evidence: _validEvidence(
                item.evidence,
                allowedSourceIds,
                evidenceStats,
              ),
            ))
        .where((item) => item.personName.isNotEmpty || item.summary.isNotEmpty)
        .toList();
  }

  List<InsightContradiction> _contradictionList(
    Object? value,
    Set<String> allowedSourceIds,
    _EvidenceFilterStats evidenceStats,
  ) {
    return _listValue(value)
        .map((item) => InsightContradiction.fromJson(_mapValue(item)))
        .map((item) => InsightContradiction(
              oldMemoryId: item.oldMemoryId,
              newEvidence: item.newEvidence,
              interpretation: item.interpretation,
              confidence: item.confidence,
              evidence: _validEvidence(
                item.evidence,
                allowedSourceIds,
                evidenceStats,
              ),
            ))
        .where((item) =>
            item.oldMemoryId.isNotEmpty || item.newEvidence.isNotEmpty)
        .toList();
  }

  RelatedMemoryInsight _sanitizeRelatedMemory(
    RelatedMemoryInsight item,
    Set<String> allowedSourceIds,
    _EvidenceFilterStats evidenceStats,
  ) {
    final entryId = item.entryId;
    final hasInvalidEntryId =
        entryId != null && !allowedSourceIds.contains(entryId);
    if (hasInvalidEntryId) {
      evidenceStats.filteredRelatedMemorySources += 1;
    }
    return RelatedMemoryInsight(
      title: item.title,
      reason: item.reason,
      entryId: entryId == null || !hasInvalidEntryId ? entryId : null,
    );
  }

  List<InsightEvidence> _validEvidence(
    List<InsightEvidence> evidence,
    Set<String> allowedSourceIds,
    _EvidenceFilterStats evidenceStats,
  ) {
    final valid = evidence.where((item) {
      if (item.id.isEmpty) return false;
      return allowedSourceIds.contains(item.id);
    }).toList(growable: false);
    evidenceStats.filteredEvidenceSources += evidence.length - valid.length;
    return valid;
  }

  Set<String> _allowedSourceIds(AiContextPackage context) {
    final ids = <String>{
      if (context.currentEntry != null) context.currentEntry!.id,
      if (context.currentSummary != null) context.currentSummary!.entryId,
      for (final segment in context.currentSegments) ...[
        segment.id,
        segment.entryId,
      ],
      for (final entry in context.recentEntries) entry.id,
      for (final match in context.calendarMatches) match.entry.id,
      for (final result in context.relatedMemories) ...[
        result.memory.id,
        result.memory.sourceEntryId,
        ...result.memory.allSourceEntryIds,
      ],
      for (final fact in context.profileFacts) ...[
        for (final evidence in fact.evidence) evidence.id,
      ],
      for (final entry in context.profileFacts.asMap().entries) ...[
        _profilePromptId(entry.key),
      ],
      for (final entry in context.relationshipProfiles.asMap().entries) ...[
        _relationshipPromptId(entry.key),
        entry.value.personName,
        for (final evidence in entry.value.evidence) evidence.id,
        for (final interaction in entry.value.recentInteractions)
          interaction.entryId,
      ],
      for (final profile in context.relationshipProfiles) ...[
        for (final evidence in profile.evidence) evidence.id,
        for (final interaction in profile.recentInteractions)
          interaction.entryId,
      ],
      for (final task in context.stoneTasks) ...[
        task.id,
        task.sourceEntryId,
        for (final checkIn in task.checkIns)
          if (checkIn.sourceEntryId != null) checkIn.sourceEntryId!,
      ],
    };
    ids.removeWhere((id) => id.trim().isEmpty);
    return ids;
  }

  String _profilePromptId(int index) => 'profile:p${index + 1}';

  String _relationshipPromptId(int index) => 'relationship:r${index + 1}';

  List<InsightClaim> _fallbackSuggestion(
    Map<String, dynamic> stone,
    DiaryEntry entry,
  ) {
    final title = _stringValue(stone['title']).trim();
    final description = _stringValue(stone['description']).trim();
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

  MemoryEntry? _memoryFromInsight(DiaryInsight insight) {
    final summary = insight.memorySummary.trim();
    if (summary.isEmpty) return null;
    return MemoryEntry(
      id: insight.entryId,
      sourceEntryId: insight.entryId,
      date: insight.entryDate,
      createdAt: insight.generatedAt,
      summary: summary,
      keywords: insight.keywords,
      emotion: insight.emotion,
      people: insight.people,
      tags: insight.memoryTags,
      evidenceEntryIds: [insight.entryId],
      importance: 0.64,
      confidence: 0.58,
    );
  }

  Future<void> _savePromptTrace({
    required String id,
    required String scenario,
    required String contextSummary,
    required String systemPrompt,
    required String userPrompt,
    String? rawResponse,
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
      rawResponsePreview: rawResponse == null ? '' : _preview(rawResponse),
      rawResponseLength: rawResponse?.length ?? 0,
      rawResponse: rawResponse,
    ));
  }

  String _preview(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 600
        ? normalized
        : '${normalized.substring(0, 600)}…';
  }

  Map<String, dynamic> _mapValue(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  List<dynamic> _listValue(Object? value) => value is List ? value : const [];

  String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  List<String> _stringList(Object? value) => _listValue(value)
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

class _EvidenceFilterStats {
  int filteredEvidenceSources = 0;
  int filteredRelatedMemorySources = 0;

  bool get hasFilteredSources =>
      filteredEvidenceSources > 0 || filteredRelatedMemorySources > 0;

  String get debugSummary {
    return [
      if (filteredEvidenceSources > 0)
        'evidenceFiltered=$filteredEvidenceSources',
      if (filteredRelatedMemorySources > 0)
        'relatedSourceFiltered=$filteredRelatedMemorySources',
    ].join(' ');
  }
}
