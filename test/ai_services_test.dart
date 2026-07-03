import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trace_stone/data/models/diary_entry.dart';
import 'package:trace_stone/data/models/diary_analysis_status.dart';
import 'package:trace_stone/data/models/diary_insight.dart';
import 'package:trace_stone/data/models/diary_segment.dart';
import 'package:trace_stone/data/models/entry_summary.dart';
import 'package:trace_stone/data/models/ai_embedding.dart';
import 'package:trace_stone/data/models/ai_feedback.dart';
import 'package:trace_stone/data/models/ai_profile.dart';
import 'package:trace_stone/data/models/ai_profile_preference.dart';
import 'package:trace_stone/data/models/ai_prompt_trace.dart';
import 'package:trace_stone/data/models/ai_retrieval_trace.dart';
import 'package:trace_stone/data/models/calendar_memory.dart';
import 'package:trace_stone/data/models/ai_analysis_job.dart';
import 'package:trace_stone/data/models/ai_context_package.dart';
import 'package:trace_stone/data/models/memory_entry.dart';
import 'package:trace_stone/data/models/period_summary.dart';
import 'package:trace_stone/data/models/stone_task.dart';
import 'package:trace_stone/data/repositories/diary_repository.dart';
import 'package:trace_stone/data/repositories/ai_analysis_queue_repository.dart';
import 'package:trace_stone/data/repositories/ai_embedding_repository.dart';
import 'package:trace_stone/data/repositories/ai_prompt_trace_repository.dart';
import 'package:trace_stone/data/repositories/ai_retrieval_trace_repository.dart';
import 'package:trace_stone/data/repositories/ai_profile_preference_repository.dart';
import 'package:trace_stone/data/repositories/calendar_memory_repository.dart';
import 'package:trace_stone/data/repositories/entry_summary_repository.dart';
import 'package:trace_stone/data/repositories/insight_repository.dart';
import 'package:trace_stone/data/repositories/memory_repository.dart';
import 'package:trace_stone/data/repositories/stone_task_repository.dart';
import 'package:trace_stone/data/services/ai_context_builder.dart';
import 'package:trace_stone/data/services/ai_analysis_queue_runner.dart';
import 'package:trace_stone/data/services/ai_search_service.dart';
import 'package:trace_stone/data/services/companion_answer_service.dart';
import 'package:trace_stone/data/services/diary_analysis_service.dart';
import 'package:trace_stone/data/services/embedding_service.dart';
import 'package:trace_stone/data/services/entry_summary_service.dart';
import 'package:trace_stone/data/services/period_summary_service.dart';
import 'package:trace_stone/data/services/profile_projection_service.dart';

