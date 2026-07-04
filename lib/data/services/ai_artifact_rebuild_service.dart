import '../models/ai_analysis_job.dart';
import '../models/ai_embedding.dart';
import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../models/diary_segment.dart';
import '../models/entry_summary.dart';
import '../repositories/ai_analysis_queue_repository.dart';
import '../repositories/ai_embedding_repository.dart';
import '../repositories/ai_prompt_trace_repository.dart';
import '../repositories/ai_retrieval_trace_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import '../repositories/insight_repository.dart';
import 'ai_embedding_text_builder.dart';
import 'diary_analysis_service.dart';
import 'embedding_service.dart';
import 'entry_summary_service.dart';

enum AiArtifactRebuildTarget {
  summaryPackage,
  embeddings,
  insight,
}

class AiArtifactRebuildResult {
  const AiArtifactRebuildResult({
    required this.entryId,
    required this.target,
    required this.message,
    this.summaryId,
    this.segmentIds = const [],
    this.embeddingIds = const [],
    this.insightId,
  });

  final String entryId;
  final AiArtifactRebuildTarget target;
  final String message;
  final String? summaryId;
  final List<String> segmentIds;
  final List<String> embeddingIds;
  final String? insightId;
}

class AiArtifactBulkRebuildResult {
  const AiArtifactBulkRebuildResult({
    required this.target,
    required this.requestedEntryIds,
    required this.rebuiltEntryIds,
    required this.embeddingIds,
    required this.skippedEntryIds,
  });

  final AiArtifactRebuildTarget target;
  final List<String> requestedEntryIds;
  final List<String> rebuiltEntryIds;
  final List<String> embeddingIds;
  final List<String> skippedEntryIds;

  String get summary =>
      'entries=${rebuiltEntryIds.length}/${requestedEntryIds.length} '
      'embeddings=${embeddingIds.length} skipped=${skippedEntryIds.length}';
}

class AiArtifactRebuildService {
  const AiArtifactRebuildService({
    DiaryRepository? diaryRepository,
    EntrySummaryRepository? summaryRepository,
    AiEmbeddingRepository? embeddingRepository,
    InsightRepository? insightRepository,
    AiAnalysisQueueRepository? queueRepository,
    AiPromptTraceRepository? promptTraceRepository,
    AiRetrievalTraceRepository? retrievalTraceRepository,
    EntrySummaryService? summaryService,
    EmbeddingService? embeddingService,
    AiEmbeddingTextBuilder? embeddingTextBuilder,
    DiaryAnalysisService? analysisService,
  })  : _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _summaryRepository =
            summaryRepository ?? const EntrySummaryRepository(),
        _embeddingRepository =
            embeddingRepository ?? const AiEmbeddingRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _queueRepository = queueRepository ?? const AiAnalysisQueueRepository(),
        _promptTraceRepository =
            promptTraceRepository ?? const AiPromptTraceRepository(),
        _retrievalTraceRepository =
            retrievalTraceRepository ?? const AiRetrievalTraceRepository(),
        _summaryService = summaryService ?? const EntrySummaryService(),
        _embeddingService = embeddingService ?? const EmbeddingService(),
        _embeddingTextBuilder =
            embeddingTextBuilder ?? const AiEmbeddingTextBuilder(),
        _analysisService = analysisService ?? const DiaryAnalysisService();

  final DiaryRepository _diaryRepository;
  final EntrySummaryRepository _summaryRepository;
  final AiEmbeddingRepository _embeddingRepository;
  final InsightRepository _insightRepository;
  final AiAnalysisQueueRepository _queueRepository;
  final AiPromptTraceRepository _promptTraceRepository;
  final AiRetrievalTraceRepository _retrievalTraceRepository;
  final EntrySummaryService _summaryService;
  final EmbeddingService _embeddingService;
  final AiEmbeddingTextBuilder _embeddingTextBuilder;
  final DiaryAnalysisService _analysisService;

