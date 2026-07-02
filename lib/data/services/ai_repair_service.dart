import 'dart:convert';

import 'package:characters/characters.dart';

import 'ai_client_service.dart';

class AiRepairService {
  const AiRepairService({AiClientService? client})
      : _client = client ?? const AiClientService();

  static const _maxLengthDeltaRatio = 0.2;
  final AiClientService _client;

  Future<AiRepairResult> repair(String text, {String? customRule}) async {
    final useCustom = customRule != null && customRule.trim().isNotEmpty;
    final systemPrompt = useCustom
        ? '你是日记文本处理助手。严格遵守用户的自定义要求处理文本。不要虚构内容。只有在非常不确定且可能改变原意时，才输出 warnings。输出必须是 JSON。'
        : '你是日记“原文保护型修复器”。只修正错别字、错误标点、明显语法不通。不得改写观点、语气、情绪、结构、句子长短。只有在非常不确定且可能改变原意时，才输出 warnings。输出必须是 JSON。';
    final userPrompt = useCustom
        ? '''请按用户要求处理下面的日记，并返回 JSON：
{
  "corrected_text": "处理后的全文",
  "warnings": ["仅在非常不确定时才给出"]
}
用户要求：
${customRule.trim()}

原文：
$text'''
        : '''请修复下面的日记，并返回 JSON：
{
  "corrected_text": "修复后的全文",
  "warnings": ["仅在非常不确定时才给出"]
}
要求：
1. 只返回修复后的文本，不要返回修复数量；
2. 不允许夸大问题；
3. 如果无需修复，corrected_text 直接返回原文。

原文：
$text''';

    final jsonText = await _client.completeJson(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      maxTokens: 1200,
    );

    final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
    final correctedText = (parsed['corrected_text'] as String? ?? text).trim();
    final safeText = correctedText.isEmpty ? text : correctedText;
    final warnings = (parsed['warnings'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();

    if (useCustom) {
      return AiRepairResult(
        correctedText: safeText,
        typoCount: 0,
        grammarCount: 0,
        punctuationCount: 0,
        warnings: warnings,
        applied: true,
      );
    }

    final computed = _computeFixStats(text, safeText);
    final lengthDelta = (safeText.length - text.length).abs();
    final ratio = text.isEmpty ? 0 : lengthDelta / text.length;
    final shouldApply = ratio <= _maxLengthDeltaRatio;

    if (safeText == text) {
      return AiRepairResult(
        correctedText: text,
        typoCount: 0,
        grammarCount: 0,
        punctuationCount: 0,
        warnings: const [],
        applied: true,
      );
    }

    final finalWarnings = <String>[
      ...warnings,
      if (!shouldApply) '本次修复改动幅度较大，建议先人工确认。',
    ];

    return AiRepairResult(
      correctedText: shouldApply ? safeText : text,
      typoCount: computed.typoCount,
      grammarCount: computed.grammarCount,
      punctuationCount: computed.punctuationCount,
      warnings: finalWarnings,
      applied: shouldApply,
    );
  }

  _ComputedFixStats _computeFixStats(String original, String corrected) {
    if (original == corrected) {
      return const _ComputedFixStats(
          typoCount: 0, grammarCount: 0, punctuationCount: 0);
    }

    final a = original.characters.toList();
    final b = corrected.characters.toList();
    final dp =
        List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));

    for (var i = 0; i <= a.length; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      dp[0][j] = j;
    }

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] =
            _min3(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost);
      }
    }

    final ops = <_DiffOp>[];
    var i = a.length;
    var j = b.length;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && a[i - 1] == b[j - 1]) {
        i--;
        j--;
        continue;
      }
      if (i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + 1) {
        ops.add(_DiffOp(
            oldChar: a[i - 1],
            newChar: b[j - 1],
            oldIndex: i - 1,
            newIndex: j - 1));
        i--;
        j--;
        continue;
      }
      if (i > 0 && dp[i][j] == dp[i - 1][j] + 1) {
        ops.add(_DiffOp(
            oldChar: a[i - 1], newChar: '', oldIndex: i - 1, newIndex: j));
        i--;
        continue;
      }
      ops.add(_DiffOp(
          oldChar: '', newChar: b[j - 1], oldIndex: i, newIndex: j - 1));
      j--;
    }

    final orderedOps = ops.reversed.toList();
    var typoCount = 0;
    var grammarCount = 0;
    var punctuationCount = 0;
    _FixCategory? lastCategory;
    int? lastOldIndex;
    int? lastNewIndex;

    for (final op in orderedOps) {
      final category = _classify(op.oldChar, op.newChar);
      final contiguous = lastCategory == category &&
          ((lastOldIndex != null && op.oldIndex == lastOldIndex + 1) ||
              (lastNewIndex != null && op.newIndex == lastNewIndex + 1));
      if (!contiguous) {
        switch (category) {
          case _FixCategory.typo:
            typoCount++;
          case _FixCategory.grammar:
            grammarCount++;
          case _FixCategory.punctuation:
            punctuationCount++;
        }
      }
      lastCategory = category;
      lastOldIndex = op.oldIndex;
      lastNewIndex = op.newIndex;
    }

    return _ComputedFixStats(
      typoCount: typoCount,
      grammarCount: grammarCount,
      punctuationCount: punctuationCount,
    );
  }

  int _min3(int a, int b, int c) => a < b ? (a < c ? a : c) : (b < c ? b : c);

  _FixCategory _classify(String oldChar, String newChar) {
    final combined = '$oldChar$newChar';
    if (RegExp(r'[，。！？；：、“”‘’（）《》【】,.!?;:]').hasMatch(combined)) {
      return _FixCategory.punctuation;
    }
    if (oldChar.trim().isEmpty || newChar.trim().isEmpty) {
      return _FixCategory.grammar;
    }
    return _FixCategory.typo;
  }
}

class AiRepairException implements Exception {
  const AiRepairException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiRepairResult {
  const AiRepairResult({
    required this.correctedText,
    required this.typoCount,
    required this.grammarCount,
    required this.punctuationCount,
    required this.warnings,
    required this.applied,
  });

  final String correctedText;
  final int typoCount;
  final int grammarCount;
  final int punctuationCount;
  final List<String> warnings;
  final bool applied;

  int get totalFixes => typoCount + grammarCount + punctuationCount;
}

enum _FixCategory { typo, grammar, punctuation }

class _DiffOp {
  const _DiffOp({
    required this.oldChar,
    required this.newChar,
    required this.oldIndex,
    required this.newIndex,
  });

  final String oldChar;
  final String newChar;
  final int oldIndex;
  final int newIndex;
}

class _ComputedFixStats {
  const _ComputedFixStats({
    required this.typoCount,
    required this.grammarCount,
    required this.punctuationCount,
  });

  final int typoCount;
  final int grammarCount;
  final int punctuationCount;
}
