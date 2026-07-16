import 'dart:convert';

import '../models/ai_context_package.dart';
import '../models/ai_prompt_trace.dart';
import '../models/ai_profile.dart';
import '../models/diary_entry.dart';
import '../models/entry_summary.dart';
import '../models/memory_retrieval_result.dart';
import '../models/period_summary.dart';
import '../models/stone_task.dart';
import '../repositories/ai_prompt_trace_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/period_summary_repository.dart';
import '../repositories/stone_task_repository.dart';
import '../utils/ai_source_formatter.dart';
import 'ai_client_service.dart';
import 'ai_context_builder.dart';
import 'entry_summary_service.dart';

class PeriodSummaryService {
  const PeriodSummaryService({
    AiContextBuilder? contextBuilder,
    AiClientService? client,
    AiPromptTraceRepository? promptTraceRepository,
    InsightRepository? insightRepository,
    PeriodSummaryRepository? periodSummaryRepository,
    StoneTaskRepository? stoneTaskRepository,
    EntrySummaryService? entrySummaryService,
  })  : _contextBuilder = contextBuilder ?? const AiContextBuilder(),
        _client = client ?? const AiClientService(),
        _promptTraceRepository =
            promptTraceRepository ?? const AiPromptTraceRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _periodSummaryRepository =
            periodSummaryRepository ?? const PeriodSummaryRepository(),
        _stoneTaskRepository =
            stoneTaskRepository ?? const StoneTaskRepository(),
        _entrySummaryService =
            entrySummaryService ?? const EntrySummaryService();

  final AiContextBuilder _contextBuilder;
  final AiClientService _client;
  final AiPromptTraceRepository _promptTraceRepository;
  final InsightRepository _insightRepository;
  final PeriodSummaryRepository _periodSummaryRepository;
  final StoneTaskRepository _stoneTaskRepository;
  final EntrySummaryService _entrySummaryService;