  Future<AiArtifactRebuildResult?> rebuildSummaryPackage(String entryId) async {
    final entry = await _diaryRepository.getEntryById(entryId);
    if (entry == null || entry.content.trim().isEmpty) return null;
    final segments = _summaryService.buildSegments(entry);
    final summary = _summaryService.buildSummary(entry, segments);
    await _summaryRepository.saveSegments(entry.id, segments);
    await _summaryRepository.saveSummary(summary);
    final embeddingIds = await _saveEmbeddings(entry, summary, segments);
    await _appendJobLog(
      entry: entry,
      stage: AiAnalysisStage.generatingSummary,
      message: '开发者重建摘要包和日记片段',
      outputSummary:
          'summary=${summary.entryId} segments=${segments.length} embeddings=${embeddingIds.length}',
      summaryId: summary.entryId,
      segmentIds: segments.map((segment) => segment.id).toList(),
      embeddingIds: embeddingIds,
    );
    await _saveStatus(entry.id, '已重建摘要包、日记片段和关联向量');
    return AiArtifactRebuildResult(
      entryId: entry.id,
      target: AiArtifactRebuildTarget.summaryPackage,
      message: '已重建摘要包、日记片段和关联向量',
      summaryId: summary.entryId,
      segmentIds: segments.map((segment) => segment.id).toList(),
      embeddingIds: embeddingIds,
    );
  }

  Future<AiArtifactRebuildResult?> rebuildEmbeddings(String entryId) async {
    final entry = await _diaryRepository.getEntryById(entryId);
    if (entry == null || entry.content.trim().isEmpty) return null;
    final artifacts = await _ensureSummaryArtifacts(entry);
    final embeddingIds =
        await _saveEmbeddings(entry, artifacts.summary, artifacts.segments);
    await _appendJobLog(
      entry: entry,
      stage: AiAnalysisStage.embedding,
      message: '开发者重建多级向量',
      outputSummary: 'embeddings=${embeddingIds.length}',
      summaryId: artifacts.summary.entryId,
      segmentIds: artifacts.segments.map((segment) => segment.id).toList(),
      embeddingIds: embeddingIds,
    );
    await _saveStatus(entry.id, '已重建多级向量');
    return AiArtifactRebuildResult(
      entryId: entry.id,
      target: AiArtifactRebuildTarget.embeddings,
      message: '已重建多级向量',
      summaryId: artifacts.summary.entryId,
      segmentIds: artifacts.segments.map((segment) => segment.id).toList(),
      embeddingIds: embeddingIds,
    );
  }

  Future<AiArtifactBulkRebuildResult> rebuildOutdatedEmbeddings() async {
    final entryIds = await _embeddingRepository.listOutdatedEntryIds(
      modelId: EmbeddingService.modelId,
      modelVersion: EmbeddingService.modelVersion,
      dimensions: EmbeddingService.dimensions,
    );
    final rebuiltEntryIds = <String>[];
    final embeddingIds = <String>[];
    final skippedEntryIds = <String>[];

    for (final entryId in entryIds) {
      final result = await rebuildEmbeddings(entryId);
      if (result == null) {
        skippedEntryIds.add(entryId);
        continue;
      }
      rebuiltEntryIds.add(entryId);
      embeddingIds.addAll(result.embeddingIds);
    }

    return AiArtifactBulkRebuildResult(
      target: AiArtifactRebuildTarget.embeddings,
      requestedEntryIds: entryIds,
      rebuiltEntryIds: rebuiltEntryIds,
      embeddingIds: embeddingIds,
      skippedEntryIds: skippedEntryIds,
    );
  }

  Future<AiArtifactRebuildResult?> rebuildInsight(String entryId) async {
    final entry = await _diaryRepository.getEntryById(entryId);
    if (entry == null || entry.content.trim().isEmpty) return null;
    await _ensureSummaryArtifacts(entry);
    await _insightRepository.deleteForEntry(entry.id);
    await _promptTraceRepository.deleteTrace(entry.id);
    await _retrievalTraceRepository.deleteForEntry(entry.id);
    final insight = await _analysisService.analyzeEntry(entry);
    await _appendJobLog(
      entry: entry,
      stage: AiAnalysisStage.generatingInsight,
      message: '开发者重建今日洞察',
      outputSummary:
          'insight=${insight.entryId} facts=${insight.facts.length} suggestions=${insight.suggestions.length}',
      insightId: insight.entryId,
      retrievalTraceId: entry.id,
    );
    await _saveStatus(entry.id, '已重建今日洞察');
    return AiArtifactRebuildResult(
      entryId: entry.id,
      target: AiArtifactRebuildTarget.insight,
      message: '已重建今日洞察',
      insightId: insight.entryId,
    );
  }

