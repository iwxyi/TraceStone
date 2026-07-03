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
      final score = (similarity * 12).round() + keywordScore;
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
        ],
        matchedTokens: _matchedTokens(queryTokens, _tokens(source.text)),
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
          summary.brief,
          ...summary.keyPoints,
          ...summary.topics,
          ...summary.people,
          ...summary.places,
          ...summary.importantQuotes,
        ].join(' ');
        final match = _matchText(
          queryTokens: queryTokens,
          sourceType: 'entry_summary',
          sourceId: entry.id,
          entryId: entry.id,
          title: entry.title ?? summary.brief,
          summary: summary.brief,
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
          text: [
            summary.brief,
            ...summary.keyPoints,
            ...summary.topics,
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
    required String text,
  }) {
    final sourceTokens = _tokens(text);
    final matchedTokens = _matchedTokens(queryTokens, sourceTokens);
    if (matchedTokens.isEmpty) return null;
    final score = _keywordScore(queryTokens, sourceTokens);
    return AiSearchMatch(
      sourceType: sourceType,
      sourceId: sourceId,
      entryId: entryId,
      title: title,
      summary: summary,
      score: score,
      reasons: ['关键词重合：${matchedTokens.take(6).join('、')}'],
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
}

class _SearchSource {
  const _SearchSource({
    required this.sourceType,
    required this.sourceId,
    required this.entryId,
    required this.title,
    required this.summary,
    required this.text,
  });

  final String sourceType;
  final String sourceId;
  final String entryId;
  final String title;
  final String summary;
  final String text;
}
