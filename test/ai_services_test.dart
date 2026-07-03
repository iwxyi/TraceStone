import 'dart:convert';

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
import 'package:trace_stone/data/models/memory_retrieval_result.dart';
import 'package:trace_stone/data/models/period_summary.dart';
import 'package:trace_stone/data/models/stone_task.dart';
import 'package:trace_stone/data/repositories/diary_repository.dart';
import 'package:trace_stone/data/repositories/ai_analysis_queue_repository.dart';
import 'package:trace_stone/data/repositories/ai_embedding_repository.dart';
import 'package:trace_stone/data/repositories/ai_feedback_repository.dart';
import 'package:trace_stone/data/repositories/ai_prompt_trace_repository.dart';
import 'package:trace_stone/data/repositories/ai_retrieval_trace_repository.dart';
import 'package:trace_stone/data/repositories/ai_profile_preference_repository.dart';
import 'package:trace_stone/data/repositories/calendar_memory_repository.dart';
import 'package:trace_stone/data/repositories/developer_settings_repository.dart';
import 'package:trace_stone/data/repositories/entry_summary_repository.dart';
import 'package:trace_stone/data/repositories/insight_repository.dart';
import 'package:trace_stone/data/repositories/memory_repository.dart';
import 'package:trace_stone/data/repositories/period_summary_repository.dart';
import 'package:trace_stone/data/repositories/stone_task_repository.dart';
import 'package:trace_stone/data/services/ai_context_builder.dart';
import 'package:trace_stone/data/services/ai_analysis_queue_runner.dart';
import 'package:trace_stone/data/services/ai_client_service.dart';
import 'package:trace_stone/data/services/ai_feedback_service.dart';
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

    test('ignores invalid prompt and retrieval trace storage values', () async {
      SharedPreferences.setMockInitialValues({
        'ai.promptTraces.list': <String>['not-json'],
        'ai.retrievalTraces.list': <String>['not-json'],
        'ai.promptTraces.broken': '{broken',
        'ai.retrievalTraces.broken': '{broken',
        'ai.promptTraces.array': '[]',
        'ai.retrievalTraces.array': '[]',
      });
      const promptRepository = AiPromptTraceRepository();
      const retrievalRepository = AiRetrievalTraceRepository();

      expect(await promptRepository.getTrace('list'), isNull);
      expect(await retrievalRepository.getTrace('list'), isNull);
      expect(await promptRepository.getTrace('broken'), isNull);
      expect(await retrievalRepository.getTrace('broken'), isNull);
      expect(await promptRepository.getTrace('array'), isNull);
      expect(await retrievalRepository.getTrace('array'), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get('ai.promptTraces.list'), ['not-json']);
      expect(prefs.get('ai.retrievalTraces.list'), ['not-json']);
      expect(prefs.get('ai.promptTraces.broken'), isNull);
      expect(prefs.get('ai.retrievalTraces.broken'), isNull);
      expect(prefs.get('ai.promptTraces.array'), isNull);
      expect(prefs.get('ai.retrievalTraces.array'), isNull);
    });
  });

  group('AI settings and feedback', () {
    test('feedback repository ignores invalid stored values', () async {
      SharedPreferences.setMockInitialValues({
        'ai.feedback.list': <String>['bad'],
        'ai.feedback.broken': '{broken',
        'ai.feedback.array': '[]',
      });
      const repository = AiFeedbackRepository();

      expect(await repository.getFeedback('list'), isNull);
      expect(await repository.getFeedback('broken'), isNull);
      expect(await repository.getFeedback('array'), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get('ai.feedback.list'), ['bad']);
      expect(prefs.get('ai.feedback.broken'), isNull);
      expect(prefs.get('ai.feedback.array'), isNull);
    });

    test('inaccurate insight feedback requeues analysis with a trace log',
        () async {
      SharedPreferences.setMockInitialValues({});
      final entry = _entry(
        id: 'feedback-entry',
        date: DateTime(2026, 7, 3),
        content: '今天的洞察需要重新整理。',
      );
      await const DiaryRepository().saveEntry(entry);
      await const InsightRepository().saveInsight(_insight(
        entryId: entry.id,
        date: entry.date,
      ));

      final feedback = await const AiFeedbackService().submitInsightFeedback(
        entryId: entry.id,
        value: AiFeedbackValue.inaccurate,
        note: '把情绪判断错了',
      );

      final savedFeedback =
          await const AiFeedbackRepository().getFeedback(entry.id);
      final job = await const AiAnalysisQueueRepository().getJob(entry.id);
      final status = await const InsightRepository().getStatus(entry.id);

      expect(feedback.value, AiFeedbackValue.inaccurate);
      expect(savedFeedback?.note, '把情绪判断错了');
      expect(await const InsightRepository().getInsight(entry.id), isNull);
      expect(await const InsightRepository().getLatestInsight(), isNull);
      expect(job?.state, AiAnalysisJobState.incomplete);
      expect(job?.currentStage, AiAnalysisStage.generatingInsight);
      expect(job?.lastError, contains('用户标记洞察不准确'));
      expect(
        job?.stageLogs.map((log) => log.message),
        contains('用户标记洞察不准确，重新生成今日洞察'),
      );
      expect(job?.stageLogs.last.outputSummary, contains('把情绪判断错了'));
      expect(status?.state, DiaryAnalysisState.incomplete);
      expect(status?.message, contains('重新整理队列'));
    });

    test('inaccurate feedback note is included in regenerated insight prompt',
        () async {
      SharedPreferences.setMockInitialValues({});
      const feedbackRepository = AiFeedbackRepository();
      const promptRepository = AiPromptTraceRepository();
      final client = _CapturingAiClientService();
      final entry = _entry(
        id: 'feedback-prompt-entry',
        date: DateTime(2026, 7, 3),
        content: '今天散步以后，状态轻松了一些。',
      );
      final recent = _entry(
        id: 'recent-source-entry',
        date: DateTime(2026, 7, 2),
        content: '昨天也写到散步后的恢复。',
      );
      await const DiaryRepository().saveEntry(entry);
      await const DiaryRepository().saveEntry(recent);
      final segments = const EntrySummaryService().buildSegments(entry);
      await const EntrySummaryRepository().saveSummary(
        const EntrySummaryService().buildSummary(entry, segments),
      );
      await const EntrySummaryRepository().saveSegments(entry.id, segments);
      await const MemoryRepository().saveMemory(MemoryEntry(
        id: 'memory-walk-source',
        sourceEntryId: 'memory-entry-source',
        date: DateTime(2026, 6, 30),
        createdAt: DateTime(2026, 6, 30),
        summary: '散步后状态更轻松。',
        keywords: const ['散步'],
        emotion: '轻松',
        people: const [],
        tags: const ['恢复'],
        evidenceEntryIds: const ['memory-entry-source', 'older-evidence'],
      ));
      await const StoneTaskRepository().saveTask(StoneTask(
        id: 'stone-walk-source',
        sourceEntryId: 'stone-entry-source',
        title: '晚饭后散步',
        description: '每天走一小圈。',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
        tags: const ['散步'],
      ));
      await feedbackRepository.saveFeedback(AiFeedback(
        entryId: entry.id,
        value: AiFeedbackValue.inaccurate,
        createdAt: DateTime(2026, 7, 3),
        note: '不要把轻松判断成焦虑',
      ));

      await DiaryAnalysisService(client: client).analyzeEntry(entry);

      final trace = await promptRepository.getTrace(entry.id);
      final insight = await const InsightRepository().getInsight(entry.id);
      expect(client.lastUserPrompt, contains('用户反馈：'));
      expect(client.lastUserPrompt, contains('上一版洞察被用户标记为不准确'));
      expect(client.lastUserPrompt, contains('不要把轻松判断成焦虑'));
      expect(client.lastUserPrompt, contains('segment:${segments.first.id}'));
      expect(client.lastUserPrompt, contains('entry:recent-source-entry'));
      expect(client.lastUserPrompt, contains('memory:memory-walk-source'));
      expect(
          client.lastUserPrompt, contains('sourceEntry:memory-entry-source'));
      expect(client.lastUserPrompt,
          contains('evidenceEntries:memory-entry-source,older-evidence'));
      expect(client.lastUserPrompt, contains('stone:stone-walk-source'));
      expect(client.lastUserPrompt, contains('sourceEntry:stone-entry-source'));
      expect(trace?.userPrompt, contains('不要把轻松判断成焦虑'));
      expect(trace?.contextSummary, contains('evidenceFiltered=3'));
      expect(trace?.contextSummary, contains('relatedSourceFiltered=1'));
      expect(insight?.relatedMemories.map((item) => item.entryId), [
        'memory-entry-source',
        null,
      ]);
      expect(insight?.facts.single.evidence.map((item) => item.id),
          ['feedback-prompt-entry']);
      expect(insight?.hypotheses.single.evidence.map((item) => item.id),
          ['memory-walk-source']);
      expect(insight?.suggestions.single.evidence.map((item) => item.id),
          ['stone-walk-source']);
    });

    test('developer mode ignores invalid boolean values', () async {
      SharedPreferences.setMockInitialValues({
        'settings.developerMode': 'true',
      });

      expect(
        await const DeveloperSettingsRepository().isDeveloperModeEnabled(),
        isFalse,
      );
    });

    test('ai client config ignores invalid preference types', () async {
      SharedPreferences.setMockInitialValues({
        'ai.useOfficial': 'false',
        'ai.platform': <String>['OpenAI'],
        'ai.baseUrl': <String>['https://example.com'],
        'ai.apiKey': <String>['key'],
        'ai.model': <String>['model'],
      });

      expect(
        () => const AiClientService().loadConfig(),
        throwsA(isA<AiClientException>()),
      );
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

    test('reads related memory source ids from AI json variants', () {
      final insight = DiaryInsight.fromJson({
        'entryId': 'entry',
        'relatedMemories': [
          {
            'title': '去年散步',
            'reason': '同样提到散步',
            'entry_id': 'entry-2025-walk',
          },
          {
            'title': '长期记忆',
            'reason': '稳定模式',
            'source_id': 'memory-walk',
          },
        ],
      });

      expect(insight.relatedMemories.map((item) => item.entryId), [
        'entry-2025-walk',
        'memory-walk',
      ]);
      expect(
        insight.relatedMemories.first.toJson()['entryId'],
        'entry-2025-walk',
      );
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

    test('ignores invalid insight and status storage values', () async {
      final date = DateTime(2026, 7, 3);
      final valid = _insight(entryId: 'valid', date: date);
      SharedPreferences.setMockInitialValues({
        'diary.insights.index': <Object?>[
          'valid',
          'broken',
          12,
          'array',
          'list',
        ],
        'diary.insights.latest': 'broken',
        'diary.insights.valid': jsonEncode(valid.toJson()),
        'diary.insights.broken': '{broken',
        'diary.insights.array': '[]',
        'diary.insights.list': <String>['bad'],
        'diary.insights.status.valid': jsonEncode(DiaryAnalysisStatus(
          entryId: 'valid',
          state: DiaryAnalysisState.completed,
          updatedAt: date,
        ).toJson()),
        'diary.insights.status.broken': '{broken',
        'diary.insights.status.array': '[]',
        'diary.insights.status.list': <String>['bad'],
      });
      const repository = InsightRepository();

      expect(await repository.getLatestInsight(), isNull);
      expect(await repository.getInsight('broken'), isNull);
      expect(await repository.getInsight('array'), isNull);
      expect(await repository.getInsight('list'), isNull);
      expect(await repository.getStatus('valid'), isNotNull);
      expect(await repository.getStatus('broken'), isNull);
      expect(await repository.getStatus('array'), isNull);
      expect(await repository.getStatus('list'), isNull);
      final insights = await repository.listInsights();
      final prefs = await SharedPreferences.getInstance();

      expect(insights.map((item) => item.entryId), ['valid']);
      expect(prefs.getStringList('diary.insights.index'), ['valid']);
      expect(prefs.get('diary.insights.latest'), isNull);
      expect(prefs.get('diary.insights.broken'), isNull);
      expect(prefs.get('diary.insights.array'), isNull);
      expect(prefs.get('diary.insights.list'), ['bad']);
      expect(prefs.get('diary.insights.status.broken'), isNull);
      expect(prefs.get('diary.insights.status.array'), isNull);
      expect(prefs.get('diary.insights.status.list'), ['bad']);
    });

    test('save recovers when insight index has a wrong type', () async {
      SharedPreferences.setMockInitialValues({
        'diary.insights.index': 'legacy-bad-index',
      });
      const repository = InsightRepository();
      final date = DateTime(2026, 7, 3);

      await repository.saveInsight(_insight(entryId: 'saved', date: date));
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getStringList('diary.insights.index'), ['saved']);
      expect((await repository.listInsights()).single.entryId, 'saved');
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
      final malformed = AiAnalysisJob.fromJson({
        'id': 'malformed',
        'entryId': 'entry',
        'pipelineVersion': 'old',
        'state': <String>['pending'],
        'currentStage': 12,
        'createdAt': <String>['bad'],
        'updatedAt': null,
        'completedStages': 'queued',
        'stageLogs': [
          'bad',
          {
            'stage': 'embedding',
            'startedAt': date.toIso8601String(),
            'message': 'ok',
            'retryCount': 'bad',
          },
        ],
        'retryCount': 'bad',
        'lastError': <String>['bad'],
      });

      expect(restored.stageLogs.single.stage, AiAnalysisStage.embedding);
      expect(restored.stageLogs.single.outputSummary, 'completed=segmenting');
      expect(legacy.stageLogs, isEmpty);
      expect(malformed.pipelineVersion, 1);
      expect(malformed.state, AiAnalysisJobState.pending);
      expect(malformed.currentStage, AiAnalysisStage.queued);
      expect(malformed.completedStages, isEmpty);
      expect(malformed.stageLogs.single.stage, AiAnalysisStage.embedding);
      expect(malformed.stageLogs.single.retryCount, 0);
      expect(malformed.retryCount, 0);
      expect(malformed.lastError, isNull);
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

    test('ignores invalid stored jobs and repairs the queue index', () async {
      final date = DateTime(2026, 7, 3);
      final valid = AiAnalysisJob(
        id: 'valid',
        entryId: 'valid',
        pipelineVersion: 1,
        state: AiAnalysisJobState.pending,
        currentStage: AiAnalysisStage.queued,
        createdAt: date,
        updatedAt: date,
      );
      SharedPreferences.setMockInitialValues({
        'ai.analysis.jobs.index': <Object?>[
          'valid',
          'broken',
          12,
          'array',
          'list',
        ],
        'ai.analysis.jobs.valid': jsonEncode(valid.toJson()),
        'ai.analysis.jobs.broken': '{broken',
        'ai.analysis.jobs.array': '[]',
        'ai.analysis.jobs.list': <String>['bad'],
      });
      const repository = AiAnalysisQueueRepository();

      final jobs = await repository.listJobs();
      final prefs = await SharedPreferences.getInstance();

      expect(jobs.map((job) => job.id), ['valid']);
      expect(await repository.getJob('broken'), isNull);
      expect(prefs.getStringList('ai.analysis.jobs.index'), ['valid']);
      expect(prefs.get('ai.analysis.jobs.broken'), isNull);
      expect(prefs.get('ai.analysis.jobs.array'), isNull);
      expect(prefs.get('ai.analysis.jobs.list'), ['bad']);
    });

    test('save operations recover when the queue index has a wrong type',
        () async {
      SharedPreferences.setMockInitialValues({
        'ai.analysis.jobs.index': 'legacy-bad-index',
      });
      const repository = AiAnalysisQueueRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'queued-entry',
        date: date,
        content: '保存后需要进入 AI 队列。',
      );

      await repository.enqueueEntry(entry);
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getStringList('ai.analysis.jobs.index'), ['queued-entry']);
      expect((await repository.listJobs()).single.id, 'queued-entry');
      await repository.deleteJob('queued-entry');
      expect(prefs.getStringList('ai.analysis.jobs.index'), isEmpty);
    });

    test('marks stale running jobs incomplete with a stage log', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = AiAnalysisQueueRepository();
      final old = DateTime.now().subtract(const Duration(minutes: 11));
      final job = AiAnalysisJob(
        id: 'stale-running',
        entryId: 'stale-running',
        pipelineVersion: 1,
        state: AiAnalysisJobState.running,
        currentStage: AiAnalysisStage.embedding,
        createdAt: old,
        updatedAt: old,
        retryCount: 1,
        stageLogs: [
          AiAnalysisStageLog(
            stage: AiAnalysisStage.embedding,
            startedAt: old,
            message: '生成多级向量',
            retryCount: 1,
          ),
        ],
      );
      await repository.saveJob(job);

      final runnable = await repository.nextRunnableJob();
      final repaired = await repository.getJob(job.id);

      expect(runnable?.id, job.id);
      expect(repaired?.state, AiAnalysisJobState.incomplete);
      expect(repaired?.currentStage, AiAnalysisStage.embedding);
      expect(repaired?.retryCount, 1);
      expect(repaired?.lastError, '上次整理被中断，已等待继续');
      expect(repaired?.stageLogs.last.message, '上次整理被系统中断');
      expect(repaired?.stageLogs.last.stage, AiAnalysisStage.embedding);
      expect(repaired?.stageLogs.last.error, contains('超过 10 分钟未更新'));
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
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('segments=2'));
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('embeddings=4'));
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('facts=1'));
      expect(job?.stageLogs.map((log) => log.inputSummary).join('\n'),
          contains('summary='));
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
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('importance='));
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
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('model=local-hashing-embedding/v1/128d'));
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

    test('ignores invalid task storage values and repairs index', () async {
      final date = DateTime(2026, 7, 3);
      final valid = StoneTask(
        id: 'stone:valid',
        sourceEntryId: 'entry',
        title: '散步 10 分钟',
        description: '晚饭后即可。',
        createdAt: date,
        updatedAt: date,
      );
      SharedPreferences.setMockInitialValues({
        'stone.tasks.index': <Object?>[
          'stone:valid',
          'broken',
          12,
          'array',
          'list',
        ],
        'stone.tasks.stone:valid': jsonEncode(valid.toJson()),
        'stone.tasks.broken': '{broken',
        'stone.tasks.array': '[]',
        'stone.tasks.list': <String>['bad'],
      });
      const repository = StoneTaskRepository();

      final tasks = await repository.listTasks();
      final prefs = await SharedPreferences.getInstance();

      expect(tasks.map((item) => item.id), ['stone:valid']);
      expect(await repository.getTask('broken'), isNull);
      expect(await repository.getTask('array'), isNull);
      expect(await repository.getTask('list'), isNull);
      expect(prefs.getStringList('stone.tasks.index'), ['stone:valid']);
      expect(prefs.get('stone.tasks.broken'), isNull);
      expect(prefs.get('stone.tasks.array'), isNull);
      expect(prefs.get('stone.tasks.list'), ['bad']);
    });

    test('save recovers when task index has a wrong type', () async {
      SharedPreferences.setMockInitialValues({
        'stone.tasks.index': 'legacy-bad-index',
      });
      const repository = StoneTaskRepository();
      final date = DateTime(2026, 7, 3);

      await repository.saveTask(StoneTask(
        id: 'stone:saved',
        sourceEntryId: 'entry',
        title: '散步 10 分钟',
        description: '晚饭后即可。',
        createdAt: date,
        updatedAt: date,
      ));
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getStringList('stone.tasks.index'), ['stone:saved']);
      expect((await repository.listTasks()).single.id, 'stone:saved');
    });

    test('removes deleted diary source ids without deleting tasks', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = StoneTaskRepository();
      final date = DateTime(2026, 7, 3);
      await repository.saveTask(StoneTask(
        id: 'stone:source-cleanup',
        sourceEntryId: 'deleted-entry',
        title: '晚饭后散步',
        description: '走一小圈。',
        createdAt: date,
        updatedAt: date,
        checkIns: [
          StoneTaskCheckIn(
            id: 'checkin:deleted',
            createdAt: date,
            note: '从被删日记来的进展',
            sourceEntryId: 'deleted-entry',
          ),
          StoneTaskCheckIn(
            id: 'checkin:kept',
            createdAt: date,
            note: '另一天的进展',
            sourceEntryId: 'kept-entry',
          ),
        ],
      ));

      await repository.deleteForSourceEntry('deleted-entry');
      final task = await repository.getTask('stone:source-cleanup');

      expect(task, isNotNull);
      expect(task?.sourceEntryId, isEmpty);
      expect(task?.checkIns.map((item) => item.id), [
        'checkin:deleted',
        'checkin:kept',
      ]);
      expect(task?.checkIns.first.sourceEntryId, isNull);
      expect(task?.checkIns.last.sourceEntryId, 'kept-entry');
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

    test('ignores invalid calendar memories and repairs index', () async {
      final date = DateTime(2026, 7, 3);
      final valid = CalendarMemory(
        id: 'anniversary',
        title: '外婆生日',
        month: 7,
        day: 3,
        createdAt: date,
        updatedAt: date,
      );
      SharedPreferences.setMockInitialValues({
        'calendar.memories.index': <Object?>[
          'anniversary',
          'broken',
          null,
          'array',
          'list',
        ],
        'calendar.memories.anniversary': jsonEncode(valid.toJson()),
        'calendar.memories.broken': '{broken',
        'calendar.memories.array': '[]',
        'calendar.memories.list': <String>['bad'],
      });
      const repository = CalendarMemoryRepository();

      final memories = await repository.listMemories();
      final prefs = await SharedPreferences.getInstance();

      expect(memories.map((item) => item.id), ['anniversary']);
      expect(prefs.getStringList('calendar.memories.index'), ['anniversary']);
      expect(prefs.get('calendar.memories.broken'), isNull);
      expect(prefs.get('calendar.memories.array'), isNull);
      expect(prefs.get('calendar.memories.list'), ['bad']);
    });

    test('save recovers when calendar memory index has a wrong type', () async {
      SharedPreferences.setMockInitialValues({
        'calendar.memories.index': 'legacy-bad-index',
      });
      const repository = CalendarMemoryRepository();
      final date = DateTime(2026, 7, 3);

      await repository.saveMemory(CalendarMemory(
        id: 'saved-anniversary',
        title: '旅行纪念日',
        month: 7,
        day: 3,
        createdAt: date,
        updatedAt: date,
      ));
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getStringList('calendar.memories.index'),
          ['saved-anniversary']);
      expect((await repository.listMemories()).single.id, 'saved-anniversary');
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

    test('ignores invalid profile preferences and repairs index', () async {
      final date = DateTime(2026, 7, 3);
      const repository = AiProfilePreferenceRepository();
      final valid = AiProfilePreference(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: 'stress_pattern',
        confirmed: true,
        updatedAt: date,
      );
      SharedPreferences.setMockInitialValues({
        'ai.profilePreferences.index': <Object?>[
          valid.id,
          'broken',
          12,
          'array',
          'list',
        ],
        'ai.profilePreferences.${valid.id}': jsonEncode(valid.toJson()),
        'ai.profilePreferences.broken': '{broken',
        'ai.profilePreferences.array': '[]',
        'ai.profilePreferences.list': <String>['bad'],
      });

      final preferences = await repository.listPreferences();
      final prefs = await SharedPreferences.getInstance();

      expect(preferences.map((item) => item.id), [valid.id]);
      expect(
        await repository.getPreference(
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: 'broken',
        ),
        isNull,
      );
      expect(prefs.getStringList('ai.profilePreferences.index'), [valid.id]);
      expect(prefs.get('ai.profilePreferences.broken'), isNull);
      expect(prefs.get('ai.profilePreferences.array'), isNull);
      expect(prefs.get('ai.profilePreferences.list'), ['bad']);
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

    test('filters companion answer sources to retrieved context ids', () async {
      SharedPreferences.setMockInitialValues({});
      final date = DateTime(2026, 7, 3);
      final client = _CompanionAiClientService(jsonEncode({
        'answer': '运动记录里反复出现恢复感。',
        'follow_up': '最近哪次运动最接近这种感觉？',
        'sources': [
          {
            'source_id': 'memory:walk-memory',
            'title': '运动',
            'reason': '同样提到运动后的恢复',
            'score': 8,
          },
          {
            'source_id': 'entry_summary:hallucinated',
            'title': '不存在的日记',
            'reason': '模型编造的来源',
            'score': 9,
          },
        ],
      }));
      final context = AiContextPackage(
        scenario: AiContextScenario.question,
        query: '我最近运动后怎么样',
        relatedMemories: [
          MemoryRetrievalResult(
            memory: MemoryEntry(
              id: 'walk-memory',
              sourceEntryId: 'walk-entry',
              date: date,
              createdAt: date,
              summary: '运动后状态更轻松。',
              keywords: const ['运动'],
              emotion: '轻松',
              people: const [],
              tags: const ['运动'],
            ),
            score: 8,
            reasons: const ['主题匹配：运动'],
            matchedTokens: const ['运动'],
          ),
        ],
        searchMatches: const [
          AiSearchMatch(
            sourceType: 'entry_summary',
            sourceId: 'walk-entry',
            entryId: 'walk-entry',
            title: '晚间运动',
            summary: '跑步后轻松了一些。',
            score: 6,
            reasons: ['关键词重合：运动'],
            matchedTokens: ['运动'],
          ),
        ],
      );

      final answer = await CompanionAnswerService(
        client: client,
        contextBuilder: _FakeQuestionContextBuilder(context),
      ).answer('我最近运动后怎么样');
      final trace =
          await const AiPromptTraceRepository().getTrace('companion:last');

      expect(client.lastUserPrompt, contains('source_id=memory:walk-memory'));
      expect(client.lastUserPrompt,
          contains('source_id=entry_summary:walk-entry'));
      expect(answer.sources, hasLength(1));
      expect(answer.sources.single.sourceType, 'memory');
      expect(answer.sources.single.sourceId, 'walk-memory');
      expect(answer.sources.single.title, '运动');
      expect(trace?.contextSummary, contains('sourceFiltered=1'));
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

    test('repositories ignore invalid summaries, segments, and embeddings',
        () async {
      final entry = _entry(
        id: 'entry',
        content: '早上开会很累。\n\n---\n\n晚上散步以后放松。',
      );
      final summary = _summaryForTest(
        entry: entry,
        brief: '今天有工作疲惫和散步恢复。',
        importance: 0.72,
      );
      final segment = DiarySegment(
        id: '${entry.id}#s1',
        entryId: entry.id,
        index: 0,
        text: '晚上散步以后放松。',
        summary: '散步后状态放松。',
        topics: const ['散步'],
        people: const [],
        boundary: DiarySegmentBoundary.divider,
        createdAt: entry.updatedAt,
      );
      final embedding = AiEmbedding(
        id: 'summary:${entry.id}',
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
        entryId: entry.id,
        modelId: 'test',
        modelVersion: '1',
        dimensions: 2,
        vector: const [0.1, 0.2],
        generatedAt: entry.updatedAt,
        textHash: 'hash',
      );
      SharedPreferences.setMockInitialValues({
        'ai.entrySummaries.${entry.id}': jsonEncode(summary.toJson()),
        'ai.entrySummaries.broken': '{broken',
        'ai.entrySegments.index.${entry.id}': <Object?>[
          segment.id,
          'broken-segment',
          12,
          'array-segment',
          'list-segment',
        ],
        'ai.entrySegments.${segment.id}': jsonEncode(segment.toJson()),
        'ai.entrySegments.broken-segment': '{broken',
        'ai.entrySegments.array-segment': '[]',
        'ai.entrySegments.list-segment': <String>['bad'],
        'ai.embeddings.entryIndex.${entry.id}': <Object?>[
          embedding.id,
          'broken',
          null,
          'array',
          'list',
        ],
        'ai.embeddings.typeIndex.summary': <Object?>[embedding.id, 'broken'],
        'ai.embeddings.${embedding.id}': jsonEncode(embedding.toJson()),
        'ai.embeddings.broken': '{broken',
        'ai.embeddings.array': '[]',
        'ai.embeddings.list': <String>['bad'],
      });
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();

      expect(await summaryRepository.getSummary(entry.id), isNotNull);
      expect(await summaryRepository.getSummary('broken'), isNull);
      expect((await summaryRepository.listSegments(entry.id)).single.id,
          segment.id);
      expect((await embeddingRepository.listForEntry(entry.id)).single.id,
          embedding.id);
      expect(
          (await embeddingRepository.listByType(
            AiEmbeddingSourceType.summary,
          ))
              .single
              .id,
          embedding.id);
      expect(
        await embeddingRepository.getBySource(
          sourceType: AiEmbeddingSourceType.summary,
          sourceId: 'broken',
        ),
        isNull,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get('ai.entrySummaries.broken'), isNull);
      expect(prefs.getStringList('ai.entrySegments.index.${entry.id}'),
          [segment.id]);
      expect(prefs.get('ai.entrySegments.broken-segment'), isNull);
      expect(prefs.get('ai.entrySegments.array-segment'), isNull);
      expect(prefs.get('ai.entrySegments.list-segment'), ['bad']);
      expect(prefs.getStringList('ai.embeddings.entryIndex.${entry.id}'),
          [embedding.id]);
      expect(prefs.getStringList('ai.embeddings.typeIndex.summary'),
          [embedding.id]);
      expect(prefs.get('ai.embeddings.broken'), isNull);
      expect(prefs.get('ai.embeddings.array'), isNull);
      expect(prefs.get('ai.embeddings.list'), ['bad']);
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

    test('uses structured people topic and emotion signals for rerank',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      final date = DateTime(2026, 7, 3);
      final plain = _entry(
        id: 'plain-search-summary',
        date: date,
        content: '散步以后焦虑下降。',
      );
      final structured = _entry(
        id: 'structured-search-summary',
        date: date,
        content: '和妈妈散步以后焦虑下降。',
      );
      await diaryRepository.saveEntry(plain);
      await diaryRepository.saveEntry(structured);
      await summaryRepository.saveSummary(_summaryForTest(
        entry: plain,
        brief: '散步以后焦虑下降',
        importance: 0.5,
      ));
      await summaryRepository.saveSummary(_summaryForTest(
        entry: structured,
        brief: '散步以后焦虑下降',
        importance: 0.5,
        topics: const ['散步'],
        people: const ['妈妈'],
        emotion: '焦虑',
      ));

      final matches = await const AiSearchService().search('妈妈 散步 焦虑');

      expect(matches.first.entryId, structured.id);
      expect(matches.first.reasons.join(' '), contains('人物匹配'));
      expect(matches.first.reasons.join(' '), contains('主题匹配'));
      expect(matches.first.reasons.join(' '), contains('情绪匹配'));
    });
  });

  group('PeriodSummaryService', () {
    test('period summary keeps context debug summary and legacy defaults',
        () async {
      final date = DateTime(2026, 7, 3);
      final summary = PeriodSummary(
        id: 'month:2026-07',
        type: PeriodSummaryType.month,
        startDate: DateTime(2026, 7),
        endDate: DateTime(2026, 7, 31, 23, 59, 59),
        generatedAt: date,
        entryCount: 1,
        brief: '七月摘要',
        themes: const ['散步'],
        emotions: const ['放松'],
        representativeEntryIds: const ['entry'],
        generator: 'test',
        contextDebugSummary: 'periodSummary sources=3',
        contextSourceLines: const ['entry_summary:e1 | 2026-07-03 | 散步'],
      );
      final restored = PeriodSummary.fromJson(summary.toJson());
      final legacy = PeriodSummary.fromJson({
        'id': 'legacy',
        'type': 'month',
        'startDate': date.toIso8601String(),
        'endDate': date.toIso8601String(),
        'generatedAt': date.toIso8601String(),
        'entryCount': <String>['bad'],
        'contextSourceLines': 'bad',
      });
      final malformed = PeriodSummary.fromJson({
        'id': 12,
        'type': <String>['month'],
        'startDate': <String>['bad'],
        'endDate': null,
        'generatedAt': 3,
        'themes': 'bad',
        'contextDebugSummary': <String>['bad'],
      });

      expect(restored.contextDebugSummary, 'periodSummary sources=3');
      expect(restored.contextSourceLines.single, contains('entry_summary:e1'));
      expect(legacy.contextDebugSummary, '');
      expect(legacy.contextSourceLines, isEmpty);
      expect(malformed.id, '');
      expect(malformed.contextDebugSummary, '');
    });

    test('period summary repository ignores invalid stored values', () async {
      SharedPreferences.setMockInitialValues({
        'ai.periodSummaries.list': <String>['not-json'],
        'ai.periodSummaries.broken': '{broken',
        'ai.periodSummaries.array': '[]',
      });
      const repository = PeriodSummaryRepository();

      expect(await repository.getSummary('list'), isNull);
      expect(await repository.getSummary('broken'), isNull);
      expect(await repository.getSummary('array'), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get('ai.periodSummaries.list'), ['not-json']);
      expect(prefs.get('ai.periodSummaries.broken'), isNull);
      expect(prefs.get('ai.periodSummaries.array'), isNull);
    });

    test('period summary repository lists recent summaries first', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = PeriodSummaryRepository();
      final oldDate = DateTime(2026, 7, 1);
      final newDate = DateTime(2026, 7, 3);
      await repository.saveSummary(PeriodSummary(
        id: 'month:2026-06',
        type: PeriodSummaryType.month,
        startDate: DateTime(2026, 6),
        endDate: DateTime(2026, 6, 30, 23, 59, 59),
        generatedAt: oldDate,
        entryCount: 1,
        brief: '六月摘要',
        themes: const [],
        emotions: const [],
        representativeEntryIds: const [],
        generator: 'test',
      ));
      await repository.saveSummary(PeriodSummary(
        id: 'month:2026-07',
        type: PeriodSummaryType.month,
        startDate: DateTime(2026, 7),
        endDate: DateTime(2026, 7, 31, 23, 59, 59),
        generatedAt: newDate,
        entryCount: 2,
        brief: '七月摘要',
        themes: const ['散步'],
        emotions: const [],
        representativeEntryIds: const [],
        generator: 'test',
      ));

      final summaries = await repository.listSummaries();

      expect(summaries.map((summary) => summary.id),
          ['month:2026-07', 'month:2026-06']);
    });

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
      expect(summary.contextDebugSummary, contains('periodSummary'));
      expect(summary.contextDebugSummary, contains('sources='));
    });

    test('period summary stores context source lines for developer tracing',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      final entry = _entry(
        id: 'period-source-entry',
        date: DateTime(2026, 7, 3),
        content: '晚上散步以后焦虑下降。',
      );
      await diaryRepository.saveEntry(entry);
      await summaryRepository.saveSummary(_summaryForTest(
        entry: entry,
        brief: '晚上散步以后焦虑下降',
        importance: 0.82,
        topics: const ['散步', '情绪调节'],
      ));

      final summary = await const PeriodSummaryService()
          .buildMonthSummary(DateTime(2026, 7), [entry]);

      expect(summary.contextSourceLines.join('\n'), contains('period_entry'));
      expect(summary.contextSourceLines.join('\n'), contains('entry_summary'));
      expect(summary.contextSourceLines.join('\n'), contains(entry.id));
      expect(summary.contextSourceLines.join('\n'), contains('2026-07-03'));
      expect(
          summary.contextSourceLines.join('\n'), contains('importance=0.82'));
    });

    test('period summary traces raw entries even before summaries exist',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      final entry = _entry(
        id: 'period-raw-entry',
        date: DateTime(2026, 7, 4),
        content: '今天只保存了原始日记，还没有摘要。',
      );
      await diaryRepository.saveEntry(entry);

      final summary = await const PeriodSummaryService()
          .buildMonthSummary(DateTime(2026, 7), [entry]);
      final sourceText = summary.contextSourceLines.join('\n');

      expect(sourceText, contains('period_entry:period-raw-entry'));
      expect(sourceText, isNot(contains('entry_summary:period-raw-entry')));
    });

    test('period summary derives themes from raw entries before insights exist',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      final entry = _entry(
        id: 'period-local-theme',
        date: DateTime(2026, 7, 5),
        content: '晚上散步以后焦虑下降，整个人轻松了一些。',
      );
      await diaryRepository.saveEntry(entry);

      final summary = await const PeriodSummaryService()
          .buildMonthSummary(DateTime(2026, 7), [entry]);

      expect(summary.themes.join(' '), contains('散步'));
      expect(summary.emotions.join(' '), contains('焦虑'));
      expect(summary.brief, contains('主要主题'));
      expect(summary.brief, contains('常见情绪'));
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
      final latestTrace =
          await const AiRetrievalTraceRepository().getTrace('period:last');

      expect(package.periodEntries, hasLength(50));
      expect(package.periodSummaries, hasLength(48));
      expect(package.periodSummaries.first.entryId, 'period-budget-49');
      expect(package.debugSummary, contains('periodSummaries=48'));
      expect(latestTrace?.scenario, AiContextScenario.periodSummary.name);
      expect(latestTrace?.contextSummary, package.debugSummary);
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

    test('matches custom solar anniversaries within a nearby window', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const calendarRepository = CalendarMemoryRepository();
      final now = DateTime(2026, 7, 5);
      await calendarRepository.saveMemory(CalendarMemory(
        id: 'anniversary-trip',
        title: '第一次旅行纪念日',
        month: 7,
        day: 3,
        createdAt: now,
        updatedAt: now,
      ));
      final current = _entry(
        id: 'anniversary-window-current',
        date: now,
        content: '这几天又想起第一次旅行。',
      );
      final nearPast = _entry(
        id: 'anniversary-window-past',
        date: DateTime(2025, 7, 2),
        content: '去年旅行纪念日前一天也写了这件事。',
      );
      final ordinaryToday = _entry(
        id: 'ordinary-today-past',
        date: DateTime(2025, 7, 5),
        content: '去年今天只是普通记录。',
      );
      final outsideWindow = _entry(
        id: 'anniversary-outside-window',
        date: DateTime(2024, 7, 8),
        content: '这条离纪念日太远。',
      );
      for (final entry in [
        current,
        nearPast,
        ordinaryToday,
        outsideWindow,
      ]) {
        await diaryRepository.saveEntry(entry);
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(current);
      final ids = package.calendarMatches.map((match) => match.entry.id);
      final anniversary = package.calendarMatches
          .firstWhere((match) => match.entry.id == 'anniversary-window-past');

      expect(ids, contains('anniversary-window-past'));
      expect(ids, contains('ordinary-today-past'));
      expect(ids, isNot(contains('anniversary-outside-window')));
      expect(anniversary.label, '第一次旅行纪念日');
      expect(anniversary.score, 11);
      expect(anniversary.dayOffset, -1);
      expect(anniversary.reason, contains('第一次旅行纪念日附近'));
      expect(
        package.retrievalTrace?.items
            .firstWhere((item) => item.sourceId == 'anniversary-window-past')
            .matchedTokens,
        contains('第一次旅行纪念日'),
      );
    });

    test('does not treat disabled or lunar memories as solar matches',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const calendarRepository = CalendarMemoryRepository();
      final now = DateTime(2026, 7, 3);
      await calendarRepository.saveMemory(CalendarMemory(
        id: 'disabled-memory',
        title: '禁用纪念日',
        month: 7,
        day: 3,
        createdAt: now,
        updatedAt: now,
        enabled: false,
      ));
      await calendarRepository.saveMemory(CalendarMemory(
        id: 'lunar-memory',
        title: '农历生日',
        month: 7,
        day: 3,
        createdAt: now,
        updatedAt: now,
        type: CalendarMemoryType.lunar,
      ));
      final current = _entry(
        id: 'calendar-filter-current',
        date: now,
        content: '今天想起一些日期。',
      );
      final past = _entry(
        id: 'calendar-filter-past',
        date: DateTime(2025, 7, 3),
        content: '去年今天也想起一些日期。',
      );
      for (final entry in [current, past]) {
        await diaryRepository.saveEntry(entry);
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(current);
      final match = package.calendarMatches.single;

      expect(match.label, isNull);
      expect(match.calendarType, 'solar');
      expect(match.reason, contains('年前的今天'));
      expect(match.reason, isNot(contains('农历生日')));
      expect(match.reason, isNot(contains('禁用纪念日')));
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
      const traceRepository = AiRetrievalTraceRepository();
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
      final savedTrace = await traceRepository.getTrace('search:last');
      expect(savedTrace?.scenario, AiContextScenario.search.name);
      expect(savedTrace?.contextSummary, package.debugSummary);
      expect(savedTrace?.items.map((item) => item.sourceType),
          containsAll(['entry_summary', 'segment']));
    });

    test('question context preserves diary and segment matches', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const traceRepository = AiRetrievalTraceRepository();
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
      expect(package.retrievalTrace?.scenario, AiContextScenario.question.name);
      final savedTrace = await traceRepository.getTrace('question:last');
      expect(savedTrace?.scenario, AiContextScenario.question.name);
      expect(savedTrace?.contextSummary, package.debugSummary);
      expect(savedTrace?.items.map((item) => item.sourceType),
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
      final prefs = await SharedPreferences.getInstance();

      expect(items, isEmpty);
      expect(prefs.containsKey('diary.trash.entry-1'), isFalse);
      expect(prefs.getStringList('diary.trash.index'), isEmpty);
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
      expect(prefs.getStringList('diary.trash.index'), isEmpty);
    });

    test('restore from trash requeues AI artifact rebuild', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const insightRepository = InsightRepository();
      final entry = _entry(
        id: 'trash-restore-ai',
        date: DateTime(2026, 7, 3),
        content: '恢复后需要重新整理 AI 资料。',
      );
      await diaryRepository.saveEntry(entry);
      await queueRepository.enqueueEntry(entry);
      await diaryRepository.moveToTrash(entry.id);

      expect(await queueRepository.getJob(entry.id), isNull);
      expect(await diaryRepository.getEntryById(entry.id), isNull);

      await diaryRepository.restoreFromTrash(entry.id);
      final restored = await diaryRepository.getEntryById(entry.id);
      final job = await queueRepository.getJob(entry.id);
      final status = await insightRepository.getStatus(entry.id);

      expect(restored?.content, entry.content);
      expect(job?.state, AiAnalysisJobState.pending);
      expect(job?.pipelineVersion, entry.updatedAt.microsecondsSinceEpoch);
      expect(status?.state, DiaryAnalysisState.queued);
      expect(status?.message, contains('回收站恢复'));
    });

    test('move to trash removes stone source references', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const stoneRepository = StoneTaskRepository();
      final entry = _entry(
        id: 'trash-stone-source',
        date: DateTime(2026, 7, 3),
        content: '这篇日记生成了一个塑石行动。',
      );
      await diaryRepository.saveEntry(entry);
      await stoneRepository.saveTask(StoneTask(
        id: 'stone:trash-source',
        sourceEntryId: entry.id,
        title: '散步',
        description: '晚饭后散步。',
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
        checkIns: [
          StoneTaskCheckIn(
            id: 'checkin:trash-source',
            createdAt: entry.createdAt,
            note: '完成了一次',
            sourceEntryId: entry.id,
          ),
        ],
      ));

      await diaryRepository.moveToTrash(entry.id);
      final task = await stoneRepository.getTask('stone:trash-source');

      expect(task, isNotNull);
      expect(task?.sourceEntryId, isEmpty);
      expect(task?.checkIns.single.sourceEntryId, isNull);
    });
  });

  group('MemoryRepository lifecycle', () {
    test('ignores invalid memory storage values and repairs index', () async {
      final date = DateTime(2026, 7, 3);
      final valid = MemoryEntry(
        id: 'valid-memory',
        sourceEntryId: 'entry',
        date: date,
        createdAt: date,
        summary: '散步后状态恢复。',
        keywords: const ['散步'],
        emotion: '放松',
        people: const [],
        tags: const ['运动'],
      );
      SharedPreferences.setMockInitialValues({
        'memory.entries.index': <Object?>[
          'valid-memory',
          'broken',
          12,
          'array',
          'list',
        ],
        'memory.entries.valid-memory': jsonEncode(valid.toJson()),
        'memory.entries.broken': '{broken',
        'memory.entries.array': '[]',
        'memory.entries.list': <String>['bad'],
      });
      const repository = MemoryRepository();

      final memories = await repository.listMemories();
      final prefs = await SharedPreferences.getInstance();

      expect(memories.map((item) => item.id), ['valid-memory']);
      expect(await repository.countMemories(), 1);
      expect(prefs.getStringList('memory.entries.index'), ['valid-memory']);
      expect(prefs.get('memory.entries.broken'), isNull);
      expect(prefs.get('memory.entries.array'), isNull);
      expect(prefs.get('memory.entries.list'), ['bad']);
    });

    test('save recovers when memory index has a wrong type', () async {
      SharedPreferences.setMockInitialValues({
        'memory.entries.index': 'legacy-bad-index',
      });
      const repository = MemoryRepository();
      final date = DateTime(2026, 7, 3);

      await repository.saveMemory(MemoryEntry(
        id: 'saved-memory',
        sourceEntryId: 'entry',
        date: date,
        createdAt: date,
        summary: '散步以后状态恢复。',
        keywords: const ['散步'],
        emotion: '放松',
        people: const [],
        tags: const ['运动'],
      ));
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getStringList('memory.entries.index'), ['saved-memory']);
      expect((await repository.listMemories()).single.id, 'saved-memory');
    });

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
  List<String> topics = const [],
  List<String> people = const [],
  String emotion = '',
}) {
  return EntrySummary(
    entryId: entry.id,
    date: entry.date,
    entryUpdatedAt: entry.updatedAt,
    generatedAt: entry.updatedAt,
    title: entry.title ?? brief,
    brief: brief,
    keyPoints: [brief],
    topics: topics,
    people: people,
    places: const [],
    emotion: emotion,
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
      facts: const [
        InsightClaim(text: '今天记录了一个测试事实。'),
      ],
      signals: const [
        InsightClaim(text: '测试信号。'),
      ],
      hypotheses: const [
        InsightClaim(text: '测试推测。', confidence: 0.6),
      ],
      suggestions: const [
        InsightClaim(text: '测试建议。'),
      ],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'test_field',
          value: '测试画像候选',
          confidence: 0.5,
        ),
      ],
    );
  }
}

