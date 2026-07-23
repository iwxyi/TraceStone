import 'dart:convert';

import '../models/diary_entry.dart';
import '../models/diary_insight.dart';
import '../models/entry_summary.dart';
import '../models/memory_entry.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/memory_repository.dart';
import 'ai_client_service.dart';

class AiUserProfileService {
  const AiUserProfileService({
    AiClientService? client,
    DiaryRepository? diaryRepository,
    EntrySummaryRepository? summaryRepository,
    InsightRepository? insightRepository,
    MemoryRepository? memoryRepository,
  })  : _client = client ?? const AiClientService(),
        _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _summaryRepository =
            summaryRepository ?? const EntrySummaryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _memoryRepository = memoryRepository ?? const MemoryRepository();

  static const profileMemoryId = 'ai-user-profile';

  final AiClientService _client;
  final DiaryRepository _diaryRepository;
  final EntrySummaryRepository _summaryRepository;
  final InsightRepository _insightRepository;
  final MemoryRepository _memoryRepository;

  Future<MemoryEntry?> currentProfile() async {
    return (await currentState()).profile;
  }

  Future<AiUserProfileState> currentState() async {
    final entries = await _diaryRepository.listEntries();
    final entryIds = entries.map((entry) => entry.id).toSet();
    final memories = await _memoryRepository.listMemories();
    for (final memory in memories) {
      if (memory.id != profileMemoryId || memory.archived) continue;
      final sourceIds = memory.allSourceEntryIds.toSet();
      final activeSourceCount = sourceIds.intersection(entryIds).length;
      final newEntryCount = entryIds.difference(sourceIds).length;
      final removedSourceCount = sourceIds.difference(entryIds).length;
      final changedCount = newEntryCount + removedSourceCount;
      return AiUserProfileState(
        profile: memory,
        totalEntryCount: entries.length,
        sourceEntryCount: activeSourceCount,
        changedEntryCount: changedCount,
        freshness: _freshnessFor(
          sourceEntryCount: activeSourceCount,
          changedEntryCount: changedCount,
        ),
      );
    }
    return AiUserProfileState(
      profile: null,
      totalEntryCount: entries.length,
      sourceEntryCount: 0,
      changedEntryCount: entries.length,
      freshness: AiUserProfileFreshness.missing,
    );
  }

  AiUserProfileFreshness _freshnessFor({
    required int sourceEntryCount,
    required int changedEntryCount,
  }) {
    if (sourceEntryCount <= 0) return AiUserProfileFreshness.staleLarge;
    if (changedEntryCount <= 0) return AiUserProfileFreshness.upToDate;
    if (changedEntryCount / sourceEntryCount <= 0.25) {
      return AiUserProfileFreshness.staleSmall;
    }
    return AiUserProfileFreshness.staleLarge;
  }

  Future<MemoryEntry> rebuildProfile() async {
    final entries = await _diaryRepository.listEntries();
    entries.sort((a, b) => b.date.compareTo(a.date));
    final summaries = <EntrySummary>[];
    for (final entry in entries.take(160)) {
      final summary = await _summaryRepository.getSummary(entry.id);
      if (summary != null) summaries.add(summary);
    }
    final insights = await _insightRepository.listInsights();
    final memories = (await _memoryRepository.listMemories())
        .where((memory) => memory.id != profileMemoryId && !memory.archived)
        .toList(growable: false);
    final now = DateTime.now();
    final systemPrompt =
        '你是拾年的长期用户画像助手。你要基于用户自己的日记摘要、长期记忆、历史洞察和少量原文预览，形成一份能帮助后续 AI 真正认识这个人的综合画像：TA 经历过什么、在意什么、如何感受和行动、什么支持方式更契合 TA。语气克制、具体、不施压。输出必须是 JSON。';
    final userPrompt = _buildPrompt(
      entries: entries,
      summaries: summaries,
      insights: insights,
      memories: memories,
    );
    final jsonText = await _client.completeJson(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      maxTokens: 2400,
    );
    final parsed = _mapValue(jsonDecode(jsonText));
    final sections = _stringList(parsed['sections']);
    final summary = _summaryText(parsed, sections);
    final sourceIds = <String>{
      for (final entry in entries) entry.id,
      for (final summary in summaries.take(80)) summary.entryId,
      for (final memory in memories.take(40)) ...memory.allSourceEntryIds,
      for (final insight in insights.take(80)) insight.entryId,
    }.where((id) => id.trim().isNotEmpty).toList(growable: false);
    final profile = MemoryEntry(
      id: profileMemoryId,
      sourceEntryId: sourceIds.isEmpty ? '' : sourceIds.first,
      date: now,
      createdAt: now,
      summary: summary,
      keywords: _stringList(parsed['keywords']).take(12).toList(),
      emotion: _stringValue(parsed['tone']).trim(),
      people: _stringList(parsed['people']).take(12).toList(),
      tags: const ['用户画像', 'AI综合画像'],
      evidenceEntryIds: sourceIds.take(120).toList(),
      importance: 0.9,
      confidence: _doubleValue(parsed['confidence'], fallback: 0.68)
          .clamp(0, 1)
          .toDouble(),
    );
    await _memoryRepository.saveMemory(profile);
    return profile;
  }

