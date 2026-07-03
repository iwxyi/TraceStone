import 'dart:convert';

import '../models/ai_context_package.dart';
import '../models/ai_prompt_trace.dart';
import '../models/ai_profile.dart';
import '../models/companion_answer.dart';
import '../models/stone_task.dart';
import '../repositories/ai_prompt_trace_repository.dart';
import 'ai_client_service.dart';
import 'ai_context_builder.dart';

class CompanionAnswerService {
  const CompanionAnswerService({
    AiClientService? client,
    AiContextBuilder? contextBuilder,
    AiPromptTraceRepository? promptTraceRepository,
  })  : _client = client ?? const AiClientService(),
        _contextBuilder = contextBuilder ?? const AiContextBuilder(),
        _promptTraceRepository =
            promptTraceRepository ?? const AiPromptTraceRepository();

  final AiClientService _client;
  final AiContextBuilder _contextBuilder;
  final AiPromptTraceRepository _promptTraceRepository;

  Future<CompanionAnswer> answer(String question) async {
    final context = await _contextBuilder.buildForQuestion(question);
    try {
      const systemPrompt =
          '你是溯石的成长陪伴助手。你只能基于给定的用户历史材料回答，不诊断、不说教、不虚构。输出必须是 JSON。';
      final userPrompt = _buildPrompt(question, context);
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
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      final sourceFilter = _CompanionSourceFilter(context);
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
          systemPrompt: trace.systemPrompt,
          userPrompt: trace.userPrompt,
        ));
      }
      return CompanionAnswer(
        answer: (parsed['answer'] as String? ?? '').trim(),
        followUp: (parsed['follow_up'] as String? ?? '').trim(),
        sources: sources,
        usedFallback: false,
      );
    } on Object {
      return _fallbackAnswer(question, context);
    }
  }

  String _buildPrompt(String question, AiContextPackage context) {
    return '''用户问题：
$question

相关记忆：
${context.relatedMemories.isEmpty ? '无' : context.relatedMemories.map((result) {
            final memory = result.memory;
            return '- source_id=memory:${memory.id}｜score ${result.score}｜${memory.title}｜${memory.summary}｜${result.reasons.join('；')}';
          }).join('\n')}

相关日记和片段：
${context.searchMatches.isEmpty ? '无' : context.searchMatches.map((match) {
            return '- source_id=${match.sourceType}:${match.sourceId}｜entry=${match.entryId}｜score ${match.score}｜${match.title}｜${match.summary}｜${match.reasons.join('；')}';
          }).join('\n')}

稳定画像：
${context.profileFacts.isEmpty ? '无' : context.profileFacts.map((profile) {
            return '- source_id=profile:${profile.id}｜${profile.field}｜${profile.value}｜${profile.evidenceCount} 条证据｜置信度 ${profile.confidence.toStringAsFixed(2)}';
          }).join('\n')}

关系档案：
${context.relationshipProfiles.isEmpty ? '无' : context.relationshipProfiles.map((profile) {
            return '- source_id=relationship:${profile.personName}｜${profile.personName}｜${profile.relationship ?? '未知关系'}｜${profile.interactionCount} 次互动｜${[
              ...profile.emotions.take(2),
              ...profile.patterns.take(2),
            ].join('、')}';
          }).join('\n')}

塑石行动：
${context.stoneTasks.isEmpty ? '无' : context.stoneTasks.map((task) {
            return '- source_id=stone:${task.id}｜${task.title}｜${task.description}';
          }).join('\n')}

要求：
1. 回答必须基于上面的相关记忆、日记摘要、日记片段、画像、关系档案或塑石行动；
2. 如果材料不足，要明确说“不太够判断”；
3. 语气温和、具体，不做医疗或心理诊断；
4. 可以提出一个帮助用户继续理解自己的追问；
5. 画像、关系档案和塑石行动只能作为辅助背景，不要当作绝对结论；
6. sources 必须使用给定材料中的 source_id；不能为没有出现在材料里的内容编造来源。

输出 JSON：
{
  "answer": "回答正文",
  "follow_up": "一个可选追问",
  "sources": [{"source_id": "memory:xxx", "title": "来源标题", "reason": "为什么引用"}]
}''';
  }

  CompanionAnswer _fallbackAnswer(String question, AiContextPackage context) {
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
            sourceId: profile.id,
          ),
        for (final relationship in relationships)
          CompanionAnswerSource(
            title: relationship.personName,
            reason: '${relationship.interactionCount} 次互动',
            score: (relationship.confidence * 10).round(),
            sourceType: 'relationship',
            sourceId: relationship.personName,
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
    );
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
}

class _CompanionSourceFilter {
  _CompanionSourceFilter(AiContextPackage context)
      : _allowedById = _buildAllowedById(context),
        _allowedByTitle = _buildAllowedByTitle(context);

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
  ) {
    final sources = _allowedSources(context);
    return {
      for (final source in sources)
        '${source.sourceType}:${source.sourceId}': source,
    };
  }

  static Map<String, _AllowedCompanionSource> _buildAllowedByTitle(
    AiContextPackage context,
  ) {
    final sources = _allowedSources(context);
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
        _AllowedCompanionSource(
          sourceType: match.sourceType,
          sourceId: match.sourceId,
          title: match.title,
          score: match.score,
        ),
      for (final profile in context.profileFacts)
        _AllowedCompanionSource(
          sourceType: 'profile',
          sourceId: profile.id,
          title: profile.field,
          score: (profile.confidence * 10).round(),
        ),
      for (final relationship in context.relationshipProfiles)
        _AllowedCompanionSource(
          sourceType: 'relationship',
          sourceId: relationship.personName,
          title: relationship.personName,
          score: (relationship.confidence * 10).round(),
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
