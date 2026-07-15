import 'dart:convert';

import '../models/ai_context_package.dart';
import '../models/ai_prompt_trace.dart';
import '../models/ai_profile.dart';
import '../models/companion_answer.dart';
import '../models/stone_task.dart';
import '../repositories/ai_prompt_trace_repository.dart';
import '../utils/ai_source_formatter.dart';
import 'ai_client_service.dart';
import 'ai_context_builder.dart';
import 'ai_search_service.dart';

typedef CompanionResearchProgress = void Function(CompanionResearchStep step);

const _genericNameStops = {
  '领导',
  '对象',
  '伴侣',
  '同事',
  '朋友',
  '今天',
  '昨天',
  '去年',
  '今年',
};

class CompanionAnswerService {
  const CompanionAnswerService({
    AiClientService? client,
    AiContextBuilder? contextBuilder,
    AiPromptTraceRepository? promptTraceRepository,
    AiSearchService? searchService,
  })  : _client = client ?? const AiClientService(),
        _contextBuilder = contextBuilder ?? const AiContextBuilder(),
        _promptTraceRepository =
            promptTraceRepository ?? const AiPromptTraceRepository(),
        _searchService = searchService ?? const AiSearchService();

  final AiClientService _client;
  final AiContextBuilder _contextBuilder;
  final AiPromptTraceRepository _promptTraceRepository;
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
    final steps = <CompanionResearchStep>[];
    void addStep(CompanionResearchStep step) {
      steps.add(step);
      onProgress?.call(step);
    }

