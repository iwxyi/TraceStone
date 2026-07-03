import 'ai_retrieval_trace.dart';
import 'ai_profile.dart';
import 'diary_entry.dart';
import 'diary_segment.dart';
import 'entry_summary.dart';
import 'memory_retrieval_result.dart';
import 'stone_task.dart';

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
    this.calendarMatches = const [],
    this.searchMatches = const [],
    this.relatedMemories = const [],
    this.profileFacts = const [],
    this.relationshipProfiles = const [],
    this.stoneTasks = const [],
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
  final List<AiCalendarMatch> calendarMatches;
  final List<AiSearchMatch> searchMatches;
  final List<MemoryRetrievalResult> relatedMemories;
  final List<ProfileFact> profileFacts;
  final List<RelationshipProfile> relationshipProfiles;
  final List<StoneTask> stoneTasks;
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
      calendarMatches.length +
      searchMatches.length +
      relatedMemories.length +
      profileFacts.length +
      relationshipProfiles.length +
      stoneTasks.length;

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
      if (calendarMatches.isNotEmpty) 'calendar=${calendarMatches.length}',
      if (searchMatches.isNotEmpty) 'search=${searchMatches.length}',
      if (profileFacts.isNotEmpty) 'profile=${profileFacts.length}',
      if (relationshipProfiles.isNotEmpty)
        'relationships=${relationshipProfiles.length}',
      if (stoneTasks.isNotEmpty) 'stone=${stoneTasks.length}',
    ];
    return parts.join(' ');
  }
}

class AiCalendarMatch {
  const AiCalendarMatch({
    required this.entry,
    required this.reason,
    required this.score,
    required this.dayOffset,
    this.label,
    this.calendarType = 'solar',
  });

  final DiaryEntry entry;
  final String reason;
  final int score;
  final int dayOffset;
  final String? label;
  final String calendarType;
}

class AiSearchMatch {
  const AiSearchMatch({
    required this.sourceType,
    required this.sourceId,
    required this.entryId,
    required this.title,
    required this.summary,
    required this.score,
    required this.reasons,
    required this.matchedTokens,
    this.rerankSignals = const {},
  });

  final String sourceType;
  final String sourceId;
  final String entryId;
  final String title;
  final String summary;
  final int score;
  final List<String> reasons;
  final List<String> matchedTokens;
  final Map<String, double> rerankSignals;
}
