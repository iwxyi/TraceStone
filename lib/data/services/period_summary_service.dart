import '../models/ai_context_package.dart';
import '../models/diary_entry.dart';
import '../models/period_summary.dart';
import '../models/stone_task.dart';
import '../repositories/insight_repository.dart';
import '../repositories/period_summary_repository.dart';
import '../repositories/stone_task_repository.dart';
import 'ai_context_builder.dart';
import 'entry_summary_service.dart';

class PeriodSummaryService {
  const PeriodSummaryService({
    AiContextBuilder? contextBuilder,
    InsightRepository? insightRepository,
    PeriodSummaryRepository? periodSummaryRepository,
    StoneTaskRepository? stoneTaskRepository,
    EntrySummaryService? entrySummaryService,
  })  : _contextBuilder = contextBuilder ?? const AiContextBuilder(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _periodSummaryRepository =
            periodSummaryRepository ?? const PeriodSummaryRepository(),
        _stoneTaskRepository =
            stoneTaskRepository ?? const StoneTaskRepository(),
        _entrySummaryService =
            entrySummaryService ?? const EntrySummaryService();

  final AiContextBuilder _contextBuilder;
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
      contextEntryIds: context.periodEntries.map((entry) => entry.id).toSet(),
      contextThemes: context.periodSummaries
          .expand((summary) => summary.topics)
          .toList(growable: false),
      contextDebugSummary: context.debugSummary,
      contextSourceLines: _periodContextSourceLines(context),
      visibleRelationshipNames: context.relationshipProfiles
          .map((profile) => profile.personName)
          .toSet(),
      relatedMemoryThemes: context.relatedMemories
          .expand((result) => [
                ...result.memory.tags,
                ...result.memory.keywords,
              ])
          .toList(growable: false),
    );
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
      contextEntryIds: context.periodEntries.map((entry) => entry.id).toSet(),
      contextThemes: context.periodSummaries
          .expand((summary) => summary.topics)
          .toList(growable: false),
      contextDebugSummary: context.debugSummary,
      contextSourceLines: _periodContextSourceLines(context),
      visibleRelationshipNames: context.relationshipProfiles
          .map((profile) => profile.personName)
          .toSet(),
      relatedMemoryThemes: context.relatedMemories
          .expand((result) => [
                ...result.memory.tags,
                ...result.memory.keywords,
              ])
          .toList(growable: false),
    );
  }

  Future<PeriodSummary> _build({
    required String id,
    required PeriodSummaryType type,
    required DateTime start,
    required DateTime end,
    required List<DiaryEntry> entries,
    required Set<String> contextEntryIds,
    required List<String> contextThemes,
    required String contextDebugSummary,
    required List<String> contextSourceLines,
    required Set<String> visibleRelationshipNames,
    required List<String> relatedMemoryThemes,
  }) async {
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
      generator: 'local-aggregate-v1',
      relationshipHighlights:
          _uniqueTake(relationshipHighlights, limit: 5).toList(),
      stoneHighlights: stoneHighlights,
      contextDebugSummary: contextDebugSummary,
      contextSourceLines: contextSourceLines,
    );
    await _periodSummaryRepository.saveSummary(summary);
    return summary;
  }

  List<String> _periodContextSourceLines(AiContextPackage context) {
    final lines = <String>[
      for (final entry in context.periodEntries.take(12))
        [
          'period_entry:${entry.id}',
          entry.date.toIso8601String().split('T').first,
          entry.title ?? entry.excerpt,
        ].join(' | '),
      for (final summary in context.periodSummaries.take(12))
        [
          'entry_summary:${summary.entryId}',
          summary.date.toIso8601String().split('T').first,
          if (summary.title.isNotEmpty) summary.title else summary.brief,
          if (summary.topics.isNotEmpty)
            'topics=${summary.topics.take(4).join('、')}',
          'importance=${summary.importance.toStringAsFixed(2)}',
        ].join(' | '),
      for (final result in context.relatedMemories.take(8))
        [
          'memory:${result.memory.id}',
          result.memory.summary,
          'score=${result.score}',
          if (result.reasons.isNotEmpty)
            'reasons=${result.reasons.take(3).join('；')}',
          if (result.rerankSignals.isNotEmpty)
            'signals=${_signalLine(result.rerankSignals)}',
        ].join(' | '),
      for (final fact in context.profileFacts.take(6))
        [
          'profile:${fact.id}',
          '${fact.field}=${fact.value}',
          'confidence=${fact.confidence.toStringAsFixed(2)}',
        ].join(' | '),
      for (final relationship in context.relationshipProfiles.take(6))
        [
          'relationship:${relationship.personName}',
          if (relationship.relationship?.isNotEmpty ?? false)
            relationship.relationship,
          if (relationship.patterns.isNotEmpty)
            relationship.patterns.take(2).join('；'),
          'confidence=${relationship.confidence.toStringAsFixed(2)}',
        ].join(' | '),
      for (final task in context.stoneTasks.take(6))
        [
          'stone:${task.id}',
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
      if (created.isNotEmpty) '新增塑石行动 ${created.length} 个',
      if (checkIns.isNotEmpty) '记录塑石进展 ${checkIns.length} 次',
      if (completed.isNotEmpty) '完成塑石行动 ${completed.length} 个',
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
}