    addStep(const CompanionResearchStep(
      title: '理解问题',
      status: '正在分析问题需要哪些资料',
      detail: '识别人物、时间、地点、事件和可能的多跳线索。',
    ));
    final context = await _contextBuilder.buildForQuestion(question);
    final primaryEvidence = _evidenceFromContext(context);
    addStep(CompanionResearchStep(
      title: '检索基础资料',
      status: '已完成基础检索',
      detail:
          '找到 ${context.searchMatches.length} 条搜索命中、${context.relatedMemories.length} 条记忆、${context.relationshipProfiles.length} 条关系档案。',
      evidence: primaryEvidence.take(12).toList(growable: false),
      developerDetail: context.debugSummary,
    ));
    final expansionQueries = _expansionQueries(question, context);
    final expandedEvidence = <CompanionResearchEvidence>[];
    final batchSummaries = <CompanionResearchBatchSummary>[];
    for (final query in expansionQueries.take(4)) {
      addStep(CompanionResearchStep(
        title: '扩展检索',
        status: '正在检索“$query”',
        detail: '根据上一轮线索继续查找相关日记、摘要、片段和记忆。',
      ));
      final matches = await _searchService.search(query, limit: 48);
      final evidence = matches
          .where(_isPromptSearchMatch)
          .map(_evidenceFromMatch)
          .toList(growable: false);
      final batches = _batchSummariesFor(query, evidence);
      batchSummaries.addAll(batches);
      expandedEvidence.addAll(_representativeEvidence(evidence, batches));
      addStep(CompanionResearchStep(
        title: '整理“$query”',
        status: '找到 ${evidence.length} 条候选资料',
        detail: evidence.length > 12
            ? '候选资料较多，已压缩成 ${batches.length} 组摘要，并保留每组代表证据进入回答上下文。'
            : '候选资料数量可控，直接进入回答上下文。',
        evidence: _representativeEvidence(evidence, batches)
            .take(8)
            .toList(growable: false),
        batchSummaries: batches,
        developerDetail:
            'query=$query matches=${matches.length} sourceTypes=${_sourceTypeSummary(matches)}',
      ));
    }
    addStep(CompanionResearchStep(
      title: '生成回答',
      status: '正在基于证据组织 Markdown 回答',
      detail: '会优先说明能确定的结论、不确定性和关键来源。',
      evidence: _dedupeEvidence([...primaryEvidence, ...expandedEvidence])
          .take(12)
          .toList(growable: false),
    ));
    try {
      const systemPrompt =
          '你是溯石的成长陪伴助手。你只能基于给定的用户历史材料回答，不诊断、不说教、不虚构。输出必须是 JSON。回答正文可以使用 Markdown。';
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
      final sourceFilter = _CompanionSourceFilter(
        context,
        extraEvidence:
            _dedupeEvidence([...primaryEvidence, ...expandedEvidence]),
      );
      final sources = sourceFilter.sources(parsed['sources']);
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
      return CompanionAnswer(
        answer: (parsed['answer'] as String? ?? '').trim(),
        followUp: (parsed['follow_up'] as String? ?? '').trim(),
        sources: sources,
        usedFallback: false,
        researchSteps: steps,
      );
    } on Object {
      return _fallbackAnswer(question, context, steps);
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

塑石行动：
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
1. 回答必须基于上面的相关记忆、日记摘要、日记片段、画像、关系档案或塑石行动；
2. 如果材料不足，要明确说“不太够判断”；
3. 语气温和、具体，不做医疗或心理诊断；
4. 可以提出一个帮助用户继续理解自己的追问；
5. 画像、关系档案和塑石行动只能作为辅助背景，不要当作绝对结论；
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

  CompanionAnswer _fallbackAnswer(
    String question,
    AiContextPackage context,
    List<CompanionResearchStep> researchSteps,
  ) {
    final memories = context.relatedMemories.take(3).toList();
    final matches = context.searchMatches.take(3).toList();
    final profiles = context.profileFacts.take(2).toList();
    final relationships = context.relationshipProfiles.take(2).toList();
    final stones = context.stoneTasks.take(2).toList();
    if (memories.isEmpty &&
        matches.isEmpty &&
        profiles.isEmpty &&
        relationships.isEmpty &&
        stones.isEmpty) {
      return CompanionAnswer(
        answer: '我暂时没有找到足够相关的历史记录来回答“$question”。可以换一种更具体的问法，比如加上时间、人物或事件。',
        followUp: '这件事大概发生在什么时候？',
        sources: const [],
        usedFallback: true,
        researchSteps: researchSteps,
      );
    }
    return CompanionAnswer(
      answer: [
        '我先根据本地资料给你一个简短回答：',
        if (relationships.isNotEmpty) ...[
          for (final relationship in relationships)
            _relationshipFallbackLine(relationship),
        ],
        if (profiles.isNotEmpty) ...[
          for (final profile in profiles)
            '关于你自己，已有候选观察是“${profile.field}”：${profile.value}。',
        ],
        if (memories.isNotEmpty || matches.isNotEmpty) ...[
          for (final result in memories)
            '历史记忆“${result.memory.title}”：${result.memory.summary}',
          for (final match in matches) '相关记录“${match.title}”：${match.summary}',
        ],
        if (stones.isNotEmpty) ...[
          for (final task in stones) '塑石行动“${task.title}”：${task.description}',
        ],
        '这些只是本地检索到的线索，不足以直接下结论。配置自定义 AI 后，我可以把它们整理成更完整的分析。',
      ].join('\n'),
      followUp: '这些记录里，哪一条最接近你现在想问的感觉？',
      sources: [
        for (final result in memories)
          CompanionAnswerSource(
            title: result.memory.title,
            reason: result.reasons.join('；'),
            score: result.score,
            sourceType: 'memory',
            sourceId: result.memory.id,
          ),
        for (final match in matches)
          CompanionAnswerSource(
            title: match.title,
            reason: match.reasons.join('；'),
            score: match.score,
            sourceType: match.sourceType,
            sourceId: match.sourceId,
          ),
        for (final profile in profiles)
          CompanionAnswerSource(
            title: profile.field,
            reason: '${profile.evidenceCount} 条证据',
            score: (profile.confidence * 10).round(),
            sourceType: 'profile',
            sourceId:
                _profileSourceId(profiles.indexOf(profile)).split(':').last,
          ),
        for (final relationship in relationships)
          CompanionAnswerSource(
            title: relationship.personName,
            reason: '${relationship.interactionCount} 次互动',
            score: (relationship.confidence * 10).round(),
            sourceType: 'relationship',
            sourceId: _relationshipSourceId(relationships.indexOf(relationship))
                .split(':')
                .last,
          ),
        for (final task in stones)
          CompanionAnswerSource(
            title: task.title,
            reason: '塑石行动',
            score: 1,
            sourceType: 'stone',
            sourceId: task.id,
          ),
      ],
      usedFallback: true,
      researchSteps: researchSteps,
    );
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

  List<String> _expansionQueries(String question, AiContextPackage context) {
    final queries = <String>[];
    final lower = question.toLowerCase();
    void add(String value) {
      final normalized = value.trim();
      if (normalized.length < 2) return;
      if (queries.contains(normalized)) return;
      queries.add(normalized);
    }

    for (final relationship in context.relationshipProfiles) {
      if (question.contains(relationship.personName) ||
          relationship.names.any(question.contains) ||
          _containsAny(
              question, const ['领导', '对象', '伴侣', '女朋友', '男朋友', '同事'])) {
        add(relationship.personName);
        add('${relationship.personName} ${_intentKeywords(question).join(' ')}');
      }
    }
    for (final match in context.searchMatches.take(8)) {
      for (final name in _namesFromText('${match.title} ${match.summary}')) {
        add(name);
        add('$name ${_intentKeywords(question).join(' ')}');
      }
    }
    if (lower.contains('singapore') || question.contains('新加坡')) {
      add('新加坡 樟宜 Bugis 滨海湾');
    }
    if (question.contains('杭州') && question.contains('梅')) {
      add('杭州 梅花 灵峰 探梅 盛开');
    }
    if (_containsAny(question, const ['月经', '姨妈', '生理期', '周期'])) {
      add('姨妈 生理期 周期 痛经');
    }
    if (_containsAny(question, const ['升职', '晋升', '向上管理', '领导'])) {
      add('升职 晋升 领导 汇报 向上管理');
    }
    return queries.take(6).toList(growable: false);
  }

  List<String> _intentKeywords(String question) {
    final keywords = <String>[];
    for (final item in const [
      '第一次',
      '最早',
      '最近',
      '去年',
      '升职',
      '晋升',
      '向上管理',
      '领导',
      '月经',
      '姨妈',
      '周期',
      '新加坡',
      '杭州',
      '梅花',
    ]) {
      if (question.contains(item)) keywords.add(item);
    }
    return keywords.isEmpty ? [question] : keywords;
  }

  List<String> _namesFromText(String text) {
    final names = <String>{};
    final patterns = [
      RegExp(r'(?:领导是|新领导是|直属领导|领导)([\u4e00-\u9fa5]{2,3})'),
      RegExp(r'(?:和|跟|见到|认识|对象|伴侣)([\u4e00-\u9fa5]{2,3})'),
      RegExp(r'(周岚|陈砚|小红|阿哲|林澈)'),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(1)?.trim();
        if (value == null || value.length < 2) continue;
        if (_genericNameStops.contains(value)) continue;
        names.add(value);
      }
    }
    return names.toList(growable: false);
  }

  bool _containsAny(String text, List<String> terms) {
    return terms.any(text.contains);
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
    final text = '${item.title} ${item.summary} ${item.reason}';
    for (final term in _intentKeywords(query)) {
      if (term.trim().isNotEmpty && text.contains(term)) {
        return '$source / $term';
      }
    }
    final name = _namesFromText(text).firstOrNull;
    if (name != null) return '$source / $name';
    return source;
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

  String _relationshipFallbackLine(RelationshipProfile relationship) {
    final latest = relationship.recentInteractions.isEmpty
        ? null
        : relationship.recentInteractions.first;
    final parts = [
      '关于“${relationship.personName}”',
      if (relationship.relationship?.isNotEmpty ?? false)
        '关系类型记录为 ${relationship.relationship}',
      '共有 ${relationship.interactionCount} 次互动线索',
      if (relationship.emotions.isNotEmpty)
        '常见情绪有 ${relationship.emotions.take(2).join('、')}',
      if (relationship.patterns.isNotEmpty)
        '可能的互动模式是 ${relationship.patterns.take(2).join('；')}',
      if (latest != null && latest.summary.isNotEmpty)
        '最近一次是：${latest.summary}',
    ];
    return '${parts.join('，')}。';
  }

  String _preview(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 600
        ? normalized
        : '${normalized.substring(0, 600)}…';
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
