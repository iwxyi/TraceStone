import '../models/ai_embedding.dart';
import '../models/ai_analysis_job.dart';
import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../models/diary_segment.dart';
import '../models/entry_summary.dart';
import '../repositories/ai_analysis_queue_repository.dart';
import '../repositories/ai_embedding_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import '../repositories/insight_repository.dart';
import 'diary_analysis_service.dart';
import 'embedding_service.dart';
import 'entry_summary_service.dart';

class AiAnalysisQueueRunner {
  const AiAnalysisQueueRunner({
    AiAnalysisQueueRepository? queueRepository,
    AiEmbeddingRepository? embeddingRepository,
    DiaryRepository? diaryRepository,
    EntrySummaryRepository? summaryRepository,
    InsightRepository? insightRepository,
    DiaryAnalysisService? analysisService,
    EmbeddingService? embeddingService,
    EntrySummaryService? summaryService,
  })  : _queueRepository = queueRepository ?? const AiAnalysisQueueRepository(),
        _embeddingRepository =
            embeddingRepository ?? const AiEmbeddingRepository(),
        _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _summaryRepository =
            summaryRepository ?? const EntrySummaryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _analysisService = analysisService ?? const DiaryAnalysisService(),
        _embeddingService = embeddingService ?? const EmbeddingService(),
        _summaryService = summaryService ?? const EntrySummaryService();

  static bool _isRunning = false;

  final AiAnalysisQueueRepository _queueRepository;
  final AiEmbeddingRepository _embeddingRepository;
  final DiaryRepository _diaryRepository;
  final EntrySummaryRepository _summaryRepository;
  final InsightRepository _insightRepository;
  final DiaryAnalysisService _analysisService;
  final EmbeddingService _embeddingService;
  final EntrySummaryService _summaryService;

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
      await processNext();
      final next = await _queueRepository.nextRunnableJob();
      if (next == null) break;
    }
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
      clearLastError: true,
    );
    try {
      final segments = _summaryService.buildSegments(entry);
      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.segmenting,
        analysisState: DiaryAnalysisState.analyzing,
        message: '拆分日记片段',
        retryCount: job.retryCount,
        completedStages: const [AiAnalysisStage.preparing],
        clearLastError: true,
      );
      await _summaryRepository.saveSegments(entry.id, segments);

      final summary = _summaryService.buildSummary(entry, segments);
      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.generatingSummary,
        analysisState: DiaryAnalysisState.analyzing,
        message: '生成摘要包',
        retryCount: job.retryCount,
        completedStages: const [
          AiAnalysisStage.preparing,
          AiAnalysisStage.segmenting,
        ],
        clearLastError: true,
      );
      await _summaryRepository.saveSummary(summary);

      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.embedding,
        analysisState: DiaryAnalysisState.analyzing,
        message: '生成多级向量',
        retryCount: job.retryCount,
        completedStages: const [
          AiAnalysisStage.preparing,
          AiAnalysisStage.segmenting,
          AiAnalysisStage.generatingSummary,
        ],
        clearLastError: true,
      );
      await _saveEmbeddings(entry, summary, segments);

      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.retrieving,
        analysisState: DiaryAnalysisState.analyzing,
        message: '关联历史记录',
        retryCount: job.retryCount,
        completedStages: const [
          AiAnalysisStage.preparing,
          AiAnalysisStage.segmenting,
          AiAnalysisStage.generatingSummary,
          AiAnalysisStage.embedding,
        ],
        clearLastError: true,
      );
      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.generatingInsight,
        analysisState: DiaryAnalysisState.analyzing,
        message: '生成今日洞察',
        retryCount: job.retryCount,
        completedStages: const [
          AiAnalysisStage.preparing,
          AiAnalysisStage.segmenting,
          AiAnalysisStage.generatingSummary,
          AiAnalysisStage.embedding,
          AiAnalysisStage.retrieving,
        ],
        clearLastError: true,
      );

      await _analysisService.analyzeEntry(entry);

      await _saveStage(
        job,
        state: AiAnalysisJobState.completed,
        stage: AiAnalysisStage.completed,
        analysisState: DiaryAnalysisState.completed,
        message: '整理完成',
        retryCount: job.retryCount,
        completedStages: const [
          AiAnalysisStage.preparing,
          AiAnalysisStage.segmenting,
          AiAnalysisStage.generatingSummary,
          AiAnalysisStage.embedding,
          AiAnalysisStage.retrieving,
          AiAnalysisStage.generatingInsight,
          AiAnalysisStage.updatingMemory,
        ],
        clearLastError: true,
      );
    } on Object catch (error) {
      await _queueRepository.saveJob(job.copyWith(
        state: AiAnalysisJobState.failed,
        currentStage: AiAnalysisStage.generatingInsight,
        updatedAt: now,
        retryCount: job.retryCount + 1,
        lastError: error.toString(),
      ));
      await _insightRepository.saveStatus(DiaryAnalysisStatus(
        entryId: job.entryId,
        state: DiaryAnalysisState.failed,
        updatedAt: DateTime.now(),
        message: error.toString(),
      ));
    }
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
  }) async {
    await _queueRepository.saveJob(job.copyWith(
      state: state,
      currentStage: stage,
      updatedAt: DateTime.now(),
      completedStages: completedStages,
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
      text: '${summary.brief}\n${entry.bodyPreview}',
    );
    await _saveEmbedding(
      entryId: entry.id,
      sourceType: AiEmbeddingSourceType.summary,
      sourceId: entry.id,
      text: [
        summary.brief,
        ...summary.keyPoints,
        ...summary.topics,
      ].join('\n'),
    );
    for (final segment in segments) {
      await _saveEmbedding(
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.segment,
        sourceId: segment.id,
        text: '${segment.summary}\n${segment.text}',
      );
    }
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

  Future<void> _failJob(AiAnalysisJob job, String message) async {
    await _queueRepository.saveJob(job.copyWith(
      state: AiAnalysisJobState.failed,
      updatedAt: DateTime.now(),
      retryCount: job.retryCount + 1,
      lastError: message,
    ));
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: job.entryId,
      state: DiaryAnalysisState.failed,
      updatedAt: DateTime.now(),
      message: message,
    ));
  }
}
