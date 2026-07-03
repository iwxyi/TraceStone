import '../models/ai_profile.dart';
import '../models/ai_context_package.dart';
import '../models/calendar_memory.dart';
import '../models/ai_retrieval_trace.dart';
import '../models/diary_entry.dart';
import '../models/entry_summary.dart';
import '../models/memory_retrieval_result.dart';
import '../models/stone_task.dart';
import '../repositories/ai_retrieval_trace_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/memory_repository.dart';
import '../repositories/ai_profile_preference_repository.dart';
import '../repositories/stone_task_repository.dart';
import '../repositories/calendar_memory_repository.dart';
import 'profile_projection_service.dart';
import 'ai_search_service.dart';

class AiContextBuilder {
  const AiContextBuilder({
    DiaryRepository? diaryRepository,
    EntrySummaryRepository? summaryRepository,
    MemoryRepository? memoryRepository,
    InsightRepository? insightRepository,
    StoneTaskRepository? stoneTaskRepository,
    CalendarMemoryRepository? calendarMemoryRepository,
    AiProfilePreferenceRepository? profilePreferenceRepository,
    ProfileProjectionService? profileProjectionService,
    AiSearchService? searchService,
    AiRetrievalTraceRepository? retrievalTraceRepository,
  })  : _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _summaryRepository =
            summaryRepository ?? const EntrySummaryRepository(),
        _memoryRepository = memoryRepository ?? const MemoryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _stoneTaskRepository =
            stoneTaskRepository ?? const StoneTaskRepository(),
        _calendarMemoryRepository =
            calendarMemoryRepository ?? const CalendarMemoryRepository(),
        _profilePreferenceRepository = profilePreferenceRepository ??
            const AiProfilePreferenceRepository(),
        _profileProjectionService =
            profileProjectionService ?? const ProfileProjectionService(),
        _searchService = searchService ?? const AiSearchService(),
        _retrievalTraceRepository =
            retrievalTraceRepository ?? const AiRetrievalTraceRepository();

  final DiaryRepository _diaryRepository;
  final EntrySummaryRepository _summaryRepository;
  final MemoryRepository _memoryRepository;
  final InsightRepository _insightRepository;
  final StoneTaskRepository _stoneTaskRepository;
  final CalendarMemoryRepository _calendarMemoryRepository;
  final AiProfilePreferenceRepository _profilePreferenceRepository;
  final ProfileProjectionService _profileProjectionService;
  final AiSearchService _searchService;
  final AiRetrievalTraceRepository _retrievalTraceRepository;

  static const _todayMemoryLimit = 8;
  static const _profileFactLimit = 5;

  Future<AiContextPackage> buildForTodayInsight(DiaryEntry entry) async {
    final recentEntries = await _recentEntries(entry);
    final recentSummaries = await _recentSummaries(recentEntries);
    final summary = await _summaryRepository.getSummary(entry.id);
    final segments = await _summaryRepository.listSegments(entry.id);
    final relatedMemories = await _memoryRepository.findRelatedWithReasons(
      entry: entry,
      limit: _todayMemoryLimit,
    );
    final calendarMatches = await _calendarMatches(entry);
    final projection = await _profileProjection();
    final profileFacts = _topProfileFacts(projection.profileFacts);
    final relationshipProfiles = _relatedRelationshipProfiles(
      projection.relationshipProfiles,
      entry.content,
    );
    final stoneTasks = await _activeStoneTasks();
    final package = AiContextPackage(
      scenario: AiContextScenario.todayInsight,
      currentEntry: entry,
      currentSummary: summary,
      currentSegments: segments,
      recentEntries: recentEntries,
      recentSummaries: recentSummaries,
      calendarMatches: calendarMatches,
      relatedMemories: relatedMemories,
      profileFacts: profileFacts,
      relationshipProfiles: relationshipProfiles,
      stoneTasks: stoneTasks,
    );
    final trace = _traceFromResults(
      entry.id,
      relatedMemories,
      calendarMatches: calendarMatches,
      profileFacts: profileFacts,
      relationshipProfiles: relationshipProfiles,
      stoneTasks: stoneTasks,
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
      recentSummaries: package.recentSummaries,
      calendarMatches: package.calendarMatches,
      relatedMemories: package.relatedMemories,
      profileFacts: package.profileFacts,
      relationshipProfiles: package.relationshipProfiles,
      stoneTasks: package.stoneTasks,
      retrievalTrace: trace,
    );
  }

