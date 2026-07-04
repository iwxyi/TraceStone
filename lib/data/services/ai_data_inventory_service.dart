import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_embedding.dart';
import '../models/ai_analysis_job.dart';
import '../models/ai_feedback.dart';
import '../models/ai_profile_preference.dart';
import '../models/ai_prompt_trace.dart';
import '../models/ai_retrieval_trace.dart';
import '../models/diary_analysis_status.dart';
import '../models/diary_insight.dart';
import '../models/calendar_memory.dart';
import '../models/entry_summary.dart';
import '../models/memory_entry.dart';
import '../models/period_summary.dart';
import '../models/stone_task.dart';
import 'embedding_service.dart';

class AiDataInventoryService {
  const AiDataInventoryService();

  Future<AiDataInventory> buildInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final sections = [
      _section(
        keys,
        label: '日记摘要',
        prefixes: const [
          'ai.entrySummaries.',
          'ai.entrySummaryRevisions.',
          'ai.entrySegments.',
        ],
        sensitivity: 'high',
        backupPolicy: '随日记备份',
        deletePolicy: '日记永久删除时清理',
        exportPolicy: '可随日记导出，需提示包含 AI 摘要和片段',
        details: _summaryQualityDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '向量索引',
        prefixes: const ['ai.embeddings.'],
        sensitivity: 'high',
        backupPolicy: '可随日记备份，也可恢复后重建',
        deletePolicy: '来源删除或重建时清理',
        exportPolicy: '默认不展示原始向量，开发者模式可导出元数据',
        details: _embeddingIndexDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '今日洞察',
        prefixes: const ['diary.insights.'],
        sensitivity: 'high',
        backupPolicy: '随日记备份',
        deletePolicy: '日记永久删除时清理',
        exportPolicy: '可随洞察导出，需保留来源提示',
        details: _insightDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '长期记忆',
        prefixes: const ['memory.entries.'],
        sensitivity: 'high',
        backupPolicy: '随 AI 记忆备份',
        deletePolicy: '用户删除记忆或来源不足时清理',
        exportPolicy: '普通导出仅摘要，开发者导出含来源链',
        details: _memoryDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '画像偏好',
        prefixes: const ['ai.profilePreferences.'],
        sensitivity: 'medium',
        backupPolicy: '随 AI 设置备份',
        deletePolicy: '目标不存在时清理',
        exportPolicy: '开发者导出含确认、隐藏、修正和合并状态',
        details: _profilePreferenceDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '关系合并历史',
        prefixes: const ['ai.relationshipMergeHistory.'],
        sensitivity: 'medium',
        backupPolicy: '随 AI 设置备份',
        deletePolicy: '保留审计历史，清除 AI 数据时清理',
        exportPolicy: '仅开发者导出',
        details: _relationshipMergeHistoryDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '后台队列',
        prefixes: const ['ai.analysis.jobs.'],
        sensitivity: 'medium',
        backupPolicy: '不要求跨设备恢复，可本地保留',
        deletePolicy: '任务完成、重建或来源删除时清理',
        exportPolicy: '开发者导出任务状态和错误摘要',
        details: _queueDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '调试记录',
        prefixes: const [
          'ai.promptTraces.',
          'ai.retrievalTraces.',
          'ai.feedback.',
        ],
        sensitivity: 'critical',
        backupPolicy: '默认不建议云备份，除非用户明确启用开发者备份',
        deletePolicy: '用户清除调试记录或来源删除时清理',
        exportPolicy: '复制前必须确认，可能包含 prompt、上下文和原始响应',
        details: _debugRecordDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '周期总结',
        prefixes: const ['ai.periodSummaries.', 'period.summaries.'],
        sensitivity: 'high',
        backupPolicy: '随日记备份',
        deletePolicy: '来源日记变更或删除时失效清理',
        exportPolicy: '可随月/年总结导出，开发者模式含来源',
        details: _periodSummaryDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '纪念日',
        prefixes: const ['calendar.memories.'],
        sensitivity: 'medium',
        backupPolicy: '随用户设置备份',
        deletePolicy: '用户删除纪念日时清理',
        exportPolicy: '普通导出可展示名称和日期',
        details: _calendarMemoryDetails(prefs, keys),
      ),
      _section(
        keys,
        label: '塑石行动',
        prefixes: const ['stone.tasks.'],
        sensitivity: 'high',
        backupPolicy: '随日记和行动记录备份',
        deletePolicy: '用户删除行动或来源删除时清理引用',
        exportPolicy: '可随行动记录导出',
        details: _stoneTaskDetails(prefs, keys),
      ),
    ];
    return AiDataInventory(sections: sections);
  }

  AiDataInventorySection _section(
    Set<String> keys, {
    required String label,
    required List<String> prefixes,
    required String sensitivity,
    required String backupPolicy,
    required String deletePolicy,
    required String exportPolicy,
    List<String> details = const [],
  }) {
    final matched = keys
        .where((key) => prefixes.any(key.startsWith))
        .toList(growable: false)
      ..sort();
    return AiDataInventorySection(
      label: label,
      count: matched.length,
      prefixes: prefixes,
      sensitivity: sensitivity,
      backupPolicy: backupPolicy,
      deletePolicy: deletePolicy,
      exportPolicy: exportPolicy,
      details: details,
      sampleKeys: matched.take(5).toList(growable: false),
    );
  }

  List<String> _embeddingIndexDetails(
      SharedPreferences prefs, Set<String> keys) {
    const objectPrefix = 'ai.embeddings.';
    const entryIndexPrefix = 'ai.embeddings.entryIndex.';
    const typeIndexPrefix = 'ai.embeddings.typeIndex.';
    final objectKeys = keys
        .where((key) =>
            key.startsWith(objectPrefix) &&
            !key.startsWith(entryIndexPrefix) &&
            !key.startsWith(typeIndexPrefix))
        .toList(growable: false);
    final entryIndexCount =
        keys.where((key) => key.startsWith(entryIndexPrefix)).length;
    final typeIndexCount =
        keys.where((key) => key.startsWith(typeIndexPrefix)).length;
    final modelCounts = <String, int>{};
    final sourceTypeCounts = <String, int>{};
    final dimensionCounts = <String, int>{};
    var malformed = 0;
    var nonCurrentModel = 0;
    var invalidDimensions = 0;

    for (final key in objectKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformed += 1;
          continue;
        }
        final embedding = AiEmbedding.fromJson(decoded);
        final model = '${embedding.modelId}/${embedding.modelVersion}';
        modelCounts.update(model, (value) => value + 1, ifAbsent: () => 1);
        sourceTypeCounts.update(
          embedding.sourceType.name,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        dimensionCounts.update(
          '${embedding.dimensions}d',
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        if (embedding.modelId != EmbeddingService.modelId ||
            embedding.modelVersion != EmbeddingService.modelVersion) {
          nonCurrentModel += 1;
        }
        if (embedding.dimensions != EmbeddingService.dimensions) {
          invalidDimensions += 1;
        }
      } on Object {
        malformed += 1;
      }
    }

    final details = <String>[
      'objects=${objectKeys.length}',
      'entryIndexes=$entryIndexCount',
      'typeIndexes=$typeIndexCount',
      if (modelCounts.isNotEmpty)
        'models=${_topStringCounts(modelCounts).take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (dimensionCounts.isNotEmpty)
        'dimensions=${_topStringCounts(dimensionCounts).take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (sourceTypeCounts.isNotEmpty)
        'sourceTypes=${_topStringCounts(sourceTypeCounts).take(6).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (malformed > 0) 'malformed=$malformed',
      if (nonCurrentModel > 0) 'staleModel=$nonCurrentModel',
      if (invalidDimensions > 0) 'invalidDimensions=$invalidDimensions',
    ];
    if (objectKeys.isNotEmpty &&
        (entryIndexCount == 0 || typeIndexCount == 0)) {
      details.add('warning=存在缺少 entry/type 索引的向量对象');
    }
    if (nonCurrentModel > 0) {
      details.add('warning=存在非当前模型版本的向量对象');
    }
    if (invalidDimensions > 0) {
      details.add('warning=存在维度不匹配的向量对象');
    }
    return details;
  }

  List<String> _summaryQualityDetails(
    SharedPreferences prefs,
    Set<String> keys,
  ) {
    const summaryPrefix = 'ai.entrySummaries.';
    final summaryKeys = keys
        .where((key) => key.startsWith(summaryPrefix))
        .toList(growable: false)
      ..sort();
    if (summaryKeys.isEmpty) return const [];

    final summaries = <_SummaryQualityRecord>[];
    final warningCounts = <String, int>{};
    var malformed = 0;
    for (final key in summaryKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformed += 1;
          continue;
        }
        final summary = EntrySummary.fromJson(decoded);
        final entryId = summary.entryId.isEmpty
            ? key.substring(summaryPrefix.length)
            : summary.entryId;
        summaries.add(_SummaryQualityRecord(
          id: entryId.isEmpty ? 'unknown' : entryId,
          qualityScore: summary.qualityScore,
          qualityWarnings: summary.qualityWarnings,
        ));
        for (final warning in summary.qualityWarnings) {
          warningCounts.update(warning, (value) => value + 1,
              ifAbsent: () => 1);
        }
        if (entryId.isEmpty) malformed += 1;
      } on Object {
        malformed += 1;
      }
    }
    if (summaries.isEmpty) {
      return [
        'summaryObjects=0',
        if (malformed > 0) 'malformed=$malformed',
      ];
    }

    final lowQuality =
        summaries.where((summary) => summary.qualityScore < 0.55).length;
    final warningSummaries =
        summaries.where((summary) => summary.qualityWarnings.isNotEmpty).length;
    final averageQuality = summaries
            .map((summary) => summary.qualityScore)
            .reduce((a, b) => a + b) /
        summaries.length;
    final sortedByQuality = [...summaries]..sort((a, b) {
        final byQuality = a.qualityScore.compareTo(b.qualityScore);
        if (byQuality != 0) return byQuality;
        return a.id.compareTo(b.id);
      });
    final warningSummary = warningCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return [
      'summaryObjects=${summaries.length}',
      'averageQuality=${averageQuality.toStringAsFixed(2)}',
      'lowQuality=$lowQuality',
      'warningSummaries=$warningSummaries',
      if (malformed > 0) 'malformed=$malformed',
      'worst=${sortedByQuality.first.id}:${sortedByQuality.first.qualityScore.toStringAsFixed(2)}',
      if (warningSummary.isNotEmpty)
        'warnings=${warningSummary.take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
    ];
  }

  List<String> _insightDetails(
    SharedPreferences prefs,
    Set<String> keys,
  ) {
    const prefix = 'diary.insights.';
    const indexKey = 'diary.insights.index';
    const latestKey = 'diary.insights.latest';
    const statusPrefix = 'diary.insights.status.';
    final objectKeys = keys
        .where((key) =>
            key.startsWith(prefix) &&
            key != indexKey &&
            key != latestKey &&
            !key.startsWith(statusPrefix))
        .toList(growable: false)
      ..sort();
    final statusKeys = keys
        .where((key) => key.startsWith(statusPrefix))
        .toList(growable: false)
      ..sort();
    if (objectKeys.isEmpty &&
        statusKeys.isEmpty &&
        !keys.contains(indexKey) &&
        !keys.contains(latestKey)) {
      return const [];
    }

    var facts = 0;
    var signals = 0;
    var hypotheses = 0;
    var suggestions = 0;
    var claimsWithoutEvidence = 0;
    var evidenceItems = 0;
    var relatedMemories = 0;
    var profileCandidates = 0;
    var relationshipCandidates = 0;
    var contradictions = 0;
    var stoneSuggestions = 0;
    var memoryUpdates = 0;
    var invalidRequired = 0;
    var malformed = 0;
    final emotionCounts = <String, int>{};
    final keywordCounts = <String, int>{};
    final peopleCounts = <String, int>{};

    for (final key in objectKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformed += 1;
          continue;
        }
        final insight = DiaryInsight.fromJson(decoded);
        final keyId = key.substring(prefix.length);
        if (insight.entryId.trim().isEmpty ||
            keyId != insight.entryId ||
            insight.reflection.trim().isEmpty) {
          invalidRequired += 1;
        }
        facts += insight.facts.length;
        signals += insight.signals.length;
        hypotheses += insight.hypotheses.length;
        suggestions += insight.suggestions.length;
        final claims = [
          ...insight.facts,
          ...insight.signals,
          ...insight.hypotheses,
          ...insight.suggestions,
        ];
        claimsWithoutEvidence +=
            claims.where((claim) => claim.evidence.isEmpty).length;
        evidenceItems += claims.fold<int>(
          0,
          (total, claim) => total + claim.evidence.length,
        );
        relatedMemories += insight.relatedMemories.length;
        profileCandidates += insight.profileUpdateCandidates.length;
        relationshipCandidates += insight.relationshipUpdates.length;
        contradictions += insight.contradictions.length;
        if (insight.stoneTitle.trim().isNotEmpty ||
            insight.stoneDescription.trim().isNotEmpty) {
          stoneSuggestions += 1;
        }
        if (insight.memorySummary.trim().isNotEmpty ||
            insight.memoryTags.isNotEmpty) {
          memoryUpdates += 1;
        }
        if (insight.emotion.trim().isNotEmpty) {
          emotionCounts.update(insight.emotion, (value) => value + 1,
              ifAbsent: () => 1);
        }
        for (final keyword in insight.keywords) {
          keywordCounts.update(keyword, (value) => value + 1,
              ifAbsent: () => 1);
        }
        for (final person in insight.people) {
          peopleCounts.update(person, (value) => value + 1, ifAbsent: () => 1);
        }
      } on Object {
        malformed += 1;
      }
    }

    final statusCounts = <DiaryAnalysisState, int>{
      for (final state in DiaryAnalysisState.values) state: 0,
    };
    var malformedStatuses = 0;
    var invalidStatuses = 0;
    for (final key in statusKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformedStatuses += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformedStatuses += 1;
          continue;
        }
        final status = DiaryAnalysisStatus.fromJson(decoded);
        statusCounts.update(status.state, (value) => value + 1);
        final keyId = key.substring(statusPrefix.length);
        if (status.entryId.trim().isEmpty || keyId != status.entryId) {
          invalidStatuses += 1;
        }
      } on Object {
        malformedStatuses += 1;
      }
    }

    final indexed = _safeGetInventoryStringList(prefs, indexKey) ?? const [];
    final objectIds =
        objectKeys.map((key) => key.substring(prefix.length)).toSet();
    final staleIndex = indexed.where((id) => !objectIds.contains(id)).length;
    final latest = _safeGetString(prefs, latestKey);
    final latestMissing = latest != null &&
        latest.trim().isNotEmpty &&
        !objectIds.contains(latest);
    return [
      'objects=${objectKeys.length}',
      'indexed=${indexed.length}',
      'statuses=${statusKeys.length}',
      if (latest != null) 'latestSet=${latest.trim().isNotEmpty}',
      'facts=$facts',
      'signals=$signals',
      'hypotheses=$hypotheses',
      'suggestions=$suggestions',
      'evidenceItems=$evidenceItems',
      'claimsWithoutEvidence=$claimsWithoutEvidence',
      'relatedMemories=$relatedMemories',
      'profileCandidates=$profileCandidates',
      'relationshipCandidates=$relationshipCandidates',
      'contradictions=$contradictions',
      'stoneSuggestions=$stoneSuggestions',
      'memoryUpdates=$memoryUpdates',
      if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
      if (malformed > 0) 'malformed=$malformed',
      if (invalidStatuses > 0) 'invalidStatuses=$invalidStatuses',
      if (malformedStatuses > 0) 'malformedStatuses=$malformedStatuses',
      if (staleIndex > 0) 'staleIndex=$staleIndex',
      if (latestMissing) 'latestMissing=true',
      if (statusKeys.isNotEmpty)
        'statusStates=${DiaryAnalysisState.values.where((state) => (statusCounts[state] ?? 0) > 0).map((state) => '${state.name}:${statusCounts[state]}').join(',')}',
      if (emotionCounts.isNotEmpty)
        'topEmotions=${_topStringCounts(emotionCounts).take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (keywordCounts.isNotEmpty)
        'topKeywords=${_topStringCounts(keywordCounts).take(5).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (peopleCounts.isNotEmpty)
        'topPeople=${_topStringCounts(peopleCounts).take(5).map((entry) => '${entry.key}:${entry.value}').join(',')}',
    ];
  }

  List<String> _profilePreferenceDetails(
    SharedPreferences prefs,
    Set<String> keys,
  ) {
    const prefix = 'ai.profilePreferences.';
    const indexKey = 'ai.profilePreferences.index';
    final objectKeys = keys
        .where((key) => key.startsWith(prefix) && key != indexKey)
        .toList(growable: false)
      ..sort();
    if (objectKeys.isEmpty && !keys.contains(indexKey)) return const [];

    var profileFacts = 0;
    var relationships = 0;
    var confirmed = 0;
    var hidden = 0;
    var corrected = 0;
    var merged = 0;
    var invalidTarget = 0;
    var malformed = 0;

    for (final key in objectKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformed += 1;
          continue;
        }
        final item = AiProfilePreference.fromJson(decoded);
        switch (item.targetType) {
          case AiProfilePreferenceTargetType.profileFact:
            profileFacts += 1;
          case AiProfilePreferenceTargetType.relationship:
            relationships += 1;
        }
        if (item.confirmed) confirmed += 1;
        if (item.hidden) hidden += 1;
        if (item.correctedValue.trim().isNotEmpty) corrected += 1;
        if (item.mergedInto.trim().isNotEmpty) merged += 1;
        final keyId = key.substring(prefix.length);
        if (item.targetId.isEmpty ||
            keyId != item.id ||
            (item.mergedInto.trim().isNotEmpty &&
                item.targetType !=
                    AiProfilePreferenceTargetType.relationship)) {
          invalidTarget += 1;
        }
      } on Object {
        malformed += 1;
      }
    }

    final index = _safeGetInventoryStringList(prefs, indexKey) ?? const [];
    final objectIds =
        objectKeys.map((key) => key.substring(prefix.length)).toSet();
    final staleIndex = index.where((id) => !objectIds.contains(id)).length;
    return [
      'objects=${objectKeys.length}',
      'indexed=${index.length}',
      'profileFacts=$profileFacts',
      'relationships=$relationships',
      if (confirmed > 0) 'confirmed=$confirmed',
      if (hidden > 0) 'hidden=$hidden',
      if (corrected > 0) 'corrected=$corrected',
      if (merged > 0) 'merged=$merged',
      if (invalidTarget > 0) 'invalidTarget=$invalidTarget',
      if (malformed > 0) 'malformed=$malformed',
      if (staleIndex > 0) 'staleIndex=$staleIndex',
    ];
  }

  List<String> _memoryDetails(
    SharedPreferences prefs,
    Set<String> keys,
  ) {
    const prefix = 'memory.entries.';
    const indexKey = 'memory.entries.index';
    final objectKeys = keys
        .where((key) => key.startsWith(prefix) && key != indexKey)
        .toList(growable: false)
      ..sort();
    if (objectKeys.isEmpty && !keys.contains(indexKey)) return const [];

    var archived = 0;
    var lowConfidence = 0;
    var highDecay = 0;
    var neverReferenced = 0;
    var missingSource = 0;
    var invalidRequired = 0;
    var malformed = 0;
    var totalEvidenceSources = 0;
    var totalReferences = 0;
    var totalImportance = 0.0;
    var totalConfidence = 0.0;
    final tagCounts = <String, int>{};
    final peopleCounts = <String, int>{};

    for (final key in objectKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformed += 1;
          continue;
        }
        final memory = MemoryEntry.fromJson(decoded);
        if (memory.archived) archived += 1;
        if (memory.confidence < 0.35) lowConfidence += 1;
        if (memory.decay >= 0.5) highDecay += 1;
        if (memory.referenceCount == 0) neverReferenced += 1;
        if (memory.allSourceEntryIds.isEmpty) missingSource += 1;
        final keyId = key.substring(prefix.length);
        if (memory.id.trim().isEmpty ||
            memory.summary.trim().isEmpty ||
            keyId != memory.id) {
          invalidRequired += 1;
        }
        totalEvidenceSources += memory.allSourceEntryIds.length;
        totalReferences += memory.referenceCount;
        totalImportance += memory.importance.clamp(0, 1);
        totalConfidence += memory.confidence.clamp(0, 1);
        for (final tag in memory.tags) {
          tagCounts.update(tag, (value) => value + 1, ifAbsent: () => 1);
        }
        for (final person in memory.people) {
          peopleCounts.update(person, (value) => value + 1, ifAbsent: () => 1);
        }
      } on Object {
        malformed += 1;
      }
    }

    final validCount = objectKeys.length - malformed;
    final averageImportance =
        validCount <= 0 ? 0 : totalImportance / validCount;
    final averageConfidence =
        validCount <= 0 ? 0 : totalConfidence / validCount;
    final index = _safeGetInventoryStringList(prefs, indexKey) ?? const [];
    final objectIds =
        objectKeys.map((key) => key.substring(prefix.length)).toSet();
    final staleIndex = index.where((id) => !objectIds.contains(id)).length;
    final topTags = tagCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    final topPeople = peopleCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return [
      'objects=${objectKeys.length}',
      'indexed=${index.length}',
      'archived=$archived',
      'lowConfidence=$lowConfidence',
      'highDecay=$highDecay',
      'neverReferenced=$neverReferenced',
      'evidenceSources=$totalEvidenceSources',
      'references=$totalReferences',
      'averageImportance=${averageImportance.toStringAsFixed(2)}',
      'averageConfidence=${averageConfidence.toStringAsFixed(2)}',
      if (missingSource > 0) 'missingSource=$missingSource',
      if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
      if (malformed > 0) 'malformed=$malformed',
      if (staleIndex > 0) 'staleIndex=$staleIndex',
      if (topTags.isNotEmpty)
        'topTags=${topTags.take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (topPeople.isNotEmpty)
        'topPeople=${topPeople.take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
    ];
  }

  List<String> _queueDetails(
    SharedPreferences prefs,
    Set<String> keys,
  ) {
    const prefix = 'ai.analysis.jobs.';
    const indexKey = 'ai.analysis.jobs.index';
    const pausedKey = 'ai.analysis.jobs.paused';
    final objectKeys = keys
        .where((key) =>
            key.startsWith(prefix) && key != indexKey && key != pausedKey)
        .toList(growable: false)
      ..sort();
    if (objectKeys.isEmpty &&
        !keys.contains(indexKey) &&
        !keys.contains(pausedKey)) {
      return const [];
    }

    final stateCounts = <AiAnalysisJobState, int>{
      for (final state in AiAnalysisJobState.values) state: 0,
    };
    final stageCounts = <AiAnalysisStage, int>{};
    final batchIds = <String>{};
    var retryableFailed = 0;
    var blockedFailed = 0;
    var retrying = 0;
    var jobsWithError = 0;
    var stageLogs = 0;
    var stageLogErrors = 0;
    var artifactRefs = 0;
    var invalidRequired = 0;
    var malformed = 0;

    for (final key in objectKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformed += 1;
          continue;
        }
        final job = AiAnalysisJob.fromJson(decoded);
        stateCounts.update(job.state, (value) => value + 1);
        stageCounts.update(job.currentStage, (value) => value + 1,
            ifAbsent: () => 1);
        if (job.state == AiAnalysisJobState.failed) {
          if (job.canRun) {
            retryableFailed += 1;
          } else {
            blockedFailed += 1;
          }
        }
        if (job.retryCount > 0) retrying += 1;
        if ((job.lastError ?? '').trim().isNotEmpty) jobsWithError += 1;
        stageLogs += job.stageLogs.length;
        stageLogErrors += job.stageLogs
            .where((log) => (log.error ?? '').trim().isNotEmpty)
            .length;
        artifactRefs += [
          job.summaryId,
          job.insightId,
          job.retrievalTraceId,
          ...job.segmentIds,
          ...job.embeddingIds,
        ].where((value) => (value ?? '').trim().isNotEmpty).length;
        final batchId = job.batchId?.trim() ?? '';
        if (batchId.isNotEmpty) batchIds.add(batchId);
        final keyId = key.substring(prefix.length);
        if (job.id.trim().isEmpty ||
            job.entryId.trim().isEmpty ||
            keyId != job.id) {
          invalidRequired += 1;
        }
      } on Object {
        malformed += 1;
      }
    }

    final index = _safeGetInventoryStringList(prefs, indexKey) ?? const [];
    final objectIds =
        objectKeys.map((key) => key.substring(prefix.length)).toSet();
    final staleIndex = index.where((id) => !objectIds.contains(id)).length;
    final topStages = stageCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.name.compareTo(b.key.name);
      });
    final paused = _safeGetInventoryBool(prefs, pausedKey);
    return [
      'objects=${objectKeys.length}',
      'indexed=${index.length}',
      if (paused != null) 'paused=$paused',
      'pending=${stateCounts[AiAnalysisJobState.pending] ?? 0}',
      'running=${stateCounts[AiAnalysisJobState.running] ?? 0}',
      'incomplete=${stateCounts[AiAnalysisJobState.incomplete] ?? 0}',
      'failed=${stateCounts[AiAnalysisJobState.failed] ?? 0}',
      'completed=${stateCounts[AiAnalysisJobState.completed] ?? 0}',
      'retryableFailed=$retryableFailed',
      'blockedFailed=$blockedFailed',
      'retrying=$retrying',
      'batches=${batchIds.length}',
      'stageLogs=$stageLogs',
      'stageLogErrors=$stageLogErrors',
      'jobsWithError=$jobsWithError',
      'artifactRefs=$artifactRefs',
      if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
      if (malformed > 0) 'malformed=$malformed',
      if (staleIndex > 0) 'staleIndex=$staleIndex',
      if (topStages.isNotEmpty)
        'topStages=${topStages.take(4).map((entry) => '${entry.key.name}:${entry.value}').join(',')}',
    ];
  }

  List<String> _periodSummaryDetails(
    SharedPreferences prefs,
    Set<String> keys,
  ) {
    const prefix = 'ai.periodSummaries.';
    const legacyPrefix = 'period.summaries.';
    final objectKeys = keys
        .where((key) => key.startsWith(prefix) || key.startsWith(legacyPrefix))
        .toList(growable: false)
      ..sort();
    if (objectKeys.isEmpty) return const [];

    final typeCounts = <PeriodSummaryType, int>{
      for (final type in PeriodSummaryType.values) type: 0,
    };
    final generatorCounts = <String, int>{};
    final themeCounts = <String, int>{};
    final emotionCounts = <String, int>{};
    var legacyObjects = 0;
    var emptyBrief = 0;
    var missingRepresentatives = 0;
    var invalidRequired = 0;
    var malformed = 0;
    var entryCount = 0;
    var representativeRefs = 0;
    var contextLines = 0;
    var relationshipHighlights = 0;
    var stoneHighlights = 0;

    for (final key in objectKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformed += 1;
          continue;
        }
        final summary = PeriodSummary.fromJson(decoded);
        typeCounts.update(summary.type, (value) => value + 1);
        if (key.startsWith(legacyPrefix)) legacyObjects += 1;
        if (summary.brief.trim().isEmpty) emptyBrief += 1;
        if (summary.representativeEntryIds.isEmpty && summary.entryCount > 0) {
          missingRepresentatives += 1;
        }
        final keyId = key.startsWith(prefix)
            ? key.substring(prefix.length)
            : key.substring(legacyPrefix.length);
        if (summary.id.trim().isEmpty ||
            keyId != summary.id ||
            summary.endDate.isBefore(summary.startDate)) {
          invalidRequired += 1;
        }
        entryCount += summary.entryCount;
        representativeRefs += summary.representativeEntryIds.length;
        contextLines += summary.contextSourceLines.length;
        relationshipHighlights += summary.relationshipHighlights.length;
        stoneHighlights += summary.stoneHighlights.length;
        final generator = summary.generator.trim();
        if (generator.isNotEmpty) {
          generatorCounts.update(generator, (value) => value + 1,
              ifAbsent: () => 1);
        }
        for (final theme in summary.themes) {
          themeCounts.update(theme, (value) => value + 1, ifAbsent: () => 1);
        }
        for (final emotion in summary.emotions) {
          emotionCounts.update(emotion, (value) => value + 1,
              ifAbsent: () => 1);
        }
      } on Object {
        malformed += 1;
      }
    }

    final topGenerators = _topStringCounts(generatorCounts);
    final topThemes = _topStringCounts(themeCounts);
    final topEmotions = _topStringCounts(emotionCounts);
    return [
      'objects=${objectKeys.length}',
      'months=${typeCounts[PeriodSummaryType.month] ?? 0}',
      'years=${typeCounts[PeriodSummaryType.year] ?? 0}',
      'entryCount=$entryCount',
      'representativeRefs=$representativeRefs',
      'contextLines=$contextLines',
      'relationshipHighlights=$relationshipHighlights',
      'stoneHighlights=$stoneHighlights',
      if (legacyObjects > 0) 'legacyObjects=$legacyObjects',
      if (emptyBrief > 0) 'emptyBrief=$emptyBrief',
      if (missingRepresentatives > 0)
        'missingRepresentatives=$missingRepresentatives',
      if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
      if (malformed > 0) 'malformed=$malformed',
      if (topGenerators.isNotEmpty)
        'generators=${topGenerators.take(3).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (topThemes.isNotEmpty)
        'topThemes=${topThemes.take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (topEmotions.isNotEmpty)
        'topEmotions=${topEmotions.take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
    ];
  }

  List<String> _debugRecordDetails(
    SharedPreferences prefs,
    Set<String> keys,
  ) {
    const promptPrefix = 'ai.promptTraces.';
    const retrievalPrefix = 'ai.retrievalTraces.';
    const feedbackPrefix = 'ai.feedback.';
    final promptKeys = keys
        .where((key) => key.startsWith(promptPrefix))
        .toList(growable: false)
      ..sort();
    final retrievalKeys = keys
        .where((key) => key.startsWith(retrievalPrefix))
        .toList(growable: false)
      ..sort();
    final feedbackKeys = keys
        .where((key) => key.startsWith(feedbackPrefix))
        .toList(growable: false)
      ..sort();
    if (promptKeys.isEmpty && retrievalKeys.isEmpty && feedbackKeys.isEmpty) {
      return const [];
    }

    var promptMalformed = 0;
    var promptInvalidRequired = 0;
    var fullPromptStored = 0;
    var rawResponsesStored = 0;
    var totalSystemPromptLength = 0;
    var totalUserPromptLength = 0;
    final promptScenarios = <String, int>{};
    for (final key in promptKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        promptMalformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          promptMalformed += 1;
          continue;
        }
        final trace = AiPromptTrace.fromJson(decoded);
        final keyId = key.substring(promptPrefix.length);
        if (trace.id.trim().isEmpty ||
            trace.scenario.trim().isEmpty ||
            keyId != trace.id) {
          promptInvalidRequired += 1;
        }
        if ((trace.systemPrompt ?? '').isNotEmpty ||
            (trace.userPrompt ?? '').isNotEmpty) {
          fullPromptStored += 1;
        }
        if ((trace.rawResponse ?? '').isNotEmpty ||
            trace.rawResponseLength > 0 ||
            trace.rawResponsePreview.isNotEmpty) {
          rawResponsesStored += 1;
        }
        totalSystemPromptLength += trace.systemPromptLength;
        totalUserPromptLength += trace.userPromptLength;
        promptScenarios.update(trace.scenario, (value) => value + 1,
            ifAbsent: () => 1);
      } on Object {
        promptMalformed += 1;
      }
    }

    var retrievalMalformed = 0;
    var retrievalInvalidRequired = 0;
    var retrievalItems = 0;
    var retrievalSourceCount = 0;
    var retrievalSignals = 0;
    final retrievalScenarios = <String, int>{};
    final sourceTypes = <String, int>{};
    final signalTypes = <String, int>{};
    for (final key in retrievalKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        retrievalMalformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          retrievalMalformed += 1;
          continue;
        }
        final trace = AiRetrievalTrace.fromJson(decoded);
        final keyId = key.substring(retrievalPrefix.length);
        if (trace.entryId.trim().isEmpty || keyId != trace.entryId) {
          retrievalInvalidRequired += 1;
        }
        retrievalItems += trace.items.length;
        retrievalSourceCount += trace.sourceCount;
        final scenario = trace.scenario?.trim() ?? '';
        if (scenario.isNotEmpty) {
          retrievalScenarios.update(scenario, (value) => value + 1,
              ifAbsent: () => 1);
        }
        for (final item in trace.items) {
          if (item.sourceType.trim().isNotEmpty) {
            sourceTypes.update(item.sourceType, (value) => value + 1,
                ifAbsent: () => 1);
          }
          retrievalSignals += item.rerankSignals.length;
          for (final signal in item.rerankSignals.keys) {
            signalTypes.update(signal, (value) => value + 1, ifAbsent: () => 1);
          }
        }
      } on Object {
        retrievalMalformed += 1;
      }
    }

    var feedbackMalformed = 0;
    var feedbackInvalidRequired = 0;
    var feedbackWithNote = 0;
    var feedbackWithPreviousInsight = 0;
    var feedbackPreviousSources = 0;
    var inaccurateFeedbackWithoutContext = 0;
    final feedbackValues = <String, int>{};
    for (final key in feedbackKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        feedbackMalformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          feedbackMalformed += 1;
          continue;
        }
        final feedback = AiFeedback.fromJson(decoded);
        final keyId = key.substring(feedbackPrefix.length);
        if (feedback.entryId.trim().isEmpty || keyId != feedback.entryId) {
          feedbackInvalidRequired += 1;
        }
        if ((feedback.note ?? '').trim().isNotEmpty) feedbackWithNote += 1;
        final hasPreviousInsight =
            (feedback.previousInsightSummary ?? '').trim().isNotEmpty;
        if (hasPreviousInsight) feedbackWithPreviousInsight += 1;
        feedbackPreviousSources += feedback.previousInsightSources.length;
        if (feedback.value == AiFeedbackValue.inaccurate &&
            !hasPreviousInsight &&
            feedback.previousInsightSources.isEmpty) {
          inaccurateFeedbackWithoutContext += 1;
        }
        feedbackValues.update(feedback.value.name, (value) => value + 1,
            ifAbsent: () => 1);
      } on Object {
        feedbackMalformed += 1;
      }
    }

    final promptCount = promptKeys.length - promptMalformed;
    final averagePromptLength = promptCount <= 0
        ? 0
        : (totalSystemPromptLength + totalUserPromptLength) / promptCount;
    final malformed = promptMalformed + retrievalMalformed + feedbackMalformed;
    final invalidRequired = promptInvalidRequired +
        retrievalInvalidRequired +
        feedbackInvalidRequired;
    return [
      'promptTraces=${promptKeys.length}',
      'retrievalTraces=${retrievalKeys.length}',
      'feedback=${feedbackKeys.length}',
      'fullPromptStored=$fullPromptStored',
      'rawResponsesStored=$rawResponsesStored',
      'averagePromptLength=${averagePromptLength.toStringAsFixed(0)}',
      'retrievalItems=$retrievalItems',
      'retrievalSourceCount=$retrievalSourceCount',
      'retrievalSignals=$retrievalSignals',
      'feedbackWithNote=$feedbackWithNote',
      'feedbackWithPreviousInsight=$feedbackWithPreviousInsight',
      'feedbackPreviousSources=$feedbackPreviousSources',
      if (inaccurateFeedbackWithoutContext > 0)
        'inaccurateFeedbackWithoutContext=$inaccurateFeedbackWithoutContext',
      if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
      if (malformed > 0) 'malformed=$malformed',
      if (promptScenarios.isNotEmpty)
        'promptScenarios=${_topStringCounts(promptScenarios).take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (retrievalScenarios.isNotEmpty)
        'retrievalScenarios=${_topStringCounts(retrievalScenarios).take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (sourceTypes.isNotEmpty)
        'sourceTypes=${_topStringCounts(sourceTypes).take(5).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (signalTypes.isNotEmpty)
        'signalTypes=${_topStringCounts(signalTypes).take(5).map((entry) => '${entry.key}:${entry.value}').join(',')}',
      if (feedbackValues.isNotEmpty)
        'feedbackValues=${_topStringCounts(feedbackValues).take(3).map((entry) => '${entry.key}:${entry.value}').join(',')}',
    ];
  }

  List<String> _relationshipMergeHistoryDetails(
    SharedPreferences prefs,
    Set<String> keys,
  ) {
    const prefix = 'ai.relationshipMergeHistory.';
    const indexKey = 'ai.relationshipMergeHistory.index';
    final objectKeys = keys
        .where((key) => key.startsWith(prefix) && key != indexKey)
        .toList(growable: false)
      ..sort();
    if (objectKeys.isEmpty && !keys.contains(indexKey)) return const [];

    var merges = 0;
    var undos = 0;
    var invalidRequired = 0;
    var malformed = 0;
    final pairCounts = <String, int>{};

    for (final key in objectKeys) {
      final raw = _safeGetString(prefs, key);
      if (raw == null) {
        malformed += 1;
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          malformed += 1;
          continue;
        }
        final item = AiRelationshipMergeEvent.fromJson(decoded);
        switch (item.action) {
          case AiRelationshipMergeEventAction.merge:
            merges += 1;
          case AiRelationshipMergeEventAction.undo:
            undos += 1;
        }
        final source = item.sourcePersonName.trim();
        final target = item.targetPersonName.trim();
        final keyId = key.substring(prefix.length);
        if (item.id.isEmpty ||
            source.isEmpty ||
            target.isEmpty ||
            keyId != item.id ||
            source.toLowerCase() == target.toLowerCase()) {
          invalidRequired += 1;
        }
        if (source.isNotEmpty && target.isNotEmpty) {
          final pair = '$source->$target';
          pairCounts.update(pair, (value) => value + 1, ifAbsent: () => 1);
        }
      } on Object {
        malformed += 1;
      }
    }

    final index = _safeGetInventoryStringList(prefs, indexKey) ?? const [];
    final objectIds =
        objectKeys.map((key) => key.substring(prefix.length)).toSet();
    final staleIndex = index.where((id) => !objectIds.contains(id)).length;
    final topPairs = pairCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return [
      'objects=${objectKeys.length}',
      'indexed=${index.length}',
      'merges=$merges',
      'undos=$undos',
      if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
      if (malformed > 0) 'malformed=$malformed',
      if (staleIndex > 0) 'staleIndex=$staleIndex',
      if (topPairs.isNotEmpty)
        'topPairs=${topPairs.take(3).map((entry) => '${entry.key}:${entry.value}').join(',')}',
    ];
  }

  String? _safeGetString(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is String ? value : null;
    } on Object {
      return null;
    }
  }
}

