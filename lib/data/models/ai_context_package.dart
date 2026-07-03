import 'ai_retrieval_trace.dart';
import 'diary_entry.dart';
import 'diary_segment.dart';
import 'entry_summary.dart';
import 'memory_retrieval_result.dart';

enum AiContextScenario { todayInsight, question, search, periodSummary }

class AiContextPackage {
  const AiContextPackage({
    required this.scenario,
    this.currentEntry,
    this.currentSummary,
    this.currentSegments = const [],
    this.periodEntries = const [],
    this.periodSummaries = const [],
    this.recentEntries = const [],
    this.relatedMemories = const [],
    this.retrievalTrace,
    this.query,
    this.periodStart,
    this.periodEnd,
  });

  final AiContextScenario scenario;
  final DiaryEntry? currentEntry;
  final EntrySummary? currentSummary;
  final List<DiarySegment> currentSegments;
  final List<DiaryEntry> periodEntries;
  final List<EntrySummary> periodSummaries;
  final List<DiaryEntry> recentEntries;
  final List<MemoryRetrievalResult> relatedMemories;
  final AiRetrievalTrace? retrievalTrace;
  final String? query;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  int get sourceCount =>
      (currentEntry == null ? 0 : 1) +
      (currentSummary == null ? 0 : 1) +
      currentSegments.length +
      periodEntries.length +
      periodSummaries.length +
      recentEntries.length +
      relatedMemories.length;

  String get debugSummary {
    final parts = [
      scenario.name,
      'sources=$sourceCount',
      if (currentSegments.isNotEmpty) 'segments=${currentSegments.length}',
      if (periodEntries.isNotEmpty) 'periodEntries=${periodEntries.length}',
      if (periodSummaries.isNotEmpty)
        'periodSummaries=${periodSummaries.length}',
      if (relatedMemories.isNotEmpty) 'memories=${relatedMemories.length}',
      if (recentEntries.isNotEmpty) 'recent=${recentEntries.length}',
    ];
    return parts.join(' ');
  }
}
