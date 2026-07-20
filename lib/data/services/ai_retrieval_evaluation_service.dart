import 'dart:convert';

import 'package:flutter/services.dart';

import 'ai_search_service.dart';

class AiRetrievalEvaluationService {
  const AiRetrievalEvaluationService({
    AiSearchService? searchService,
    AssetBundle? assetBundle,
  })  : _searchService = searchService ?? const AiSearchService(),
        _assetBundle = assetBundle;

  static const defaultAssetPath = 'assets/dev/retrieval_evaluation_cases.json';

  final AiSearchService _searchService;
  final AssetBundle? _assetBundle;

  Future<List<AiRetrievalEvaluationCase>> loadCases({
    String assetPath = defaultAssetPath,
  }) async {
    final raw = await (_assetBundle ?? rootBundle).loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('检索评测数据格式错误：根节点必须是对象');
    }
    final casesJson = decoded['cases'];
    if (casesJson is! List) {
      throw const FormatException('检索评测数据格式错误：cases 必须是数组');
    }
    return casesJson
        .whereType<Map<String, dynamic>>()
        .map(AiRetrievalEvaluationCase.fromJson)
        .where((item) =>
            item.id.trim().isNotEmpty &&
            item.question.trim().isNotEmpty &&
            item.expectedSourceIds.isNotEmpty)
        .toList(growable: false);
  }

  Future<AiRetrievalEvaluationReport> evaluateDefaultCases({
    int limit = 20,
  }) async {
    return evaluate(await loadCases(), limit: limit);
  }

  Future<AiRetrievalEvaluationReport> evaluate(
    List<AiRetrievalEvaluationCase> cases, {
    int limit = 20,
  }) async {
    final results = <AiRetrievalEvaluationResult>[];
    for (final item in cases) {
      final matches = await _searchService.search(item.question, limit: limit);
      final matchedIds = matches.map((match) => match.sourceId).toSet();
      final expectedIds = item.expectedSourceIds.toSet();
      final hitIds = expectedIds.intersection(matchedIds);
      final unexpectedIds = matchedIds.difference(expectedIds);
      final recall =
          expectedIds.isEmpty ? 1.0 : hitIds.length / expectedIds.length;
      final precision =
          matchedIds.isEmpty ? 0.0 : hitIds.length / matchedIds.length;
      results.add(AiRetrievalEvaluationResult(
        caseId: item.id,
        question: item.question,
        expectedSourceIds: expectedIds.toList()..sort(),
        matchedSourceIds: matchedIds.toList()..sort(),
        hitSourceIds: hitIds.toList()..sort(),
        unexpectedSourceIds: unexpectedIds.toList()..sort(),
        recall: recall,
        precision: precision,
        passed: recall >= item.minimumRecall,
      ));
    }
    return AiRetrievalEvaluationReport(results: results);
  }
}

class AiRetrievalEvaluationCase {
  const AiRetrievalEvaluationCase({
    required this.id,
    required this.question,
    required this.expectedSourceIds,
    this.minimumRecall = 0.8,
  });

  final String id;
  final String question;
  final List<String> expectedSourceIds;
  final double minimumRecall;

  factory AiRetrievalEvaluationCase.fromJson(Map<String, dynamic> json) {
    return AiRetrievalEvaluationCase(
      id: _string(json['id']),
      question: _string(json['question']),
      expectedSourceIds: _stringList(json['expectedSourceIds']),
      minimumRecall: _double(json['minimumRecall'], fallback: 0.8),
    );
  }
}

class AiRetrievalEvaluationReport {
  const AiRetrievalEvaluationReport({required this.results});

  final List<AiRetrievalEvaluationResult> results;

  int get totalCount => results.length;

  int get passedCount => results.where((result) => result.passed).length;

  int get failedCount => totalCount - passedCount;

  double get averageRecall {
    if (results.isEmpty) return 1.0;
    final total = results.fold<double>(
      0,
      (sum, result) => sum + result.recall,
    );
    return total / results.length;
  }

  double get averagePrecision {
    if (results.isEmpty) return 1.0;
    final total = results.fold<double>(
      0,
      (sum, result) => sum + result.precision,
    );
    return total / results.length;
  }

  String get summary =>
      'cases=$totalCount passed=$passedCount failed=$failedCount '
      'recall=${averageRecall.toStringAsFixed(3)} '
      'precision=${averagePrecision.toStringAsFixed(3)}';

  String toDebugText() {
    return [
      '## Retrieval Evaluation',
      summary,
      for (final result in results) ...[
        '',
        '- ${result.caseId} ${result.passed ? 'PASS' : 'FAIL'}',
        '  question=${result.question}',
        '  recall=${result.recall.toStringAsFixed(3)} precision=${result.precision.toStringAsFixed(3)}',
        '  expected=${result.expectedSourceIds.join(',')}',
        '  hit=${result.hitSourceIds.join(',')}',
        '  matched=${result.matchedSourceIds.take(12).join(',')}',
        if (result.unexpectedSourceIds.isNotEmpty)
          '  unexpected=${result.unexpectedSourceIds.take(12).join(',')}',
      ],
    ].join('\n');
  }
}

class AiRetrievalEvaluationResult {
  const AiRetrievalEvaluationResult({
    required this.caseId,
    required this.question,
    required this.expectedSourceIds,
    required this.matchedSourceIds,
    required this.hitSourceIds,
    required this.unexpectedSourceIds,
    required this.recall,
    required this.precision,
    required this.passed,
  });

  final String caseId;
  final String question;
  final List<String> expectedSourceIds;
  final List<String> matchedSourceIds;
  final List<String> hitSourceIds;
  final List<String> unexpectedSourceIds;
  final double recall;
  final double precision;
  final bool passed;
}

String _string(Object? value) => value is String ? value : '${value ?? ''}';

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Object?>()
      .map(_string)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

double _double(Object? value, {required double fallback}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
