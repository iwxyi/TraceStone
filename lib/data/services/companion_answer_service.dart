import 'dart:convert';

import '../models/ai_context_package.dart';
import '../models/ai_prompt_trace.dart';
import '../models/ai_research_session.dart';
import '../models/companion_answer.dart';
import '../models/stone_task.dart';
import '../repositories/ai_prompt_trace_repository.dart';
import '../repositories/ai_research_session_repository.dart';
import '../utils/ai_source_formatter.dart';
import 'ai_client_service.dart';
import 'ai_context_builder.dart';
import 'ai_search_service.dart';

typedef CompanionResearchProgress = void Function(CompanionResearchStep step);

class CompanionAnswerService {
  const CompanionAnswerService({
    AiClientService? client,
    AiContextBuilder? contextBuilder,
    AiPromptTraceRepository? promptTraceRepository,
    AiResearchSessionRepository? researchSessionRepository,
    AiSearchService? searchService,
  })  : _client = client ?? const AiClientService(),
        _contextBuilder = contextBuilder ?? const AiContextBuilder(),
        _promptTraceRepository =
            promptTraceRepository ?? const AiPromptTraceRepository(),
        _researchSessionRepository =
            researchSessionRepository ?? const AiResearchSessionRepository(),
        _searchService = searchService ?? const AiSearchService();

  final AiClientService _client;
  final AiContextBuilder _contextBuilder;
  final AiPromptTraceRepository _promptTraceRepository;
  final AiResearchSessionRepository _researchSessionRepository;
  final AiSearchService _searchService;

  Future<CompanionAnswer> answer(
    String question, {
    CompanionResearchProgress? onProgress,
  }) async {
    return answerWithResearch(question, onProgress: onProgress);
  }

  Future<CompanionAnswer> answerWithResearch(
    String question, {
    CompanionResearchProgress? onProgress,
  }) async {
    final startedAt = DateTime.now();
    final sessionId = 'companion:${startedAt.millisecondsSinceEpoch}';
    final steps = <CompanionResearchStep>[];
    var session = AiResearchSession(
      id: sessionId,
      question: question,
      startedAt: startedAt,
      updatedAt: startedAt,
      state: AiResearchSessionState.running,
    );
    await _researchSessionRepository.saveSession(session);

    Future<void> addStep(CompanionResearchStep step) async {
      steps.add(step);
      onProgress?.call(step);
      session = session.copyWith(
        updatedAt: DateTime.now(),
        steps: List.unmodifiable(steps),
      );
      await _researchSessionRepository.saveSession(session);
    }

    try {
      await addStep(const CompanionResearchStep(
        title: '理解问题',
        status: '正在让 AI 规划需要核对的资料',
        detail: '由模型拆分子问题、确定检索线索和停止条件。',
      ));
      final context = await _contextBuilder.buildForQuestion(question);
      final primaryEvidence = _evidenceFromContext(context);
      await addStep(CompanionResearchStep(
        title: '检索基础资料',
        status: '已完成基础检索',
        detail:
            '找到 ${context.searchMatches.length} 条搜索命中、${context.relatedMemories.length} 条记忆、${context.relationshipProfiles.length} 条关系档案。',
        evidence: primaryEvidence.take(12).toList(growable: false),
        developerDetail: context.debugSummary,
      ));
      final researchResult = await _runDynamicResearch(
        question: question,
        context: context,
        primaryEvidence: primaryEvidence,
        addStep: addStep,
      );
      final expandedEvidence = researchResult.evidence;
      final allEvidence =
          _dedupeEvidence([...primaryEvidence, ...expandedEvidence]);
      await addStep(CompanionResearchStep(
        title: '评估证据覆盖',
        status: researchResult.coverageStatus,
        detail: researchResult.coverageDetail,
        evidence: allEvidence.take(10).toList(growable: false),
        developerDetail: researchResult.developerDetail,
      ));
      await addStep(CompanionResearchStep(
        title: '生成回答',
        status: '正在基于证据组织 Markdown 回答',
        detail: '会优先说明能确定的结论、不确定性和关键来源。',
        evidence: allEvidence.take(12).toList(growable: false),
      ));
      const systemPrompt =
          '你是拾年的成长陪伴助手。你只能基于给定的用户历史材料回答，在轻松、不施压的氛围中帮助用户记录生活、理解自己、看见变化；不诊断、不说教、不虚构。输出必须是 JSON。回答正文可以使用 Markdown。';
      final userPrompt = _buildPrompt(question, context, steps);
      final trace = AiPromptTrace(
        id: 'companion:last',
        scenario: context.scenario.name,
        createdAt: DateTime.now(),
        contextSummary: context.debugSummary,
        systemPromptPreview: _preview(systemPrompt),
        userPromptPreview: _preview(userPrompt),
        systemPromptLength: systemPrompt.length,
        userPromptLength: userPrompt.length,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );
      await _promptTraceRepository.saveTrace(trace);
      final jsonText = await _client.completeJson(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxTokens: 1200,
      );
      await _promptTraceRepository.saveTrace(AiPromptTrace(
        id: trace.id,
        scenario: trace.scenario,
        createdAt: trace.createdAt,
        contextSummary: trace.contextSummary,
        systemPromptPreview: trace.systemPromptPreview,
        userPromptPreview: trace.userPromptPreview,
        systemPromptLength: trace.systemPromptLength,
        userPromptLength: trace.userPromptLength,
        rawResponsePreview: _preview(jsonText),
        rawResponseLength: jsonText.length,
        systemPrompt: trace.systemPrompt,
        userPrompt: trace.userPrompt,
        rawResponse: jsonText,
      ));
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      final verified = await _verifyAnswer(
        question: question,
        context: context,
        researchSteps: steps,
        answerJson: parsed,
      );
      final sourceFilter = _CompanionSourceFilter(
        context,
        extraEvidence: allEvidence,
      );
      final sources = sourceFilter.sources(verified['sources']);
      if (sourceFilter.filteredCount > 0) {
        await _promptTraceRepository.saveTrace(AiPromptTrace(
          id: trace.id,
          scenario: trace.scenario,
          createdAt: trace.createdAt,
          contextSummary:
              '${trace.contextSummary} sourceFiltered=${sourceFilter.filteredCount}',
          systemPromptPreview: trace.systemPromptPreview,
          userPromptPreview: trace.userPromptPreview,
          systemPromptLength: trace.systemPromptLength,
          userPromptLength: trace.userPromptLength,
          rawResponsePreview: _preview(jsonText),
          rawResponseLength: jsonText.length,
          systemPrompt: trace.systemPrompt,
          userPrompt: trace.userPrompt,
          rawResponse: jsonText,
        ));
      }
      final answer = CompanionAnswer(
        answer: (verified['answer'] as String? ?? '').trim(),
        followUp: (verified['follow_up'] as String? ?? '').trim(),
        sources: sources,
        usedFallback: false,
        researchSteps: steps,
      );
      session = session.copyWith(
        updatedAt: DateTime.now(),
        state: AiResearchSessionState.completed,
        completedAt: DateTime.now(),
        answerPreview: _preview(answer.answer),
        steps: List.unmodifiable(steps),
      );
      await _researchSessionRepository.saveSession(session);
      return answer;
    } on Object catch (error) {
      session = session.copyWith(
        updatedAt: DateTime.now(),
        state: AiResearchSessionState.failed,
        completedAt: DateTime.now(),
        error: error.toString(),
        steps: List.unmodifiable(steps),
      );
      await _researchSessionRepository.saveSession(session);
      rethrow;
    }
  }

