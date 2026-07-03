import '../models/ai_context_package.dart';
import '../models/ai_embedding.dart';
import '../models/ai_profile.dart';
import '../models/diary_insight.dart';
import '../models/memory_entry.dart';
import '../models/stone_task.dart';
import '../repositories/ai_embedding_repository.dart';
import '../repositories/ai_profile_preference_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/memory_repository.dart';
import '../repositories/stone_task_repository.dart';
import 'embedding_service.dart';
import 'profile_projection_service.dart';

class AiSearchService {
  const AiSearchService({
    AiEmbeddingRepository? embeddingRepository,
    DiaryRepository? diaryRepository,
    EntrySummaryRepository? summaryRepository,
    MemoryRepository? memoryRepository,
    InsightRepository? insightRepository,
    AiProfilePreferenceRepository? profilePreferenceRepository,
    ProfileProjectionService? profileProjectionService,
    StoneTaskRepository? stoneTaskRepository,
    EmbeddingService? embeddingService,
  })  : _embeddingRepository =
            embeddingRepository ?? const AiEmbeddingRepository(),
        _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _summaryRepository =
            summaryRepository ?? const EntrySummaryRepository(),
        _memoryRepository = memoryRepository ?? const MemoryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _profilePreferenceRepository = profilePreferenceRepository ??
            const AiProfilePreferenceRepository(),
        _profileProjectionService =
            profileProjectionService ?? const ProfileProjectionService(),
        _stoneTaskRepository =
            stoneTaskRepository ?? const StoneTaskRepository(),
        _embeddingService = embeddingService ?? const EmbeddingService();

  final AiEmbeddingRepository _embeddingRepository;
  final DiaryRepository _diaryRepository;
  final EntrySummaryRepository _summaryRepository;
  final MemoryRepository _memoryRepository;
  final InsightRepository _insightRepository;
  final AiProfilePreferenceRepository _profilePreferenceRepository;
  final ProfileProjectionService _profileProjectionService;
  final StoneTaskRepository _stoneTaskRepository;
  final EmbeddingService _embeddingService;