  Future<AiContextPackage> buildForSearch(String query) async {
    return _buildForQuery(
      query,
      scenario: AiContextScenario.search,
      traceId: 'search:last',
    );
  }

  Future<AiContextPackage> buildForQuestion(String question) async {
    return _buildForQuery(
      question,
      scenario: AiContextScenario.question,
      traceId: 'question:last',
    );
  }

  Future<AiContextPackage> _buildForQuery(
    String query, {
    required AiContextScenario scenario,
    required String traceId,
  }) async {
    final now = DateTime.now();
    final entry = DiaryEntry(
      id: traceId,
      date: now,
      createdAt: now,
      content: query,
      location: '',
      weather: '',
      temperature: null,
      updatedAt: now,
    );
    final relatedMemories =
        await _memoryRepository.findRelatedWithReasons(entry: entry, limit: 12);
    final searchMatches = await _searchService.search(query);
    final searchMemoryIds = searchMatches
        .where((match) => match.sourceType == 'memory')
        .map((match) => match.sourceId)
        .toSet();
    final dedupedRelatedMemories = relatedMemories
        .where((result) => !searchMemoryIds.contains(result.memory.id))
        .toList(growable: false);
    final projection = await _profileProjection();
    final profileFacts =
        _topProfileFacts(_matchingProfileFacts(projection.profileFacts, query));
    final relationshipProfiles = _relatedRelationshipProfiles(
      projection.relationshipProfiles,
      query,
    );
    final stoneTasks = await _matchingStoneTasks(query);
    final package = AiContextPackage(
      scenario: scenario,
      query: query,
      searchMatches: searchMatches,
      relatedMemories: dedupedRelatedMemories,
      profileFacts: profileFacts,
      relationshipProfiles: relationshipProfiles,
      stoneTasks: stoneTasks,
    );
    final trace = _traceFromResults(
      traceId,
      dedupedRelatedMemories,
      searchMatches: searchMatches,
      profileFacts: profileFacts,
      relationshipProfiles: relationshipProfiles,
      stoneTasks: stoneTasks,
      scenario: package.scenario.name,
      contextSummary: package.debugSummary,
      sourceCount: package.sourceCount,
    );
    await _retrievalTraceRepository.saveTrace(trace);
    return AiContextPackage(
      scenario: package.scenario,
      query: package.query,
      searchMatches: package.searchMatches,
      relatedMemories: package.relatedMemories,
      profileFacts: package.profileFacts,
      relationshipProfiles: package.relationshipProfiles,
      stoneTasks: package.stoneTasks,
      retrievalTrace: trace,
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
    summaries.sort((a, b) {
      final byImportance = b.importance.compareTo(a.importance);
      if (byImportance != 0) return byImportance;
      return b.date.compareTo(a.date);
    });
    final contextSummaries = summaries.take(48).toList(growable: false);
    final queryText = [
      for (final summary in contextSummaries) ...[
        if (summary.title.isNotEmpty) summary.title,
        summary.brief,
        ...summary.keyPoints,
        ...summary.topics,
        if (summary.emotion.isNotEmpty) summary.emotion,
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
    final projection = await _profileProjection();
    final profileFacts = _topProfileFacts(projection.profileFacts);
    final relationshipProfiles =
        projection.relationshipProfiles.take(5).toList(growable: false);
    final stoneTasks = await _activeStoneTasks(limit: 8);
    final package = AiContextPackage(
      scenario: AiContextScenario.periodSummary,
      periodStart: start,
      periodEnd: end,
      periodEntries: periodEntries,
      periodSummaries: contextSummaries,
      relatedMemories: relatedMemories,
      profileFacts: profileFacts,
      relationshipProfiles: relationshipProfiles,
      stoneTasks: stoneTasks,
    );
    final traceId =
        'period:${start.toIso8601String()}:${end.toIso8601String()}';
    final trace = _traceFromResults(
      traceId,
      relatedMemories,
      profileFacts: profileFacts,
      relationshipProfiles: relationshipProfiles,
      stoneTasks: stoneTasks,
      scenario: package.scenario.name,
      contextSummary: package.debugSummary,
      sourceCount: package.sourceCount,
    );
    await _retrievalTraceRepository.saveTrace(trace);
    await _retrievalTraceRepository.saveTrace(
      _traceWithEntryId(trace, 'period:last'),
    );
    return AiContextPackage(
      scenario: package.scenario,
      periodStart: package.periodStart,
      periodEnd: package.periodEnd,
      periodEntries: package.periodEntries,
      periodSummaries: package.periodSummaries,
      relatedMemories: package.relatedMemories,
      profileFacts: package.profileFacts,
      relationshipProfiles: package.relationshipProfiles,
      stoneTasks: package.stoneTasks,
      retrievalTrace: trace,
    );
  }

  Future<ProfileProjection> _profileProjection() async {
    final insights = await _insightRepository.listInsights();
    final projection = _profileProjectionService.build(insights);
    return ProfileProjection(
      profileFacts: await _profilePreferenceRepository.applyToProfileFacts(
        projection.profileFacts,
      ),
      relationshipProfiles:
          await _profilePreferenceRepository.applyToRelationshipProfiles(
        projection.relationshipProfiles,
      ),
    );
  }

  List<ProfileFact> _topProfileFacts(List<ProfileFact> facts) {
    return facts
        .where((fact) =>
            fact.status != ProfileFactStatus.weak || fact.userConfirmed)
        .take(_profileFactLimit)
        .toList(growable: false);
  }

  List<ProfileFact> _matchingProfileFacts(
    List<ProfileFact> facts,
    String query,
  ) {
    final queryTokens = _tokens(query);
    if (queryTokens.isEmpty) return facts;
    return facts.where((fact) {
      final textTokens = _tokens('${fact.field} ${fact.value}');
      return queryTokens.any(textTokens.contains);
    }).toList(growable: false);
  }

  List<RelationshipProfile> _relatedRelationshipProfiles(
    List<RelationshipProfile> profiles,
    String text,
  ) {
    final tokens = _tokens(text);
    final matched = profiles.where((profile) {
      final nameMatches =
          profile.names.any((name) => name.isNotEmpty && text.contains(name));
      if (nameMatches) return true;
      final profileTokens = _tokens([
        profile.personName,
        profile.relationship ?? '',
        ...profile.patterns,
        ...profile.emotions,
      ].join(' '));
      return tokens.any(profileTokens.contains);
    }).toList();
    if (matched.isEmpty) {
      return profiles.take(3).toList(growable: false);
    }
    return matched.take(5).toList(growable: false);
  }

  Future<List<StoneTask>> _activeStoneTasks({int limit = 5}) async {
    final tasks = await _stoneTaskRepository.listTasks();
    return tasks
        .where((task) => task.status == StoneTaskStatus.active)
        .take(limit)
        .toList(growable: false);
  }

  Future<List<StoneTask>> _matchingStoneTasks(String query) async {
    final tasks = await _stoneTaskRepository.listTasks();
    final queryTokens = _tokens(query);
    if (queryTokens.isEmpty) return _activeStoneTasks();
    final matches = tasks.where((task) {
      final tokens = _tokens('${task.title} ${task.description}');
      return queryTokens.any(tokens.contains);
    }).toList();
    if (matches.isEmpty) return _activeStoneTasks(limit: 3);
    return matches.take(5).toList(growable: false);
  }

  Future<List<DiaryEntry>> _recentEntries(DiaryEntry entry) async {
    final entries = await _diaryRepository.listEntries();
    return entries
        .where((item) => item.id != entry.id)
        .take(5)
        .toList(growable: false);
  }

  Future<List<EntrySummary>> _recentSummaries(List<DiaryEntry> entries) async {
    final summaries = <EntrySummary>[];
    for (final entry in entries) {
      final summary = await _summaryRepository.getSummary(entry.id);
      if (summary != null) summaries.add(summary);
    }
    return summaries;
  }

  Future<List<AiCalendarMatch>> _calendarMatches(DiaryEntry entry) async {
    final entries = await _diaryRepository.listEntries();
    final calendarMemories = await _calendarMemoryRepository.listMemories();
    final matches = <AiCalendarMatch>[];
    final currentFestival = _fixedSolarFestival(entry.date);
    final currentMemory = _matchingCalendarMemory(entry.date, calendarMemories);
    for (final item in entries) {
      if (item.id == entry.id) continue;
      if (!item.date.isBefore(entry.date)) continue;
      final yearDistance = entry.date.year - item.date.year;
      if (yearDistance <= 0) continue;
      final dayOffset = _dayOffsetFromMonthDay(
        item.date,
        month: entry.date.month,
        day: entry.date.day,
      );
      final absoluteOffset = dayOffset?.abs();
      final itemFestival = _fixedSolarFestival(item.date);
      final sameFestival =
          currentFestival != null && currentFestival == itemFestival;
      final itemMemory = _matchingCalendarMemory(item.date, calendarMemories);
      final sameMemory = currentMemory != null &&
          itemMemory != null &&
          currentMemory.memory.id == itemMemory.memory.id;
      final festivalNearby = currentFestival != null &&
          dayOffset != null &&
          absoluteOffset != null &&
          absoluteOffset <= 1;
      final solarTodayNearby =
          dayOffset != null && absoluteOffset != null && absoluteOffset <= 1;
      if (!sameMemory &&
          !sameFestival &&
          !festivalNearby &&
          !solarTodayNearby) {
        continue;
      }
      final label = sameMemory
          ? currentMemory.memory.title
          : sameFestival
              ? currentFestival
              : festivalNearby
                  ? currentFestival
                  : null;
      final effectiveOffset = sameMemory
          ? itemMemory.dayOffset
          : dayOffset ?? item.date.difference(entry.date).inDays;
      final absoluteEffectiveOffset = effectiveOffset.abs();
      final calendarType = sameMemory
          ? currentMemory.memory.type.name
          : festivalNearby || sameFestival
              ? 'solar_festival'
              : null;
      final reason = _calendarReason(
        yearDistance: yearDistance,
        dayOffset: effectiveOffset,
        festival: label,
      );
      final summary = await _summaryRepository.getSummary(item.id);
      matches.add(AiCalendarMatch(
        entry: item,
        reason: reason,
        score: sameMemory
            ? 11
            : sameFestival
                ? 10
                : festivalNearby
                    ? 9
                    : absoluteEffectiveOffset == 0
                        ? 8
                        : 5,
        dayOffset: effectiveOffset,
        label: label,
        calendarType: calendarType ?? 'solar',
        summary: summary,
      ));
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byOffset = a.dayOffset.abs().compareTo(b.dayOffset.abs());
      if (byOffset != 0) return byOffset;
      return b.entry.date.compareTo(a.entry.date);
    });
    return matches.take(8).toList(growable: false);
  }

  _CalendarMemoryMatch? _matchingCalendarMemory(
    DateTime date,
    List<CalendarMemory> memories,
  ) {
    const anniversaryWindowDays = 3;
    for (final memory in memories) {
      if (!memory.enabled || memory.type != CalendarMemoryType.solar) continue;
      final dayOffset = _dayOffsetFromMonthDay(
        date,
        month: memory.month,
        day: memory.day,
      );
      if (dayOffset == null) continue;
      if (dayOffset.abs() <= anniversaryWindowDays) {
        return _CalendarMemoryMatch(memory: memory, dayOffset: dayOffset);
      }
    }
    return null;
  }

  int? _dayOffsetFromMonthDay(
    DateTime date, {
    required int month,
    required int day,
  }) {
    final anchor = DateTime(date.year, month, day);
    if (anchor.month != month || anchor.day != day) return null;
    return date.difference(anchor).inDays;
  }

  String _calendarReason({
    required int yearDistance,
    required int dayOffset,
    String? festival,
  }) {
    final offset = dayOffset.abs();
    if (festival != null && offset == 0) {
      return '$yearDistance 年前的$festival';
    }
    if (festival != null) {
      return '$yearDistance 年前$festival附近（${dayOffset > 0 ? '+' : ''}$dayOffset 天）';
    }
    return offset == 0
        ? '$yearDistance 年前的今天'
        : '$yearDistance 年前今日附近（${dayOffset > 0 ? '+' : ''}$dayOffset 天）';
  }

  String? _fixedSolarFestival(DateTime date) {
    const festivals = {
      '1-1': '元旦',
      '2-14': '情人节',
      '3-8': '妇女节',
      '5-1': '劳动节',
      '6-1': '儿童节',
      '9-10': '教师节',
      '10-1': '国庆节',
      '12-24': '平安夜',
      '12-25': '圣诞节',
      '12-31': '跨年',
    };
    return festivals['${date.month}-${date.day}'];
  }

  Set<String> _tokens(String text) {
    final cleaned = text
        .replaceAll(
            RegExp(r'[\s\n\r\t，。！？；：、“”‘’（）《》【】,.!?;:#>*_`\[\](){}/\\-]+'), ' ')
        .trim();
    final tokens = <String>{};
    for (final part in cleaned.split(' ')) {
      final value = part.trim();
      if (value.length >= 2) tokens.add(value);
      if (value.length >= 4) {
        for (var i = 0; i <= value.length - 2; i++) {
          tokens.add(value.substring(i, i + 2));
        }
      }
    }
    return tokens;
  }

  AiRetrievalTrace _traceFromResults(
    String entryId,
    List<MemoryRetrievalResult> results, {
    List<AiCalendarMatch> calendarMatches = const [],
    List<AiSearchMatch> searchMatches = const [],
    List<ProfileFact> profileFacts = const [],
    List<RelationshipProfile> relationshipProfiles = const [],
    List<StoneTask> stoneTasks = const [],
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
            rerankSignals: result.rerankSignals,
          ),
        for (final match in calendarMatches)
          AiRetrievalTraceItem(
            sourceType: 'calendar',
            sourceId: match.entry.id,
            title: match.reason,
            summary: match.contextSummary,
            score: match.score,
            reasons: [
              match.reason,
              if (match.label != null) '阳历节日：${match.label}',
              if (match.summary != null) '使用历史摘要包',
            ],
            matchedTokens: [
              if (match.label != null) match.label!,
            ],
          ),
        for (final match in searchMatches)
          AiRetrievalTraceItem(
            sourceType: match.sourceType,
            sourceId: match.sourceId,
            title: match.title,
            summary: match.summary,
            score: match.score,
            reasons: match.reasons,
            matchedTokens: match.matchedTokens,
            rerankSignals: match.rerankSignals,
          ),
        for (final fact in profileFacts)
          AiRetrievalTraceItem(
            sourceType: 'profile',
            sourceId: fact.id,
            title: fact.field,
            summary: fact.value,
            score: _profileStatusScore(fact.status),
            reasons: [
              '${fact.evidenceCount} 条证据',
              '${fact.distinctDays} 天',
              '置信度 ${fact.confidence.toStringAsFixed(2)}',
              if (fact.userConfirmed) '用户确认',
            ],
            matchedTokens: const [],
            rerankSignals: _profileFactSignals(fact),
          ),
        for (final profile in relationshipProfiles)
          AiRetrievalTraceItem(
            sourceType: 'relationship',
            sourceId: profile.personName,
            title: profile.personName,
            summary: [
              if (profile.relationship?.isNotEmpty ?? false)
                profile.relationship,
              ...profile.patterns.take(2),
            ].whereType<String>().join('；'),
            score: _profileStatusScore(profile.status),
            reasons: [
              '${profile.interactionCount} 次互动',
              '${profile.distinctDays} 天',
              '置信度 ${profile.confidence.toStringAsFixed(2)}',
              if (profile.userConfirmed) '用户确认',
            ],
            matchedTokens: const [],
            rerankSignals: _relationshipSignals(profile),
          ),
        for (final task in stoneTasks)
          AiRetrievalTraceItem(
            sourceType: 'stone',
            sourceId: task.id,
            title: task.title,
            summary: task.description,
            score: task.status == StoneTaskStatus.active ? 6 : 3,
            reasons: [
              task.status == StoneTaskStatus.active ? '进行中的塑石行动' : '历史塑石行动',
            ],
            matchedTokens: task.tags,
          ),
      ],
    );
  }