  String _buildPrompt(
    String question,
    AiContextPackage context,
    List<CompanionResearchStep> researchSteps,
  ) {
    final searchMatches = _promptSearchMatches(context);
    return '''用户问题：
$question

相关记忆：
${context.relatedMemories.isEmpty ? '无' : context.relatedMemories.map((result) {
            final memory = result.memory;
            return '- source_id=${formatAiSourceId('memory', memory.id)}｜score ${result.score}｜${memory.title}｜${memory.summary}｜${result.reasons.join('；')}${result.rerankSignals.isEmpty ? '' : '｜signals:${_signalLine(result.rerankSignals)}'}';
          }).join('\n')}

相关搜索命中（可能包含日记摘要、片段、全文预览或长期记忆）：
${searchMatches.isEmpty ? '无' : searchMatches.map((match) {
            return '- source_id=${formatAiSourceId(match.sourceType, match.sourceId)}｜entry=${match.entryId}｜score ${match.score}｜${match.title}｜${match.summary}｜${match.reasons.join('；')}${match.rerankSignals.isEmpty ? '' : '｜signals:${_signalLine(match.rerankSignals)}'}';
          }).join('\n')}

稳定画像：
${context.profileFacts.isEmpty ? '无' : context.profileFacts.asMap().entries.map((entry) {
            final sourceId = _profileSourceId(entry.key);
            final profile = entry.value;
            return '- source_id=$sourceId｜${profile.field}｜${profile.value}｜${profile.evidenceCount} 条证据｜置信度 ${profile.confidence.toStringAsFixed(2)}';
          }).join('\n')}

关系档案：
${context.relationshipProfiles.isEmpty ? '无' : context.relationshipProfiles.asMap().entries.map((entry) {
            final sourceId = _relationshipSourceId(entry.key);
            final profile = entry.value;
            return '- source_id=$sourceId｜${profile.personName}｜${profile.relationship ?? '未知关系'}｜${profile.interactionCount} 次互动｜${[
              ...profile.emotions.take(2),
              ...profile.patterns.take(2),
            ].join('、')}';
          }).join('\n')}

成长线索：
${context.stoneTasks.isEmpty ? '无' : context.stoneTasks.map((task) {
            return '- source_id=${formatAiSourceId('stone', task.id)}｜${task.title}｜${task.description}';
          }).join('\n')}

研究步骤与扩展证据：
${researchSteps.isEmpty ? '无' : researchSteps.map((step) {
            final evidenceLines = step.evidence.isEmpty
                ? '无证据'
                : step.evidence.map((item) {
                    final sourceId = item.sourceType == null ||
                            item.sourceId == null
                        ? ''
                        : formatAiSourceId(item.sourceType!, item.sourceId!);
                    return '  - source_id=$sourceId｜entry=${item.entryId ?? ''}｜score ${item.score}｜${item.title}｜${item.summary}｜${item.reason}';
                  }).join('\n');
            final batchLines = step.batchSummaries.isEmpty
                ? ''
                : '\n  批次摘要：\n${step.batchSummaries.map((batch) {
                    final representatives = batch.evidence.map((item) {
                      final sourceId = item.sourceType == null ||
                              item.sourceId == null
                          ? ''
                          : formatAiSourceId(item.sourceType!, item.sourceId!);
                      return '${item.title}(${sourceId.isEmpty ? item.score : sourceId})';
                    }).join('；');
                    return '  - ${batch.title}｜${batch.candidateCount} 条｜${batch.summary}${representatives.isEmpty ? '' : '｜代表：$representatives'}';
                  }).join('\n')}';
            return '- ${step.title}｜${step.status}｜${step.detail}\n$evidenceLines$batchLines';
          }).join('\n')}

要求：
1. 回答必须基于上面的相关记忆、日记摘要、日记片段、画像、关系档案或成长线索；
2. 如果材料不足，要明确说“不太够判断”；
3. 语气温和、具体，不做医疗或心理诊断；
4. 可以提出一个帮助用户继续理解自己的追问；
5. 画像、关系档案和成长线索只能作为辅助背景，不要当作绝对结论；
6. sources 必须使用给定材料中的 source_id；不能为没有出现在材料里的内容编造来源。
7. 如果问题适合，回答可以使用 Markdown 表格、时间线、列表或行动计划，不要只限于纯段落。

输出 JSON：
{
  "answer": "回答正文",
  "follow_up": "一个可选追问",
  "sources": [{"source_id": "memory:xxx", "title": "来源标题", "reason": "为什么引用"}]
}''';
  }

