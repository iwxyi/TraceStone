import '../models/ai_context_package.dart';
import '../models/ai_embedding.dart';
import '../repositories/ai_embedding_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import 'embedding_service.dart';

class AiSearchService {
  const AiSearchService({
    AiEmbeddingRepository? embeddingRepository,
    DiaryRepository? diaryRepository,
    EntrySummaryRepository? summaryRepository,
    EmbeddingService? embeddingService,
  })  : _embeddingRepository =
            embeddingRepository ?? const AiEmbeddingRepository(),
        _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _summaryRepository =
            summaryRepository ?? const EntrySummaryRepository(),
        _embeddingService = embeddingService ?? const EmbeddingService();

  final AiEmbeddingRepository _embeddingRepository;
  final DiaryRepository _diaryRepository;
  final EntrySummaryRepository _summaryRepository;
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
    final queryEmbedding = _embeddingService.embed(query);
    final embeddings = <AiEmbedding>[
      ...await _embeddingRepository.listByType(AiEmbeddingSourceType.summary),
      ...await _embeddingRepository.listByType(AiEmbeddingSourceType.segment),
      ...await _embeddingRepository.listByType(AiEmbeddingSourceType.entry),
    ];
    final candidates = <AiSearchMatch>[];
    for (final embedding in embeddings) {
      final similarity = _embeddingService.cosineSimilarity(
        queryEmbedding.vector,
        embedding.vector,
      );
      if (similarity < 0.18) continue;
      final source = await _sourceForEmbedding(embedding);
      if (source == null) continue;
      final keywordScore = _keywordScore(queryTokens, _tokens(source.text));
      final structuredScore = _structuredScore(queryTokens, source);
      final importanceBonus = _importanceBonus(source.importance);
      final recencyBonus = _recencyBonus(source.date);
      final score = (similarity * 12).round() +
          keywordScore +
          structuredScore +
          importanceBonus +
          recencyBonus;
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
        ],
        matchedTokens:
            _matchedTokens(queryTokens, _tokens(_searchableText(source))),
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
    return matches;
  }

  Future<_SearchSource?> _sourceForEmbedding(AiEmbedding embedding) async {
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
    }
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
    final sourceTokens = _tokens(_searchableText(source));
    final matchedTokens = _matchedTokens(queryTokens, sourceTokens);
    if (matchedTokens.isEmpty) return null;
    final importanceBonus = _importanceBonus(importance);
    final structuredScore = _structuredScore(queryTokens, source);
    final recencyBonus = _recencyBonus(date);
    final score = _keywordScore(queryTokens, sourceTokens) +
        structuredScore +
        importanceBonus +
        recencyBonus;
    return AiSearchMatch(
      sourceType: sourceType,
      sourceId: sourceId,
      entryId: entryId,
      title: title,
      summary: summary,
      score: score,
      reasons: [
        '关键词重合：${matchedTokens.take(6).join('、')}',
        ..._structuredReasons(queryTokens, source),
        if (importanceBonus > 0) '摘要重要度 ${importance.toStringAsFixed(2)}',
        if (recencyBonus > 0) '近期记录校准 +$recencyBonus',
      ],
      matchedTokens: matchedTokens.take(12).toList(),
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

  int _structuredScore(Set<String> queryTokens, _SearchSource source) {
    var score = 0;
    if (_matchedTokens(queryTokens, _tokens(source.people.join(' ')))
        .isNotEmpty) {
      score += 3;
    }
    if (_matchedTokens(queryTokens, _tokens(source.topics.join(' ')))
        .isNotEmpty) {
      score += 2;
    }
    if (_matchedTokens(queryTokens, _tokens(source.emotion)).isNotEmpty) {
      score += 1;
    }
    return score;
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
  final String text;
}
