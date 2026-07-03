import '../models/ai_context_package.dart';
import '../models/ai_retrieval_trace.dart';
import '../models/diary_entry.dart';
import '../models/entry_summary.dart';
import '../models/memory_retrieval_result.dart';
import '../repositories/ai_retrieval_trace_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import '../repositories/memory_repository.dart';

class AiContextBuilder {
  const AiContextBuilder({
    DiaryRepository? diaryRepository,
    EntrySummaryRepository? summaryRepository,
    MemoryRepository? memoryRepository,
    AiRetrievalTraceRepository? retrievalTraceRepository,
  })  : _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _summaryRepository =
            summaryRepository ?? const EntrySummaryRepository(),
        _memoryRepository = memoryRepository ?? const MemoryRepository(),
        _retrievalTraceRepository =
            retrievalTraceRepository ?? const AiRetrievalTraceRepository();

  final DiaryRepository _diaryRepository;
  final EntrySummaryRepository _summaryRepository;
  final MemoryRepository _memoryRepository;
  final AiRetrievalTraceRepository _retrievalTraceRepository;

  Future<AiContextPackage> buildForTodayInsight(DiaryEntry entry) async {
    final recentEntries = await _recentEntries(entry);
    final summary = await _summaryRepository.getSummary(entry.id);
    final segments = await _summaryRepository.listSegments(entry.id);
    final relatedMemories =
        await _memoryRepository.findRelatedWithReasons(entry: entry);
    final package = AiContextPackage(
      scenario: AiContextScenario.todayInsight,
      currentEntry: entry,
      currentSummary: summary,
      currentSegments: segments,
      recentEntries: recentEntries,
      relatedMemories: relatedMemories,
    );
    final trace = _traceFromResults(
      entry.id,
      relatedMemories,
      scenario: package.scenario.name,
      contextSummary: package.debugSummary,
      sourceCount: package.sourceCount,
    );
    await _retrievalTraceRepository.saveTrace(trace);
    return AiContextPackage(
      scenario: package.scenario,
      currentEntry: package.currentEntry,
      currentSummary: package.currentSummary,
      currentSegments: package.currentSegments,
      recentEntries: package.recentEntries,
      relatedMemories: package.relatedMemories,
      retrievalTrace: trace,
    );
  }

  Future<AiContextPackage> buildForSearch(String query) async {
    final entry = DiaryEntry(
      id: 'search-query',
      date: DateTime.now(),
      createdAt: DateTime.now(),
      content: query,
      location: '',
      weather: '',
      temperature: null,
      updatedAt: DateTime.now(),
    );
    final relatedMemories =
        await _memoryRepository.findRelatedWithReasons(entry: entry, limit: 12);
    return AiContextPackage(
      scenario: AiContextScenario.search,
      query: query,
      relatedMemories: relatedMemories,
      retrievalTrace: _traceFromResults(
        'search-query',
        relatedMemories,
        scenario: AiContextScenario.search.name,
        sourceCount: relatedMemories.length,
      ),
    );
  }

  Future<AiContextPackage> buildForQuestion(String question) async {
    final package = await buildForSearch(question);
    return AiContextPackage(
      scenario: AiContextScenario.question,
      query: question,
      relatedMemories: package.relatedMemories,
      retrievalTrace: package.retrievalTrace,
    );
  }

  Future<AiContextPackage> buildForPeriodSummary({
    required DateTime start,
    required DateTime end,
  }) async {
    final allEntries = await _diaryRepository.listEntries();
    final periodEntries = allEntries
        .where(
            (entry) => !entry.date.isBefore(start) && !entry.date.isAfter(end))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final summaries = <EntrySummary>[];
    for (final entry in periodEntries) {
      final summary = await _summaryRepository.getSummary(entry.id);
      if (summary != null) summaries.add(summary);
    }
    final queryText = [
      for (final summary in summaries) ...[
        summary.brief,
        ...summary.keyPoints,
        ...summary.topics,
      ],
      if (summaries.isEmpty)
        for (final entry in periodEntries) entry.excerpt,
    ].join('\n');
    final queryEntry = DiaryEntry(
      id: 'period-summary-query',
      date: start,
      createdAt: DateTime.now(),
      content: queryText,
      location: '',
      weather: '',
      temperature: null,
      updatedAt: DateTime.now(),
    );
    final relatedMemories = queryText.trim().isEmpty
        ? <MemoryRetrievalResult>[]
        : await _memoryRepository.findRelatedWithReasons(
            entry: queryEntry,
            limit: 12,
          );
    final package = AiContextPackage(
      scenario: AiContextScenario.periodSummary,
      periodStart: start,
      periodEnd: end,
      periodEntries: periodEntries,
      periodSummaries: summaries,
      relatedMemories: relatedMemories,
    );
    final traceId =
        'period:${start.toIso8601String()}:${end.toIso8601String()}';
    final trace = _traceFromResults(
      traceId,
      relatedMemories,
      scenario: package.scenario.name,
      contextSummary: package.debugSummary,
      sourceCount: package.sourceCount,
    );
    await _retrievalTraceRepository.saveTrace(trace);
    return AiContextPackage(
      scenario: package.scenario,
      periodStart: package.periodStart,
      periodEnd: package.periodEnd,
      periodEntries: package.periodEntries,
      periodSummaries: package.periodSummaries,
      relatedMemories: package.relatedMemories,
      retrievalTrace: trace,
    );
  }

  Future<List<DiaryEntry>> _recentEntries(DiaryEntry entry) async {
    final entries = await _diaryRepository.listEntries();
    return entries
        .where((item) => item.id != entry.id)
        .take(5)
        .toList(growable: false);
  }

  AiRetrievalTrace _traceFromResults(
    String entryId,
    List<MemoryRetrievalResult> results, {
    String? scenario,
    String? contextSummary,
    int sourceCount = 0,
  }) {
    return AiRetrievalTrace(
      entryId: entryId,
      generatedAt: DateTime.now(),
      scenario: scenario,
      contextSummary: contextSummary,
      sourceCount: sourceCount,
      items: [
        for (final result in results)
          AiRetrievalTraceItem(
            sourceType: 'memory',
            sourceId: result.memory.id,
            title: result.memory.title,
            summary: result.memory.summary,
            score: result.score,
            reasons: result.reasons,
            matchedTokens: result.matchedTokens,
          ),
      ],
    );
  }
}