  String _signalLine(Map<String, double> signals) {
    return signals.entries
        .map((entry) => '${entry.key}:${entry.value.toStringAsFixed(2)}')
        .join(',');
  }

  List<AiSearchMatch> _promptSearchMatches(AiContextPackage context) {
    return context.searchMatches
        .where((match) =>
            match.sourceType != 'profile' && match.sourceType != 'relationship')
        .toList(growable: false);
  }

  List<CompanionResearchEvidence> _evidenceFromContext(
    AiContextPackage context,
  ) {
    return [
      for (final match in context.searchMatches)
        if (_isPromptSearchMatch(match)) _evidenceFromMatch(match),
      for (final result in context.relatedMemories)
        CompanionResearchEvidence(
          title: result.memory.title,
          summary: result.memory.summary,
          reason: result.reasons.join('；'),
          score: result.score,
          sourceType: 'memory',
          sourceId: result.memory.id,
          entryId: result.memory.sourceEntryId,
        ),
      for (final entry in context.profileFacts.asMap().entries)
        CompanionResearchEvidence(
          title: entry.value.field,
          summary: entry.value.value,
          reason: '${entry.value.evidenceCount} 条证据',
          score: (entry.value.confidence * 10).round(),
          sourceType: 'profile',
          sourceId: 'p${entry.key + 1}',
        ),
      for (final entry in context.relationshipProfiles.asMap().entries)
        CompanionResearchEvidence(
          title: entry.value.personName,
          summary: [
            entry.value.relationship ?? '',
            ...entry.value.emotions.take(2),
            ...entry.value.patterns.take(2),
          ].where((item) => item.trim().isNotEmpty).join('；'),
          reason: '${entry.value.interactionCount} 次互动',
          score: (entry.value.confidence * 10).round(),
          sourceType: 'relationship',
          sourceId: 'r${entry.key + 1}',
        ),
    ];
  }

  CompanionResearchEvidence _evidenceFromMatch(AiSearchMatch match) {
    return CompanionResearchEvidence(
      title: match.title,
      summary: match.summary,
      reason: match.reasons.join('；'),
      score: match.score,
      sourceType: match.sourceType,
      sourceId: match.sourceId,
      entryId: match.entryId,
    );
  }