List<String> _calendarMemoryDetails(
  SharedPreferences prefs,
  Set<String> keys,
) {
  const prefix = 'calendar.memories.';
  const indexKey = 'calendar.memories.index';
  final objectKeys = keys
      .where((key) => key.startsWith(prefix) && key != indexKey)
      .toList(growable: false)
    ..sort();
  if (objectKeys.isEmpty && !keys.contains(indexKey)) return const [];

  var solar = 0;
  var lunar = 0;
  var disabled = 0;
  var invalidRequired = 0;
  var malformed = 0;
  final monthBuckets = <String, int>{};

  for (final key in objectKeys) {
    final raw = _safeGetInventoryString(prefs, key);
    if (raw == null) {
      malformed += 1;
      continue;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        malformed += 1;
        continue;
      }
      final memory = CalendarMemory.fromJson(decoded);
      switch (memory.type) {
        case CalendarMemoryType.solar:
          solar += 1;
        case CalendarMemoryType.lunar:
          lunar += 1;
      }
      if (!memory.enabled) disabled += 1;
      if (memory.id.trim().isEmpty || memory.title.trim().isEmpty) {
        invalidRequired += 1;
      }
      final monthKey = '${memory.type.name}-${memory.month}';
      monthBuckets.update(monthKey, (value) => value + 1, ifAbsent: () => 1);
    } on Object {
      malformed += 1;
    }
  }

  final densestMonths = monthBuckets.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  final indexed = _safeGetInventoryStringList(prefs, indexKey)?.length ?? 0;
  return [
    'objects=${objectKeys.length}',
    'indexed=$indexed',
    'solar=$solar',
    'lunar=$lunar',
    if (disabled > 0) 'disabled=$disabled',
    if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
    if (malformed > 0) 'malformed=$malformed',
    if (densestMonths.isNotEmpty)
      'topMonths=${densestMonths.take(3).map((entry) => '${entry.key}:${entry.value}').join(',')}',
  ];
}

