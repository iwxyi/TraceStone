import 'dart:convert';

import '../models/ai_context_package.dart';
import '../models/ai_prompt_trace.dart';
import '../models/companion_answer.dart';
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
      await _promptTraceRepository.saveTrace(AiPromptTrace(
        id: 'companion:last',
        scenario: context.scenario.name,
        createdAt: DateTime.now(),
        contextSummary: context.debugSummary,
        systemPromptPreview: _preview(systemPrompt),
        userPromptPreview: _preview(userPrompt),
        systemPromptLength: systemPrompt.length,
        userPromptLength: userPrompt.length,
      ));
      final jsonText = await _client.completeJson(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxTokens: 1200,
      );
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      return CompanionAnswer(
        answer: (parsed['answer'] as String? ?? '').trim(),
        followUp: (parsed['follow_up'] as String? ?? '').trim(),
        sources: _sources(parsed['sources']),
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
            return '- score ${result.score}｜${memory.title}｜${memory.summary}｜${result.reasons.join('；')}';
          }).join('\n')}

要求：
1. 回答必须基于上面的相关记忆；
2. 如果材料不足，要明确说“不太够判断”；
3. 语气温和、具体，不做医疗或心理诊断；
4. 可以提出一个帮助用户继续理解自己的追问；
5. sources 只能来自给定的相关记忆。

输出 JSON：
{
  "answer": "回答正文",
  "follow_up": "一个可选追问",
  "sources": [{"title": "来源标题", "reason": "为什么引用"}]
}''';
  }

  CompanionAnswer _fallbackAnswer(String question, AiContextPackage context) {
    if (context.relatedMemories.isEmpty) {
      return CompanionAnswer(
        answer: '我暂时没有找到足够相关的历史记录来回答“$question”。可以换一种更具体的问法，比如加上时间、人物或事件。',
        followUp: '这件事大概发生在什么时候？',
        sources: const [],
        usedFallback: true,
      );
    }
    final top = context.relatedMemories.take(3).toList();
    return CompanionAnswer(
      answer: [
        '我先根据本地记忆给你一个简短回答：这件事可能和这些记录有关。',
        for (final result in top)
          '“${result.memory.title}”：${result.memory.summary}',
        '如果配置了自定义 AI，我可以把这些线索整理成更完整的分析。',
      ].join('\n'),
      followUp: '这些记录里，哪一条最接近你现在想问的感觉？',
      sources: [
        for (final result in top)
          CompanionAnswerSource(
            title: result.memory.title,
            reason: result.reasons.join('；'),
            score: result.score,
          ),
      ],
      usedFallback: true,
    );
  }

  List<CompanionAnswerSource> _sources(Object? value) {
    return (value as List<dynamic>? ?? [])
        .map((item) => item as Map<String, dynamic>? ?? const {})
        .map((item) => CompanionAnswerSource(
              title: (item['title'] as String? ?? '').trim(),
              reason: (item['reason'] as String? ?? '').trim(),
              score: item['score'] as int? ?? 0,
            ))
        .where((item) => item.title.isNotEmpty || item.reason.isNotEmpty)
        .toList();
  }

  String _preview(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 600
        ? normalized
        : '${normalized.substring(0, 600)}…';
  }
}