  Future<_DynamicResearchResult> _runDynamicResearch({
    required String question,
    required AiContextPackage context,
    required List<CompanionResearchEvidence> primaryEvidence,
    required Future<void> Function(CompanionResearchStep step) addStep,
  }) async {
    final plan = await _createResearchPlan(question, context, primaryEvidence);
    final budget = _ResearchBudget.forPlan(plan);
    final queues = plan.items
        .map(
          (item) => _ResearchSubquestion(
            text: item.question,
            queue: _ResearchQueryQueue(item.queries),
          ),
        )
        .toList(growable: false);
    if (queues.isEmpty) throw const AiClientException('AI 未生成研究计划');

    await addStep(CompanionResearchStep(
      title: '规划研究路径',
      status:
          '拆成 ${queues.length} 个子问题，最多 ${budget.maxRounds} 轮、${budget.maxQueries} 次检索',
      detail:
          plan.items.map((item) => '${item.question}：${item.reason}').join('；'),
      developerDetail:
          'aiPlan confidence=${plan.confidence.toStringAsFixed(2)} '
          'budget(rounds=${budget.maxRounds}, queries=${budget.maxQueries}, evidence=${budget.maxEvidence}) '
          'stop=${plan.stopCondition}',
    ));

    final expandedEvidence = <CompanionResearchEvidence>[];
    final seenEvidenceKeys = <String>{};
    var queryCount = 0;
    for (var round = 1; round <= budget.maxRounds; round++) {
      final active = queues.where((item) => item.queue.hasNext).toList();
      if (active.isEmpty) break;
      final planned = <_ResearchPlannedQuery>[];
      final perRoundLimit =
          budget.queriesPerRound(round).clamp(1, budget.remaining(queryCount));
      for (final item in active) {
        if (planned.length >= perRoundLimit) break;
        final query = item.queue.next();
        if (query == null) continue;
        planned.add(_ResearchPlannedQuery(item, query));
      }
      if (planned.isEmpty) break;

      await addStep(CompanionResearchStep(
        title: '研究第 $round 轮',
        status: '正在检索 ${planned.length} 条线索',
        detail: planned.map((item) => item.query).join('；'),
        developerDetail:
            'round=$round remaining=${budget.remaining(queryCount)} queues=${queues.map((item) => '${item.text}:${item.queue.pendingCount}').join(',')}',
      ));

      var roundNewEvidence = 0;
      for (final plannedQuery in planned) {
        if (queryCount >= budget.maxQueries) break;
        queryCount++;
        final matches = await _searchService.search(
          plannedQuery.query,
          limit: budget.searchLimitFor(plannedQuery.query),
        );
        final evidence = matches
            .where(_isPromptSearchMatch)
            .map(_evidenceFromMatch)
            .toList(growable: false);
        final batches = _batchSummariesFor(plannedQuery.query, evidence);
        final representatives = _representativeEvidence(evidence, batches);
        final newEvidence = <CompanionResearchEvidence>[];
        for (final item in representatives) {
          final key = _evidenceKey(item);
          if (seenEvidenceKeys.add(key)) {
            newEvidence.add(item);
            expandedEvidence.add(item);
          }
        }
        roundNewEvidence += newEvidence.length;
        plannedQuery.subquestion.evidenceCount += newEvidence.length;
        await addStep(CompanionResearchStep(
          title: '整理“${plannedQuery.query}”',
          status: '找到 ${evidence.length} 条候选，新增 ${newEvidence.length} 条证据',
          detail: evidence.length > 12
              ? '候选资料较多，已压缩成 ${batches.length} 组摘要，并继续追踪新线索。'
              : '候选资料数量可控，已评估是否需要继续追踪。',
          evidence: newEvidence.take(8).toList(growable: false),
          batchSummaries: batches,
          developerDetail:
              'subquestion=${plannedQuery.subquestion.text} query=${plannedQuery.query} matches=${matches.length} sourceTypes=${_sourceTypeSummary(matches)}',
        ));
        if (expandedEvidence.length >= budget.maxEvidence) break;
      }
      if (expandedEvidence.length >= budget.maxEvidence) break;
      final decision = await _planNextResearchRound(
        question: question,
        plan: plan,
        round: round,
        queues: queues,
        evidence: _dedupeEvidence([...primaryEvidence, ...expandedEvidence]),
        remainingQueries: budget.remaining(queryCount),
      );
      for (final item in decision.queries) {
        final target = queues.firstWhere(
          (queue) => queue.text == item.subquestion,
          orElse: () => queues.first,
        );
        target.queue.addAll([item.query]);
      }
      await addStep(CompanionResearchStep(
        title: 'AI 判断下一步',
        status: decision.shouldContinue ? '继续追踪新线索' : '证据已经收敛',
        detail: decision.reason,
        developerDetail:
            'round=$round next=${decision.queries.map((item) => '${item.subquestion}:${item.query}').join(' | ')}',
      ));
      if (!decision.shouldContinue) break;
      if (roundNewEvidence == 0 && decision.queries.isEmpty && round >= 2) {
        await addStep(CompanionResearchStep(
          title: '研究收敛',
          status: '连续扩展没有新增关键证据',
          detail: '停止继续扩大检索，避免用低相关资料稀释回答。',
          developerDetail: 'round=$round queryCount=$queryCount',
        ));
        break;
      }
      for (final item in queues) {
        if (item.evidenceCount >= budget.enoughEvidencePerSubquestion) {
          item.queue.trim(2);
        }
      }
    }
    final evidence = _dedupeEvidence(expandedEvidence)
        .take(budget.maxEvidence)
        .toList(growable: false);
    return _DynamicResearchResult(
      evidence: evidence,
      subquestionEvidenceCounts: {
        for (final item in queues) item.text: item.evidenceCount,
      },
      coverageNote: plan.stopCondition,
      queryCount: queryCount,
      budget: budget,
    );
  }