void main() {
  group('AiPromptTrace', () {
    test('round trips full prompts and remains legacy compatible', () {
      final date = DateTime(2026, 7, 3);
      final trace = AiPromptTrace(
        id: 'entry',
        scenario: 'todayInsight',
        createdAt: date,
        contextSummary: 'sources=1',
        systemPromptPreview: 'system preview',
        userPromptPreview: 'user preview',
        systemPromptLength: 6,
        userPromptLength: 4,
        systemPrompt: '完整 system prompt',
        userPrompt: '完整 user prompt',
      );

      final restored = AiPromptTrace.fromJson(trace.toJson());
      final legacy = AiPromptTrace.fromJson({
        'id': 'legacy',
        'scenario': 'todayInsight',
        'createdAt': date.toIso8601String(),
        'contextSummary': 'sources=0',
        'systemPromptPreview': 'old system',
        'userPromptPreview': 'old user',
        'systemPromptLength': 10,
        'userPromptLength': 20,
      });

      expect(restored.systemPrompt, '完整 system prompt');
      expect(restored.userPrompt, '完整 user prompt');
      expect(legacy.systemPrompt, isNull);
      expect(legacy.userPromptPreview, 'old user');
    });

    test('can clear prompt and retrieval traces for an entry', () async {
      SharedPreferences.setMockInitialValues({});
      const promptRepository = AiPromptTraceRepository();
      const retrievalRepository = AiRetrievalTraceRepository();
      final date = DateTime(2026, 7, 3);
      await promptRepository.saveTrace(AiPromptTrace(
        id: 'entry',
        scenario: 'todayInsight',
        createdAt: date,
        contextSummary: 'sources=1',
        systemPromptPreview: 'system',
        userPromptPreview: 'user',
        systemPromptLength: 6,
        userPromptLength: 4,
        systemPrompt: 'full system',
        userPrompt: 'full user',
      ));
      await retrievalRepository.saveTrace(AiRetrievalTrace(
        entryId: 'entry',
        generatedAt: date,
        items: const [],
      ));

      await promptRepository.deleteTrace('entry');
      await retrievalRepository.deleteForEntry('entry');

      expect(await promptRepository.getTrace('entry'), isNull);
      expect(await retrievalRepository.getTrace('entry'), isNull);
    });
  });

  group('DiaryInsight', () {
    test('round trips structured claims with evidence', () {
      final date = DateTime(2026, 7, 3);
      final insight = DiaryInsight(
        entryId: 'entry',
        entryDate: date,
        generatedAt: date,
        reflection: '今天的记录有恢复感。',
        relatedMemories: const [],
        emotion: '放松',
        keywords: const ['运动'],
        people: const [],
        stoneTitle: '散步 10 分钟',
        stoneDescription: '晚饭后即可。',
        memorySummary: '运动后恢复状态。',
        memoryTags: const ['运动'],
        facts: const [
          InsightClaim(
            text: '今天记录了跑步。',
            evidence: [
              InsightEvidence(type: 'current_entry', id: 'entry#s1'),
            ],
          ),
        ],
        hypotheses: const [
          InsightClaim(text: '运动可能有助于恢复。', confidence: 0.62),
        ],
        profileUpdateCandidates: const [
          ProfileUpdateCandidate(
            field: 'self_regulation',
            value: '运动可能帮助恢复状态',
            confidence: 0.58,
            evidence: [
              InsightEvidence(type: 'current_entry', id: 'entry#s1'),
            ],
          ),
        ],
        relationshipUpdates: const [
          RelationshipUpdateCandidate(
            personName: '小林',
            summary: '一起讨论产品设计',
            relationship: '同事',
            confidence: 0.55,
          ),
        ],
        contradictions: const [
          InsightContradiction(
            oldMemoryId: 'memory-old',
            newEvidence: '今天运动后状态变好',
            interpretation: '旧记忆可能需要增加条件',
            confidence: 0.6,
          ),
        ],
      );

      final restored = DiaryInsight.fromJson(insight.toJson());

      expect(restored.facts.single.text, '今天记录了跑步。');
      expect(restored.facts.single.evidence.single.id, 'entry#s1');
      expect(restored.hypotheses.single.confidence, 0.62);
      expect(restored.profileUpdateCandidates.single.field, 'self_regulation');
      expect(restored.relationshipUpdates.single.personName, '小林');
      expect(restored.contradictions.single.oldMemoryId, 'memory-old');
    });

    test('reads snake case update candidates from AI json', () {
      final insight = DiaryInsight.fromJson({
        'entryId': 'entry',
        'profile_update_candidates': [
          {
            'field': 'stress_pattern',
            'value': '汇报可能带来压力',
            'confidence': 0.57,
          }
        ],
        'relationship_updates': [
          {
            'person': '妈妈',
            'summary': '因为安排产生争执',
            'pattern': '边界感相关互动候选',
          }
        ],
        'contradictions': [
          {
            'old_memory_id': 'memory_social',
            'new_evidence': '聚会后感觉放松',
            'interpretation': '旧社交压力记忆可能需要降权',
          }
        ],
      });

      expect(insight.profileUpdateCandidates.single.field, 'stress_pattern');
      expect(insight.relationshipUpdates.single.personName, '妈妈');
      expect(insight.contradictions.single.oldMemoryId, 'memory_social');
    });

    test('reads legacy insight json without structured claims', () {
      final insight = DiaryInsight.fromJson({
        'entryId': 'entry',
        'reflection': '旧洞察',
      });

      expect(insight.reflection, '旧洞察');
      expect(insight.facts, isEmpty);
      expect(insight.signals, isEmpty);
      expect(insight.hypotheses, isEmpty);
      expect(insight.suggestions, isEmpty);
      expect(insight.profileUpdateCandidates, isEmpty);
      expect(insight.relationshipUpdates, isEmpty);
      expect(insight.contradictions, isEmpty);
    });
  });

  group('InsightRepository', () {
    test('lists saved insights and removes deleted entries from index',
        () async {
      SharedPreferences.setMockInitialValues({});
      const repository = InsightRepository();
      final date = DateTime(2026, 7, 3);
      final first = _insight(
        entryId: 'first',
        date: date,
        personName: '小林',
      );
      final second = _insight(
        entryId: 'second',
        date: date.add(const Duration(days: 1)),
        personName: '妈妈',
      );

      await repository.saveInsight(first);
      await repository.saveInsight(second);
      await repository.deleteForEntry('first');

      final insights = await repository.listInsights();

      expect(insights.map((item) => item.entryId), ['second']);
      expect(insights.single.relationshipUpdates.single.personName, '妈妈');
    });
  });

  group('AiAnalysisQueueRepository', () {
    test('job round trips stage logs and reads legacy jobs', () {
      final date = DateTime(2026, 7, 3);
      final job = AiAnalysisJob(
        id: 'job',
        entryId: 'entry',
        pipelineVersion: 1,
        state: AiAnalysisJobState.running,
        currentStage: AiAnalysisStage.embedding,
        createdAt: date,
        updatedAt: date,
        stageLogs: [
          AiAnalysisStageLog(
            stage: AiAnalysisStage.embedding,
            startedAt: date,
            message: '生成多级向量',
            inputSummary: 'entryId=entry',
            outputSummary: 'completed=segmenting',
            retryCount: 1,
          ),
        ],
      );
      final restored = AiAnalysisJob.fromJson(job.toJson());
      final legacy = AiAnalysisJob.fromJson({
        'id': 'legacy',
        'entryId': 'entry',
        'pipelineVersion': 1,
        'state': 'pending',
        'currentStage': 'queued',
        'createdAt': date.toIso8601String(),
        'updatedAt': date.toIso8601String(),
      });

      expect(restored.stageLogs.single.stage, AiAnalysisStage.embedding);
      expect(restored.stageLogs.single.outputSummary, 'completed=segmenting');
      expect(legacy.stageLogs, isEmpty);
    });

    test('snapshot exposes queue progress counts', () {
      final date = DateTime(2026, 7, 3);
      final running = AiAnalysisJob(
        id: 'running',
        entryId: 'running',
        pipelineVersion: 1,
        state: AiAnalysisJobState.running,
        currentStage: AiAnalysisStage.embedding,
        createdAt: date,
        updatedAt: date,
      );
      final pending = AiAnalysisJob(
        id: 'pending',
        entryId: 'pending',
        pipelineVersion: 1,
        state: AiAnalysisJobState.pending,
        currentStage: AiAnalysisStage.queued,
        createdAt: date,
        updatedAt: date,
      );
      final incomplete = AiAnalysisJob(
        id: 'incomplete',
        entryId: 'incomplete',
        pipelineVersion: 1,
        state: AiAnalysisJobState.incomplete,
        currentStage: AiAnalysisStage.generatingInsight,
        createdAt: date,
        updatedAt: date,
      );
      final completed = AiAnalysisJob(
        id: 'completed',
        entryId: 'completed',
        pipelineVersion: 1,
        state: AiAnalysisJobState.completed,
        currentStage: AiAnalysisStage.completed,
        createdAt: date,
        updatedAt: date,
      );
      final snapshot = AiAnalysisQueueSnapshot(
        jobs: [running, pending, incomplete, completed],
        currentJob: running,
      );

      expect(snapshot.runnableCount, 2);
      expect(snapshot.waitingCount, 2);
      expect(snapshot.incompleteCount, 1);
      expect(snapshot.completedCount, 1);
      expect(snapshot.totalTrackedCount, 4);
      expect(snapshot.activeOrdinal, 1);
    });

    test('reenqueue resets failed job with current entry version', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = AiAnalysisQueueRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'entry',
        date: date,
        content: '今天需要重新分析。',
      );
      await repository.saveJob(AiAnalysisJob(
        id: entry.id,
        entryId: entry.id,
        pipelineVersion: 1,
        state: AiAnalysisJobState.failed,
        currentStage: AiAnalysisStage.generatingInsight,
        createdAt: date,
        updatedAt: date,
        retryCount: 5,
        lastError: 'failed',
      ));

      final job = await repository.enqueueEntry(entry);

      expect(job.state, AiAnalysisJobState.pending);
      expect(job.currentStage, AiAnalysisStage.queued);
      expect(job.retryCount, 0);
      expect(job.lastError, isNull);
      expect(job.pipelineVersion, entry.updatedAt.microsecondsSinceEpoch);
      expect((await repository.listJobs()).single.id, entry.id);
    });

    test('runner resumes incomplete jobs without rewriting existing embeddings',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const summaryService = EntrySummaryService();
      const embeddingService = EmbeddingService();
      final entry = _entry(
        id: 'resume-entry',
        date: DateTime(2026, 7, 3),
        content: '今天先写工作压力。\n\n---\n\n晚上散步恢复了一点。',
      );
      await diaryRepository.saveEntry(entry);
      final segments = summaryService.buildSegments(entry);
      final summary = summaryService.buildSummary(entry, segments);
      await summaryRepository.saveSegments(entry.id, segments);
      await summaryRepository.saveSummary(summary);
      final oldGeneratedAt = DateTime(2026, 7, 1);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: entry.id,
        text: _entryEmbeddingTextForTest(entry, summary),
        generatedAt: oldGeneratedAt,
      );
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
        text: _summaryEmbeddingTextForTest(summary),
        generatedAt: oldGeneratedAt,
      );
      for (final segment in segments) {
        await _saveTestEmbedding(
          repository: embeddingRepository,
          service: embeddingService,
          entryId: entry.id,
          sourceType: AiEmbeddingSourceType.segment,
          sourceId: segment.id,
          text: _segmentEmbeddingTextForTest(segment),
          generatedAt: oldGeneratedAt,
        );
      }
      await queueRepository.saveJob(AiAnalysisJob(
        id: entry.id,
        entryId: entry.id,
        pipelineVersion: entry.updatedAt.microsecondsSinceEpoch,
        state: AiAnalysisJobState.incomplete,
        currentStage: AiAnalysisStage.embedding,
        createdAt: oldGeneratedAt,
        updatedAt: oldGeneratedAt,
        completedStages: const [
          AiAnalysisStage.preparing,
          AiAnalysisStage.segmenting,
          AiAnalysisStage.generatingSummary,
        ],
      ));

      await AiAnalysisQueueRunner(
        analysisService: _FakeDiaryAnalysisService(),
      ).processNext();

      final job = await queueRepository.getJob(entry.id);
      final entryEmbedding = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: entry.id,
      );

      expect(job?.state, AiAnalysisJobState.completed);
      expect(job?.completedStages, contains(AiAnalysisStage.embedding));
      expect(job?.completedStages, contains(AiAnalysisStage.generatingInsight));
      expect(job?.stageLogs.map((log) => log.stage),
          contains(AiAnalysisStage.embedding));
      expect(job?.stageLogs.map((log) => log.message), contains('整理完成'));
      expect(entryEmbedding?.generatedAt, oldGeneratedAt);
    });

    test('runner rebuilds stale summary and segments after entry edits',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const summaryService = EntrySummaryService();
      final oldEntry = _entry(
        id: 'edited-entry',
        date: DateTime(2026, 7, 3, 20),
        content: '旧内容：今天只写了工作压力。',
      );
      final newEntry = _entry(
        id: oldEntry.id,
        date: DateTime(2026, 7, 3, 21),
        content: '新内容：晚上散步以后状态恢复。',
      );
      await diaryRepository.saveEntry(oldEntry);
      final oldSegments = summaryService.buildSegments(oldEntry);
      final oldSummary = summaryService.buildSummary(oldEntry, oldSegments);
      await summaryRepository.saveSegments(oldEntry.id, oldSegments);
      await summaryRepository.saveSummary(oldSummary);
      await diaryRepository.saveEntry(newEntry);
      await queueRepository.enqueueEntry(newEntry);

      await AiAnalysisQueueRunner(
        analysisService: _FakeDiaryAnalysisService(),
      ).processNext();

      final rebuiltSummary = await summaryRepository.getSummary(newEntry.id);
      final rebuiltSegments = await summaryRepository.listSegments(newEntry.id);
      final job = await queueRepository.getJob(newEntry.id);

      expect(rebuiltSummary?.entryUpdatedAt, newEntry.updatedAt);
      expect(rebuiltSummary?.brief, contains('晚上散步'));
      expect(rebuiltSegments.single.text, contains('晚上散步'));
      expect(job?.stageLogs.map((log) => log.message),
          containsAll(['日记已更新，重建日记片段', '日记已更新，重建摘要包']));
    });

    test('runner rebuilds embeddings when stored hashes are stale', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const summaryService = EntrySummaryService();
      const embeddingService = EmbeddingService();
      final entry = _entry(
        id: 'stale-embedding-entry',
        date: DateTime(2026, 7, 3),
        content: '晚上散步以后状态恢复。',
      );
      await diaryRepository.saveEntry(entry);
      final segments = summaryService.buildSegments(entry);
      final summary = summaryService.buildSummary(entry, segments);
      await summaryRepository.saveSegments(entry.id, segments);
      await summaryRepository.saveSummary(summary);
      final oldGeneratedAt = DateTime(2026, 7, 1);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: entry.id,
        text: '旧 entry embedding',
        generatedAt: oldGeneratedAt,
      );
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
        text: '旧 summary embedding',
        generatedAt: oldGeneratedAt,
      );
      final oldSummaryEmbedding = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
      );
      for (final segment in segments) {
        await _saveTestEmbedding(
          repository: embeddingRepository,
          service: embeddingService,
          entryId: entry.id,
          sourceType: AiEmbeddingSourceType.segment,
          sourceId: segment.id,
          text: '旧 segment embedding',
          generatedAt: oldGeneratedAt,
        );
      }
      await queueRepository.enqueueEntry(entry);

      await AiAnalysisQueueRunner(
        analysisService: _FakeDiaryAnalysisService(),
      ).processNext();

      final summaryEmbedding = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
      );
      final job = await queueRepository.getJob(entry.id);

      expect(summaryEmbedding?.textHash, isNot(oldSummaryEmbedding?.textHash));
      expect(summaryEmbedding?.generatedAt, isNot(oldGeneratedAt));
      expect(job?.stageLogs.map((log) => log.message), contains('生成多级向量'));
    });

    test('backfill enqueues entries with missing AI artifacts only', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const insightRepository = InsightRepository();
      const summaryService = EntrySummaryService();
      const embeddingService = EmbeddingService();
      final date = DateTime(2026, 7, 3);
      final missing = _entry(
        id: 'missing-ai',
        date: date,
        content: '这篇旧日记还没有 AI 资料。',
      );
      final complete = _entry(
        id: 'complete-ai',
        date: date,
        content: '这篇日记已经整理完成。',
      );
      final queued = _entry(
        id: 'already-queued',
        date: date,
        content: '这篇日记已经在队列里。',
      );
      for (final entry in [missing, complete, queued]) {
        await diaryRepository.saveEntry(entry);
      }
      final segments = summaryService.buildSegments(complete);
      final summary = summaryService.buildSummary(complete, segments);
      await summaryRepository.saveSegments(complete.id, segments);
      await summaryRepository.saveSummary(summary);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: complete.id,
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: complete.id,
        text: _entryEmbeddingTextForTest(complete, summary),
        generatedAt: date,
      );
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: complete.id,
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: complete.id,
        text: _summaryEmbeddingTextForTest(summary),
        generatedAt: date,
      );
      for (final segment in segments) {
        await _saveTestEmbedding(
          repository: embeddingRepository,
          service: embeddingService,
          entryId: complete.id,
          sourceType: AiEmbeddingSourceType.segment,
          sourceId: segment.id,
          text: _segmentEmbeddingTextForTest(segment),
          generatedAt: date,
        );
      }
      await insightRepository.saveInsight(_insight(
        entryId: complete.id,
        date: complete.date,
      ));
      await queueRepository.saveJob(AiAnalysisJob(
        id: complete.id,
        entryId: complete.id,
        pipelineVersion: complete.updatedAt.microsecondsSinceEpoch,
        state: AiAnalysisJobState.completed,
        currentStage: AiAnalysisStage.completed,
        createdAt: date,
        updatedAt: date,
      ));
      await queueRepository.enqueueEntry(queued);

      final count = await const AiAnalysisQueueRunner().enqueueBackfill();
      final jobs = await queueRepository.listJobs();

      expect(count, 1);
      expect(jobs.where((job) => job.id == 'missing-ai').single.state,
          AiAnalysisJobState.pending);
      expect(jobs.where((job) => job.id == 'already-queued'), hasLength(1));
      expect(jobs.where((job) => job.id == 'complete-ai').single.state,
          AiAnalysisJobState.completed);
    });

    test('developer rebuild clears generated artifacts before enqueue',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const insightRepository = InsightRepository();
      const promptRepository = AiPromptTraceRepository();
      const retrievalRepository = AiRetrievalTraceRepository();
      const queueRunner = AiAnalysisQueueRunner();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'rebuild-entry',
        date: date,
        content: '今天散步以后状态恢复。',
      );
      await diaryRepository.saveEntry(entry);
      final segments = const EntrySummaryService().buildSegments(entry);
      final summary = const EntrySummaryService().buildSummary(entry, segments);
      await summaryRepository.saveSummary(summary);
      await summaryRepository.saveSegments(entry.id, segments);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: const EmbeddingService(),
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
        text: summary.brief,
        generatedAt: date,
      );
      await insightRepository.saveInsight(_insight(
        entryId: entry.id,
        date: date,
      ));
      await promptRepository.saveTrace(AiPromptTrace(
        id: entry.id,
        scenario: 'todayInsight',
        createdAt: date,
        contextSummary: 'sources=1',
        systemPromptPreview: 'system',
        userPromptPreview: 'user',
        systemPromptLength: 6,
        userPromptLength: 4,
      ));
      await retrievalRepository.saveTrace(AiRetrievalTrace(
        entryId: entry.id,
        generatedAt: date,
        items: const [],
      ));

      await insightRepository.deleteForEntry(entry.id);
      await embeddingRepository.deleteForEntry(entry.id);
      await summaryRepository.deleteForEntry(entry.id);
      await promptRepository.deleteTrace(entry.id);
      await retrievalRepository.deleteForEntry(entry.id);
      await queueRunner.enqueue(entry, start: false);

      expect(await insightRepository.getInsight(entry.id), isNull);
      expect(await summaryRepository.getSummary(entry.id), isNull);
      expect(await embeddingRepository.listForEntry(entry.id), isEmpty);
      expect(await promptRepository.getTrace(entry.id), isNull);
      expect(await retrievalRepository.getTrace(entry.id), isNull);
      expect((await const AiAnalysisQueueRepository().getJob(entry.id))?.state,
          AiAnalysisJobState.pending);
    });

    test('defers insight generation when custom AI is unavailable', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const queueRunner = AiAnalysisQueueRunner();
      const queueRepository = AiAnalysisQueueRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const insightRepository = InsightRepository();
      final entry = _entry(
        id: 'no-ai-entry',
        date: DateTime(2026, 7, 3),
        content: '今天写了一篇没有配置 AI 时的日记。',
      );
      await diaryRepository.saveEntry(entry);
      await queueRunner.enqueue(entry, start: false);

      await queueRunner.processUntilIdle(maxJobs: 3);

      final job = await queueRepository.getJob(entry.id);
      final status = await insightRepository.getStatus(entry.id);
      final summary = await summaryRepository.getSummary(entry.id);
      final embeddings = await embeddingRepository.listForEntry(entry.id);

      expect(job?.state, AiAnalysisJobState.incomplete);
      expect(job?.currentStage, AiAnalysisStage.generatingInsight);
      expect(job?.retryCount, 0);
      expect(job?.lastError, contains('等待 AI 可用'));
      expect(status?.state, DiaryAnalysisState.incomplete);
      expect(status?.message, contains('等待 AI 可用'));
      expect(summary, isNotNull);
      expect(embeddings, isNotEmpty);
    });
  });

  group('StoneTaskRepository', () {
    test('saves tasks and toggles completion', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = StoneTaskRepository();
      final date = DateTime(2026, 7, 3);
      await repository.saveTask(StoneTask(
        id: 'stone:entry',
        sourceEntryId: 'entry',
        title: '散步 10 分钟',
        description: '晚饭后即可。',
        createdAt: date,
        updatedAt: date,
      ));

      await repository.addCheckIn('stone:entry', note: '晚饭后散步了 8 分钟');
      await repository.setCompleted('stone:entry', true);
      final completed = await repository.getTask('stone:entry');
      await repository.setCompleted('stone:entry', false);
      final active = await repository.getTask('stone:entry');

      expect(completed?.status, StoneTaskStatus.completed);
      expect(completed?.completedAt, isNotNull);
      expect(completed?.checkIns.single.note, '晚饭后散步了 8 分钟');
      expect(active?.status, StoneTaskStatus.active);
      expect(active?.completedAt, isNull);
      expect(active?.copyWith(dueDate: date).dueDate, date);
      expect(
          active?.copyWith(dueDate: date).copyWith(clearDueDate: true).dueDate,
          isNull);
      expect((await repository.listTasks()).single.title, '散步 10 分钟');
    });
  });

  group('CalendarMemoryRepository', () {
    test('saves custom solar anniversaries', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = CalendarMemoryRepository();
      final date = DateTime(2026, 7, 3);

      await repository.saveMemory(CalendarMemory(
        id: 'anniversary',
        title: '外婆生日',
        month: 7,
        day: 3,
        createdAt: date,
        updatedAt: date,
        note: '重要家庭纪念日',
      ));

      final memories = await repository.listMemories();

      expect(memories.single.title, '外婆生日');
      expect(memories.single.month, 7);
      expect(memories.single.day, 3);
      expect(memories.single.enabled, isTrue);
    });
  });

  group('ProfileProjectionService', () {
    test('promotes repeated profile candidates into stable facts', () {
      final insights = [
        _insight(
          entryId: 'first',
          date: DateTime(2026, 7, 1),
          profileCandidate: const ProfileUpdateCandidate(
            field: 'self_regulation',
            value: '散步可能帮助恢复状态',
            confidence: 0.6,
          ),
        ),
        _insight(
          entryId: 'second',
          date: DateTime(2026, 7, 2),
          profileCandidate: const ProfileUpdateCandidate(
            field: 'self_regulation',
            value: '散步可能帮助恢复状态',
            confidence: 0.62,
          ),
        ),
        _insight(
          entryId: 'third',
          date: DateTime(2026, 7, 2),
          profileCandidate: const ProfileUpdateCandidate(
            field: 'self_regulation',
            value: '散步可能帮助恢复状态',
            confidence: 0.59,
          ),
        ),
      ];

      final facts =
          const ProfileProjectionService().buildProfileFacts(insights);

      expect(facts.single.status, ProfileFactStatus.stable);
      expect(facts.single.evidenceCount, 3);
      expect(facts.single.distinctDays, 2);
      expect(facts.single.confidence, closeTo(0.603, 0.001));
    });

    test('builds relationship profiles from interaction candidates', () {
      final insights = [
        _insight(
          entryId: 'first',
          date: DateTime(2026, 7, 1),
          personName: '妈妈',
          relationshipUpdate: const RelationshipUpdateCandidate(
            personName: '妈妈',
            relationship: 'family',
            summary: '讨论假期安排时有些委屈',
            emotion: '委屈',
            pattern: '边界感相关互动候选',
            confidence: 0.6,
          ),
        ),
        _insight(
          entryId: 'second',
          date: DateTime(2026, 7, 3),
          personName: '妈妈',
          relationshipUpdate: const RelationshipUpdateCandidate(
            personName: '妈妈',
            relationship: 'family',
            summary: '晚饭后沟通更平和',
            emotion: '平和',
            pattern: '晚间沟通更顺畅',
            confidence: 0.62,
          ),
        ),
      ];

      final profiles =
          const ProfileProjectionService().buildRelationshipProfiles(insights);

      expect(profiles.single.personName, '妈妈');
      expect(profiles.single.relationship, 'family');
      expect(profiles.single.status, ProfileFactStatus.emerging);
      expect(profiles.single.recentInteractions.first.entryId, 'second');
      expect(profiles.single.patterns, contains('边界感相关互动候选'));
    });

    test('applies user confirmation and hidden preferences', () async {
      SharedPreferences.setMockInitialValues({});
      const projectionService = ProfileProjectionService();
      const preferenceRepository = AiProfilePreferenceRepository();
      final date = DateTime(2026, 7, 3);
      final insights = [
        _insight(
          entryId: 'weak-profile',
          date: date,
          profileCandidate: const ProfileUpdateCandidate(
            field: 'stress_pattern',
            value: '汇报前可能更容易紧张',
            confidence: 0.52,
          ),
        ),
        _insight(
          entryId: 'hidden-profile',
          date: date.add(const Duration(days: 1)),
          profileCandidate: const ProfileUpdateCandidate(
            field: 'preference',
            value: '可能喜欢夜间写作',
            confidence: 0.62,
          ),
        ),
        _insight(
          entryId: 'relationship-hidden',
          date: date,
          relationshipUpdate: const RelationshipUpdateCandidate(
            personName: '小林',
            relationship: '同事',
            summary: '讨论产品方案',
            confidence: 0.66,
          ),
        ),
      ];
      final facts = projectionService.buildProfileFacts(insights);
      final weakFact =
          facts.firstWhere((fact) => fact.field == 'stress_pattern');
      final hiddenFact = facts.firstWhere((fact) => fact.field == 'preference');

      await preferenceRepository.setConfirmed(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: weakFact.id,
        confirmed: true,
      );
      await preferenceRepository.setHidden(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: hiddenFact.id,
        hidden: true,
      );
      await preferenceRepository.setHidden(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: '小林',
        hidden: true,
      );

      final visibleFacts =
          await preferenceRepository.applyToProfileFacts(facts);
      final visibleRelationships =
          await preferenceRepository.applyToRelationshipProfiles(
        projectionService.buildRelationshipProfiles(insights),
      );

      expect(
          visibleFacts.map((fact) => fact.field), contains('stress_pattern'));
      expect(visibleFacts.map((fact) => fact.field),
          isNot(contains('preference')));
      expect(
        visibleFacts
            .firstWhere((fact) => fact.field == 'stress_pattern')
            .status,
        ProfileFactStatus.stable,
      );
      expect(
        visibleFacts
            .firstWhere((fact) => fact.field == 'stress_pattern')
            .userConfirmed,
        isTrue,
      );
      expect(visibleRelationships, isEmpty);
    });

    test('applies user corrected profile fact value', () async {
      SharedPreferences.setMockInitialValues({});
      const projectionService = ProfileProjectionService();
      const preferenceRepository = AiProfilePreferenceRepository();
      final insight = _insight(
        entryId: 'profile-correction',
        date: DateTime(2026, 7, 3),
        profileCandidate: const ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '运动一定能解决压力',
          confidence: 0.5,
        ),
      );
      final fact = projectionService.buildProfileFacts([insight]).single;

      await preferenceRepository.setCorrectedValue(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: fact.id,
        correctedValue: '运动有时能帮助我从压力中恢复',
      );

      final visible = await preferenceRepository.applyToProfileFacts([fact]);

      expect(visible.single.value, '运动有时能帮助我从压力中恢复');
      expect(visible.single.status, ProfileFactStatus.stable);
      expect(visible.single.userConfirmed, isTrue);
    });

    test('applies user corrected relationship type', () async {
      SharedPreferences.setMockInitialValues({});
      const projectionService = ProfileProjectionService();
      const preferenceRepository = AiProfilePreferenceRepository();
      final insight = _insight(
        entryId: 'relationship-correction',
        date: DateTime(2026, 7, 3),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '阿姨',
          relationship: '未知',
          summary: '聊了身体情况',
          confidence: 0.5,
        ),
      );
      final profile =
          projectionService.buildRelationshipProfiles([insight]).single;

      await preferenceRepository.setCorrectedValue(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: profile.personName,
        correctedValue: '家人',
      );

      final visible =
          await preferenceRepository.applyToRelationshipProfiles([profile]);

      expect(visible.single.relationship, '家人');
      expect(visible.single.status, ProfileFactStatus.stable);
      expect(visible.single.userConfirmed, isTrue);
    });
  });

  group('CompanionAnswerService', () {
    test('fallback answer uses relationship profiles with sources', () async {
      SharedPreferences.setMockInitialValues({});
      const insightRepository = InsightRepository();
      final date = DateTime(2026, 7, 3);
      await insightRepository.saveInsight(_insight(
        entryId: 'relationship-question',
        date: date,
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '妈妈',
          relationship: 'family',
          summary: '晚饭后沟通更平和',
          emotion: '平和',
          pattern: '晚间沟通更顺畅',
          confidence: 0.64,
        ),
      ));

      final answer = await const CompanionAnswerService().answer('我和妈妈最近怎么样');

      expect(answer.usedFallback, isTrue);
      expect(answer.answer, contains('妈妈'));
      expect(answer.answer, contains('晚饭后沟通更平和'));
      expect(answer.sources.map((source) => source.title), contains('妈妈'));
      expect(answer.sources.firstWhere((source) => source.title == '妈妈').score,
          greaterThan(0));
    });
  });

  group('EntrySummaryService', () {
    test('splits diary content by markdown headings and dividers', () {
      final entry = _entry(
        content: [
          '# 今日记录',
          '上午和 @小林 讨论产品设计。',
          '',
          '---',
          '晚上健身，状态不错。',
          '',
          '## 饮食',
          '吃了清淡的晚饭。',
        ].join('\n'),
      );

      final segments = const EntrySummaryService().buildSegments(entry);

      expect(segments, hasLength(3));
      expect(segments[0].boundary, DiarySegmentBoundary.markdownHeading);
      expect(segments[1].boundary, DiarySegmentBoundary.divider);
      expect(segments[2].boundary, DiarySegmentBoundary.markdownHeading);
      expect(segments[0].people, contains('小林'));
    });

    test('builds summary from segment key points', () {
      final entry = _entry(
        content: '# 晚间恢复\n\n今天跑步，也整理了产品计划，感觉轻松了一些。',
        location: '上海',
      );
      final segments = const EntrySummaryService().buildSegments(entry);

      final summary = const EntrySummaryService().buildSummary(entry, segments);

      expect(summary.entryId, entry.id);
      expect(summary.date, entry.date);
      expect(summary.title, '晚间恢复');
      expect(summary.brief, contains('今天跑步'));
      expect(summary.keyPoints, isNotEmpty);
      expect(summary.places, contains('上海'));
      expect(summary.emotion, contains('放松'));
      expect(summary.importance, greaterThan(0.4));
      expect(summary.generator, 'local-rule-v1');
    });

    test('reads legacy summary json with safe defaults', () {
      final updatedAt = DateTime(2026, 7, 3);

      final summary = EntrySummary.fromJson({
        'entryId': 'legacy-summary',
        'entryUpdatedAt': updatedAt.toIso8601String(),
        'generatedAt': updatedAt.toIso8601String(),
        'brief': '旧摘要',
      });

      expect(summary.date, updatedAt);
      expect(summary.title, isEmpty);
      expect(summary.emotion, isEmpty);
      expect(summary.importance, 0.5);
    });

    test('corrects summary brief and refreshes summary embedding', () async {
      SharedPreferences.setMockInitialValues({});
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const embeddingService = EmbeddingService();
      final entry = _entry(
        id: 'summary-correction',
        date: DateTime(2026, 7, 3),
        content: '今天散步以后焦虑下降。',
      );
      final segments = const EntrySummaryService().buildSegments(entry);
      final summary = const EntrySummaryService().buildSummary(entry, segments);
      await summaryRepository.saveSummary(summary);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
        text: summary.brief,
        generatedAt: DateTime(2026, 7, 3),
      );
      final before = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
      );

      final updated = await summaryRepository.correctBrief(
        entryId: entry.id,
        brief: '晚上散步后，焦虑感有所下降。',
      );
      final after = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
      );

      expect(updated?.brief, '晚上散步后，焦虑感有所下降。');
      expect(updated?.generator, 'user-corrected');
      expect(after?.textHash, isNot(before?.textHash));
      expect((await summaryRepository.getSummary(entry.id))?.brief,
          '晚上散步后，焦虑感有所下降。');
    });

    test('corrects summary package details and refreshes embedding', () async {
      SharedPreferences.setMockInitialValues({});
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      final entry = _entry(
        id: 'summary-package-correction',
        date: DateTime(2026, 7, 3),
        content: '今天散步以后焦虑下降，也记录了一句关键原文。',
      );
      final summary = _summaryForTest(
        entry: entry,
        brief: '旧摘要',
        importance: 0.7,
      );
      await summaryRepository.saveSummary(summary);
      await summaryRepository.correctSummaryPackage(
        entryId: entry.id,
        brief: '散步后焦虑下降。',
        title: '散步恢复',
        emotion: '放松',
        importance: 0.88,
        keyPoints: const ['完成散步', '焦虑下降'],
        importantQuotes: const ['走完以后轻松一点'],
      );
      final firstEmbedding = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
      );

      await summaryRepository.correctSummaryPackage(
        entryId: entry.id,
        brief: '散步后焦虑下降，并保留关键原文。',
        title: '散步恢复',
        emotion: '放松',
        importance: 0.9,
        keyPoints: const ['完成散步', '焦虑下降', '保留原文'],
        importantQuotes: const ['走完以后轻松一点'],
      );
      final updated = await summaryRepository.getSummary(entry.id);
      final secondEmbedding = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
      );

      expect(updated?.brief, '散步后焦虑下降，并保留关键原文。');
      expect(updated?.title, '散步恢复');
      expect(updated?.emotion, '放松');
      expect(updated?.importance, 0.9);
      expect(updated?.keyPoints, ['完成散步', '焦虑下降', '保留原文']);
      expect(updated?.importantQuotes, ['走完以后轻松一点']);
      expect(updated?.generator, 'user-corrected');
      expect(secondEmbedding?.textHash, isNot(firstEmbedding?.textHash));
    });
  });

  group('EmbeddingService', () {
    test('creates stable normalized embeddings', () {
      const service = EmbeddingService();

      final first = service.embed('今天跑步 状态很好');
      final second = service.embed('今天跑步 状态很好');

      expect(first.dimensions, EmbeddingService.dimensions);
      expect(first.textHash, second.textHash);
      expect(first.vector, second.vector);
      expect(service.cosineSimilarity(first.vector, second.vector),
          closeTo(1, 0.0001));
    });

    test('keeps unrelated empty vectors at zero similarity', () {
      const service = EmbeddingService();

      final empty = service.embed('');
      final diary = service.embed('今天完成了日记分析设计');

      expect(service.cosineSimilarity(empty.vector, diary.vector), 0);
    });
  });

  group('AiSearchService', () {
    test('returns vector matches with similarity reasons', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const embeddingService = EmbeddingService();
      final entry = _entry(
        id: 'vector-entry',
        date: DateTime(2026, 7, 3),
        content: '晚上散步以后，焦虑明显下降，身体也放松了一些。',
      );
      await diaryRepository.saveEntry(entry);
      final segments = const EntrySummaryService().buildSegments(entry);
      final summary = const EntrySummaryService().buildSummary(entry, segments);
      await summaryRepository.saveSegments(entry.id, segments);
      await summaryRepository.saveSummary(summary);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
        text: [
          summary.brief,
          ...summary.keyPoints,
          ...summary.topics,
        ].join('\n'),
        generatedAt: DateTime(2026, 7, 3),
      );

      final matches = await const AiSearchService().search('散步后焦虑下降');

      expect(
          matches.map((match) => match.sourceType), contains('entry_summary'));
      expect(matches.first.reasons.join(' '), contains('向量相似度'));
    });

    test('uses summary importance as a rerank signal', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      final date = DateTime(2026, 7, 3);
      final low = _entry(
        id: 'low-importance-summary',
        date: date,
        content: '散步 焦虑',
      );
      final high = _entry(
        id: 'high-importance-summary',
        date: date.add(const Duration(days: 1)),
        content: '散步 焦虑',
      );
      await diaryRepository.saveEntry(low);
      await diaryRepository.saveEntry(high);
      await summaryRepository.saveSummary(_summaryForTest(
        entry: low,
        brief: '散步 焦虑',
        importance: 0.3,
      ));
      await summaryRepository.saveSummary(_summaryForTest(
        entry: high,
        brief: '散步 焦虑',
        importance: 0.82,
      ));

      final matches = await const AiSearchService().search('散步 焦虑');

      expect(matches.first.entryId, high.id);
      expect(matches.first.reasons.join(' '), contains('摘要重要度'));
    });
  });

  group('PeriodSummaryService', () {
    test('builds month summary for scoped entries only', () async {
      SharedPreferences.setMockInitialValues({});
      final entries = [
        _entry(
          id: 'june-entry',
          date: DateTime(2026, 6, 10),
          content: '六月记录',
        ),
        _entry(
          id: 'july-entry',
          date: DateTime(2026, 7, 1),
          content: '七月记录',
        ),
      ];

      final summary = await const PeriodSummaryService()
          .buildMonthSummary(DateTime(2026, 7), entries);

      expect(summary.type, PeriodSummaryType.month);
      expect(summary.entryCount, 1);
      expect(summary.brief, contains('2026年7月 共记录 1 篇日记'));
      expect(summary.representativeEntryIds, contains('july-entry'));
      expect(summary.representativeEntryIds, isNot(contains('june-entry')));
    });

    test('includes relationship and stone progress highlights', () async {
      SharedPreferences.setMockInitialValues({});
      const insightRepository = InsightRepository();
      const stoneRepository = StoneTaskRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'period-entry',
        date: date,
        content: '今天和妈妈沟通，也完成了晚饭后散步。',
      );
      await insightRepository.saveInsight(_insight(
        entryId: entry.id,
        date: date,
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '妈妈',
          relationship: 'family',
          summary: '晚饭后沟通更平和',
          emotion: '平和',
          pattern: '晚间沟通更顺畅',
          confidence: 0.62,
        ),
      ));
      await stoneRepository.saveTask(StoneTask(
        id: 'stone:period',
        sourceEntryId: entry.id,
        title: '晚饭后散步 10 分钟',
        description: '走一小圈即可。',
        createdAt: date,
        updatedAt: date,
        completedAt: date.add(const Duration(hours: 2)),
        status: StoneTaskStatus.completed,
      ));
      await stoneRepository.addCheckIn(
        'stone:period',
        note: '晚饭后散步完成了一小圈',
      );

      final summary = await const PeriodSummaryService()
          .buildMonthSummary(DateTime(2026, 7), [entry]);

      expect(summary.relationshipHighlights.join(' '), contains('妈妈'));
      expect(summary.relationshipHighlights.join(' '), contains('晚饭后沟通更平和'));
      expect(summary.stoneHighlights, contains('新增塑石行动 1 个'));
      expect(summary.stoneHighlights, contains('记录塑石进展 1 次'));
      expect(summary.stoneHighlights, contains('完成塑石行动 1 个'));
      expect(summary.stoneHighlights.join(' '), contains('晚饭后散步 10 分钟'));
    });
  });

  group('AiContextBuilder calendar matches', () {
    test('period context keeps higher-importance summaries within budget',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      final entries = <DiaryEntry>[];
      for (var index = 0; index < 50; index++) {
        final entry = _entry(
          id: 'period-budget-$index',
          date: DateTime(2026, 7, 1 + (index % 28)),
          content: '周期摘要预算 $index',
        );
        entries.add(entry);
        await diaryRepository.saveEntry(entry);
        await summaryRepository.saveSummary(_summaryForTest(
          entry: entry,
          brief: '周期摘要预算 $index',
          importance: index == 49 ? 0.95 : 0.3,
        ));
      }

      final package = await const AiContextBuilder().buildForPeriodSummary(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31, 23, 59, 59),
      );

      expect(package.periodEntries, hasLength(50));
      expect(package.periodSummaries, hasLength(48));
      expect(package.periodSummaries.first.entryId, 'period-budget-49');
      expect(package.debugSummary, contains('periodSummaries=48'));
    });

    test('loads historical solar today and nearby entries', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      final current = _entry(
        id: 'current',
        date: DateTime(2026, 7, 3),
        content: '今天重新开始跑步。',
      );
      final sameDay = _entry(
        id: 'same-day',
        date: DateTime(2025, 7, 3),
        content: '去年今天也去跑步。',
      );
      final nearby = _entry(
        id: 'nearby',
        date: DateTime(2024, 7, 2),
        content: '前年差一天记录运动。',
      );
      final far = _entry(
        id: 'far',
        date: DateTime(2023, 7, 8),
        content: '距离太远。',
      );
      final future = _entry(
        id: 'future',
        date: DateTime(2027, 7, 3),
        content: '未来日记。',
      );
      for (final entry in [current, sameDay, nearby, far, future]) {
        await diaryRepository.saveEntry(entry);
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(current);

      expect(package.calendarMatches.map((match) => match.entry.id),
          ['same-day', 'nearby']);
      expect(package.calendarMatches.first.reason, contains('年前的今天'));
      expect(
        package.retrievalTrace?.items
            .where((item) => item.sourceType == 'calendar')
            .map((item) => item.sourceId),
        ['same-day', 'nearby'],
      );
    });

    test('labels fixed solar festival matches', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      final current = _entry(
        id: 'national-current',
        date: DateTime(2026, 10, 1),
        content: '今年国庆在家休息。',
      );
      final festivalPast = _entry(
        id: 'national-past',
        date: DateTime(2025, 10, 1),
        content: '去年国庆和家人吃饭。',
      );
      final nearbyPast = _entry(
        id: 'national-nearby',
        date: DateTime(2024, 10, 2),
        content: '前年差一天还在旅途中。',
      );
      for (final entry in [current, festivalPast, nearbyPast]) {
        await diaryRepository.saveEntry(entry);
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(current);
      final festival = package.calendarMatches.first;

      expect(festival.entry.id, 'national-past');
      expect(festival.label, '国庆节');
      expect(festival.reason, contains('国庆节'));
      expect(
        package.retrievalTrace?.items
            .firstWhere((item) => item.sourceId == 'national-past')
            .matchedTokens,
        contains('国庆节'),
      );
    });

    test('uses custom calendar memories for today matches', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const calendarRepository = CalendarMemoryRepository();
      final date = DateTime(2026, 7, 3);
      await calendarRepository.saveMemory(CalendarMemory(
        id: 'grandma-birthday',
        title: '外婆生日',
        month: 7,
        day: 3,
        createdAt: date,
        updatedAt: date,
      ));
      final current = _entry(
        id: 'anniversary-current',
        date: date,
        content: '今天想起外婆。',
      );
      final past = _entry(
        id: 'anniversary-past',
        date: DateTime(2025, 7, 3),
        content: '去年这天也写到了外婆。',
      );
      for (final entry in [current, past]) {
        await diaryRepository.saveEntry(entry);
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(current);
      final match = package.calendarMatches.single;

      expect(match.label, '外婆生日');
      expect(match.reason, contains('外婆生日'));
      expect(match.score, 11);
      expect(
        package.retrievalTrace?.items.single.matchedTokens,
        contains('外婆生日'),
      );
    });

    test('includes profile relationship and stone context', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const insightRepository = InsightRepository();
      const stoneRepository = StoneTaskRepository();
      final current = _entry(
        id: 'current-context',
        date: DateTime(2026, 7, 3),
        content: '今天和妈妈聊完以后去散步，感觉恢复了一些。',
      );
      await diaryRepository.saveEntry(current);
      for (final item in [
        _insight(
          entryId: 'profile-1',
          date: DateTime(2026, 7, 1),
          profileCandidate: const ProfileUpdateCandidate(
            field: 'self_regulation',
            value: '散步可能帮助恢复状态',
            confidence: 0.64,
          ),
        ),
        _insight(
          entryId: 'profile-2',
          date: DateTime(2026, 7, 2),
          profileCandidate: const ProfileUpdateCandidate(
            field: 'self_regulation',
            value: '散步可能帮助恢复状态',
            confidence: 0.65,
          ),
        ),
        _insight(
          entryId: 'profile-3',
          date: DateTime(2026, 7, 3),
          profileCandidate: const ProfileUpdateCandidate(
            field: 'self_regulation',
            value: '散步可能帮助恢复状态',
            confidence: 0.63,
          ),
        ),
        _insight(
          entryId: 'relationship-1',
          date: DateTime(2026, 7, 2),
          relationshipUpdate: const RelationshipUpdateCandidate(
            personName: '妈妈',
            relationship: 'family',
            summary: '晚饭后沟通更平和',
            emotion: '平和',
            pattern: '晚间沟通更顺畅',
            confidence: 0.62,
          ),
        ),
      ]) {
        await insightRepository.saveInsight(item);
      }
      await stoneRepository.saveTask(StoneTask(
        id: 'stone:walk',
        sourceEntryId: 'profile-1',
        title: '晚饭后散步 10 分钟',
        description: '走一小圈即可。',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
        tags: const ['散步'],
      ));

      final package =
          await const AiContextBuilder().buildForTodayInsight(current);

      expect(package.profileFacts.map((item) => item.field),
          contains('self_regulation'));
      expect(package.relationshipProfiles.map((item) => item.personName),
          contains('妈妈'));
      expect(package.stoneTasks.map((item) => item.title),
          contains('晚饭后散步 10 分钟'));
      expect(package.debugSummary, contains('profile='));
      expect(package.retrievalTrace?.items.map((item) => item.sourceType),
          containsAll(['profile', 'relationship', 'stone']));
    });

    test('search returns entry summaries and diary segments', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      final entry = _entry(
        id: 'entry-search',
        date: DateTime(2026, 7, 3),
        content: '晚上跑步以后状态恢复。',
      );
      await diaryRepository.saveEntry(entry);
      final segments = const EntrySummaryService().buildSegments(entry);
      final summary = const EntrySummaryService().buildSummary(entry, segments);
      await summaryRepository.saveSegments(entry.id, segments);
      await summaryRepository.saveSummary(summary);

      final package = await const AiContextBuilder().buildForSearch('跑步 恢复');

      expect(package.searchMatches.map((match) => match.sourceType),
          containsAll(['entry_summary', 'segment']));
      expect(package.debugSummary, contains('search='));
      expect(
        package.retrievalTrace?.items
            .map((item) => item.sourceType)
            .where((type) => type == 'entry_summary' || type == 'segment'),
        isNotEmpty,
      );
    });

    test('question context preserves diary and segment matches', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      final entry = _entry(
        id: 'entry-question',
        date: DateTime(2026, 7, 3),
        content: '晚上散步以后焦虑下降。',
      );
      await diaryRepository.saveEntry(entry);
      final segments = const EntrySummaryService().buildSegments(entry);
      final summary = const EntrySummaryService().buildSummary(entry, segments);
      await summaryRepository.saveSegments(entry.id, segments);
      await summaryRepository.saveSummary(summary);

      final package = await const AiContextBuilder().buildForQuestion('散步 焦虑');

      expect(package.scenario, AiContextScenario.question);
      expect(package.searchMatches, isNotEmpty);
      expect(package.searchMatches.map((match) => match.sourceType),
          contains('segment'));
    });
  });

  group('DiaryRepository trash', () {
    test('ignores trash index key when scanning trash items', () async {
      SharedPreferences.setMockInitialValues({
        'diary.trash.index': <String>['index'],
      });

      final items = await const DiaryRepository().listTrashEntries();

      expect(items, isEmpty);
    });

    test('ignores trash items stored with a non-string value', () async {
      SharedPreferences.setMockInitialValues({
        'diary.trash.index': <String>['entry-1'],
        'diary.trash.entry-1': <String>['corrupted'],
      });

      final items = await const DiaryRepository().listTrashEntries();

      expect(items, isEmpty);
    });

    test('ignores corrupted trash json without failing the list', () async {
      SharedPreferences.setMockInitialValues({
        'diary.trash.index': <String>['entry-1'],
        'diary.trash.entry-1': '{broken',
      });

      final items = await const DiaryRepository().listTrashEntries();

      expect(items, isEmpty);
    });

    test('repairs trash index values when non-string ids are present',
        () async {
      SharedPreferences.setMockInitialValues({
        'diary.trash.index': <Object?>['entry-1', 12, null],
      });

      final items = await const DiaryRepository().listTrashEntries();
      final prefs = await SharedPreferences.getInstance();

      expect(items, isEmpty);
      expect(prefs.getStringList('diary.trash.index'), ['entry-1']);
    });
  });

  group('MemoryRepository lifecycle', () {
    test('saves memory embeddings and keeps them stable on reference updates',
        () async {
      SharedPreferences.setMockInitialValues({});
      const repository = MemoryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      final oldDate = DateTime(2026, 6, 1);
      await repository.saveMemory(MemoryEntry(
        id: 'memory-with-embedding',
        sourceEntryId: 'old-entry',
        date: oldDate,
        createdAt: oldDate,
        summary: '散步以后焦虑下降，状态恢复。',
        keywords: const ['散步', '焦虑'],
        emotion: '放松',
        people: const [],
        tags: const ['运动'],
      ));
      final before = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.memory,
        sourceId: 'memory-with-embedding',
      );

      await repository.findRelatedWithReasons(
        entry: _entry(
          id: 'today-memory-query',
          date: DateTime(2026, 7, 3),
          content: '今天散步以后焦虑小了很多。',
        ),
      );
      final after = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.memory,
        sourceId: 'memory-with-embedding',
      );

      expect(before, isNotNull);
      expect(before?.sourceType, AiEmbeddingSourceType.memory);
      expect(after?.textHash, before?.textHash);
      expect(after?.generatedAt, before?.generatedAt);
    });

    test('feedback adjusts memory lifecycle', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = MemoryRepository();
      final date = DateTime(2026, 7, 3);
      await repository.saveMemory(MemoryEntry(
        id: 'feedback-memory',
        sourceEntryId: 'entry-feedback',
        date: date,
        createdAt: date,
        summary: '这条洞察可能不准确。',
        keywords: const ['洞察'],
        emotion: '',
        people: const [],
        tags: const [],
        importance: 0.4,
        confidence: 0.3,
      ));

      await repository.applyFeedback(
        sourceEntryId: 'entry-feedback',
        value: AiFeedbackValue.inaccurate,
      );
      final lowered = (await repository.listMemories()).single;
      await repository.applyFeedback(
        sourceEntryId: 'entry-feedback',
        value: AiFeedbackValue.helpful,
      );
      final restored = (await repository.listMemories()).single;

      expect(lowered.confidence, lessThan(0.3));
      expect(lowered.importance, lessThan(0.4));
      expect(lowered.archived, isTrue);
      expect(restored.confidence, greaterThan(lowered.confidence));
      expect(restored.archived, isFalse);
    });

    test('corrects memory summary and refreshes embedding', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = MemoryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      final date = DateTime(2026, 7, 3);
      await repository.saveMemory(MemoryEntry(
        id: 'correct-memory',
        sourceEntryId: 'entry',
        date: date,
        createdAt: date,
        summary: '散步一定能解决所有压力。',
        keywords: const ['散步'],
        emotion: '',
        people: const [],
        tags: const ['运动'],
        confidence: 0.4,
        archived: true,
      ));
      final before = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.memory,
        sourceId: 'correct-memory',
      );

      await repository.correctSummary(
        id: 'correct-memory',
        summary: '散步有时能帮助缓解压力。',
      );
      final memory = (await repository.listMemories()).single;
      final after = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.memory,
        sourceId: 'correct-memory',
      );

      expect(memory.summary, '散步有时能帮助缓解压力。');
      expect(memory.confidence, greaterThan(0.4));
      expect(memory.archived, isFalse);
      expect(after?.textHash, isNot(before?.textHash));
    });

    test('skips archived memories and increments references', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = MemoryRepository();
      final oldDate = DateTime(2026, 6, 1);
      await repository.saveMemory(MemoryEntry(
        id: 'active-memory',
        sourceEntryId: 'old-entry',
        date: oldDate,
        createdAt: oldDate,
        summary: '跑步以后压力下降，状态恢复。',
        keywords: const ['跑步', '压力'],
        emotion: '放松',
        people: const [],
        tags: const ['运动'],
        importance: 0.9,
        confidence: 0.8,
      ));
      await repository.saveMemory(MemoryEntry(
        id: 'archived-memory',
        sourceEntryId: 'older-entry',
        date: oldDate,
        createdAt: oldDate,
        summary: '跑步以后压力下降。',
        keywords: const ['跑步'],
        emotion: '放松',
        people: const [],
        tags: const ['运动'],
        archived: true,
      ));

      final results = await repository.findRelatedWithReasons(
        entry: _entry(
          id: 'today-entry',
          date: DateTime(2026, 7, 3),
          content: '今天跑步以后压力小了很多。',
        ),
      );
      final memories = await repository.listMemories();
      final active =
          memories.firstWhere((memory) => memory.id == 'active-memory');

      expect(results.map((result) => result.memory.id), ['active-memory']);
      expect(active.referenceCount, 1);
      expect(active.lastReferencedAt.isAfter(oldDate), isTrue);
    });

    test('removes deleted entry evidence without deleting shared memories',
        () async {
      SharedPreferences.setMockInitialValues({});
      const repository = MemoryRepository();
      final date = DateTime(2026, 7, 3);
      await repository.saveMemory(MemoryEntry(
        id: 'shared-memory',
        sourceEntryId: 'first-entry',
        date: date,
        createdAt: date,
        summary: '多次记录显示散步帮助恢复状态。',
        keywords: const ['散步', '恢复'],
        emotion: '放松',
        people: const [],
        tags: const ['运动'],
        evidenceEntryIds: const ['first-entry', 'second-entry'],
        confidence: 0.72,
      ));
      await repository.saveMemory(MemoryEntry(
        id: 'single-memory',
        sourceEntryId: 'first-entry',
        date: date,
        createdAt: date,
        summary: '只来自一篇日记的记忆。',
        keywords: const ['单次'],
        emotion: '',
        people: const [],
        tags: const [],
        evidenceEntryIds: const ['first-entry'],
      ));

      await repository.deleteForSourceEntry('first-entry');
      final memories = await repository.listMemories();
      final shared =
          memories.firstWhere((memory) => memory.id == 'shared-memory');

      expect(memories.map((memory) => memory.id), ['shared-memory']);
      expect(shared.sourceEntryId, 'second-entry');
      expect(shared.evidenceEntryIds, ['second-entry']);
      expect(shared.confidence, lessThan(0.72));
    });

    test('reads lifecycle defaults from legacy memory json', () {
      final date = DateTime(2026, 7, 3);
      final memory = MemoryEntry.fromJson({
        'id': 'legacy',
        'sourceEntryId': 'entry',
        'date': date.toIso8601String(),
        'createdAt': date.toIso8601String(),
        'summary': '旧记忆',
      });

      expect(memory.importance, 0.56);
      expect(memory.confidence, 0.58);
      expect(memory.referenceCount, 0);
      expect(memory.archived, isFalse);
      expect(memory.evidenceEntryIds, ['entry']);
    });
  });
}