  AiRetrievalTrace _traceWithEntryId(AiRetrievalTrace trace, String entryId) {
    return AiRetrievalTrace(
      entryId: entryId,
      generatedAt: trace.generatedAt,
      items: trace.items,
      scenario: trace.scenario,
      contextSummary: trace.contextSummary,
      sourceCount: trace.sourceCount,
    );
  }

  int _profileStatusScore(ProfileFactStatus status) {
    switch (status) {
      case ProfileFactStatus.stable:
        return 8;
      case ProfileFactStatus.emerging:
        return 5;
      case ProfileFactStatus.weak:
        return 2;
    }
  }

  Map<String, double> _profileFactSignals(ProfileFact fact) {
    return {
      'status': _profileStatusScore(fact.status).toDouble(),
      'confidence': fact.confidence,
      'evidence': fact.evidenceCount.clamp(0, 6).toDouble(),
      'days': fact.distinctDays.clamp(0, 6).toDouble(),
      if (fact.userConfirmed) 'userConfirmed': 1,
    };
  }

  Map<String, double> _relationshipSignals(RelationshipProfile profile) {
    return {
      'status': _profileStatusScore(profile.status).toDouble(),
      'confidence': profile.confidence,
      'evidence': profile.interactionCount.clamp(0, 6).toDouble(),
      'days': profile.distinctDays.clamp(0, 6).toDouble(),
      if (profile.userConfirmed) 'userConfirmed': 1,
    };
  }
}

class _CalendarMemoryMatch {
  const _CalendarMemoryMatch({
    required this.memory,
    required this.dayOffset,
  });

  final CalendarMemory memory;
  final int dayOffset;
}