  Future<_SummaryArtifacts> _ensureSummaryArtifacts(DiaryEntry entry) async {
    var segments = await _summaryRepository.listSegments(entry.id);
    var summary = await _summaryRepository.getSummary(entry.id);
    final stale = summary != null &&
        !summary.entryUpdatedAt.isAtSameMomentAs(entry.updatedAt);
    if (segments.isEmpty || summary == null || stale) {
      segments = _summaryService.buildSegments(entry);
      summary = _summaryService.buildSummary(entry, segments);
      await _summaryRepository.saveSegments(entry.id, segments);
      await _summaryRepository.saveSummary(summary);
    }
    return _SummaryArtifacts(summary: summary, segments: segments);
  }

  Future<List<String>> _saveEmbeddings(
    DiaryEntry entry,
    EntrySummary summary,
    List<DiarySegment> segments,
  ) async {
    await _embeddingRepository.deleteForEntry(entry.id);
    final ids = <String>[];
    ids.add(await _saveEmbedding(
      entryId: entry.id,
      sourceType: AiEmbeddingSourceType.entry,
      sourceId: entry.id,
      text: _embeddingTextBuilder.entryText(entry, summary),
    ));
    ids.add(await _saveEmbedding(
      entryId: entry.id,
      sourceType: AiEmbeddingSourceType.summary,
      sourceId: entry.id,
      text: _embeddingTextBuilder.summaryText(summary),
    ));
    for (final segment in segments) {
      ids.add(await _saveEmbedding(
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.segment,
        sourceId: segment.id,
        text: _embeddingTextBuilder.segmentText(segment),
      ));
    }
    return ids;
  }

  Future<String> _saveEmbedding({
    required String entryId,
    required AiEmbeddingSourceType sourceType,
    required String sourceId,
    required String text,
  }) async {
    final result = _embeddingService.embed(text);
    final id = '${sourceType.name}:$sourceId';
    await _embeddingRepository.saveEmbedding(AiEmbedding(
      id: id,
      sourceType: sourceType,
      sourceId: sourceId,
      entryId: entryId,
      modelId: result.modelId,
      modelVersion: result.modelVersion,
      dimensions: result.dimensions,
      vector: result.vector,
      generatedAt: DateTime.now(),
      textHash: result.textHash,
    ));
    return id;
  }

  Future<void> _appendJobLog({
    required DiaryEntry entry,
    required AiAnalysisStage stage,
    required String message,
    String outputSummary = '',
    String? summaryId,
    List<String>? segmentIds,
    List<String>? embeddingIds,
    String? insightId,
    String? retrievalTraceId,
  }) async {
    final now = DateTime.now();
    final existing = await _queueRepository.getJob(entry.id);
    final base = existing ??
        AiAnalysisJob(
          id: entry.id,
          entryId: entry.id,
          pipelineVersion: entry.updatedAt.microsecondsSinceEpoch,
          state: AiAnalysisJobState.completed,
          currentStage: AiAnalysisStage.completed,
          createdAt: now,
          updatedAt: now,
        );
    final completed = _markCompleted(base.completedStages, stage);
    final logs = [
      ...base.stageLogs,
      AiAnalysisStageLog(
        stage: stage,
        startedAt: now,
        message: message,
        inputSummary: 'entryId=${entry.id}',
        outputSummary: outputSummary,
        retryCount: base.retryCount,
      ),
    ];
    await _queueRepository.saveJob(base.copyWith(
      state: AiAnalysisJobState.completed,
      currentStage: AiAnalysisStage.completed,
      updatedAt: now,
      completedStages: completed,
      stageLogs: logs.length <= 80 ? logs : logs.sublist(logs.length - 80),
      summaryId: summaryId,
      segmentIds: segmentIds,
      embeddingIds: embeddingIds,
      insightId: insightId,
      retrievalTraceId: retrievalTraceId,
      clearLastError: true,
    ));
  }

  Future<void> _saveStatus(String entryId, String message) async {
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: entryId,
      state: DiaryAnalysisState.completed,
      updatedAt: DateTime.now(),
      message: message,
    ));
  }

  List<AiAnalysisStage> _markCompleted(
    List<AiAnalysisStage> stages,
    AiAnalysisStage stage,
  ) {
    if (stages.contains(stage)) return stages;
    return [...stages, stage];
  }
}

class _SummaryArtifacts {
  const _SummaryArtifacts({
    required this.summary,
    required this.segments,
  });

  final EntrySummary summary;
  final List<DiarySegment> segments;
}