DiaryEntry _entry({
  String id = 'entry-1',
  DateTime? date,
  String content = '今天写日记。',
  String location = '未选择地点',
}) {
  final valueDate = date ?? DateTime(2026, 7, 3, 20);
  return DiaryEntry(
    id: id,
    date: valueDate,
    createdAt: valueDate,
    content: content,
    location: location,
    weather: '晴',
    temperature: '26',
    updatedAt: valueDate,
  );
}

EntrySummary _summaryForTest({
  required DiaryEntry entry,
  required String brief,
  required double importance,
}) {
  return EntrySummary(
    entryId: entry.id,
    date: entry.date,
    entryUpdatedAt: entry.updatedAt,
    generatedAt: entry.updatedAt,
    title: entry.title ?? brief,
    brief: brief,
    keyPoints: [brief],
    topics: const [],
    people: const [],
    places: const [],
    emotion: '',
    importance: importance,
    importantQuotes: const [],
    generator: 'test',
  );
}

String _entryEmbeddingTextForTest(DiaryEntry entry, EntrySummary summary) {
  return '${summary.brief}\n${entry.bodyPreview}';
}

String _summaryEmbeddingTextForTest(EntrySummary summary) {
  return [
    summary.title,
    summary.brief,
    ...summary.keyPoints,
    ...summary.topics,
    ...summary.people,
    ...summary.places,
    summary.emotion,
    ...summary.importantQuotes,
  ].join('\n');
}