  Future<PeriodSummary> buildMonthSummary(
    DateTime month,
    List<DiaryEntry> entries,
  ) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    final scoped = entries
        .where((entry) =>
            entry.date.year == month.year && entry.date.month == month.month)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final context =
        await _contextBuilder.buildForPeriodSummary(start: start, end: end);
    return _build(
        id: PeriodSummaryRepository.monthId(month),
        type: PeriodSummaryType.month,
        start: start,
        end: end,
        entries: scoped,
        context: context);
  }

  Future<PeriodSummary> buildYearSummary(
    int year,
    List<DiaryEntry> entries,
  ) async {
    final start = DateTime(year);
    final end = DateTime(year, 12, 31, 23, 59, 59);
    final scoped = entries.where((entry) => entry.date.year == year).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final context =
        await _contextBuilder.buildForPeriodSummary(start: start, end: end);
    return _build(
        id: PeriodSummaryRepository.yearId(year),
        type: PeriodSummaryType.year,
        start: start,
        end: end,
        entries: scoped,
        context: context);
  }

  Future<PeriodSummary> _build({
    required String id,
    required PeriodSummaryType type,
    required DateTime start,
    required DateTime end,
    required List<DiaryEntry> entries,
    required AiContextPackage context,
  }) async {
    await _periodSummaryRepository.saveStatus(PeriodSummaryStatus(
      id: id,
      state: PeriodSummaryState.generating,
      updatedAt: DateTime.now(),
      message: '正在生成 AI 周期总结',
    ));
    try {
      final summary = await _buildAiSummary(
        id: id,
        type: type,
        start: start,
        end: end,
        entries: entries,
        context: context,
      );
      await _periodSummaryRepository.saveSummary(summary);
      await _periodSummaryRepository.saveStatus(PeriodSummaryStatus(
        id: id,
        state: PeriodSummaryState.completed,
        updatedAt: DateTime.now(),
        message: 'AI 周期总结已生成',
      ));
      return summary;
    } on AiClientException catch (error) {
      final summary = await _buildLocalSummary(
        id: id,
        type: type,
        start: start,
        end: end,
        entries: entries,
        context: context,
        fallbackReason: error.message,
      );
      await _periodSummaryRepository.saveSummary(summary);
      await _periodSummaryRepository.saveStatus(PeriodSummaryStatus(
        id: id,
        state: PeriodSummaryState.failed,
        updatedAt: DateTime.now(),
        message: 'AI 生成失败，已使用本地回退：${error.message}',
      ));
      return summary;
    } on FormatException catch (error) {
      final summary = await _buildLocalSummary(
        id: id,
        type: type,
        start: start,
        end: end,
        entries: entries,
        context: context,
        fallbackReason: error.message,
      );
      await _periodSummaryRepository.saveSummary(summary);
      await _periodSummaryRepository.saveStatus(PeriodSummaryStatus(
        id: id,
        state: PeriodSummaryState.failed,
        updatedAt: DateTime.now(),
        message: 'AI 返回格式异常，已使用本地回退',
      ));
      return summary;
    }
  }

  Future<PeriodSummary> _buildAiSummary({
    required String id,
    required PeriodSummaryType type,
    required DateTime start,
    required DateTime end,
    required List<DiaryEntry> entries,
    required AiContextPackage context,
  }) async {
    final systemPrompt =
        '你是拾年的周期总结助手。你必须基于日记摘要、用户画像、关系档案、相关记忆和成长线索生成具体回顾，帮助用户看见生活脉络和真实变化；不做统计报表式堆砌，不制造任务压力，不虚构事实。输出必须是 JSON。';
    final monthlySummaries = type == PeriodSummaryType.year
        ? await _monthSummariesForYear(start.year)
        : const <PeriodSummary>[];
    final userPrompt = _buildPrompt(
      type: type,
      start: start,
      end: end,
      entries: entries,
      context: context,
      monthlySummaries: monthlySummaries,
    );
    await _savePromptTrace(
      id: id,
      contextSummary: context.debugSummary,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
    );
    final jsonText = await _client.completeJson(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      maxTokens: type == PeriodSummaryType.year ? 2200 : 1600,
    );
    await _savePromptTrace(
      id: id,
      contextSummary: context.debugSummary,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      rawResponse: jsonText,
    );
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('周期总结 JSON 必须是对象');
    }
    return _parseAiSummary(
      id: id,
      type: type,
      start: start,
      end: end,
      entries: entries,
      context: context,
      monthlySummaries: monthlySummaries,
      json: decoded,
    );
  }

  Future<PeriodSummary> _buildLocalSummary({
    required String id,
    required PeriodSummaryType type,
    required DateTime start,
    required DateTime end,
    required List<DiaryEntry> entries,
    required AiContextPackage context,
    String? fallbackReason,
  }) async {
    final contextEntryIds =
        context.periodEntries.map((entry) => entry.id).toSet();
    final contextThemes = context.periodSummaries
        .expand((summary) => summary.topics)
        .toList(growable: false);
    final visibleRelationshipNames = context.relationshipProfiles
        .map((profile) => profile.personName)
        .toSet();
    final relatedMemoryThemes = context.relatedMemories
        .expand((result) => [
              ...result.memory.tags,
              ...result.memory.keywords,
            ])
        .toList(growable: false);
    final themes = <String, int>{};
    final emotions = <String, int>{};
    final briefs = <String>[];
    final representativeIds = <String>[];
    final relationshipHighlights = <String>[];

    for (final theme in contextThemes) {
      themes[theme] = (themes[theme] ?? 0) + 2;
    }
    for (final theme in relatedMemoryThemes) {
      themes[theme] = (themes[theme] ?? 0) + 1;
    }

    for (final entry in entries) {
      final insight = await _insightRepository.getInsight(entry.id);
      final fallbackSegments = _entrySummaryService.buildSegments(entry);
      final fallbackSummary =
          _entrySummaryService.buildSummary(entry, fallbackSegments);
      briefs.add(entry.excerpt);
      for (final topic in fallbackSummary.topics) {
        themes[topic] = (themes[topic] ?? 0) + 2;
      }
      if (fallbackSummary.emotion.isNotEmpty) {
        emotions[fallbackSummary.emotion] =
            (emotions[fallbackSummary.emotion] ?? 0) + 1;
      }
      if (insight != null) {
        if (insight.emotion.isNotEmpty) {
          emotions[insight.emotion] = (emotions[insight.emotion] ?? 0) + 1;
        }
        for (final keyword in insight.keywords) {
          themes[keyword] = (themes[keyword] ?? 0) + 1;
        }
        for (final update in insight.relationshipUpdates.take(3)) {
          if (!visibleRelationshipNames.contains(update.personName)) continue;
          final line = [
            if (update.personName.isNotEmpty) update.personName,
            if (update.summary.isNotEmpty) update.summary,
            if (update.pattern?.isNotEmpty ?? false) update.pattern!,
          ].join('｜');
          if (line.isNotEmpty) relationshipHighlights.add(line);
        }
      }
    }
    final stoneHighlights = await _stoneHighlights(start, end);

    final topThemes = _topKeys(themes, 8);
    final topEmotions = _topKeys(emotions, 5);
    representativeIds.addAll(entries
        .where((entry) =>
            entry.content.trim().isNotEmpty &&
            contextEntryIds.contains(entry.id))
        .take(5)
        .map((entry) => entry.id));
    if (representativeIds.isEmpty) {
      representativeIds.addAll(entries
          .where((entry) => entry.content.trim().isNotEmpty)
          .take(5)
          .map((entry) => entry.id));
    }

    final label = type == PeriodSummaryType.month
        ? '${start.year}年${start.month}月'
        : '${start.year}年';
    final brief = entries.isEmpty
        ? '$label 还没有日记。'
        : [
            '$label 共记录 ${entries.length} 篇日记。',
            if (topThemes.isNotEmpty) '主要主题：${topThemes.take(4).join('、')}。',
            if (topEmotions.isNotEmpty)
              '常见情绪：${topEmotions.take(3).join('、')}。',
          ].join('');

    final summary = PeriodSummary(
      id: id,
      type: type,
      startDate: start,
      endDate: end,
      generatedAt: DateTime.now(),
      entryCount: entries.length,
      brief: brief,
      themes: topThemes,
      emotions: topEmotions,
      representativeEntryIds: representativeIds,
      generator:
          fallbackReason == null ? 'local-aggregate-v1' : 'local-fallback-v1',
      coveredEntryIds: entries.map((entry) => entry.id).toList(),
      relationshipHighlights:
          _uniqueTake(relationshipHighlights, limit: 5).toList(),
      stoneHighlights: stoneHighlights,
      growthHighlights: [
        if (fallbackReason != null) 'AI 总结暂不可用，已保留本地聚合结果。',
      ],
      contextDebugSummary: [
        context.debugSummary,
        if (fallbackReason != null) 'fallback=$fallbackReason',
      ].join(' '),
      contextSourceLines: _periodContextSourceLines(context),
    );
    return summary;
  }

  PeriodSummary _parseAiSummary({
    required String id,
    required PeriodSummaryType type,
    required DateTime start,
    required DateTime end,
    required List<DiaryEntry> entries,
    required AiContextPackage context,
    required List<PeriodSummary> monthlySummaries,
    required Map<String, dynamic> json,
  }) {
    final brief = _stringValue(json['brief']).trim();
    if (brief.isEmpty && entries.isNotEmpty) {
      throw const FormatException('AI 周期总结缺少 brief');
    }
    return PeriodSummary(
      id: id,
      type: type,
      startDate: start,
      endDate: end,
      generatedAt: DateTime.now(),
      entryCount: entries.length,
      brief: brief.isEmpty ? _emptyBrief(type, start) : brief,
      themes: _stringList(json['themes']).take(8).toList(growable: false),
      emotions: _stringList(json['emotions']).take(5).toList(growable: false),
      representativeEntryIds: _representativeIds(
        entries,
        context.periodEntries.map((entry) => entry.id).toSet(),
        modelIds: _stringList(json['representative_entry_ids']),
      ),
      generator: type == PeriodSummaryType.month
          ? 'ai-month-summary-v1'
          : 'ai-year-summary-v1',
      coveredEntryIds: entries.map((entry) => entry.id).toList(),
      relationshipHighlights:
          _stringList(json['relationship_highlights']).take(5).toList(),
      stoneHighlights: _stringList(json['stone_highlights']).take(5).toList(),
      growthHighlights: _stringList(json['growth_highlights']).take(6).toList(),
      notableChanges: _stringList(json['notable_changes']).take(6).toList(),
      outlook: _stringValue(json['outlook']),
      contextDebugSummary: context.debugSummary,
      contextSourceLines: [
        ..._monthlySummarySourceLines(monthlySummaries),
        ..._periodContextSourceLines(context),
      ],
    );
  }

  String _buildPrompt({
    required PeriodSummaryType type,
    required DateTime start,
    required DateTime end,
    required List<DiaryEntry> entries,
    required AiContextPackage context,
    required List<PeriodSummary> monthlySummaries,
  }) {
    final isYear = type == PeriodSummaryType.year;
    final label = isYear ? '${start.year}年' : '${start.year}年${start.month}月';
    return '''请为用户生成$label${isYear ? '年度总结' : '月度总结'}。

输出 JSON 格式：
{
  "brief": "${isYear ? '350字以内，像年度回望，强调阶段变化、主线、成长和未完成的问题' : '220字以内，像月度回顾，强调这个月具体发生了什么、状态变化和重要线索'}",
  "themes": ["主题词"],
  "emotions": ["情绪词"],
  "growth_highlights": ["成长、恢复、尝试或新的理解"],
  "notable_changes": ["和过去相比的变化，必须有来源支撑"],
  "relationship_highlights": ["重要关系互动变化"],
  "stone_highlights": ["成长线索和微小变化"],
  "outlook": "${isYear ? '下一年的温和提醒，80字以内' : '下个月的温和提醒，60字以内'}",
  "representative_entry_ids": ["只能填下方出现过的 entry id"]
}

周期：${_dateLabel(start)} 至 ${_dateLabel(end)}
日记数量：${entries.length}

${isYear ? _yearInstruction() : _monthInstruction()}

${isYear ? '已生成月度总结：\n${_monthlySummaryPromptLines(monthlySummaries)}' : ''}

当期日记摘要：
${context.periodSummaries.isEmpty ? _rawEntryLines(entries) : context.periodSummaries.map(_periodSummaryLine).join('\n')}

当期原始日记索引：
${context.periodEntries.isEmpty ? '无' : context.periodEntries.take(40).map(_entryIndexLine).join('\n')}

相关长期记忆：
${context.relatedMemories.isEmpty ? '无' : context.relatedMemories.map(_memoryLine).join('\n')}

稳定画像：
${context.profileFacts.isEmpty ? '无' : context.profileFacts.asMap().entries.map((entry) => _profileLine(entry.key, entry.value)).join('\n')}

关系档案：
${context.relationshipProfiles.isEmpty ? '无' : context.relationshipProfiles.asMap().entries.map((entry) => _relationshipLine(entry.key, entry.value)).join('\n')}

成长线索：
${context.stoneTasks.isEmpty ? '无' : context.stoneTasks.map(_stoneLine).join('\n')}

要求：
1. 以当期日记摘要为主体，画像、关系、记忆只能辅助解释；
2. 不要写空泛鸡汤，不要只列统计；
3. 如果资料不足，要承认资料有限；
4. representative_entry_ids 只能使用“当期原始日记索引”里的 entry id；
5. 月度总结关注具体事件、情绪波动、关系互动和下月可延续的小线索；
6. 年度总结关注阶段性主线、跨月变化、反复出现的模式和成长，不要逐月流水账；
7. 不要编造没有出现过的人、地点、事件或节日。''';
  }

  String _monthInstruction() =>
      '月度定位：帮助用户看清这个月的生活纹理，包括重要事件、反复出现的情绪/主题、关系变化和可以带到下个月的一两个线索。';

  String _yearInstruction() =>
      '年度定位：优先参考已生成的月度总结和高重要度日记摘要，把一年写成阶段变化与成长主线，而不是 12 个月流水账。';

  Future<List<PeriodSummary>> _monthSummariesForYear(int year) async {
    final summaries = await _periodSummaryRepository.listSummaries();
    final months = summaries
        .where((summary) =>
            summary.type == PeriodSummaryType.month &&
            summary.startDate.year == year)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return months;
  }

  String _monthlySummaryPromptLines(List<PeriodSummary> summaries) {
    if (summaries.isEmpty) {
      return '无。请使用高重要度日记摘要归纳年度主线，不要逐月流水账。';
    }
    return summaries.map((summary) {
      return [
        '- ${formatAiSourceId('period_summary', summary.id)}',
        '${summary.startDate.year}-${summary.startDate.month.toString().padLeft(2, '0')}',
        summary.brief,
        if (summary.themes.isNotEmpty)
          'themes=${summary.themes.take(5).join('、')}',
        if (summary.growthHighlights.isNotEmpty)
          'growth=${summary.growthHighlights.take(3).join('；')}',
        if (summary.notableChanges.isNotEmpty)
          'changes=${summary.notableChanges.take(3).join('；')}',
      ].where((value) => value.trim().isNotEmpty).join(' | ');
    }).join('\n');
  }

  List<String> _monthlySummarySourceLines(List<PeriodSummary> summaries) {
    return summaries
        .map((summary) => [
              formatAiSourceId('period_summary', summary.id),
              '${summary.startDate.year}-${summary.startDate.month.toString().padLeft(2, '0')}',
              summary.brief,
              if (summary.generator.isNotEmpty)
                'generator=${summary.generator}',
            ].join(' | '))
        .toList(growable: false);
  }

  String _periodSummaryLine(EntrySummary summary) => [
        '- ${formatAiSourceId('entry_summary', summary.entryId)}',
        'entry:${summary.entryId}',
        _dateLabel(summary.date),
        if (summary.title.isNotEmpty) summary.title,
        summary.brief,
        if (summary.keyPoints.isNotEmpty)
          'points=${summary.keyPoints.take(3).join('；')}',
        if (summary.topics.isNotEmpty)
          'topics=${summary.topics.take(5).join('、')}',
        if (summary.emotion.isNotEmpty) 'emotion=${summary.emotion}',
        'importance=${summary.importance.toStringAsFixed(2)}',
      ].where((value) => value.trim().isNotEmpty).join(' | ');

  String _entryIndexLine(DiaryEntry entry) =>
      '- entry:${entry.id} | ${_dateLabel(entry.date)} | ${entry.title ?? entry.excerpt}';

  String _rawEntryLines(List<DiaryEntry> entries) {
    if (entries.isEmpty) return '无';
    return entries.take(40).map((entry) {
      return '- entry:${entry.id} | ${_dateLabel(entry.date)} | ${entry.excerpt}';
    }).join('\n');
  }

  Future<void> _savePromptTrace({
    required String id,
    required String contextSummary,
    required String systemPrompt,
    required String userPrompt,
    String? rawResponse,
  }) async {
    await _promptTraceRepository.saveTrace(AiPromptTrace(
      id: id,
      scenario: AiContextScenario.periodSummary.name,
      createdAt: DateTime.now(),
      contextSummary: contextSummary,
      systemPromptPreview: _compact(systemPrompt, maxLength: 240),
      userPromptPreview: _compact(userPrompt, maxLength: 500),
      systemPromptLength: systemPrompt.length,
      userPromptLength: userPrompt.length,
      rawResponsePreview:
          rawResponse == null ? '' : _compact(rawResponse, maxLength: 500),
      rawResponseLength: rawResponse?.length ?? 0,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      rawResponse: rawResponse,
    ));
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _emptyBrief(PeriodSummaryType type, DateTime start) {
    if (type == PeriodSummaryType.month) {
      return '${start.year}年${start.month}月还没有日记。';
    }
    return '${start.year}年还没有日记。';
  }

  List<String> _representativeIds(
    List<DiaryEntry> entries,
    Set<String> contextEntryIds, {
    required List<String> modelIds,
  }) {
    final validIds = entries.map((entry) => entry.id).toSet();
    final result = <String>[];
    for (final id in modelIds) {
      final normalized = id.startsWith('entry:') ? id.substring(6) : id;
      if (validIds.contains(normalized) && !result.contains(normalized)) {
        result.add(normalized);
      }
      if (result.length >= 6) return result;
    }
    for (final entry in entries) {
      if (!contextEntryIds.contains(entry.id)) continue;
      if (!result.contains(entry.id)) result.add(entry.id);
      if (result.length >= 6) return result;
    }
    for (final entry in entries) {
      if (!result.contains(entry.id)) result.add(entry.id);
      if (result.length >= 6) return result;
    }
    return result;
  }

  String _memoryLine(MemoryRetrievalResult result) {
    final memory = result.memory;
    return '- ${formatAiSourceId('memory', memory.id)} | sourceEntry:${memory.sourceEntryId} | ${_dateLabel(memory.date)} | score=${result.score} | ${memory.title} | ${memory.summary} | ${memory.emotion} | ${[
      ...memory.keywords,
      ...memory.people,
      ...memory.tags
    ].join('、')}';
  }

  String _profileLine(int index, ProfileFact profile) =>
      '- profile:$index | ${profile.field}=${profile.value} | confidence=${profile.confidence.toStringAsFixed(2)}';

  String _relationshipLine(int index, RelationshipProfile profile) => [
        '- relationship:$index',
        profile.personName,
        if (profile.relationship?.isNotEmpty ?? false) profile.relationship!,
        if (profile.emotions.isNotEmpty)
          'emotions=${profile.emotions.take(3).join('、')}',
        if (profile.patterns.isNotEmpty)
          'patterns=${profile.patterns.take(3).join('；')}',
        'confidence=${profile.confidence.toStringAsFixed(2)}',
      ].join(' | ');

  String _stoneLine(StoneTask task) =>
      '- ${formatAiSourceId('stone', task.id)} | sourceEntry:${task.sourceEntryId} | ${task.title} | ${task.description} | ${task.status.name}';

  String _stringValue(Object? value) => value is String ? value : '';

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _periodContextSourceLines(AiContextPackage context) {
    final lines = <String>[
      for (final entry in context.periodEntries.take(12))
        [
          formatAiSourceId('period_entry', entry.id),
          entry.date.toIso8601String().split('T').first,
          entry.title ?? entry.excerpt,
        ].join(' | '),
      for (final summary in context.periodSummaries.take(12))
        [
          formatAiSourceId('entry_summary', summary.entryId),
          summary.date.toIso8601String().split('T').first,
          if (summary.title.isNotEmpty) summary.title else summary.brief,
          if (summary.brief.isNotEmpty) 'brief=${_compact(summary.brief)}',
          if (summary.topics.isNotEmpty)
            'topics=${summary.topics.take(4).join('、')}',
          'importance=${summary.importance.toStringAsFixed(2)}',
        ].join(' | '),
      for (final result in context.relatedMemories.take(8))
        [
          formatAiSourceId('memory', result.memory.id),
          result.memory.summary,
          'score=${result.score}',
          if (result.reasons.isNotEmpty)
            'reasons=${result.reasons.take(3).join('；')}',
          if (result.rerankSignals.isNotEmpty)
            'signals=${_signalLine(result.rerankSignals)}',
        ].join(' | '),
      for (final fact in context.profileFacts.take(6))
        [
          formatAiSourceId('profile', fact.id),
          '${fact.field}=${fact.value}',
          'confidence=${fact.confidence.toStringAsFixed(2)}',
        ].join(' | '),
      for (final relationship in context.relationshipProfiles.take(6))
        [
          formatAiSourceId('relationship', relationship.personName),
          if (relationship.relationship?.isNotEmpty ?? false)
            relationship.relationship,
          if (relationship.patterns.isNotEmpty)
            relationship.patterns.take(2).join('；'),
          'confidence=${relationship.confidence.toStringAsFixed(2)}',
        ].join(' | '),
      for (final task in context.stoneTasks.take(6))
        [
          formatAiSourceId('stone', task.id),
          task.title,
          task.status.name,
        ].join(' | '),
    ];
    return _uniqueTake(lines, limit: 32).toList(growable: false);
  }

  Future<List<String>> _stoneHighlights(DateTime start, DateTime end) async {
    final tasks = await _stoneTaskRepository.listTasks();
    final created = <StoneTask>[];
    final completed = <StoneTask>[];
    final checkIns = <StoneTaskCheckIn>[];
    for (final task in tasks) {
      if (_within(task.createdAt, start, end)) created.add(task);
      final completedAt = task.completedAt;
      if (completedAt != null && _within(completedAt, start, end)) {
        completed.add(task);
      }
      checkIns.addAll(
        task.checkIns.where((item) => _within(item.createdAt, start, end)),
      );
    }
    final lines = <String>[
      if (created.isNotEmpty) '收藏成长线索 ${created.length} 条',
      if (checkIns.isNotEmpty) '记录微小变化 ${checkIns.length} 次',
      if (completed.isNotEmpty) '标记已有变化 ${completed.length} 条',
      for (final task in completed.take(3)) '完成：${task.title}',
      if (completed.isEmpty)
        for (final task in created.take(3)) '进行中：${task.title}',
    ];
    return lines;
  }

  bool _within(DateTime date, DateTime start, DateTime end) {
    return !date.isBefore(start) && !date.isAfter(end);
  }

  Iterable<String> _uniqueTake(List<String> values,
      {required int limit}) sync* {
    final seen = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) continue;
      seen.add(trimmed);
      yield trimmed;
      if (seen.length >= limit) return;
    }
  }

  List<String> _topKeys(Map<String, int> values, int limit) {
    final entries = values.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return entries.map((entry) => entry.key).take(limit).toList();
  }

  String _signalLine(Map<String, double> signals) {
    return signals.entries
        .map((entry) => '${entry.key}:${entry.value.toStringAsFixed(2)}')
        .join(',');
  }

  String _compact(String value, {int maxLength = 80}) {
    final compacted = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compacted.length <= maxLength) return compacted;
    return '${compacted.substring(0, maxLength)}...';
  }
}