String? _safeGetInventoryString(SharedPreferences prefs, String key) {
  try {
    final value = prefs.get(key);
    return value is String ? value : null;
  } on Object {
    return null;
  }
}

List<String>? _safeGetInventoryStringList(SharedPreferences prefs, String key) {
  try {
    final value = prefs.get(key);
    if (value is List<String>) return List<String>.from(value);
    if (value is List) return value.whereType<String>().toList();
    return null;
  } on Object {
    return null;
  }
}

bool? _safeGetInventoryBool(SharedPreferences prefs, String key) {
  try {
    final value = prefs.get(key);
    return value is bool ? value : null;
  } on Object {
    return null;
  }
}

List<MapEntry<String, int>> _topStringCounts(Map<String, int> counts) {
  return counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
}

List<String> _stoneTaskDetails(
  SharedPreferences prefs,
  Set<String> keys,
) {
  const prefix = 'stone.tasks.';
  const indexKey = 'stone.tasks.index';
  final objectKeys = keys
      .where((key) => key.startsWith(prefix) && key != indexKey)
      .toList(growable: false)
    ..sort();
  if (objectKeys.isEmpty && !keys.contains(indexKey)) return const [];

  final statusCounts = <StoneTaskStatus, int>{
    for (final status in StoneTaskStatus.values) status: 0,
  };
  var checkIns = 0;
  var sourcedTasks = 0;
  var sourcedCheckIns = 0;
  var missingSource = 0;
  var invalidRequired = 0;
  var malformed = 0;
  final tagCounts = <String, int>{};

  for (final key in objectKeys) {
    final raw = _safeGetInventoryString(prefs, key);
    if (raw == null) {
      malformed += 1;
      continue;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        malformed += 1;
        continue;
      }
      final task = StoneTask.fromJson(decoded);
      statusCounts.update(task.status, (value) => value + 1);
      checkIns += task.checkIns.length;
      if (task.sourceEntryId.trim().isEmpty) {
        missingSource += 1;
      } else {
        sourcedTasks += 1;
      }
      sourcedCheckIns += task.checkIns
          .where((item) => (item.sourceEntryId ?? '').trim().isNotEmpty)
          .length;
      if (task.id.trim().isEmpty || task.title.trim().isEmpty) {
        invalidRequired += 1;
      }
      for (final tag in task.tags) {
        tagCounts.update(tag, (value) => value + 1, ifAbsent: () => 1);
      }
    } on Object {
      malformed += 1;
    }
  }

  final topTags = tagCounts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  final indexed = _safeGetInventoryStringList(prefs, indexKey)?.length ?? 0;
  return [
    'objects=${objectKeys.length}',
    'indexed=$indexed',
    'active=${statusCounts[StoneTaskStatus.active] ?? 0}',
    'completed=${statusCounts[StoneTaskStatus.completed] ?? 0}',
    'archived=${statusCounts[StoneTaskStatus.archived] ?? 0}',
    'checkIns=$checkIns',
    'sourcedTasks=$sourcedTasks',
    'sourcedCheckIns=$sourcedCheckIns',
    if (missingSource > 0) 'missingSource=$missingSource',
    if (invalidRequired > 0) 'invalidRequired=$invalidRequired',
    if (malformed > 0) 'malformed=$malformed',
    if (topTags.isNotEmpty)
      'topTags=${topTags.take(4).map((entry) => '${entry.key}:${entry.value}').join(',')}',
  ];
}

