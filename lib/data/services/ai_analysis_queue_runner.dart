import '../models/ai_embedding.dart';
import '../models/ai_analysis_job.dart';
import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../models/diary_insight.dart';
import '../models/diary_segment.dart';
import '../models/entry_summary.dart';
import '../repositories/ai_analysis_queue_repository.dart';
import '../repositories/ai_embedding_repository.dart';
import '../repositories/ai_retrieval_trace_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import '../repositories/insight_repository.dart';
import 'diary_analysis_service.dart';
import 'embedding_service.dart';
import 'entry_summary_service.dart';
import 'ai_client_service.dart';
import 'ai_embedding_text_builder.dart';

class AiAnalysisQueueRunner {
  const AiAnalysisQueueRunner({
    AiAnalysisQueueRepository? queueRepository,
    AiEmbeddingRepository? embeddingRepository,
    DiaryRepository? diaryRepository,
    EntrySummaryRepository? summaryRepository,
    InsightRepository? insightRepository,
    AiRetrievalTraceRepository? retrievalTraceRepository,
    DiaryAnalysisService? analysisService,
    EmbeddingService? embeddingService,
    EntrySummaryService? summaryService,
    AiEmbeddingTextBuilder? embeddingTextBuilder,
  })  : _queueRepository = queueRepository ?? const AiAnalysisQueueRepository(),
        _embeddingRepository =
            embeddingRepository ?? const AiEmbeddingRepository(),
        _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _summaryRepository =
            summaryRepository ?? const EntrySummaryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _retrievalTraceRepository =
            retrievalTraceRepository ?? const AiRetrievalTraceRepository(),
        _analysisService = analysisService ?? const DiaryAnalysisService(),
        _embeddingService = embeddingService ?? const EmbeddingService(),
        _summaryService = summaryService ?? const EntrySummaryService(),
        _embeddingTextBuilder =
            embeddingTextBuilder ?? const AiEmbeddingTextBuilder();

  static bool _isRunning = false;

  final AiAnalysisQueueRepository _queueRepository;
  final AiEmbeddingRepository _embeddingRepository;
  final DiaryRepository _diaryRepository;
  final EntrySummaryRepository _summaryRepository;
  final InsightRepository _insightRepository;
  final AiRetrievalTraceRepository _retrievalTraceRepository;
  final DiaryAnalysisService _analysisService;
  final EmbeddingService _embeddingService;
  final EntrySummaryService _summaryService;
  final AiEmbeddingTextBuilder _embeddingTextBuilder;