  Future<_ResearchPlan> _createResearchPlan(
    String question,
    AiContextPackage context,
    List<CompanionResearchEvidence> primaryEvidence,
  ) async {
    const systemPrompt = '你是拾年的研究规划器。你必须为用户问题规划可验证的个人历史检索路径，不要回答问题。输出必须是 JSON。';
    final userPrompt = '''用户问题：
$question

已有基础资料：
${_evidencePromptLines(primaryEvidence.take(16).toList(growable: false))}

请生成研究计划。要求：
1. 不要依赖固定模板，按问题实际复杂度拆分 1-6 个子问题；
2. 每个子问题给出 1-5 个检索查询，查询应是用户历史中可能出现的自然关键词、人物、地点、事件或时间组合；
3. 如果问题需要多跳，请先查能定位下一跳的信息，例如“领导”可能先查真实姓名，再查姓名相关记录；
4. 不要回答问题，不要编造资料中没有的人名；
5. stop_condition 写清楚什么情况下可以停止检索；
6. confidence 表示计划本身的把握，0-1。

输出 JSON：
{
  "subquestions": [
    {
      "question": "需要回答的子问题",
      "reason": "为什么需要查这条线",
      "queries": ["检索词1", "检索词2"]
    }
  ],
  "stop_condition": "停止检索条件",
  "confidence": 0.7
}''';
    final jsonText = await _client.completeJson(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      maxTokens: 900,
    );
    final parsed = _mapValue(jsonDecode(jsonText));
    final items = _listValue(parsed['subquestions'])
        .map(_mapValue)
        .map((item) {
          final queries = _stringList(item['queries'])
              .map((query) => query.trim())
              .where((query) => query.length >= 2)
              .take(5)
              .toList(growable: false);
          return _ResearchPlanItem(
            question: _stringValue(item['question']).trim(),
            reason: _stringValue(item['reason']).trim(),
            queries: queries,
          );
        })
        .where((item) => item.question.isNotEmpty && item.queries.isNotEmpty)
        .take(6)
        .toList(growable: false);
    if (items.isEmpty) {
      throw const AiClientException('AI 研究计划为空');
    }
    return _ResearchPlan(
      items: items,
      stopCondition: _stringValue(parsed['stop_condition']).trim(),
      confidence: _doubleValue(parsed['confidence'], fallback: 0.5),
    );
  }

  Future<_NextResearchDecision> _planNextResearchRound({
    required String question,
    required _ResearchPlan plan,
    required int round,
    required List<_ResearchSubquestion> queues,
    required List<CompanionResearchEvidence> evidence,
    required int remainingQueries,
  }) async {
    if (remainingQueries <= 0) {
      return const _NextResearchDecision(
        shouldContinue: false,
        reason: '检索预算已用完。',
      );
    }
    const systemPrompt =
        '你是拾年的研究控制器。你要根据已找到的证据判断是否需要继续检索，以及下一轮该查什么。输出必须是 JSON。';
    final userPrompt = '''用户问题：
$question

原始研究计划：
${plan.items.map((item) => '- ${item.question}｜${item.reason}｜queries=${item.queries.join('、')}').join('\n')}

当前轮次：$round
剩余检索次数：$remainingQueries
停止条件：${plan.stopCondition}

当前证据：
${_evidencePromptLines(evidence.take(28).toList(growable: false))}

子问题覆盖：
${queues.map((item) => '- ${item.text}：${item.evidenceCount} 条证据，待查 ${item.queue.pendingCount} 条').join('\n')}

请判断下一步。要求：
1. 如果证据已经足够回答，should_continue=false；
2. 如果证据不足，给出 1-5 条新的检索 query；
3. 新 query 必须基于已出现的证据、用户问题或明确缺口，不要凭空发明人物或事件；
4. queries[].subquestion 必须使用上方某个子问题原文。

输出 JSON：
{
  "should_continue": true,
  "reason": "为什么继续或停止",
  "queries": [
    {"subquestion": "子问题原文", "query": "下一轮检索词", "reason": "为什么查"}
  ]
}''';
    final jsonText = await _client.completeJson(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      maxTokens: 800,
    );
    final parsed = _mapValue(jsonDecode(jsonText));
    final queries = _listValue(parsed['queries'])
        .map(_mapValue)
        .map((item) => _NextResearchQuery(
              subquestion: _stringValue(item['subquestion']).trim(),
              query: _stringValue(item['query']).trim(),
              reason: _stringValue(item['reason']).trim(),
            ))
        .where((item) => item.subquestion.isNotEmpty && item.query.length >= 2)
        .take(5)
        .toList(growable: false);
    return _NextResearchDecision(
      shouldContinue:
          _boolValue(parsed['should_continue']) && queries.isNotEmpty,
      reason: _stringValue(parsed['reason']).trim(),
      queries: queries,
    );
  }

  Future<Map<String, dynamic>> _verifyAnswer({
    required String question,
    required AiContextPackage context,
    required List<CompanionResearchStep> researchSteps,
    required Map<String, dynamic> answerJson,
  }) async {
    const systemPrompt =
        '你是拾年的回答校验器。你只检查回答是否严格基于证据、是否遗漏子问题、是否把推测说成事实。输出必须是 JSON。';
    final userPrompt = '''用户问题：
$question

候选回答 JSON：
${jsonEncode(answerJson)}

可用证据与研究过程：
${_buildPrompt(question, context, researchSteps)}

请校验候选回答。要求：
1. 如果回答没有超出证据，status=ok，并原样返回 answer/follow_up/sources；
2. 如果有轻微超证据、遗漏不确定性或结构不清，status=revise，并给出修正版；
3. 如果回答严重编造或无法基于证据回答，status=reject，并说明 issues；
4. sources 只能保留上方可用 source_id。

输出 JSON：
{
  "status": "ok",
  "issues": ["问题"],
  "answer": "校验后的 Markdown 回答",
  "follow_up": "追问",
  "sources": [{"source_id": "entry_summary:xxx", "title": "来源标题", "reason": "引用原因"}]
}''';
    final jsonText = await _client.completeJson(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      maxTokens: 1400,
    );
    final parsed = _mapValue(jsonDecode(jsonText));
    final status = _stringValue(parsed['status']).trim().toLowerCase();
    if (status == 'reject') {
      final issues = _stringList(parsed['issues']).join('；');
      throw AiClientException(issues.isEmpty ? 'AI 回答校验未通过' : issues);
    }
    if (status != 'ok' && status != 'revise') {
      throw const AiClientException('AI 回答校验返回无效状态');
    }
    final answer = _stringValue(parsed['answer']).trim();
    if (answer.isEmpty) {
      throw const AiClientException('AI 回答校验返回空回答');
    }
    return parsed;
  }