  Future<List<AiSearchMatch>> search(String query, {int limit = 12}) async {
    final queryTokens = _tokens(query);
    if (queryTokens.isEmpty) return const [];
    final vectorMatches = await _vectorMatches(query, queryTokens);
    final keywordMatches = await _keywordMatches(queryTokens);
    final merged = <String, AiSearchMatch>{};
    for (final match in [...vectorMatches, ...keywordMatches]) {
      final key = '${match.sourceType}:${match.sourceId}';
      final previous = merged[key];
      if (previous == null || match.score > previous.score) {
        merged[key] = match;
      } else {
        merged[key] = _mergeReasons(previous, match);
      }
    }
    final matches = merged.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.title.compareTo(b.title);
      });
    return matches.take(limit).toList(growable: false);
  }

  Future<List<AiSearchMatch>> _vectorMatches(
    String query,
    Set<String> queryTokens,
  ) async {
    final AiEmbeddingResult queryEmbedding;
    final List<AiEmbedding> embeddings;
    try {
      queryEmbedding = _embeddingService.embed(query);
      final profileSources = await _profileSearchSources();
      final stoneSources = await _stoneSearchSources();
      await _ensureProfileEmbeddings(profileSources);
      await _ensureStoneEmbeddings(stoneSources);
      embeddings = <AiEmbedding>[
        ...await _embeddingRepository.listByType(AiEmbeddingSourceType.summary),
        ...await _embeddingRepository.listByType(AiEmbeddingSourceType.segment),
        ...await _embeddingRepository.listByType(AiEmbeddingSourceType.entry),
        ...await _embeddingRepository.listByType(AiEmbeddingSourceType.memory),
        ...await _embeddingRepository.listByType(AiEmbeddingSourceType.profile),
        ...await _embeddingRepository
            .listByType(AiEmbeddingSourceType.relationship),
        ...await _embeddingRepository.listByType(AiEmbeddingSourceType.stone),
      ];
    } on Object {
      return const [];
    }
    final memories = {
      for (final memory in await _memoryRepository.listMemories())
        memory.id: memory,
    };
    final profileSources = await _profileSearchSources();
    final stoneSources = await _stoneSearchSources();
    final candidates = <AiSearchMatch>[];
    for (final embedding in embeddings) {
      final similarity = _embeddingService.cosineSimilarity(
        queryEmbedding.vector,
        embedding.vector,
      );
      if (similarity < 0.18) continue;
      final source = await _sourceForEmbedding(
        embedding,
        memories: memories,
        profileSources: profileSources,
        stoneSources: stoneSources,
      );
      if (source == null) continue;
      final keywordScore = _keywordScore(queryTokens, _tokens(source.text));
      final structuredScore = _structuredScore(queryTokens, source);
      final importanceBonus = _importanceBonus(source.importance);
      final recencyBonus = _recencyBonus(source.date);
      final lifecycleScore = _memoryLifecycleScore(source);
      final score = (similarity * 12).round() +
          keywordScore +
          structuredScore +
          importanceBonus +
          recencyBonus +
          lifecycleScore;
      candidates.add(AiSearchMatch(
        sourceType: source.sourceType,
        sourceId: source.sourceId,
        entryId: source.entryId,
        title: source.title,
        summary: source.summary,
        score: score,
        reasons: [
          '向量相似度 ${similarity.toStringAsFixed(2)}',
          if (keywordScore > 0) '关键词校准 +$keywordScore',
          ..._structuredReasons(queryTokens, source),
          if (importanceBonus > 0)
            '摘要重要度 ${source.importance.toStringAsFixed(2)}',
          if (recencyBonus > 0) '近期记录校准 +$recencyBonus',
          ..._memoryLifecycleReasons(source),
        ],
        matchedTokens:
            _matchedTokens(queryTokens, _tokens(_searchableText(source))),
        rerankSignals: _signals(
          semantic: similarity,
          keyword: keywordScore,
          structured: _structuredSignals(queryTokens, source),
          importance: importanceBonus,
          recency: recencyBonus,
          lifecycle: _memoryLifecycleSignals(source),
        ),
      ));
    }
    return candidates;
  }

  Future<List<AiSearchMatch>> _keywordMatches(Set<String> queryTokens) async {
    final entries = await _diaryRepository.listEntries();
    final matches = <AiSearchMatch>[];
    for (final entry in entries) {
      final summary = await _summaryRepository.getSummary(entry.id);
      if (summary != null) {
        final text = [
          summary.title,
          summary.brief,
          ...summary.keyPoints,
          ...summary.topics,
          ...summary.people,
          ...summary.places,
          summary.emotion,
          ...summary.importantQuotes,
        ].join(' ');
        final match = _matchText(
          queryTokens: queryTokens,
          sourceType: 'entry_summary',
          sourceId: entry.id,
          entryId: entry.id,
          title: entry.title ?? summary.brief,
          summary: summary.brief,
          importance: summary.importance,
          date: entry.date,
          topics: summary.topics,
          people: summary.people,
          emotion: summary.emotion,
          text: text,
        );
        if (match != null) matches.add(match);
      } else {
        final match = _matchText(
          queryTokens: queryTokens,
          sourceType: 'entry',
          sourceId: entry.id,
          entryId: entry.id,
          title: entry.title ?? entry.excerpt,
          summary: entry.excerpt,
          importance: 0,
          date: entry.date,
          text: entry.bodyPreview,
        );
        if (match != null) matches.add(match);
      }

      final segments = await _summaryRepository.listSegments(entry.id);
      for (final segment in segments) {
        final match = _matchText(
          queryTokens: queryTokens,
          sourceType: 'segment',
          sourceId: segment.id,
          entryId: entry.id,
          title: segment.summary,
          summary: segment.text,
          importance: 0,
          date: entry.date,
          topics: segment.topics,
          people: segment.people,
          text: [
            segment.summary,
            segment.text,
            ...segment.topics,
            ...segment.people,
          ].join(' '),
        );
        if (match != null) matches.add(match);
      }
    }
    for (final memory in await _memoryRepository.listMemories()) {
      final source = _sourceForMemory(memory);
      if (source == null) continue;
      final match = _matchSource(queryTokens: queryTokens, source: source);
      if (match != null) matches.add(match);
    }
    matches.addAll(await _profileMatches(queryTokens));
    matches.addAll(await _stoneMatches(queryTokens));
    return matches;
  }

  Future<List<AiSearchMatch>> _profileMatches(Set<String> queryTokens) async {
    final profileSources = await _profileSearchSources();
    final matches = <AiSearchMatch>[];
    for (final fact in profileSources.profileFacts.values) {
      final match = _profileFactMatch(queryTokens, fact);
      if (match != null) matches.add(match);
    }
    for (final profile in profileSources.relationshipProfiles.values) {
      final match = _relationshipMatch(queryTokens, profile);
      if (match != null) matches.add(match);
    }
    return matches;
  }

  Future<_ProfileSearchSources> _profileSearchSources() async {
    final projection = _profileProjectionService
        .build(await _insightRepository.listInsights());
    final profileFacts = await _profilePreferenceRepository.applyToProfileFacts(
      projection.profileFacts,
    );
    final relationshipProfiles =
        await _profilePreferenceRepository.applyToRelationshipProfiles(
      projection.relationshipProfiles,
    );
    return _ProfileSearchSources(
      profileFacts: {
        for (final fact in profileFacts) fact.id: fact,
      },
      relationshipProfiles: {
        for (final profile in relationshipProfiles) profile.personName: profile,
      },
    );
  }

  Future<void> _ensureProfileEmbeddings(
    _ProfileSearchSources profileSources,
  ) async {
    for (final fact in profileSources.profileFacts.values) {
      await _saveDerivedEmbedding(
        sourceType: AiEmbeddingSourceType.profile,
        sourceId: fact.id,
        entryId: _firstEvidenceEntryId(fact.evidence),
        text: _profileFactText(fact),
      );
    }
    for (final profile in profileSources.relationshipProfiles.values) {
      await _saveDerivedEmbedding(
        sourceType: AiEmbeddingSourceType.relationship,
        sourceId: profile.personName,
        entryId: _firstEvidenceEntryId(profile.evidence),
        text: _relationshipText(profile),
      );
    }
  }

  Future<Map<String, StoneTask>> _stoneSearchSources() async {
    return {
      for (final task in await _stoneTaskRepository.listTasks()) task.id: task,
    };
  }

  Future<void> _ensureStoneEmbeddings(Map<String, StoneTask> tasks) async {
    for (final task in tasks.values) {
      await _saveDerivedEmbedding(
        sourceType: AiEmbeddingSourceType.stone,
        sourceId: task.id,
        entryId: task.sourceEntryId,
        text: _stoneTaskText(task),
      );
    }
  }

  Future<void> _saveDerivedEmbedding({
    required AiEmbeddingSourceType sourceType,
    required String sourceId,
    required String entryId,
    required String text,
  }) async {
    final result = _embeddingService.embed(text);
    final existing = await _embeddingRepository.getBySource(
      sourceType: sourceType,
      sourceId: sourceId,
    );
    if (existing?.textHash == result.textHash &&
        existing?.modelId == result.modelId &&
        existing?.modelVersion == result.modelVersion) {
      return;
    }
    await _embeddingRepository.saveEmbedding(AiEmbedding(
      id: '${sourceType.name}:$sourceId',
      sourceType: sourceType,
      sourceId: sourceId,
      entryId: entryId.isEmpty ? sourceId : entryId,
      modelId: result.modelId,
      modelVersion: result.modelVersion,
      dimensions: result.dimensions,
      vector: result.vector,
      generatedAt: DateTime.now(),
      textHash: result.textHash,
    ));
  }

  AiSearchMatch? _profileFactMatch(
    Set<String> queryTokens,
    ProfileFact fact,
  ) {
    final text = [
      fact.field,
      fact.value,
      fact.status.name,
      for (final evidence in fact.evidence) ...[
        evidence.summary ?? '',
        evidence.quote ?? '',
        evidence.relevance ?? '',
      ],
    ].join(' ');
    final sourceTokens = _tokens(text);
    final matchedTokens = _matchedTokens(queryTokens, sourceTokens);
    if (matchedTokens.isEmpty) return null;
    final score = _keywordScore(queryTokens, sourceTokens) +
        _profileStatusScore(fact.status) +
        (fact.confidence * 4).round() +
        fact.evidenceCount.clamp(0, 3).toInt() +
        (fact.userConfirmed ? 3 : 0) +
        _recencyBonus(fact.lastSeenAt);
    return AiSearchMatch(
      sourceType: 'profile',
      sourceId: fact.id,
      entryId: _firstEvidenceEntryId(fact.evidence),
      title: fact.field,
      summary: fact.value,
      score: score,
      reasons: [
        '画像匹配：${matchedTokens.take(6).join('、')}',
        '${fact.evidenceCount} 条证据',
        '${fact.distinctDays} 天',
        '置信度 ${fact.confidence.toStringAsFixed(2)}',
        if (fact.userConfirmed) '用户确认',
      ],
      matchedTokens: matchedTokens.take(12).toList(),
      rerankSignals: {
        'keyword': _keywordScore(queryTokens, sourceTokens).toDouble(),
        'status': _profileStatusScore(fact.status).toDouble(),
        'confidence': fact.confidence,
        'evidence': fact.evidenceCount.clamp(0, 3).toDouble(),
        if (fact.userConfirmed) 'userConfirmed': 1,
        if (_recencyBonus(fact.lastSeenAt) > 0)
          'time': _recencyBonus(fact.lastSeenAt).toDouble(),
      },
    );
  }

  AiSearchMatch? _relationshipMatch(
    Set<String> queryTokens,
    RelationshipProfile profile,
  ) {
    final text = [
      profile.personName,
      ...profile.names,
      profile.relationship ?? '',
      ...profile.emotions,
      ...profile.patterns,
      for (final interaction in profile.recentInteractions)
        '${interaction.summary} ${interaction.emotion ?? ''}',
      for (final evidence in profile.evidence) ...[
        evidence.summary ?? '',
        evidence.quote ?? '',
        evidence.relevance ?? '',
      ],
    ].join(' ');
    final sourceTokens = _tokens(text);
    final matchedTokens = _matchedTokens(queryTokens, sourceTokens);
    if (matchedTokens.isEmpty) return null;
    final score = _keywordScore(queryTokens, sourceTokens) +
        _profileStatusScore(profile.status) +
        (profile.confidence * 4).round() +
        profile.interactionCount.clamp(0, 4).toInt() +
        (profile.userConfirmed ? 3 : 0) +
        _recencyBonus(profile.lastInteractionAt);
    return AiSearchMatch(
      sourceType: 'relationship',
      sourceId: profile.personName,
      entryId: _firstEvidenceEntryId(profile.evidence),
      title: profile.personName,
      summary: [
        if (profile.relationship?.isNotEmpty ?? false) profile.relationship,
        ...profile.patterns.take(2),
        ...profile.emotions.take(2),
      ].whereType<String>().join('；'),
      score: score,
      reasons: [
        '关系匹配：${matchedTokens.take(6).join('、')}',
        '${profile.interactionCount} 次互动',
        '${profile.distinctDays} 天',
        '置信度 ${profile.confidence.toStringAsFixed(2)}',
        if (profile.userConfirmed) '用户确认',
      ],
      matchedTokens: matchedTokens.take(12).toList(),
      rerankSignals: {
        'keyword': _keywordScore(queryTokens, sourceTokens).toDouble(),
        'status': _profileStatusScore(profile.status).toDouble(),
        'confidence': profile.confidence,
        'evidence': profile.interactionCount.clamp(0, 4).toDouble(),
        if (profile.userConfirmed) 'userConfirmed': 1,
        if (_recencyBonus(profile.lastInteractionAt) > 0)
          'time': _recencyBonus(profile.lastInteractionAt).toDouble(),
      },
    );
  }

  Future<List<AiSearchMatch>> _stoneMatches(Set<String> queryTokens) async {
    final matches = <AiSearchMatch>[];
    for (final task in (await _stoneSearchSources()).values) {
      final source = _sourceForStoneTask(task);
      if (source == null) continue;
      final match = _matchSource(queryTokens: queryTokens, source: source);
      if (match != null) matches.add(match);
    }
    return matches;
  }

  Future<_SearchSource?> _sourceForEmbedding(
    AiEmbedding embedding, {
    Map<String, MemoryEntry> memories = const {},
    _ProfileSearchSources profileSources = const _ProfileSearchSources(),
    Map<String, StoneTask> stoneSources = const {},
  }) async {
    if (embedding.sourceType == AiEmbeddingSourceType.memory) {
      return _sourceForMemory(memories[embedding.sourceId]);
    }
    if (embedding.sourceType == AiEmbeddingSourceType.profile) {
      return _sourceForProfileFact(
        profileSources.profileFacts[embedding.sourceId],
      );
    }
    if (embedding.sourceType == AiEmbeddingSourceType.relationship) {
      return _sourceForRelationship(
        profileSources.relationshipProfiles[embedding.sourceId],
      );
    }
    if (embedding.sourceType == AiEmbeddingSourceType.stone) {
      return _sourceForStoneTask(stoneSources[embedding.sourceId]);
    }
    final entry = await _diaryRepository.getEntryById(embedding.entryId);
    if (entry == null) return null;
    switch (embedding.sourceType) {
      case AiEmbeddingSourceType.summary:
        final summary = await _summaryRepository.getSummary(embedding.entryId);
        if (summary == null) return null;
        return _SearchSource(
          sourceType: 'entry_summary',
          sourceId: embedding.sourceId,
          entryId: embedding.entryId,
          title: entry.title ?? summary.brief,
          summary: summary.brief,
          importance: summary.importance,
          date: entry.date,
          topics: summary.topics,
          people: summary.people,
          emotion: summary.emotion,
          text: [
            summary.title,
            summary.brief,
            ...summary.keyPoints,
            ...summary.topics,
            summary.emotion,
            ...summary.importantQuotes,
          ].join(' '),
        );
      case AiEmbeddingSourceType.segment:
        final segments = await _summaryRepository.listSegments(
          embedding.entryId,
        );
        final segment =
            segments.where((item) => item.id == embedding.sourceId).firstOrNull;
        if (segment == null) return null;
        return _SearchSource(
          sourceType: 'segment',
          sourceId: segment.id,
          entryId: embedding.entryId,
          title: segment.summary,
          summary: segment.text,
          importance: 0,
          date: entry.date,
          topics: segment.topics,
          people: segment.people,
          text: [
            segment.summary,
            segment.text,
            ...segment.topics,
            ...segment.people,
          ].join(' '),
        );
      case AiEmbeddingSourceType.entry:
        return _SearchSource(
          sourceType: 'entry',
          sourceId: embedding.sourceId,
          entryId: embedding.entryId,
          title: entry.title ?? entry.excerpt,
          summary: entry.excerpt,
          importance: 0,
          date: entry.date,
          text: entry.bodyPreview,
        );
      case AiEmbeddingSourceType.memory:
        return null;
      case AiEmbeddingSourceType.profile:
        return null;
      case AiEmbeddingSourceType.relationship:
        return null;
      case AiEmbeddingSourceType.stone:
        return null;
    }
  }

  _SearchSource? _sourceForProfileFact(ProfileFact? fact) {
    if (fact == null) return null;
    return _SearchSource(
      sourceType: 'profile',
      sourceId: fact.id,
      entryId: _firstEvidenceEntryId(fact.evidence),
      title: fact.field,
      summary: fact.value,
      importance: fact.confidence,
      date: fact.lastSeenAt,
      topics: [fact.field, fact.status.name],
      confidence: fact.confidence,
      referenceCount: fact.evidenceCount,
      text: _profileFactText(fact),
    );
  }

  _SearchSource? _sourceForRelationship(RelationshipProfile? profile) {
    if (profile == null) return null;
    return _SearchSource(
      sourceType: 'relationship',
      sourceId: profile.personName,
      entryId: _firstEvidenceEntryId(profile.evidence),
      title: profile.personName,
      summary: [
        if (profile.relationship?.isNotEmpty ?? false) profile.relationship,
        ...profile.patterns.take(2),
        ...profile.emotions.take(2),
      ].whereType<String>().join('；'),
      importance: profile.confidence,
      date: profile.lastInteractionAt,
      topics: [
        if (profile.relationship?.isNotEmpty ?? false) profile.relationship!,
        ...profile.patterns,
        profile.status.name,
      ],
      people: [profile.personName, ...profile.names],
      emotion: profile.emotions.join(' '),
      confidence: profile.confidence,
      referenceCount: profile.interactionCount,
      text: _relationshipText(profile),
    );
  }

  _SearchSource? _sourceForStoneTask(StoneTask? task) {
    if (task == null) return null;
    return _SearchSource(
      sourceType: 'stone',
      sourceId: task.id,
      entryId: task.sourceEntryId,
      title: task.title,
      summary: [
        task.description,
        if (task.checkIns.isNotEmpty) '最近进展：${task.checkIns.first.note}',
      ].where((item) => item.trim().isNotEmpty).join('；'),
      importance: task.status == StoneTaskStatus.active ? 0.72 : 0.48,
      date: task.updatedAt,
      topics: [
        ...task.tags,
        task.status.name,
      ],
      text: _stoneTaskText(task),
    );
  }

  _SearchSource? _sourceForMemory(MemoryEntry? memory) {
    if (memory == null) return null;
    return _SearchSource(
      sourceType: 'memory',
      sourceId: memory.id,
      entryId: memory.sourceEntryId,
      title: memory.title,
      summary: memory.summary,
      importance: memory.importance,
      date: memory.date,
      topics: memory.tags,
      people: memory.people,
      emotion: memory.emotion,
      confidence: memory.confidence,
      referenceCount: memory.referenceCount,
      decay: memory.decay,
      archived: memory.archived,
      text: [
        memory.summary,
        ...memory.keywords,
        ...memory.tags,
        ...memory.people,
        memory.emotion,
      ].join(' '),
    );
  }

  AiSearchMatch? _matchText({
    required Set<String> queryTokens,
    required String sourceType,
    required String sourceId,
    required String entryId,
    required String title,
    required String summary,
    required double importance,
    required DateTime date,
    List<String> topics = const [],
    List<String> people = const [],
    String emotion = '',
    required String text,
  }) {
    final source = _SearchSource(
      sourceType: sourceType,
      sourceId: sourceId,
      entryId: entryId,
      title: title,
      summary: summary,
      importance: importance,
      date: date,
      topics: topics,
      people: people,
      emotion: emotion,
      text: text,
    );
    return _matchSource(queryTokens: queryTokens, source: source);
  }

  AiSearchMatch? _matchSource({
    required Set<String> queryTokens,
    required _SearchSource source,
  }) {
    final sourceTokens = _tokens(_searchableText(source));
    final matchedTokens = _matchedTokens(queryTokens, sourceTokens);
    if (matchedTokens.isEmpty) return null;
    final importanceBonus = _importanceBonus(source.importance);
    final structuredScore = _structuredScore(queryTokens, source);
    final recencyBonus = _recencyBonus(source.date);
    final lifecycleScore = _memoryLifecycleScore(source);
    final score = _keywordScore(queryTokens, sourceTokens) +
        structuredScore +
        importanceBonus +
        recencyBonus +
        lifecycleScore;
    return AiSearchMatch(
      sourceType: source.sourceType,
      sourceId: source.sourceId,
      entryId: source.entryId,
      title: source.title,
      summary: source.summary,
      score: score,
      reasons: [
        '关键词重合：${matchedTokens.take(6).join('、')}',
        ..._structuredReasons(queryTokens, source),
        if (importanceBonus > 0)
          '${source.sourceType == 'memory' ? '记忆重要度' : '摘要重要度'} ${source.importance.toStringAsFixed(2)}',
        if (recencyBonus > 0) '近期记录校准 +$recencyBonus',
        ..._memoryLifecycleReasons(source),
      ],
      matchedTokens: matchedTokens.take(12).toList(),
      rerankSignals: _signals(
        keyword: _keywordScore(queryTokens, sourceTokens),
        structured: _structuredSignals(queryTokens, source),
        importance: importanceBonus,
        recency: recencyBonus,
        lifecycle: _memoryLifecycleSignals(source),
      ),
    );
  }

  AiSearchMatch _mergeReasons(AiSearchMatch first, AiSearchMatch second) {
    return AiSearchMatch(
      sourceType: first.sourceType,
      sourceId: first.sourceId,
      entryId: first.entryId,
      title: first.title,
      summary: first.summary,
      score: first.score,
      reasons: {...first.reasons, ...second.reasons}.toList(),
      matchedTokens: {...first.matchedTokens, ...second.matchedTokens}.toList(),
      rerankSignals: _mergeSignals(first.rerankSignals, second.rerankSignals),
    );
  }

  int _keywordScore(Set<String> queryTokens, Set<String> sourceTokens) {
    var score = 0;
    for (final token in queryTokens) {
      if (!sourceTokens.contains(token)) continue;
      score += token.length >= 4 ? 3 : 2;
    }
    return score;
  }

  int _importanceBonus(double importance) {
    if (importance >= 0.75) return 2;
    if (importance >= 0.6) return 1;
    return 0;
  }

  int _profileStatusScore(ProfileFactStatus status) {
    switch (status) {
      case ProfileFactStatus.stable:
        return 6;
      case ProfileFactStatus.emerging:
        return 4;
      case ProfileFactStatus.weak:
        return 2;
    }
  }

  int _memoryLifecycleScore(_SearchSource source) {
    if (source.sourceType != 'memory') return 0;
    final confidenceBonus = source.confidence >= 0.8
        ? 2
        : source.confidence >= 0.55
            ? 1
            : 0;
    final referenceBonus = source.referenceCount.clamp(0, 2).toInt();
    final decayPenalty = (source.decay * 3).round();
    final archivedPenalty = source.archived ? 4 : 0;
    final confidencePenalty = source.confidence < 0.2 ? 2 : 0;
    return confidenceBonus +
        referenceBonus -
        decayPenalty -
        archivedPenalty -
        confidencePenalty;
  }

  List<String> _memoryLifecycleReasons(_SearchSource source) {
    if (source.sourceType != 'memory') return const [];
    return [
      if (source.confidence >= 0.55)
        '记忆置信度 ${source.confidence.toStringAsFixed(2)}',
      if (source.referenceCount > 0)
        '历史引用 ${source.referenceCount.clamp(0, 2).toInt()}',
      if ((source.decay * 3).round() > 0) '记忆衰减 -${(source.decay * 3).round()}',
      if (source.archived) '已归档记忆',
      if (source.confidence < 0.2) '低置信记忆',
    ];
  }

  Map<String, double> _memoryLifecycleSignals(_SearchSource source) {
    if (source.sourceType != 'memory') return const {};
    final decayPenalty = (source.decay * 3).round();
    return {
      'confidence': source.confidence,
      if (source.referenceCount > 0)
        'reference': source.referenceCount.clamp(0, 2).toDouble(),
      if (decayPenalty > 0) 'decay': -decayPenalty.toDouble(),
      if (source.archived) 'archived': -1,
      if (source.confidence < 0.2) 'lowConfidence': -1,
    };
  }

  int _structuredScore(Set<String> queryTokens, _SearchSource source) {
    return _structuredSignals(queryTokens, source)
        .values
        .fold<int>(0, (total, value) => total + value.round());
  }

  Map<String, double> _structuredSignals(
    Set<String> queryTokens,
    _SearchSource source,
  ) {
    return {
      if (_matchedTokens(queryTokens, _tokens(source.people.join(' ')))
          .isNotEmpty)
        'people': 3,
      if (_matchedTokens(queryTokens, _tokens(source.topics.join(' ')))
          .isNotEmpty)
        'topic': 2,
      if (_matchedTokens(queryTokens, _tokens(source.emotion)).isNotEmpty)
        'emotion': 1,
    };
  }

  List<String> _structuredReasons(
    Set<String> queryTokens,
    _SearchSource source,
  ) {
    final people =
        _matchedTokens(queryTokens, _tokens(source.people.join(' ')));
    final topics =
        _matchedTokens(queryTokens, _tokens(source.topics.join(' ')));
    final emotions = _matchedTokens(queryTokens, _tokens(source.emotion));
    return [
      if (people.isNotEmpty) '人物匹配：${people.take(3).join('、')}',
      if (topics.isNotEmpty) '主题匹配：${topics.take(3).join('、')}',
      if (emotions.isNotEmpty) '情绪匹配：${emotions.take(3).join('、')}',
    ];
  }

  int _recencyBonus(DateTime date) {
    final age = DateTime.now().difference(date).inDays;
    if (age < 0) return 0;
    if (age <= 30) return 2;
    if (age <= 180) return 1;
    return 0;
  }

  Map<String, double> _signals({
    double? semantic,
    int keyword = 0,
    Map<String, double> structured = const {},
    int importance = 0,
    int recency = 0,
    Map<String, double> lifecycle = const {},
  }) {
    return {
      if (semantic != null) 'semantic': semantic,
      if (keyword > 0) 'keyword': keyword.toDouble(),
      ...structured,
      if (importance > 0) 'importance': importance.toDouble(),
      if (recency > 0) 'time': recency.toDouble(),
      ...lifecycle,
    };
  }

  Map<String, double> _mergeSignals(
    Map<String, double> first,
    Map<String, double> second,
  ) {
    return {
      ...first,
      for (final entry in second.entries)
        entry.key: entry.value > (first[entry.key] ?? 0)
            ? entry.value
            : first[entry.key]!,
    };
  }

  List<String> _matchedTokens(
    Set<String> queryTokens,
    Set<String> sourceTokens,
  ) {
    return queryTokens.where(sourceTokens.contains).take(12).toList();
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

  String _searchableText(_SearchSource source) {
    return [
      source.text,
      ...source.topics,
      ...source.people,
      source.emotion,
    ].join(' ');
  }

  String _profileFactText(ProfileFact fact) {
    return [
      fact.field,
      fact.value,
      fact.status.name,
      for (final evidence in fact.evidence) ...[
        evidence.summary ?? '',
        evidence.quote ?? '',
        evidence.relevance ?? '',
      ],
    ].join(' ');
  }

  String _relationshipText(RelationshipProfile profile) {
    return [
      profile.personName,
      ...profile.names,
      profile.relationship ?? '',
      ...profile.emotions,
      ...profile.patterns,
      for (final interaction in profile.recentInteractions)
        '${interaction.summary} ${interaction.emotion ?? ''}',
      for (final evidence in profile.evidence) ...[
        evidence.summary ?? '',
        evidence.quote ?? '',
        evidence.relevance ?? '',
      ],
    ].join(' ');
  }

  String _stoneTaskText(StoneTask task) {
    return [
      task.title,
      task.description,
      task.status.name,
      ...task.tags,
      for (final checkIn in task.checkIns) checkIn.note,
    ].join(' ');
  }

  String _firstEvidenceEntryId(List<InsightEvidence> evidence) {
    for (final item in evidence) {
      final id = item.id.trim();
      if (id.isEmpty) continue;
      return id.split('#').first;
    }
    return '';
  }
}

class _SearchSource {
  const _SearchSource({
    required this.sourceType,
    required this.sourceId,
    required this.entryId,
    required this.title,
    required this.summary,
    required this.importance,
    required this.date,
    this.topics = const [],
    this.people = const [],
    this.emotion = '',
    this.confidence = 1,
    this.referenceCount = 0,
    this.decay = 0,
    this.archived = false,
    required this.text,
  });

  final String sourceType;
  final String sourceId;
  final String entryId;
  final String title;
  final String summary;
  final double importance;
  final DateTime date;
  final List<String> topics;
  final List<String> people;
  final String emotion;
  final double confidence;
  final int referenceCount;
  final double decay;
  final bool archived;
  final String text;
}

class _ProfileSearchSources {
  const _ProfileSearchSources({
    this.profileFacts = const {},
    this.relationshipProfiles = const {},
  });

  final Map<String, ProfileFact> profileFacts;
  final Map<String, RelationshipProfile> relationshipProfiles;
}