class _SummaryQualityRecord {
  const _SummaryQualityRecord({
    required this.id,
    required this.qualityScore,
    required this.qualityWarnings,
  });

  final String id;
  final double qualityScore;
  final List<String> qualityWarnings;
}

class AiDataInventory {
  const AiDataInventory({required this.sections});

  final List<AiDataInventorySection> sections;

  int get totalCount =>
      sections.fold(0, (total, section) => total + section.count);

  int get highSensitivitySectionCount => sections
      .where((section) =>
          section.count > 0 &&
          (section.sensitivity == 'high' || section.sensitivity == 'critical'))
      .length;

  int get reviewSectionCount =>
      sections.where((section) => section.needsReview).length;

  String toDebugText({
    String? scope,
    Iterable<AiDataInventorySection>? selectedSections,
  }) {
    final exportSections =
        selectedSections?.toList(growable: false) ?? sections;
    final exportTotal =
        exportSections.fold(0, (total, section) => total + section.count);
    return [
      '## TraceStone AI Data Inventory',
      'total=$exportTotal',
      if (scope != null && scope.isNotEmpty) 'scope=$scope',
      'policy=AI 衍生数据默认视为日记数据的一部分，应随日记一起备份、删除和保护。',
      '',
      for (final section in exportSections) ...[
        section.toDebugText(),
        '',
      ],
    ].join('\n');
  }
}