  String _evidencePromptLines(List<CompanionResearchEvidence> evidence) {
    if (evidence.isEmpty) return '无';
    return evidence.map((item) {
      final sourceId = item.sourceType == null || item.sourceId == null
          ? ''
          : formatAiSourceId(item.sourceType!, item.sourceId!);
      return '- source_id=$sourceId｜entry=${item.entryId ?? ''}｜score ${item.score}｜${item.title}｜${item.summary}｜${item.reason}';
    }).join('\n');
  }

  String _evidenceKey(CompanionResearchEvidence item) {
    return '${item.sourceType}:${item.sourceId}:${item.entryId}:${item.title}';
  }

  List<CompanionResearchEvidence> _dedupeEvidence(
    List<CompanionResearchEvidence> evidence,
  ) {
    final byKey = <String, CompanionResearchEvidence>{};
    for (final item in evidence) {
      final key = '${item.sourceType}:${item.sourceId}:${item.entryId}';
      final previous = byKey[key];
      if (previous == null || item.score > previous.score) {
        byKey[key] = item;
      }
    }
    final result = byKey.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return result;
  }

  List<CompanionResearchBatchSummary> _batchSummariesFor(
    String query,
    List<CompanionResearchEvidence> evidence,
  ) {
    if (evidence.length <= 12) return const [];
    final groups = <String, List<CompanionResearchEvidence>>{};
    for (final item in evidence) {
      final key = _batchKey(query, item);
      groups.putIfAbsent(key, () => []).add(item);
    }
    final batches = groups.entries.map((entry) {
      final items = entry.value.toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      final top = items.take(3).toList(growable: false);
      final topics = _topTerms(items);
      return CompanionResearchBatchSummary(
        title: entry.key,
        candidateCount: items.length,
        summary: [
          if (topics.isNotEmpty) '集中在 ${topics.join('、')}',
          '最高分 ${items.first.score}',
          '已保留 ${top.length} 条代表证据',
        ].join('；'),
        evidence: top,
        developerDetail:
            'query=$query bucket=${entry.key} kept=${top.length}/${items.length}',
      );
    }).toList()
      ..sort((a, b) {
        final byCount = b.candidateCount.compareTo(a.candidateCount);
        if (byCount != 0) return byCount;
        final aScore = a.evidence.isEmpty ? 0 : a.evidence.first.score;
        final bScore = b.evidence.isEmpty ? 0 : b.evidence.first.score;
        return bScore.compareTo(aScore);
      });
    return batches.take(6).toList(growable: false);
  }

  String _batchKey(String query, CompanionResearchEvidence item) {
    final source = item.sourceType ?? 'unknown';
    return '$source / $query';
  }