  String _buildPrompt({
    required List<DiaryEntry> entries,
    required List<EntrySummary> summaries,
    required List<DiaryInsight> insights,
    required List<MemoryEntry> memories,
  }) {
    return '''请生成一份“长期用户画像”。这份画像的目标不是贴标签，也不是只记录事实清单，而是帮助后续 AI 清楚理解：这个用户是谁、经历过什么、在意什么、如何感受和行动、处在哪个阶段、哪些建议和回答方式会真正契合 TA。

输出 JSON：
{
  "overview": "总体认识，150字以内",
  "sections": [
    "一个维度一段。可以覆盖经历脉络、当前处境、内在模式、关系模式、压力与恢复、力量之源、模式陷阱、突破时刻、价值偏好、回答注意等。每段都要具体、有依据、能指导后续回答。"
  ],
  "keywords": ["后续检索可用关键词"],
  "people": ["重要人物"],
  "tone": "适合与用户交流的语气/注意点",
  "confidence": 0.72
}

要求：
1. 这是“认识一个人”的画像，不是性格测试报告；不要输出 MBTI 式、模板式、空泛的性格判断；
2. 可以包含具体资料，也可以包含内在模式、经历影响、关系处境、成长阶段、动机、矛盾和脆弱点；
3. 每个判断都必须来自下方材料，不能编造；证据不足时要写成“不确定/目前看起来/只在少量记录中出现”；
4. 后续 AI 会用这份画像生成今日分析、月年总结、建议和问答，所以内容要能实际帮助回答更贴合用户；
5. 区分稳定模式、近期状态和不确定观察，不要把短期状态写成固定人格；
6. 可以记录“力量之源”“模式陷阱”“突破时刻”，但必须写清具体条件或证据，不要写成励志模板；
7. 避免“用户倾向于……”后面接空泛概括；如果这样写，必须说明在什么场景下、由哪些记录体现、对后续回答有什么用；
8. 不要过度心理诊断，不要给用户贴病理化标签；
9. 不要出现内部 ID、字段名、JSON 外文本或调试说明；
10. sections 控制在 6-10 段，每段 60-140 字。

日记摘要：
${summaries.isEmpty ? '无' : summaries.take(100).map(_summaryLine).join('\n')}

长期记忆：
${memories.isEmpty ? '无' : memories.take(60).map(_memoryLine).join('\n')}

历史洞察：
${insights.isEmpty ? '无' : insights.take(80).map(_insightLine).join('\n')}

最近原文预览：
${entries.isEmpty ? '无' : entries.take(20).map(_entryLine).join('\n')}''';
  }

  String _summaryLine(EntrySummary summary) =>
      '- ${_dateLabel(summary.date)}｜${summary.title}｜${summary.brief}｜${summary.keyPoints.take(3).join('；')}';

  String _memoryLine(MemoryEntry memory) =>
      '- ${_dateLabel(memory.date)}｜${memory.summary}｜${[
        ...memory.keywords,
        ...memory.people,
        ...memory.tags
      ].take(8).join('、')}';

  String _insightLine(DiaryInsight insight) =>
      '- ${_dateLabel(insight.entryDate)}｜${insight.reflection}｜情绪:${insight.emotion}｜关键词:${insight.keywords.take(6).join('、')}｜记忆:${insight.memorySummary}';

  String _entryLine(DiaryEntry entry) =>
      '- ${_dateLabel(entry.date)}｜${entry.title ?? entry.excerpt}｜${entry.excerpt}';

  String _summaryText(Map<String, dynamic> parsed, List<String> sections) {
    final overview = _stringValue(parsed['overview']).trim();
    final parts = [
      if (overview.isNotEmpty) overview,
      ...sections,
    ].where((item) => item.trim().isNotEmpty).toList(growable: false);
    return parts.join('\n\n');
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _mapValue(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  double _doubleValue(Object? value, {required double fallback}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

enum AiUserProfileFreshness { missing, upToDate, staleSmall, staleLarge }

class AiUserProfileState {
  const AiUserProfileState({
    required this.profile,
    required this.totalEntryCount,
    required this.sourceEntryCount,
    required this.changedEntryCount,
    required this.freshness,
  });

  final MemoryEntry? profile;
  final int totalEntryCount;
  final int sourceEntryCount;
  final int changedEntryCount;
  final AiUserProfileFreshness freshness;

  bool get shouldAutoRefresh => freshness == AiUserProfileFreshness.staleLarge;

  String get label {
    switch (freshness) {
      case AiUserProfileFreshness.missing:
        return '未生成';
      case AiUserProfileFreshness.upToDate:
        return '最新';
      case AiUserProfileFreshness.staleSmall:
        return '有少量变化';
      case AiUserProfileFreshness.staleLarge:
        return '需要更新';
    }
  }
}