class AiDataInventorySection {
  const AiDataInventorySection({
    required this.label,
    required this.count,
    required this.prefixes,
    required this.sensitivity,
    required this.backupPolicy,
    required this.deletePolicy,
    required this.exportPolicy,
    this.details = const [],
    required this.sampleKeys,
  });

  final String label;
  final int count;
  final List<String> prefixes;
  final String sensitivity;
  final String backupPolicy;
  final String deletePolicy;
  final String exportPolicy;
  final List<String> details;
  final List<String> sampleKeys;

  bool get isHighSensitivity =>
      count > 0 && (sensitivity == 'high' || sensitivity == 'critical');

  bool get needsReview => details.any((detail) {
        return detail.startsWith('warning=') ||
            detail.startsWith('malformed=') ||
            detail.startsWith('invalid') ||
            detail.startsWith('missing') ||
            detail.startsWith('stale') ||
            detail.startsWith('lowQuality=') ||
            detail.startsWith('lowConfidence=') ||
            detail.startsWith('highDecay=') ||
            detail.startsWith('claimsWithoutEvidence=') ||
            detail.startsWith('inaccurateFeedbackWithoutContext=');
      });

  int get reviewDetailCount => details.where((detail) {
        return detail.startsWith('warning=') ||
            detail.startsWith('malformed=') ||
            detail.startsWith('invalid') ||
            detail.startsWith('missing') ||
            detail.startsWith('stale') ||
            detail.startsWith('lowQuality=') ||
            detail.startsWith('lowConfidence=') ||
            detail.startsWith('highDecay=') ||
            detail.startsWith('claimsWithoutEvidence=') ||
            detail.startsWith('inaccurateFeedbackWithoutContext=');
      }).length;

  String toDebugText() {
    return [
      '### $label',
      'count=$count',
      'sensitivity=$sensitivity',
      'backupPolicy=$backupPolicy',
      'deletePolicy=$deletePolicy',
      'exportPolicy=$exportPolicy',
      if (details.isNotEmpty) 'details=${details.join(';')}',
      'prefixes=${prefixes.join(',')}',
      if (sampleKeys.isNotEmpty) 'sampleKeys=${sampleKeys.join(',')}',
    ].join('\n');
  }
}