  List<String> _topTerms(List<CompanionResearchEvidence> evidence) {
    final counts = <String, int>{};
    for (final item in evidence) {
      final text = '${item.title} ${item.summary} ${item.reason}';
      for (final token in _compactTokens(text)) {
        counts.update(token, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return b.key.length.compareTo(a.key.length);
      });
    return entries.take(4).map((entry) => entry.key).toList(growable: false);
  }

  Set<String> _compactTokens(String text) {
    final tokens = <String>{};
    final cleaned = text
        .replaceAll(
            RegExp(r'[\s\n\r\t，。！？；：、“”‘’（）《》【】,.!?;:#>*_`\[\](){}/\\-]+'), ' ')
        .trim();
    for (final part in cleaned.split(' ')) {
      final value = part.trim();
      if (value.length >= 2 && value.length <= 8) tokens.add(value);
      if (value.length >= 4) {
        for (var i = 0; i <= value.length - 2; i++) {
          tokens.add(value.substring(i, i + 2));
        }
      }
    }
    tokens.removeWhere(_isLowValueToken);
    return tokens;
  }

  bool _isLowValueToken(String token) {
    return const {
      '今天',
      '感觉',
      '记录',
      '相关',
      '候选',
      '资料',
      '同样',
      '提到',
      '关键词',
      '重合',
    }.contains(token);
  }

  List<CompanionResearchEvidence> _representativeEvidence(
    List<CompanionResearchEvidence> evidence,
    List<CompanionResearchBatchSummary> batches,
  ) {
    if (batches.isEmpty) return evidence;
    return _dedupeEvidence([
      for (final batch in batches) ...batch.evidence,
      ...evidence.take(4),
    ]);
  }

  String _sourceTypeSummary(List<AiSearchMatch> matches) {
    final counts = <String, int>{};
    for (final match in matches) {
      counts.update(match.sourceType, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
  }

  bool _isPromptSearchMatch(AiSearchMatch match) {
    return match.sourceType != 'profile' && match.sourceType != 'relationship';
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

  List<Object?> _listValue(Object? value) {
    if (value is List) return value;
    return const [];
  }

  List<String> _stringList(Object? value) {
    return _listValue(value)
        .map((item) => _stringValue(item).trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  bool _boolValue(Object? value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  double _doubleValue(Object? value, {required double fallback}) {
    if (value is num) return value.toDouble().clamp(0, 1);
    return (double.tryParse(value?.toString() ?? '') ?? fallback).clamp(0, 1);
  }

  static String _profileSourceId(int index) => 'profile:p${index + 1}';

  static String _relationshipSourceId(int index) =>
      'relationship:r${index + 1}';
}

class _CompanionSourceFilter {
  _CompanionSourceFilter(
    AiContextPackage context, {
    List<CompanionResearchEvidence> extraEvidence = const [],
  })  : _allowedById = _buildAllowedById(context, extraEvidence),
        _allowedByTitle = _buildAllowedByTitle(context, extraEvidence);

  final Map<String, _AllowedCompanionSource> _allowedById;
  final Map<String, _AllowedCompanionSource> _allowedByTitle;
  int filteredCount = 0;

  List<CompanionAnswerSource> sources(Object? value) {
    final items = value is List ? value : const [];
    final sources = <CompanionAnswerSource>[];
    for (final raw in items) {
      if (raw is! Map) {
        filteredCount++;
        continue;
      }
      final sourceId = _string(raw['source_id']) ??
          _string(raw['sourceId']) ??
          _string(raw['id']);
      final title = (_string(raw['title']) ?? '').trim();
      final reason = (_string(raw['reason']) ?? '').trim();
      final score = raw['score'] is int ? raw['score'] as int : 0;
      final allowed = sourceId == null
          ? _allowedByTitle[title]
          : _allowedById[sourceId.trim()];
      if (allowed == null) {
        filteredCount++;
        continue;
      }
      sources.add(CompanionAnswerSource(
        title: title.isEmpty ? allowed.title : title,
        reason: reason,
        score: score == 0 ? allowed.score : score,
        sourceType: allowed.sourceType,
        sourceId: allowed.sourceId,
      ));
    }
    return sources;
  }

  static Map<String, _AllowedCompanionSource> _buildAllowedById(
    AiContextPackage context,
    List<CompanionResearchEvidence> extraEvidence,
  ) {
    final sources = [
      ..._allowedSources(context),
      ..._allowedSourcesFromEvidence(extraEvidence),
    ];
    final byId = <String, _AllowedCompanionSource>{};
    for (final source in sources) {
      byId[formatAiSourceId(source.sourceType, source.sourceId)] = source;
      byId.putIfAbsent(source.sourceId, () => source);
    }
    return byId;
  }

  static Map<String, _AllowedCompanionSource> _buildAllowedByTitle(
    AiContextPackage context,
    List<CompanionResearchEvidence> extraEvidence,
  ) {
    final sources = [
      ..._allowedSources(context),
      ..._allowedSourcesFromEvidence(extraEvidence),
    ];
    final byTitle = <String, _AllowedCompanionSource>{};
    for (final source in sources) {
      if (source.title.trim().isEmpty) continue;
      byTitle.putIfAbsent(source.title.trim(), () => source);
    }
    return byTitle;
  }

  static List<_AllowedCompanionSource> _allowedSources(
    AiContextPackage context,
  ) {
    return [
      for (final result in context.relatedMemories)
        _AllowedCompanionSource(
          sourceType: 'memory',
          sourceId: result.memory.id,
          title: result.memory.title,
          score: result.score,
        ),
      for (final match in context.searchMatches)
        if (match.sourceType != 'profile' && match.sourceType != 'relationship')
          _AllowedCompanionSource(
            sourceType: match.sourceType,
            sourceId: match.sourceId,
            title: match.title,
            score: match.score,
          ),
      for (final entry in context.profileFacts.asMap().entries)
        _AllowedCompanionSource(
          sourceType: 'profile',
          sourceId: 'p${entry.key + 1}',
          title: entry.value.field,
          score: (entry.value.confidence * 10).round(),
        ),
      for (final entry in context.relationshipProfiles.asMap().entries)
        _AllowedCompanionSource(
          sourceType: 'relationship',
          sourceId: 'r${entry.key + 1}',
          title: entry.value.personName,
          score: (entry.value.confidence * 10).round(),
        ),
      for (final task in context.stoneTasks)
        _AllowedCompanionSource(
          sourceType: 'stone',
          sourceId: task.id,
          title: task.title,
          score: task.status == StoneTaskStatus.active ? 6 : 3,
        ),
    ];
  }

  static List<_AllowedCompanionSource> _allowedSourcesFromEvidence(
    List<CompanionResearchEvidence> evidence,
  ) {
    return [
      for (final item in evidence)
        if ((item.sourceType?.isNotEmpty ?? false) &&
            (item.sourceId?.isNotEmpty ?? false))
          _AllowedCompanionSource(
            sourceType: item.sourceType!,
            sourceId: item.sourceId!,
            title: item.title,
            score: item.score,
          ),
    ];
  }

  static String? _string(Object? value) => value is String ? value : null;
}

class _AllowedCompanionSource {
  const _AllowedCompanionSource({
    required this.sourceType,
    required this.sourceId,
    required this.title,
    required this.score,
  });

  final String sourceType;
  final String sourceId;
  final String title;
  final int score;
}

class _ResearchPlan {
  const _ResearchPlan({
    required this.items,
    required this.stopCondition,
    required this.confidence,
  });

  final List<_ResearchPlanItem> items;
  final String stopCondition;
  final double confidence;
}

class _ResearchPlanItem {
  const _ResearchPlanItem({
    required this.question,
    required this.reason,
    required this.queries,
  });

  final String question;
  final String reason;
  final List<String> queries;
}

class _NextResearchDecision {
  const _NextResearchDecision({
    required this.shouldContinue,
    required this.reason,
    this.queries = const [],
  });

  final bool shouldContinue;
  final String reason;
  final List<_NextResearchQuery> queries;
}

class _NextResearchQuery {
  const _NextResearchQuery({
    required this.subquestion,
    required this.query,
    required this.reason,
  });

  final String subquestion;
  final String query;
  final String reason;
}

class _ResearchBudget {
  const _ResearchBudget({
    required this.maxRounds,
    required this.maxQueries,
    required this.maxEvidence,
    required this.enoughEvidencePerSubquestion,
  });

  final int maxRounds;
  final int maxQueries;
  final int maxEvidence;
  final int enoughEvidencePerSubquestion;

  factory _ResearchBudget.forPlan(_ResearchPlan plan) {
    final subquestions = plan.items.length;
    final querySeeds =
        plan.items.fold<int>(0, (sum, item) => sum + item.queries.length);
    final complexity = (subquestions * 2 + querySeeds).clamp(3, 14);
    return _ResearchBudget(
      maxRounds: complexity >= 11
          ? 5
          : complexity >= 7
              ? 4
              : 3,
      maxQueries: complexity >= 11
          ? 18
          : complexity >= 7
              ? 12
              : 7,
      maxEvidence: complexity >= 11
          ? 36
          : complexity >= 7
              ? 28
              : 18,
      enoughEvidencePerSubquestion: complexity >= 11 ? 8 : 5,
    );
  }

  int queriesPerRound(int round) {
    if (round <= 1) return 4;
    if (round == 2) return 5;
    return 3;
  }

  int remaining(int usedQueries) => (maxQueries - usedQueries).clamp(0, 999);

  int searchLimitFor(String query) {
    final length = query.trim().length;
    if (length <= 3) return 32;
    if (length >= 12) return 64;
    return 48;
  }
}

class _DynamicResearchResult {
  const _DynamicResearchResult({
    required this.evidence,
    this.subquestionEvidenceCounts = const {},
    this.coverageNote = '',
    this.queryCount = 0,
    this.budget,
  });

  final List<CompanionResearchEvidence> evidence;
  final Map<String, int> subquestionEvidenceCounts;
  final String coverageNote;
  final int queryCount;
  final _ResearchBudget? budget;

  String get coverageStatus {
    if (subquestionEvidenceCounts.isEmpty) return '没有拆出明确子问题';
    final covered =
        subquestionEvidenceCounts.values.where((count) => count > 0).length;
    return '已覆盖 $covered/${subquestionEvidenceCounts.length} 个子问题';
  }

  String get coverageDetail {
    if (subquestionEvidenceCounts.isEmpty) return '会根据基础资料直接回答。';
    final detail = subquestionEvidenceCounts.entries
        .map((entry) =>
            '${entry.key}：${entry.value > 0 ? '${entry.value} 条证据' : '证据不足'}')
        .join('；');
    return coverageNote.isEmpty ? detail : '$detail。停止条件：$coverageNote';
  }

  String get developerDetail {
    final budgetText = budget == null
        ? ''
        : ' budget(rounds=${budget!.maxRounds}, queries=${budget!.maxQueries}, evidence=${budget!.maxEvidence})';
    return 'queries=$queryCount evidence=${evidence.length}$budgetText';
  }
}

class _ResearchSubquestion {
  _ResearchSubquestion({
    required this.text,
    required this.queue,
  });

  final String text;
  final _ResearchQueryQueue queue;
  int evidenceCount = 0;
}

class _ResearchPlannedQuery {
  const _ResearchPlannedQuery(this.subquestion, this.query);

  final _ResearchSubquestion subquestion;
  final String query;
}

class _ResearchQueryQueue {
  _ResearchQueryQueue(Iterable<String> values) {
    addAll(values);
  }

  final List<String> _pending = [];
  final Set<String> _seen = {};

  bool get hasNext => _pending.isNotEmpty;
  int get pendingCount => _pending.length;

  void addAll(Iterable<String> values) {
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.length < 2) continue;
      if (!_seen.add(normalized)) continue;
      _pending.add(normalized);
    }
  }

  String? next() {
    if (_pending.isEmpty) return null;
    return _pending.removeAt(0);
  }

  void trim(int keep) {
    if (_pending.length <= keep) return;
    _pending.removeRange(keep, _pending.length);
  }
}