  Future<void> enqueue(DiaryEntry entry, {bool start = true}) async {
    if (entry.content.trim().isEmpty) return;
    await _queueRepository.enqueueEntry(entry);
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: entry.id,
      state: DiaryAnalysisState.queued,
      updatedAt: DateTime.now(),
      message: '等待整理',
    ));
    if (start) {
      await processNext();
    }
  }

  Future<int> enqueueBackfill({int limit = 200}) async {
    final entries = await _diaryRepository.listEntries();
    var enqueued = 0;
    for (final entry in entries) {
      if (enqueued >= limit) break;
      if (entry.content.trim().isEmpty) continue;
      if (!await _needsBackfill(entry)) continue;
      await _queueRepository.enqueueEntry(entry);
      await _insightRepository.saveStatus(DiaryAnalysisStatus(
        entryId: entry.id,
        state: DiaryAnalysisState.queued,
        updatedAt: DateTime.now(),
        message: '等待补建 AI 资料',
      ));
      enqueued += 1;
    }
    return enqueued;
  }

  Future<void> processNext() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      final job = await _queueRepository.nextRunnableJob();
      if (job == null) return;
      await _runJob(job);
    } finally {
      _isRunning = false;
    }
  }

  Future<void> processUntilIdle({int maxJobs = 1}) async {
    for (var index = 0; index < maxJobs; index++) {
      final current = await _queueRepository.nextRunnableJob();
      if (current == null) break;
      await processNext();
      final next = await _queueRepository.nextRunnableJob();
      if (next == null) break;
      if (next.id == current.id) break;
    }
  }

  Future<bool> _needsBackfill(DiaryEntry entry) async {
    final job = await _queueRepository.getJob(entry.id);
    if (job != null &&
        (job.state == AiAnalysisJobState.running || job.canRun)) {
      return false;
    }
    final pipelineVersion = entry.updatedAt.microsecondsSinceEpoch;
    if (job == null || job.pipelineVersion != pipelineVersion) {
      return true;
    }
    final summary = await _summaryRepository.getSummary(entry.id);
    final segments = await _summaryRepository.listSegments(entry.id);
    if (summary == null || segments.isEmpty) return true;
    if (!await _hasAllEmbeddings(entry, summary, segments)) return true;
    final insight = await _insightRepository.getInsight(entry.id);
    if (insight == null) return true;
    return job.state != AiAnalysisJobState.completed;
  }

  Future<void> _runJob(AiAnalysisJob job) async {
    final now = DateTime.now();
    final entry = await _diaryRepository.getEntryById(job.entryId);
    if (entry == null) {
      await _failJob(job, '日记不存在，无法整理');
      return;
    }
    if (entry.updatedAt.microsecondsSinceEpoch != job.pipelineVersion) {
      await _queueRepository.enqueueEntry(entry);
      return;
    }

    await _saveStage(
      job,
      state: AiAnalysisJobState.running,
      stage: AiAnalysisStage.preparing,
      analysisState: DiaryAnalysisState.analyzing,
      message: '准备日记内容',
      retryCount: job.retryCount,
      inputSummary: 'entryId=${job.entryId}',
      outputSummary:
          'date=${_dateLabel(entry.date)} chars=${entry.content.length} '
          'location=${entry.location}',
      clearLastError: true,
    );
    try {
      var completedStages = [...job.completedStages];
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.preparing,
      );

      var summary = await _summaryRepository.getSummary(entry.id);
      final staleArtifacts = summary != null &&
          !summary.entryUpdatedAt.isAtSameMomentAs(entry.updatedAt);
      var segments = await _summaryRepository.listSegments(entry.id);
      if (segments.isEmpty || staleArtifacts) {
        segments = _summaryService.buildSegments(entry);
        await _saveStage(
          job,
          state: AiAnalysisJobState.running,
          stage: AiAnalysisStage.segmenting,
          analysisState: DiaryAnalysisState.analyzing,
          message: staleArtifacts ? '日记已更新，重建日记片段' : '拆分日记片段',
          retryCount: job.retryCount,
          completedStages: completedStages,
          outputSummary: _segmentOutputSummary(segments),
          clearLastError: true,
        );
        await _summaryRepository.saveSegments(entry.id, segments);
      } else {
        await _saveStage(
          job,
          state: AiAnalysisJobState.running,
          stage: AiAnalysisStage.segmenting,
          analysisState: DiaryAnalysisState.analyzing,
          message: '复用已有日记片段',
          retryCount: job.retryCount,
          completedStages: completedStages,
          outputSummary: _segmentOutputSummary(segments),
          clearLastError: true,
        );
      }
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.segmenting,
      );

      if (summary == null || staleArtifacts) {
        summary = _summaryService.buildSummary(entry, segments);
        await _saveStage(
          job,
          state: AiAnalysisJobState.running,
          stage: AiAnalysisStage.generatingSummary,
          analysisState: DiaryAnalysisState.analyzing,
          message: staleArtifacts ? '日记已更新，重建摘要包' : '生成摘要包',
          retryCount: job.retryCount,
          completedStages: completedStages,
          outputSummary: _summaryOutputSummary(summary),
          clearLastError: true,
        );
        await _summaryRepository.saveSummary(summary);
      } else {
        await _saveStage(
          job,
          state: AiAnalysisJobState.running,
          stage: AiAnalysisStage.generatingSummary,
          analysisState: DiaryAnalysisState.analyzing,
          message: '复用已有摘要包',
          retryCount: job.retryCount,
          completedStages: completedStages,
          outputSummary: _summaryOutputSummary(summary),
          clearLastError: true,
        );
      }
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.generatingSummary,
      );

      final embeddingsReady = await _hasAllEmbeddings(entry, summary, segments);
      if (!embeddingsReady) {
        await _saveStage(
          job,
          state: AiAnalysisJobState.running,
          stage: AiAnalysisStage.embedding,
          analysisState: DiaryAnalysisState.analyzing,
          message: '生成多级向量',
          retryCount: job.retryCount,
          completedStages: completedStages,
          outputSummary: _embeddingOutputSummary(segments),
          clearLastError: true,
        );
        await _saveEmbeddings(entry, summary, segments);
      } else {
        await _saveStage(
          job,
          state: AiAnalysisJobState.running,
          stage: AiAnalysisStage.embedding,
          analysisState: DiaryAnalysisState.analyzing,
          message: '复用已有多级向量',
          retryCount: job.retryCount,
          completedStages: completedStages,
          outputSummary: _embeddingOutputSummary(segments),
          clearLastError: true,
        );
      }
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.embedding,
      );

      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.retrieving,
        analysisState: DiaryAnalysisState.analyzing,
        message: '关联历史记录',
        retryCount: job.retryCount,
        completedStages: completedStages,
        outputSummary: '由今日洞察上下文构建器执行，生成后写入 retrieval trace',
        clearLastError: true,
      );
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.retrieving,
      );
      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.generatingInsight,
        analysisState: DiaryAnalysisState.analyzing,
        message: '生成今日洞察',
        retryCount: job.retryCount,
        completedStages: completedStages,
        inputSummary: 'entryId=${entry.id} summary=${summary.brief}',
        clearLastError: true,
      );
      final insight = await _analysisService.analyzeEntry(entry);
      final trace = await _retrievalTraceRepository.getTrace(entry.id);
      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.generatingInsight,
        analysisState: DiaryAnalysisState.analyzing,
        message: '今日洞察已生成',
        retryCount: job.retryCount,
        completedStages: completedStages,
        outputSummary: [
          _insightOutputSummary(insight),
          if (trace != null)
            'retrievalSources=${trace.sourceCount} items=${trace.items.length}',
        ].join(' '),
        clearLastError: true,
      );
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.generatingInsight,
      );
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.updatingMemory,
      );

      await _saveStage(
        job,
        state: AiAnalysisJobState.completed,
        stage: AiAnalysisStage.completed,
        analysisState: DiaryAnalysisState.completed,
        message: '整理完成',
        retryCount: job.retryCount,
        completedStages: completedStages,
        outputSummary:
            'completed=${completedStages.map((item) => item.name).join(',')}',
        clearLastError: true,
      );
    } on AiClientException catch (error) {
      await _deferJobForAi(job, error.message);
    } on Object catch (error) {
      final latest = await _queueRepository.getJob(job.id) ?? job;
      await _queueRepository.saveJob(latest.copyWith(
        state: AiAnalysisJobState.failed,
        currentStage: latest.currentStage,
        updatedAt: now,
        retryCount: latest.retryCount + 1,
        lastError: error.toString(),
        stageLogs: _appendStageLog(
          latest.stageLogs,
          AiAnalysisStageLog(
            stage: latest.currentStage,
            startedAt: DateTime.now(),
            message: '阶段失败',
            inputSummary: 'entryId=${job.entryId}',
            outputSummary: '',
            error: error.toString(),
            retryCount: latest.retryCount + 1,
          ),
        ),
      ));
      await _insightRepository.saveStatus(DiaryAnalysisStatus(
        entryId: job.entryId,
        state: DiaryAnalysisState.failed,
        updatedAt: DateTime.now(),
        message: error.toString(),
      ));
    }
  }

  Future<void> _deferJobForAi(AiAnalysisJob job, String message) async {
    final latest = await _queueRepository.getJob(job.id) ?? job;
    final now = DateTime.now();
    await _queueRepository.saveJob(latest.copyWith(
      state: AiAnalysisJobState.incomplete,
      currentStage: AiAnalysisStage.generatingInsight,
      updatedAt: now,
      lastError: '等待 AI 可用：$message',
      stageLogs: _appendStageLog(
        latest.stageLogs,
        AiAnalysisStageLog(
          stage: AiAnalysisStage.generatingInsight,
          startedAt: now,
          message: '等待 AI 可用',
          inputSummary: 'entryId=${job.entryId}',
          outputSummary: '本地摘要、分段和向量已保留',
          error: message,
          retryCount: latest.retryCount,
        ),
      ),
    ));
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: job.entryId,
      state: DiaryAnalysisState.incomplete,
      updatedAt: now,
      message: '本地资料已整理，等待 AI 可用后生成今日洞察',
    ));
  }

  Future<void> _saveStage(
    AiAnalysisJob job, {
    required AiAnalysisJobState state,
    required AiAnalysisStage stage,
    required DiaryAnalysisState analysisState,
    required String message,
    required int retryCount,
    List<AiAnalysisStage>? completedStages,
    bool clearLastError = false,
    String? inputSummary,
    String? outputSummary,
  }) async {
    final latest = await _queueRepository.getJob(job.id) ?? job;
    final logs = _appendStageLog(
      latest.stageLogs,
      AiAnalysisStageLog(
        stage: stage,
        startedAt: DateTime.now(),
        message: message,
        inputSummary: inputSummary ?? 'entryId=${job.entryId}',
        outputSummary: outputSummary ??
            [
              if (completedStages != null)
                'completed=${completedStages.map((item) => item.name).join(',')}',
              'state=${state.name}',
            ].join(' '),
        retryCount: retryCount,
      ),
    );
    await _queueRepository.saveJob(latest.copyWith(
      state: state,
      currentStage: stage,
      updatedAt: DateTime.now(),
      completedStages: completedStages,
      stageLogs: logs,
      retryCount: retryCount,
      clearLastError: clearLastError,
    ));
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: job.entryId,
      state: analysisState,
      updatedAt: DateTime.now(),
      message: message,
    ));
  }

  List<AiAnalysisStageLog> _appendStageLog(
    List<AiAnalysisStageLog> logs,
    AiAnalysisStageLog log,
  ) {
    final next = [...logs, log];
    if (next.length <= 80) return next;
    return next.sublist(next.length - 80);
  }

  Future<void> _saveEmbeddings(
    DiaryEntry entry,
    EntrySummary summary,
    List<DiarySegment> segments,
  ) async {
    await _embeddingRepository.deleteForEntry(entry.id);
    await _saveEmbedding(
      entryId: entry.id,
      sourceType: AiEmbeddingSourceType.entry,
      sourceId: entry.id,
      text: _embeddingTextBuilder.entryText(entry, summary),
    );
    await _saveEmbedding(
      entryId: entry.id,
      sourceType: AiEmbeddingSourceType.summary,
      sourceId: entry.id,
      text: _embeddingTextBuilder.summaryText(summary),
    );
    for (final segment in segments) {
      await _saveEmbedding(
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.segment,
        sourceId: segment.id,
        text: _embeddingTextBuilder.segmentText(segment),
      );
    }
  }

  Future<bool> _hasAllEmbeddings(
    DiaryEntry entry,
    EntrySummary summary,
    List<DiarySegment> segments,
  ) async {
    final entryEmbedding = await _embeddingRepository.getBySource(
      sourceType: AiEmbeddingSourceType.entry,
      sourceId: entry.id,
    );
    final summaryEmbedding = await _embeddingRepository.getBySource(
      sourceType: AiEmbeddingSourceType.summary,
      sourceId: entry.id,
    );
    if (entryEmbedding == null || summaryEmbedding == null) return false;
    if (entryEmbedding.textHash !=
        _embeddingService
            .embed(_embeddingTextBuilder.entryText(entry, summary))
            .textHash) {
      return false;
    }
    if (summaryEmbedding.textHash !=
        _embeddingService
            .embed(_embeddingTextBuilder.summaryText(summary))
            .textHash) {
      return false;
    }
    for (final segment in segments) {
      final embedding = await _embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.segment,
        sourceId: segment.id,
      );
      if (embedding == null) return false;
      if (embedding.textHash !=
          _embeddingService
              .embed(_embeddingTextBuilder.segmentText(segment))
              .textHash) {
        return false;
      }
    }
    return true;
  }

  List<AiAnalysisStage> _markCompleted(
    List<AiAnalysisStage> stages,
    AiAnalysisStage stage,
  ) {
    if (stages.contains(stage)) return stages;
    return [...stages, stage];
  }

  Future<void> _saveEmbedding({
    required String entryId,
    required AiEmbeddingSourceType sourceType,
    required String sourceId,
    required String text,
  }) async {
    final result = _embeddingService.embed(text);
    await _embeddingRepository.saveEmbedding(AiEmbedding(
      id: '${sourceType.name}:$sourceId',
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
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _segmentOutputSummary(List<DiarySegment> segments) {
    final boundaryCounts = <String, int>{};
    for (final segment in segments) {
      boundaryCounts[segment.boundary.name] =
          (boundaryCounts[segment.boundary.name] ?? 0) + 1;
    }
    final boundaries = boundaryCounts.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
    return [
      'segments=${segments.length}',
      if (boundaries.isNotEmpty) 'boundaries=$boundaries',
      if (segments.isNotEmpty) 'first=${segments.first.summary}',
    ].join(' ');
  }

  String _summaryOutputSummary(EntrySummary summary) {
    return [
      'brief=${summary.brief}',
      'keyPoints=${summary.keyPoints.length}',
      'topics=${summary.topics.join(',')}',
      'importance=${summary.importance.toStringAsFixed(2)}',
      'generator=${summary.generator}',
    ].where((item) => !item.endsWith('=')).join(' ');
  }

  String _embeddingOutputSummary(List<DiarySegment> segments) {
    final count = 2 + segments.length;
    return [
      'embeddings=$count',
      'entry=1',
      'summary=1',
      'segments=${segments.length}',
      'model=${EmbeddingService.modelId}/${EmbeddingService.modelVersion}/${EmbeddingService.dimensions}d',
    ].join(' ');
  }

  String _insightOutputSummary(DiaryInsight insight) {
    return [
      'reflection=${insight.reflection.length}',
      'facts=${insight.facts.length}',
      'signals=${insight.signals.length}',
      'hypotheses=${insight.hypotheses.length}',
      'suggestions=${insight.suggestions.length}',
      'profileCandidates=${insight.profileUpdateCandidates.length}',
      'relationshipUpdates=${insight.relationshipUpdates.length}',
      'contradictions=${insight.contradictions.length}',
    ].join(' ');
  }

  Future<void> _failJob(AiAnalysisJob job, String message) async {
    final latest = await _queueRepository.getJob(job.id) ?? job;
    await _queueRepository.saveJob(latest.copyWith(
      state: AiAnalysisJobState.failed,
      updatedAt: DateTime.now(),
      retryCount: latest.retryCount + 1,
      lastError: message,
      stageLogs: _appendStageLog(
        latest.stageLogs,
        AiAnalysisStageLog(
          stage: latest.currentStage,
          startedAt: DateTime.now(),
          message: '任务失败',
          inputSummary: 'entryId=${job.entryId}',
          error: message,
          retryCount: latest.retryCount + 1,
        ),
      ),
    ));
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: job.entryId,
      state: DiaryAnalysisState.failed,
      updatedAt: DateTime.now(),
      message: message,
    ));
  }
}
