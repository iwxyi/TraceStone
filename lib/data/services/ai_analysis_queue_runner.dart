import '../models/ai_embedding.dart';
import '../models/ai_analysis_job.dart';
import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../models/diary_insight.dart';
import '../models/diary_segment.dart';
import '../models/entry_summary.dart';
import '../models/period_summary.dart';
import '../repositories/ai_analysis_queue_repository.dart';
import '../repositories/ai_embedding_repository.dart';
import '../repositories/ai_retrieval_trace_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/period_summary_repository.dart';
import 'diary_analysis_service.dart';
import 'embedding_service.dart';
import 'entry_summary_service.dart';
import 'ai_client_service.dart';
import 'ai_embedding_text_builder.dart';
import 'ai_user_profile_service.dart';
import 'period_summary_service.dart';

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
    PeriodSummaryRepository? periodSummaryRepository,
    PeriodSummaryService? periodSummaryService,
    AiUserProfileService? userProfileService,
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
            embeddingTextBuilder ?? const AiEmbeddingTextBuilder(),
        _periodSummaryRepository =
            periodSummaryRepository ?? const PeriodSummaryRepository(),
        _periodSummaryService =
            periodSummaryService ?? const PeriodSummaryService(),
        _userProfileService =
            userProfileService ?? const AiUserProfileService();

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
  final PeriodSummaryRepository _periodSummaryRepository;
  final PeriodSummaryService _periodSummaryService;
  final AiUserProfileService _userProfileService;

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
    entries.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.createdAt.compareTo(b.createdAt);
    });
    final batchStartedAt = DateTime.now();
    final batchId = 'backfill:${batchStartedAt.microsecondsSinceEpoch}';
    final batchLabel = '补建缺失资料 ${_dateTimeLabel(batchStartedAt)}';
    var enqueued = 0;
    for (final entry in entries) {
      if (enqueued >= limit) break;
      if (entry.content.trim().isEmpty) continue;
      if (!await _needsBackfill(entry)) continue;
      await _queueRepository.enqueueEntry(
        entry,
        batchId: batchId,
        batchLabel: batchLabel,
      );
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

  Future<int> enqueueOutdatedEmbeddingRebuild({int limit = 5000}) async {
    final signature = await _embeddingService.currentTargetSignature();
    final entryIds = await _embeddingRepository.listOutdatedEntryIds(
      modelId: signature.modelId,
      modelVersion: signature.modelVersion,
      dimensions: signature.dimensions,
    );
    final batchStartedAt = DateTime.now();
    final batchId =
        'embedding-rebuild:${batchStartedAt.microsecondsSinceEpoch}';
    final batchLabel = '重建历史相似度 ${_dateTimeLabel(batchStartedAt)}';
    var enqueued = 0;
    for (final entryId in entryIds) {
      if (enqueued >= limit) break;
      final entry = await _diaryRepository.getEntryById(entryId);
      if (entry == null || entry.content.trim().isEmpty) continue;
      await _queueRepository.enqueueEmbeddingRebuildEntry(
        entry,
        batchId: batchId,
        batchLabel: batchLabel,
      );
      await _insightRepository.saveStatus(DiaryAnalysisStatus(
        entryId: entry.id,
        state: DiaryAnalysisState.queued,
        updatedAt: DateTime.now(),
        message: '等待重建历史相似度',
      ));
      enqueued += 1;
    }
    return enqueued;
  }

  Future<void> processNext() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      await _syncInterruptedStatuses();
      await _queueRepository.enqueueMissingPeriodDependencies();
      final job = await _queueRepository.nextRunnableJob();
      if (job == null) return;
      await _runJob(job);
    } finally {
      _isRunning = false;
    }
  }

  Future<void> processUntilIdle({int maxJobs = 1}) async {
    await _syncInterruptedStatuses();
    for (var index = 0; index < maxJobs; index++) {
      await _queueRepository.enqueueMissingPeriodDependencies();
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

  Future<void> _syncInterruptedStatuses() async {
    await _queueRepository.markStaleRunningIncomplete();
    final jobs = await _queueRepository.listJobs();
    for (final job in jobs) {
      if (job.state != AiAnalysisJobState.incomplete) continue;
      if (job.lastError != '上次整理被中断，已等待继续') continue;
      if (job.type == AiAnalysisJobType.embeddingRebuild) {
        final status = await _insightRepository.getStatus(job.entryId);
        if (status?.state == DiaryAnalysisState.incomplete) continue;
        await _insightRepository.saveStatus(DiaryAnalysisStatus(
          entryId: job.entryId,
          state: DiaryAnalysisState.incomplete,
          updatedAt: DateTime.now(),
          message: '上次重建历史相似度被系统中断，下次将继续',
        ));
        continue;
      }
      if (job.type == AiAnalysisJobType.userProfile) {
        await _queueRepository.saveJob(job.copyWith(
          state: AiAnalysisJobState.incomplete,
          updatedAt: DateTime.now(),
          lastError: '上次更新用户画像被中断，已等待继续',
        ));
        continue;
      }
      if (job.type != AiAnalysisJobType.diary) {
        final status = await _periodSummaryRepository.getStatus(job.targetId);
        if (status?.state == PeriodSummaryState.failed) continue;
        await _periodSummaryRepository.saveStatus(PeriodSummaryStatus(
          id: job.targetId,
          state: PeriodSummaryState.failed,
          updatedAt: DateTime.now(),
          message: '上次生成被系统中断，下次将继续',
        ));
        continue;
      }
      final status = await _insightRepository.getStatus(job.entryId);
      if (status?.state == DiaryAnalysisState.incomplete) continue;
      await _insightRepository.saveStatus(DiaryAnalysisStatus(
        entryId: job.entryId,
        state: DiaryAnalysisState.incomplete,
        updatedAt: DateTime.now(),
        message: '上次整理被系统中断，下次将继续',
      ));
    }
  }

  Future<void> _runJob(AiAnalysisJob job) async {
    if (job.type == AiAnalysisJobType.embeddingRebuild) {
      await _runEmbeddingRebuildJob(job);
      return;
    }
    if (job.type == AiAnalysisJobType.monthSummary ||
        job.type == AiAnalysisJobType.yearSummary) {
      await _runPeriodSummaryJob(job);
      return;
    }
    if (job.type == AiAnalysisJobType.userProfile) {
      await _runUserProfileJob(job);
      return;
    }
    final now = DateTime.now();
    final entry = await _diaryRepository.getEntryById(job.entryId);
    if (entry == null) {
      await _discardMissingEntryJob(job, '日记不存在，已从整理队列移除');
      return;
    }
    if (entry.updatedAt.microsecondsSinceEpoch != job.pipelineVersion) {
      await _queueRepository.enqueueEntry(entry);
      return;
    }
    await _insightRepository.deleteForEntry(entry.id);
    await _retrievalTraceRepository.deleteForEntry(entry.id);

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
        var segmentMessage = staleArtifacts ? '日记已更新，重建日记片段' : '拆分日记片段';
        try {
          segments = _summaryService.buildSegments(entry);
        } on Object catch (error) {
          segments = _fallbackSegments(entry);
          segmentMessage = '日记片段拆分失败，使用全文片段';
          await _saveStage(
            job,
            state: AiAnalysisJobState.running,
            stage: AiAnalysisStage.segmenting,
            analysisState: DiaryAnalysisState.analyzing,
            message: segmentMessage,
            retryCount: job.retryCount,
            completedStages: completedStages,
            outputSummary: 'fallback=true error=$error',
            segmentIds: segments.map((segment) => segment.id).toList(),
          );
        }
        if (segmentMessage != '日记片段拆分失败，使用全文片段') {
          await _saveStage(
            job,
            state: AiAnalysisJobState.running,
            stage: AiAnalysisStage.segmenting,
            analysisState: DiaryAnalysisState.analyzing,
            message: segmentMessage,
            retryCount: job.retryCount,
            completedStages: completedStages,
            outputSummary: _segmentOutputSummary(segments),
            segmentIds: segments.map((segment) => segment.id).toList(),
            clearLastError: true,
          );
        }
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
          segmentIds: segments.map((segment) => segment.id).toList(),
          clearLastError: true,
        );
      }
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.segmenting,
      );

      if (summary == null || staleArtifacts) {
        var summaryMessage = staleArtifacts ? '日记已更新，重建摘要包' : '生成摘要包';
        try {
          summary = _summaryService.buildSummary(entry, segments);
        } on Object catch (error) {
          summary = _fallbackSummary(entry, segments);
          summaryMessage = '摘要生成失败，使用正文预览';
          await _saveStage(
            job,
            state: AiAnalysisJobState.running,
            stage: AiAnalysisStage.generatingSummary,
            analysisState: DiaryAnalysisState.analyzing,
            message: summaryMessage,
            retryCount: job.retryCount,
            completedStages: completedStages,
            outputSummary: 'fallback=true error=$error',
            summaryId: summary.entryId,
          );
        }
        if (summaryMessage != '摘要生成失败，使用正文预览') {
          await _saveStage(
            job,
            state: AiAnalysisJobState.running,
            stage: AiAnalysisStage.generatingSummary,
            analysisState: DiaryAnalysisState.analyzing,
            message: summaryMessage,
            retryCount: job.retryCount,
            completedStages: completedStages,
            outputSummary: _summaryOutputSummary(summary),
            summaryId: summary.entryId,
            clearLastError: true,
          );
        }
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
          summaryId: summary.entryId,
          clearLastError: true,
        );
      }
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.generatingSummary,
      );

      var embeddingIds = <String>[];
      try {
        final embeddingsReady =
            await _hasAllEmbeddings(entry, summary, segments);
        embeddingIds = _embeddingIds(entry, segments);
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
            embeddingIds: embeddingIds,
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
            embeddingIds: embeddingIds,
            clearLastError: true,
          );
        }
      } on Object catch (error) {
        embeddingIds = const [];
        await _saveStage(
          job,
          state: AiAnalysisJobState.running,
          stage: AiAnalysisStage.embedding,
          analysisState: DiaryAnalysisState.analyzing,
          message: '向量生成失败，保留结构化摘要',
          retryCount: job.retryCount,
          completedStages: completedStages,
          outputSummary: 'embeddingSkipped=true error=$error',
          embeddingIds: embeddingIds,
        );
        throw AiClientException('向量生成失败：$error');
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
        outputSummary: '由今日分析上下文构建器执行，生成后写入 retrieval trace',
        retrievalTraceId: entry.id,
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
        message: '生成今日分析',
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
        message: '今日分析已生成',
        retryCount: job.retryCount,
        completedStages: completedStages,
        outputSummary: [
          _insightOutputSummary(insight),
          if (trace != null)
            'retrievalSources=${trace.sourceCount} items=${trace.items.length}',
        ].join(' '),
        insightId: insight.entryId,
        retrievalTraceId: trace?.entryId ?? entry.id,
        clearLastError: true,
      );
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.generatingInsight,
      );

      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.updatingMemory,
        analysisState: DiaryAnalysisState.analyzing,
        message: '更新长期记忆和候选资料',
        retryCount: job.retryCount,
        completedStages: completedStages,
        inputSummary: 'entryId=${entry.id} insight=${insight.entryId}',
        outputSummary: _memoryUpdateOutputSummary(insight),
        insightId: insight.entryId,
        clearLastError: true,
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
        summaryId: summary.entryId,
        segmentIds: segments.map((segment) => segment.id).toList(),
        embeddingIds: embeddingIds,
        insightId: insight.entryId,
        retrievalTraceId: trace?.entryId ?? entry.id,
        clearLastError: true,
      );
    } on AiClientException catch (error) {
      if (error.retryable) {
        await _handleUnexpectedStageError(job, error, now);
      } else {
        await _deferJobForAi(job, error.message);
      }
    } on Object catch (error) {
      await _handleUnexpectedStageError(job, error, now);
    }
  }

  Future<void> _runEmbeddingRebuildJob(AiAnalysisJob job) async {
    final entry = await _diaryRepository.getEntryById(job.entryId);
    if (entry == null) {
      await _discardMissingEntryJob(job, '日记不存在，已从历史相似度队列移除');
      return;
    }
    if (entry.updatedAt.microsecondsSinceEpoch != job.pipelineVersion) {
      await _queueRepository.enqueueEntry(entry);
      await _queueRepository.deleteJob(job.id);
      return;
    }
    await _saveStage(
      job,
      state: AiAnalysisJobState.running,
      stage: AiAnalysisStage.preparing,
      analysisState: DiaryAnalysisState.analyzing,
      message: '准备历史相似度索引资料',
      retryCount: job.retryCount,
      inputSummary: 'entryId=${job.entryId}',
      outputSummary:
          'date=${_dateLabel(entry.date)} chars=${entry.content.length}',
      clearLastError: true,
    );
    try {
      var completedStages = _markCompleted(
        job.completedStages,
        AiAnalysisStage.preparing,
      );
      var segments = await _summaryRepository.listSegments(entry.id);
      var summary = await _summaryRepository.getSummary(entry.id);
      final staleArtifacts = summary != null &&
          !summary.entryUpdatedAt.isAtSameMomentAs(entry.updatedAt);
      if (segments.isEmpty || summary == null || staleArtifacts) {
        segments = _summaryService.buildSegments(entry);
        summary = _summaryService.buildSummary(entry, segments);
        await _summaryRepository.saveSegments(entry.id, segments);
        await _summaryRepository.saveSummary(summary);
        await _saveStage(
          job,
          state: AiAnalysisJobState.running,
          stage: AiAnalysisStage.generatingSummary,
          analysisState: DiaryAnalysisState.analyzing,
          message: '补齐索引摘要资料',
          retryCount: job.retryCount,
          completedStages: completedStages,
          outputSummary:
              'summary=${summary.entryId} segments=${segments.length}',
          summaryId: summary.entryId,
          segmentIds: segments.map((segment) => segment.id).toList(),
          clearLastError: true,
        );
        completedStages = _markCompleted(
          completedStages,
          AiAnalysisStage.generatingSummary,
        );
      }
      final embeddingIds = _embeddingIds(entry, segments);
      await _saveStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.embedding,
        analysisState: DiaryAnalysisState.analyzing,
        message: '重建历史相似度',
        retryCount: job.retryCount,
        completedStages: completedStages,
        outputSummary: _embeddingOutputSummary(segments),
        summaryId: summary.entryId,
        segmentIds: segments.map((segment) => segment.id).toList(),
        embeddingIds: embeddingIds,
        clearLastError: true,
      );
      await _saveEmbeddings(entry, summary, segments);
      completedStages =
          _markCompleted(completedStages, AiAnalysisStage.embedding);
      completedStages =
          _markCompleted(completedStages, AiAnalysisStage.completed);
      await _saveStage(
        job,
        state: AiAnalysisJobState.completed,
        stage: AiAnalysisStage.completed,
        analysisState: DiaryAnalysisState.completed,
        message: '历史相似度已更新',
        retryCount: job.retryCount,
        completedStages: completedStages,
        outputSummary: 'embeddings=${embeddingIds.length}',
        summaryId: summary.entryId,
        segmentIds: segments.map((segment) => segment.id).toList(),
        embeddingIds: embeddingIds,
        clearLastError: true,
      );
    } on Object catch (error) {
      await _failJob(job, '历史相似度重建失败：$error');
    }
  }

  Future<void> _runPeriodSummaryJob(AiAnalysisJob job) async {
    final now = DateTime.now();
    final entries = await _diaryRepository.listEntries();
    final period = _periodFromJob(job);
    if (period == null) {
      await _failJob(job, '周期任务目标无效：${job.targetId}');
      return;
    }
    await _savePeriodStage(
      job,
      state: AiAnalysisJobState.running,
      stage: AiAnalysisStage.preparing,
      message: '准备周期资料',
      inputSummary: 'target=${job.targetId}',
      outputSummary: _periodEntrySummary(job.type, period, entries),
      clearLastError: true,
    );
    var completedStages = _markCompleted(
      job.completedStages,
      AiAnalysisStage.preparing,
    );
    try {
      final periodEntries = _entriesForPeriodJob(job.type, period, entries);
      completedStages = await _ensurePeriodEntryArtifacts(
        job,
        periodEntries,
        completedStages,
      );
      if (job.type == AiAnalysisJobType.yearSummary) {
        await _ensureMonthlySummariesForYear(job, period.year, entries);
      }
      await _savePeriodStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.generatingSummary,
        message:
            job.type == AiAnalysisJobType.monthSummary ? '生成月度总结' : '生成年度总结',
        completedStages: completedStages,
        inputSummary: 'target=${job.targetId}',
        clearLastError: true,
      );
      final summary = job.type == AiAnalysisJobType.monthSummary
          ? await _periodSummaryService.buildMonthSummary(period, entries)
          : await _periodSummaryService.buildYearSummary(period.year, entries);
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.generatingSummary,
      );
      await _savePeriodStage(
        job,
        state: AiAnalysisJobState.completed,
        stage: AiAnalysisStage.completed,
        message:
            job.type == AiAnalysisJobType.monthSummary ? '月度总结已生成' : '年度总结已生成',
        completedStages: completedStages,
        outputSummary: [
          'summary=${summary.id}',
          'entries=${summary.entryCount}',
          'generator=${summary.generator}',
        ].join(' '),
        clearLastError: true,
      );
    } on Object catch (error) {
      await _handlePeriodSummaryError(job, error, now);
    }
  }

  Future<List<AiAnalysisStage>> _ensurePeriodEntryArtifacts(
    AiAnalysisJob job,
    List<DiaryEntry> entries,
    List<AiAnalysisStage> completedStages,
  ) async {
    final targetEntries = entries
        .where((entry) => entry.content.trim().isNotEmpty)
        .toList(growable: false);
    if (targetEntries.isEmpty) return completedStages;
    await _savePeriodStage(
      job,
      state: AiAnalysisJobState.running,
      stage: AiAnalysisStage.segmenting,
      message: '补齐当期摘要和片段',
      completedStages: completedStages,
      inputSummary: 'target=${job.targetId}',
      outputSummary: 'entries=${targetEntries.length}',
      clearLastError: true,
    );
    var summaryCount = 0;
    var segmentCount = 0;
    for (final entry in targetEntries) {
      var summary = await _summaryRepository.getSummary(entry.id);
      var segments = await _summaryRepository.listSegments(entry.id);
      final stale = summary != null &&
          !summary.entryUpdatedAt.isAtSameMomentAs(entry.updatedAt);
      if (segments.isEmpty || stale) {
        segments = _summaryService.buildSegments(entry);
        await _summaryRepository.saveSegments(entry.id, segments);
      }
      if (summary == null || stale) {
        summary = _summaryService.buildSummary(entry, segments);
        await _summaryRepository.saveSummary(summary);
      }
      summaryCount++;
      segmentCount += segments.length;
    }
    completedStages = _markCompleted(
      completedStages,
      AiAnalysisStage.segmenting,
    );
    await _savePeriodStage(
      job,
      state: AiAnalysisJobState.running,
      stage: AiAnalysisStage.embedding,
      message: '补齐当期多级向量',
      completedStages: completedStages,
      inputSummary: 'target=${job.targetId}',
      outputSummary: 'summaries=$summaryCount segments=$segmentCount',
      clearLastError: true,
    );
    var embeddingCount = 0;
    for (final entry in targetEntries) {
      final summary = await _summaryRepository.getSummary(entry.id);
      final segments = await _summaryRepository.listSegments(entry.id);
      if (summary == null || segments.isEmpty) continue;
      final ready = await _hasAllEmbeddings(entry, summary, segments);
      if (!ready) {
        await _saveEmbeddings(entry, summary, segments);
      }
      embeddingCount += 2 + segments.length;
    }
    completedStages = _markCompleted(
      completedStages,
      AiAnalysisStage.embedding,
    );
    await _savePeriodStage(
      job,
      state: AiAnalysisJobState.running,
      stage: AiAnalysisStage.embedding,
      message: '当期基础资料已就绪',
      completedStages: completedStages,
      inputSummary: 'target=${job.targetId}',
      outputSummary:
          'entries=${targetEntries.length} embeddings=$embeddingCount',
      clearLastError: true,
    );
    return completedStages;
  }

  List<DiaryEntry> _entriesForPeriodJob(
    AiAnalysisJobType type,
    DateTime period,
    List<DiaryEntry> entries,
  ) {
    final result = entries.where((entry) {
      if (type == AiAnalysisJobType.yearSummary) {
        return entry.date.year == period.year;
      }
      if (type == AiAnalysisJobType.monthSummary) {
        return entry.date.year == period.year &&
            entry.date.month == period.month;
      }
      return false;
    }).toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.createdAt.compareTo(b.createdAt);
      });
    return result;
  }

  Future<void> _ensureMonthlySummariesForYear(
    AiAnalysisJob job,
    int year,
    List<DiaryEntry> entries,
  ) async {
    final months = entries
        .where((entry) => entry.date.year == year)
        .map((entry) => DateTime(entry.date.year, entry.date.month))
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    for (final month in months) {
      final id = PeriodSummaryRepository.monthId(month);
      final existing = await _periodSummaryRepository.getSummary(id);
      if (existing != null && existing.generator.startsWith('ai-')) continue;
      await _savePeriodStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.generatingSummary,
        message: '补齐${month.month}月月度总结',
        inputSummary: 'year=$year month=${month.month}',
        outputSummary: 'beforeYearSummary=true',
        clearLastError: true,
      );
      await _periodSummaryService.buildMonthSummary(month, entries);
    }
  }

  Future<void> _handlePeriodSummaryError(
    AiAnalysisJob job,
    Object error,
    DateTime now,
  ) async {
    final latest = await _queueRepository.getJob(job.id) ?? job;
    final nextRetry = latest.retryCount + 1;
    final nextState = nextRetry < 3
        ? AiAnalysisJobState.incomplete
        : AiAnalysisJobState.failed;
    await _queueRepository.saveJob(latest.copyWith(
      state: nextState,
      updatedAt: now,
      retryCount: nextRetry,
      lastError: error.toString(),
      stageLogs: _appendStageLog(
        latest.stageLogs,
        AiAnalysisStageLog(
          stage: latest.currentStage,
          startedAt: DateTime.now(),
          message: nextState == AiAnalysisJobState.incomplete
              ? '周期总结中断，等待继续'
              : '周期总结失败',
          inputSummary: 'target=${job.targetId}',
          error: error.toString(),
          retryCount: nextRetry,
        ),
      ),
    ));
    await _periodSummaryRepository.saveStatus(PeriodSummaryStatus(
      id: job.targetId,
      state: PeriodSummaryState.failed,
      updatedAt: now,
      message: error.toString(),
    ));
  }

  Future<void> _runUserProfileJob(AiAnalysisJob job) async {
    final now = DateTime.now();
    await _saveQueueOnlyStage(
      job,
      state: AiAnalysisJobState.running,
      stage: AiAnalysisStage.preparing,
      message: '准备用户画像资料',
      inputSummary: 'target=${job.targetId}',
      outputSummary: 'source=diary summaries memories insights',
      clearLastError: true,
    );
    var completedStages = _markCompleted(
      job.completedStages,
      AiAnalysisStage.preparing,
    );
    try {
      await _saveQueueOnlyStage(
        job,
        state: AiAnalysisJobState.running,
        stage: AiAnalysisStage.generatingSummary,
        message: '生成用户画像',
        completedStages: completedStages,
        inputSummary: 'target=${job.targetId}',
        clearLastError: true,
      );
      final profile = await _userProfileService.rebuildProfile();
      completedStages = _markCompleted(
        completedStages,
        AiAnalysisStage.generatingSummary,
      );
      await _saveQueueOnlyStage(
        job,
        state: AiAnalysisJobState.completed,
        stage: AiAnalysisStage.completed,
        message: '用户画像已更新',
        completedStages: completedStages,
        outputSummary:
            'memory=${profile.id} sources=${profile.allSourceEntryIds.length}',
        clearLastError: true,
      );
    } on Object catch (error) {
      final latest = await _queueRepository.getJob(job.id) ?? job;
      final nextRetry = latest.retryCount + 1;
      final nextState = nextRetry < 3
          ? AiAnalysisJobState.incomplete
          : AiAnalysisJobState.failed;
      await _queueRepository.saveJob(latest.copyWith(
        state: nextState,
        updatedAt: now,
        retryCount: nextRetry,
        lastError: error.toString(),
        stageLogs: _appendStageLog(
          latest.stageLogs,
          AiAnalysisStageLog(
            stage: latest.currentStage,
            startedAt: DateTime.now(),
            message: nextState == AiAnalysisJobState.incomplete
                ? '用户画像生成中断，等待继续'
                : '用户画像生成失败',
            inputSummary: 'target=${job.targetId}',
            error: error.toString(),
            retryCount: nextRetry,
          ),
        ),
      ));
    }
  }

  Future<void> _saveQueueOnlyStage(
    AiAnalysisJob job, {
    required AiAnalysisJobState state,
    required AiAnalysisStage stage,
    required String message,
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
        inputSummary: inputSummary ?? 'target=${job.targetId}',
        outputSummary: outputSummary ??
            [
              if (completedStages != null)
                'completed=${completedStages.map((item) => item.name).join(',')}',
              'state=${state.name}',
            ].join(' '),
        retryCount: latest.retryCount,
      ),
    );
    await _queueRepository.saveJob(latest.copyWith(
      state: state,
      currentStage: stage,
      updatedAt: DateTime.now(),
      completedStages: completedStages,
      stageLogs: logs,
      retryCount: latest.retryCount,
      clearLastError: clearLastError,
    ));
  }

  Future<void> _savePeriodStage(
    AiAnalysisJob job, {
    required AiAnalysisJobState state,
    required AiAnalysisStage stage,
    required String message,
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
        inputSummary: inputSummary ?? 'target=${job.targetId}',
        outputSummary: outputSummary ??
            [
              if (completedStages != null)
                'completed=${completedStages.map((item) => item.name).join(',')}',
              'state=${state.name}',
            ].join(' '),
        retryCount: latest.retryCount,
      ),
    );
    await _queueRepository.saveJob(latest.copyWith(
      state: state,
      currentStage: stage,
      updatedAt: DateTime.now(),
      completedStages: completedStages,
      stageLogs: logs,
      retryCount: latest.retryCount,
      clearLastError: clearLastError,
    ));
    await _periodSummaryRepository.saveStatus(PeriodSummaryStatus(
      id: job.targetId,
      state: state == AiAnalysisJobState.completed
          ? PeriodSummaryState.completed
          : PeriodSummaryState.generating,
      updatedAt: DateTime.now(),
      message: message,
    ));
  }

  Future<void> _handleUnexpectedStageError(
    AiAnalysisJob job,
    Object error,
    DateTime now,
  ) async {
    final latest = await _queueRepository.getJob(job.id) ?? job;
    final nextRetry = latest.retryCount + 1;
    final hasRecoverableArtifacts = latest.completedStages.isNotEmpty ||
        (latest.summaryId?.isNotEmpty ?? false) ||
        latest.segmentIds.isNotEmpty ||
        latest.embeddingIds.isNotEmpty ||
        (latest.retrievalTraceId?.isNotEmpty ?? false);
    final shouldKeepRecoverable = hasRecoverableArtifacts && nextRetry < 3;
    final nextState = shouldKeepRecoverable
        ? AiAnalysisJobState.incomplete
        : AiAnalysisJobState.failed;
    final analysisState = shouldKeepRecoverable
        ? DiaryAnalysisState.incomplete
        : DiaryAnalysisState.failed;
    final message = shouldKeepRecoverable ? '阶段被中断，等待继续' : '阶段失败';
    final statusMessage =
        shouldKeepRecoverable ? '已保留本地资料，下次将从未完成阶段继续' : error.toString();

    await _queueRepository.saveJob(latest.copyWith(
      state: nextState,
      currentStage: latest.currentStage,
      updatedAt: now,
      retryCount: nextRetry,
      lastError: error.toString(),
      stageLogs: _appendStageLog(
        latest.stageLogs,
        AiAnalysisStageLog(
          stage: latest.currentStage,
          startedAt: DateTime.now(),
          message: message,
          inputSummary: 'entryId=${job.entryId}',
          outputSummary: shouldKeepRecoverable
              ? [
                  if (latest.completedStages.isNotEmpty)
                    'completed=${latest.completedStages.map((item) => item.name).join(',')}',
                  if (latest.summaryId?.isNotEmpty ?? false)
                    'summaryId=${latest.summaryId}',
                  if (latest.segmentIds.isNotEmpty)
                    'segments=${latest.segmentIds.length}',
                  if (latest.embeddingIds.isNotEmpty)
                    'embeddings=${latest.embeddingIds.length}',
                ].join(' ')
              : '',
          error: error.toString(),
          retryCount: nextRetry,
        ),
      ),
    ));
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: job.entryId,
      state: analysisState,
      updatedAt: DateTime.now(),
      message: statusMessage,
    ));
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
      message: '本地资料已整理，等待 AI 可用后生成今日分析',
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
    String? summaryId,
    List<String>? segmentIds,
    List<String>? embeddingIds,
    String? insightId,
    String? retrievalTraceId,
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
      summaryId: summaryId,
      segmentIds: segmentIds,
      embeddingIds: embeddingIds,
      insightId: insightId,
      retrievalTraceId: retrievalTraceId,
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
    final entryResult =
        await _embeddingService.embedForAi(_embeddingTextBuilder.entryText(
      entry,
      summary,
    ));
    if (!_embeddingMatches(entryEmbedding, entryResult)) {
      return false;
    }
    final summaryResult = await _embeddingService
        .embedForAi(_embeddingTextBuilder.summaryText(summary));
    if (!_embeddingMatches(summaryEmbedding, summaryResult)) {
      return false;
    }
    for (final segment in segments) {
      final embedding = await _embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.segment,
        sourceId: segment.id,
      );
      if (embedding == null) return false;
      final segmentResult = await _embeddingService
          .embedForAi(_embeddingTextBuilder.segmentText(segment));
      if (!_embeddingMatches(embedding, segmentResult)) {
        return false;
      }
    }
    return true;
  }

  bool _embeddingMatches(AiEmbedding embedding, AiEmbeddingResult result) {
    return embedding.textHash == result.textHash &&
        embedding.modelId == result.modelId &&
        embedding.modelVersion == result.modelVersion &&
        embedding.dimensions == result.dimensions;
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
    final result = await _embeddingService.embedForAi(text);
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

  List<DiarySegment> _fallbackSegments(DiaryEntry entry) {
    return [
      DiarySegment(
        id: '${entry.id}#s1',
        entryId: entry.id,
        index: 0,
        text: entry.content,
        summary: entry.excerpt,
        topics: const [],
        people: const [],
        boundary: DiarySegmentBoundary.wholeEntry,
        createdAt: DateTime.now(),
      ),
    ];
  }

  EntrySummary _fallbackSummary(
    DiaryEntry entry,
    List<DiarySegment> segments,
  ) {
    final brief = entry.bodyPreview.trim().isEmpty
        ? entry.excerpt
        : entry.bodyPreview.trim();
    return EntrySummary(
      entryId: entry.id,
      date: entry.date,
      entryUpdatedAt: entry.updatedAt,
      generatedAt: DateTime.now(),
      title: entry.title ?? entry.excerpt,
      brief: brief,
      keyPoints: [
        if (segments.isNotEmpty) segments.first.summary else entry.excerpt,
      ],
      topics: const [],
      people: const [],
      places: [
        if (entry.location.trim().isNotEmpty &&
            entry.location.trim() != '未选择地点')
          entry.location.trim(),
      ],
      emotion: '',
      importance: 0.42,
      importantQuotes: const [],
      generator: 'fallback-local-v1',
    );
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  DateTime? _periodFromJob(AiAnalysisJob job) {
    if (job.type == AiAnalysisJobType.yearSummary) {
      final value = job.targetId.startsWith('year:')
          ? job.targetId.substring('year:'.length)
          : job.targetId;
      final year = int.tryParse(value);
      return year == null ? null : DateTime(year);
    }
    if (job.type == AiAnalysisJobType.monthSummary) {
      final value = job.targetId.startsWith('month:')
          ? job.targetId.substring('month:'.length)
          : job.targetId;
      final parts = value.split('-');
      if (parts.length != 2) return null;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year == null || month == null) return null;
      return DateTime(year, month);
    }
    return null;
  }

  String _periodEntrySummary(
    AiAnalysisJobType type,
    DateTime period,
    List<DiaryEntry> entries,
  ) {
    final scoped = type == AiAnalysisJobType.yearSummary
        ? entries.where((entry) => entry.date.year == period.year)
        : entries.where((entry) =>
            entry.date.year == period.year && entry.date.month == period.month);
    return [
      'target=${type.name}',
      if (type == AiAnalysisJobType.yearSummary) 'year=${period.year}',
      if (type == AiAnalysisJobType.monthSummary)
        'month=${period.year}-${period.month.toString().padLeft(2, '0')}',
      'entries=${scoped.length}',
    ].join(' ');
  }

  String _dateTimeLabel(DateTime date) {
    final day = _dateLabel(date);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day $hour:$minute';
  }

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

  List<String> _embeddingIds(
    DiaryEntry entry,
    List<DiarySegment> segments,
  ) {
    return [
      '${AiEmbeddingSourceType.entry.name}:${entry.id}',
      '${AiEmbeddingSourceType.summary.name}:${entry.id}',
      for (final segment in segments)
        '${AiEmbeddingSourceType.segment.name}:${segment.id}',
    ];
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

  String _memoryUpdateOutputSummary(DiaryInsight insight) {
    return [
      'memoryUpdate=${insight.memorySummary.trim().isEmpty ? 0 : 1}',
      'memoryTags=${insight.memoryTags.length}',
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
    if (job.type == AiAnalysisJobType.embeddingRebuild) {
      await _insightRepository.saveStatus(DiaryAnalysisStatus(
        entryId: job.entryId,
        state: DiaryAnalysisState.failed,
        updatedAt: DateTime.now(),
        message: message,
      ));
      return;
    }
    if (job.type != AiAnalysisJobType.diary) {
      await _periodSummaryRepository.saveStatus(PeriodSummaryStatus(
        id: job.targetId,
        state: PeriodSummaryState.failed,
        updatedAt: DateTime.now(),
        message: message,
      ));
      return;
    }
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: job.entryId,
      state: DiaryAnalysisState.failed,
      updatedAt: DateTime.now(),
      message: message,
    ));
  }

  Future<void> _discardMissingEntryJob(
    AiAnalysisJob job,
    String message,
  ) async {
    await _queueRepository.deleteJob(job.id);
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: job.entryId,
      state: DiaryAnalysisState.completed,
      updatedAt: DateTime.now(),
      message: message,
    ));
  }
}