class _CapturingAiClientService extends AiClientService {
  String? lastSystemPrompt;
  String? lastUserPrompt;

  @override
  Future<String> completeJson({
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    lastSystemPrompt = systemPrompt;
    lastUserPrompt = userPrompt;
    return jsonEncode({
      'reflection': '散步后状态更轻松。',
      'related_memories': [
        {
          'title': '散步记忆',
          'reason': '同样提到散步后放松',
          'entry_id': 'memory-entry-source',
        },
        {
          'title': '不存在的历史',
          'reason': '模型误填来源',
          'entry_id': 'hallucinated-entry',
        }
      ],
      'facts': [
        {
          'text': '今天记录了散步后状态变轻松。',
          'evidence': [
            {'type': 'current_entry', 'id': 'feedback-prompt-entry'},
            {'type': 'entry_summary', 'id': 'hallucinated-entry'}
          ],
        }
      ],
      'signals': [],
      'hypotheses': [
        {
          'text': '散步可能帮助恢复状态。',
          'confidence': 0.62,
          'evidence': [
            {'type': 'memory', 'id': 'memory-walk-source'},
            {'type': 'memory', 'id': 'hallucinated-memory'}
          ],
        }
      ],
      'suggestions': [
        {
          'text': '明天晚饭后散步 10 分钟。',
          'evidence': [
            {'type': 'stone', 'id': 'stone-walk-source'},
            {'type': 'stone', 'id': 'hallucinated-stone'}
          ],
        }
      ],
      'emotion': '轻松',
      'keywords': ['散步'],
      'people': [],
      'stone_suggestion': {
        'title': '散步 10 分钟',
        'description': '晚饭后出门走一小圈。',
      },
      'memory_update': {
        'summary': '散步后状态更轻松。',
        'tags': ['散步'],
      },
      'profile_update_candidates': [],
      'relationship_updates': [],
      'contradictions': [],
    });
  }
}

class _CompanionAiClientService extends AiClientService {
  _CompanionAiClientService(this.response);

  final String response;
  String? lastUserPrompt;

  @override
  Future<String> completeJson({
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    lastUserPrompt = userPrompt;
    return response;
  }
}

class _FakeQuestionContextBuilder extends AiContextBuilder {
  const _FakeQuestionContextBuilder(this.package);

  final AiContextPackage package;

  @override
  Future<AiContextPackage> buildForQuestion(String question) async => package;
}
