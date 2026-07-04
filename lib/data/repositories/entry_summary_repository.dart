import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_embedding.dart';
import '../models/diary_segment.dart';
import '../models/entry_summary.dart';
import '../services/ai_embedding_text_builder.dart';
import '../services/embedding_service.dart';
import 'ai_embedding_repository.dart';

class EntrySummaryRepository {
  const EntrySummaryRepository();

  static const _summaryPrefix = 'ai.entrySummaries.';
  static const _segmentIndexPrefix = 'ai.entrySegments.index.';
  static const _segmentPrefix = 'ai.entrySegments.';

  Future<void> saveSummary(EntrySummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_summaryPrefix${summary.entryId}', jsonEncode(summary.toJson()));
  }

  Future<EntrySummary?> getSummary(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_summaryPrefix$entryId';
    final raw = _safeGetString(prefs, key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(key);
        return null;
      }
      return EntrySummary.fromJson(decoded);
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<EntrySummary?> correctBrief({
    required String entryId,
    required String brief,
  }) async {
    return correctSummaryPackage(entryId: entryId, brief: brief);
  }

  Future<EntrySummary?> correctSummaryPackage({
    required String entryId,
    required String brief,
    String? title,
    String? emotion,
    double? importance,
    List<String>? keyPoints,
    List<String>? importantQuotes,
  }) async {
    final value = brief.trim();
    if (value.isEmpty) return getSummary(entryId);
    final current = await getSummary(entryId);
    if (current == null) return null;
    final correctedAt = DateTime.now();
    final quality = _qualityFor(
      brief: value,
      keyPoints: keyPoints ?? current.keyPoints,
      topics: current.topics,
      emotion: emotion ?? current.emotion,
      importantQuotes: importantQuotes ?? current.importantQuotes,
    );
    final updated = current.copyWith(
      title: title ?? current.title,
      brief: value,
      emotion: emotion ?? current.emotion,
      importance: importance ?? current.importance,
      keyPoints: keyPoints ?? current.keyPoints,
      importantQuotes: importantQuotes ?? current.importantQuotes,
      generatedAt: correctedAt,
      generator: 'user-corrected',
      qualityScore: quality.score,
      qualityWarnings: quality.warnings,
      revision: current.revision + 1,
      correctedAt: correctedAt,
    );
    await saveSummary(updated);
    await _refreshSummaryEmbedding(updated);
    return updated;
  }

  Future<void> saveSegments(String entryId, List<DiarySegment> segments) async {
    final prefs = await SharedPreferences.getInstance();
    final oldIds =
        _safeGetStringList(prefs, '$_segmentIndexPrefix$entryId') ?? [];
    const embeddingRepository = AiEmbeddingRepository();
    for (final id in oldIds) {
      await prefs.remove('$_segmentPrefix$id');
      await embeddingRepository.deleteBySource(
        sourceType: AiEmbeddingSourceType.segment,
        sourceId: id,
      );
    }
    final ids = <String>[];
    for (final segment in segments) {
      ids.add(segment.id);
      await prefs.setString(
          '$_segmentPrefix${segment.id}', jsonEncode(segment.toJson()));
    }
    await prefs.setStringList('$_segmentIndexPrefix$entryId', ids);
  }

  Future<List<DiarySegment>> listSegments(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final indexKey = '$_segmentIndexPrefix$entryId';
    final ids = _safeGetStringList(prefs, indexKey) ?? [];
    final segments = <DiarySegment>[];
    for (final id in ids) {
      final key = '$_segmentPrefix$id';
      final raw = _safeGetString(prefs, key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          await prefs.remove(key);
          continue;
        }
        segments.add(DiarySegment.fromJson(decoded));
      } on Object {
        await prefs.remove(key);
      }
    }
    segments.sort((a, b) => a.index.compareTo(b.index));
    await prefs.setStringList(
        indexKey, segments.map((item) => item.id).toList());
    return segments;
  }

  Future<void> deleteForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    const embeddingRepository = AiEmbeddingRepository();
    await prefs.remove('$_summaryPrefix$entryId');
    await embeddingRepository.deleteBySource(
      sourceType: AiEmbeddingSourceType.summary,
      sourceId: entryId,
    );
    final ids = _safeGetStringList(prefs, '$_segmentIndexPrefix$entryId') ?? [];
    for (final id in ids) {
      await prefs.remove('$_segmentPrefix$id');
      await embeddingRepository.deleteBySource(
        sourceType: AiEmbeddingSourceType.segment,
        sourceId: id,
      );
    }
    await prefs.remove('$_segmentIndexPrefix$entryId');
  }

  Future<void> _refreshSummaryEmbedding(EntrySummary summary) async {
    const embeddingService = EmbeddingService();
    const textBuilder = AiEmbeddingTextBuilder();
    const embeddingRepository = AiEmbeddingRepository();
    final text = textBuilder.summaryText(summary);
    final result = embeddingService.embed(text);
    await embeddingRepository.saveEmbedding(AiEmbedding(
      id: '${AiEmbeddingSourceType.summary.name}:${summary.entryId}',
      sourceType: AiEmbeddingSourceType.summary,
      sourceId: summary.entryId,
      entryId: summary.entryId,
      modelId: result.modelId,
      modelVersion: result.modelVersion,
      dimensions: result.dimensions,
      vector: result.vector,
      generatedAt: DateTime.now(),
      textHash: result.textHash,
    ));
  }

  _SummaryQuality _qualityFor({
    required String brief,
    required List<String> keyPoints,
    required List<String> topics,
    required String emotion,
    required List<String> importantQuotes,
  }) {
    var score = 0.36;
    final warnings = <String>[];
    if (brief.trim().length >= 20) {
      score += 0.22;
    } else {
      warnings.add('摘要过短');
    }
    if (keyPoints.length >= 2) {
      score += 0.18;
    } else if (keyPoints.isNotEmpty) {
      score += 0.1;
    } else {
      warnings.add('缺少关键点');
    }
    if (topics.isNotEmpty) {
      score += 0.1;
    } else {
      warnings.add('缺少主题');
    }
    if (emotion.isNotEmpty) score += 0.06;
    if (importantQuotes.isNotEmpty) score += 0.08;
    return _SummaryQuality(
      score: score.clamp(0.05, 1).toDouble(),
      warnings: warnings.take(4).toList(growable: false),
    );
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }

  List<String>? _safeGetStringList(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      if (value is List<String>) return List<String>.from(value);
      if (value is List) return value.whereType<String>().toList();
      return null;
    } on Object {
      return null;
    }
  }
}

class _SummaryQuality {
  const _SummaryQuality({
    required this.score,
    required this.warnings,
  });

  final double score;
  final List<String> warnings;
}