String _segmentEmbeddingTextForTest(DiarySegment segment) {
  return '${segment.summary}\n${segment.text}';
}

Future<void> _saveTestEmbedding({
  required AiEmbeddingRepository repository,
  required EmbeddingService service,
  required String entryId,
  required AiEmbeddingSourceType sourceType,
  required String sourceId,
  required String text,
  required DateTime generatedAt,
}) async {
  final result = service.embed(text);
  await repository.saveEmbedding(AiEmbedding(
    id: '${sourceType.name}:$sourceId',
    sourceType: sourceType,
    sourceId: sourceId,
    entryId: entryId,
    modelId: result.modelId,
    modelVersion: result.modelVersion,
    dimensions: result.dimensions,
    vector: result.vector,
    generatedAt: generatedAt,
    textHash: result.textHash,
  ));
}

DiaryInsight _insight({
  required String entryId,
  required DateTime date,
  String personName = '',
  ProfileUpdateCandidate? profileCandidate,
  RelationshipUpdateCandidate? relationshipUpdate,
}) {
  final relationshipUpdates = <RelationshipUpdateCandidate>[];
  if (relationshipUpdate != null) {
    relationshipUpdates.add(relationshipUpdate);
  } else if (personName.isNotEmpty) {
    relationshipUpdates.add(RelationshipUpdateCandidate(
      personName: personName,
      summary: '一次互动',
      confidence: 0.55,
    ));
  }
  return DiaryInsight(
    entryId: entryId,
    entryDate: date,
    generatedAt: date,
    reflection: '洞察',
    relatedMemories: const [],
    emotion: '平静',
    keywords: const [],
    people: personName.isEmpty ? const [] : [personName],
    stoneTitle: '',
    stoneDescription: '',
    memorySummary: '',
    memoryTags: const [],
    profileUpdateCandidates:
        profileCandidate == null ? const [] : [profileCandidate],
    relationshipUpdates: relationshipUpdates,
  );
}

class _FakeDiaryAnalysisService extends DiaryAnalysisService {
  const _FakeDiaryAnalysisService();

  @override
  Future<DiaryInsight> analyzeEntry(DiaryEntry entry) async {
    return DiaryInsight(
      entryId: entry.id,
      entryDate: entry.date,
      generatedAt: DateTime(2026, 7, 3),
      reflection: '本地测试洞察',
      relatedMemories: const [],
      emotion: '平静',
      keywords: const [],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
    );
  }
}
