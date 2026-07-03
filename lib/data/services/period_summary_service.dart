import '../models/diary_entry.dart';
import '../models/period_summary.dart';
import '../repositories/insight_repository.dart';
import '../repositories/period_summary_repository.dart';
import 'ai_context_builder.dart';

class PeriodSummaryService {
  const PeriodSummaryService({
    AiContextBuilder? contextBuilder,
    InsightRepository? insightRepository,
    PeriodSummaryRepository? periodSummaryRepository,
  })  : _contextBuilder = contextBuilder ?? const AiContextBuilder(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _periodSummaryRepository =
            periodSummaryRepository ?? const PeriodSummaryRepository();

  final AiContextBuilder _contextBuilder;
  final InsightRepository _insightRepository;
  final PeriodSummaryRepository _periodSummaryRepository;

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
    required List<String> relatedMemoryThemes,
  }) async {
    final themes = <String, int>{};
    final emotions = <String, int>{};
    final briefs = <String>[];
    final representativeIds = <String>[];

    for (final theme in contextThemes) {
      themes[theme] = (themes[theme] ?? 0) + 2;
    }
    for (final theme in relatedMemoryThemes) {
      themes[theme] = (themes[theme] ?? 0) + 1;
    }

    for (final entry in entries) {
      final insight = await _insightRepository.getInsight(entry.id);
      briefs.add(entry.excerpt);
      if (insight != null) {
        if (insight.emotion.isNotEmpty) {
          emotions[insight.emotion] = (emotions[insight.emotion] ?? 0) + 1;
        }
        for (final keyword in insight.keywords) {
          themes[keyword] = (themes[keyword] ?? 0) + 1;
        }
      }
    }

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
    );
    await _periodSummaryRepository.saveSummary(summary);
    return summary;
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
}
