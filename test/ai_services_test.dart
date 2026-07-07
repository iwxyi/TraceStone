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
import 'package:trace_stone/data/services/ai_artifact_rebuild_service.dart';
import 'package:trace_stone/data/services/ai_client_service.dart';
import 'package:trace_stone/data/services/ai_data_inventory_service.dart';
import 'package:trace_stone/data/services/ai_feedback_service.dart';
import 'package:trace_stone/data/services/ai_profile_decision_service.dart';
import 'package:trace_stone/data/services/ai_search_service.dart';
import 'package:trace_stone/data/services/app_startup_service.dart';
import 'package:trace_stone/data/services/companion_answer_service.dart';
import 'package:trace_stone/data/services/diary_analysis_service.dart';
import 'package:trace_stone/data/services/embedding_service.dart';
import 'package:trace_stone/data/services/entry_summary_service.dart';
import 'package:trace_stone/data/services/period_summary_service.dart';
import 'package:trace_stone/data/services/profile_projection_service.dart';
import 'package:trace_stone/data/utils/ai_source_formatter.dart';

Future<void> _throwStartupCleanupError() async {
  throw StateError('cleanup failed');
}

void main() {
  group('AppStartupService', () {
    test('runs blocking cleanup before app and resumes AI queue after start',
        () async {
      final events = <String>[];
      final service = AppStartupService(
        purgeExpiredTrash: () async {
          events.add('purge');
        },
        resumeAiQueue: () async {
          events.add('resume');
        },
      );

      await service.runBeforeApp();
      service.runAfterAppStart();
      await Future<void>.delayed(Duration.zero);

      expect(events, ['purge', 'resume']);
    });

    test('does not block launch when trash cleanup fails', () async {
      const service = AppStartupService(
        purgeExpiredTrash: _throwStartupCleanupError,
      );

      await service.runBeforeApp();
    });
  });

  group('AiPromptTrace', () {
    test('AI source formatter avoids duplicate typed prefixes', () {
      expect(formatAiSourceId('memory', 'memory:walk'), 'memory:walk');
      expect(formatAiSourceId('stone', 'stone:walk'), 'stone:walk');
      expect(formatAiSourceId('entry_summary', 'entry-1'),
          'entry_summary:entry-1');
      expect(
        formatInsightEvidenceId(const InsightEvidence(
          type: 'current_entry',
          id: 'current_entry:entry-1',
        )),
        'current_entry:entry-1',
      );
    });

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
        rawResponsePreview: '{"reflection":"preview"}',
        rawResponseLength: 25,
        systemPrompt: '完整 system prompt',
        userPrompt: '完整 user prompt',
        rawResponse: '{"reflection":"raw"}',
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
      expect(restored.rawResponse, '{"reflection":"raw"}');
      expect(restored.rawResponseLength, 25);
      expect(legacy.systemPrompt, isNull);
      expect(legacy.rawResponse, isNull);
      expect(legacy.rawResponsePreview, isEmpty);
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

    test('clears prompt and retrieval traces that reference an entry',
        () async {
      SharedPreferences.setMockInitialValues({});
      const promptRepository = AiPromptTraceRepository();
      const retrievalRepository = AiRetrievalTraceRepository();
      final date = DateTime(2026, 7, 3);
      await promptRepository.saveTrace(AiPromptTrace(
        id: 'companion:last',
        scenario: 'question',
        createdAt: date,
        contextSummary: 'sources=1',
        systemPromptPreview: 'system',
        userPromptPreview: 'entry_summary:deleted-entry',
        systemPromptLength: 6,
        userPromptLength: 28,
        userPrompt: 'source_id=entry_summary:deleted-entry｜散步摘要',
      ));
      await promptRepository.saveTrace(AiPromptTrace(
        id: 'unrelated',
        scenario: 'question',
        createdAt: date,
        contextSummary: 'sources=0',
        systemPromptPreview: 'system',
        userPromptPreview: 'unrelated-entry',
        systemPromptLength: 6,
        userPromptLength: 15,
      ));
      await retrievalRepository.saveTrace(AiRetrievalTrace(
        entryId: 'search:last',
        generatedAt: date,
        scenario: 'search',
        items: const [
          AiRetrievalTraceItem(
            sourceType: 'entry_summary',
            sourceId: 'deleted-entry',
            title: '旧摘要',
            summary: '这条 trace 引用了已删除日记',
            score: 8,
            reasons: ['关键词重合'],
            matchedTokens: ['散步'],
          ),
        ],
      ));
      await retrievalRepository.saveTrace(AiRetrievalTrace(
        entryId: 'question:last',
        generatedAt: date,
        scenario: 'question',
        items: const [
          AiRetrievalTraceItem(
            sourceType: 'entry_summary',
            sourceId: 'kept-entry',
            title: '保留摘要',
            summary: '未引用删除日记',
            score: 8,
            reasons: ['关键词重合'],
            matchedTokens: ['散步'],
          ),
        ],
      ));

      await promptRepository.deleteForEntry('deleted-entry');
      await retrievalRepository.deleteForEntry('deleted-entry');

      expect(await promptRepository.getTrace('companion:last'), isNull);
      expect(await promptRepository.getTrace('unrelated'), isNotNull);
      expect(await retrievalRepository.getTrace('search:last'), isNull);
      expect(await retrievalRepository.getTrace('question:last'), isNotNull);
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

    test('reads malformed retrieval trace fields with safe defaults', () {
      final trace = AiRetrievalTrace.fromJson({
        'entryId': 42,
        'generatedAt': <String>['bad'],
        'scenario': <String>['search'],
        'contextSummary': 99,
        'sourceCount': '3',
        'items': [
          {
            'sourceType': 'memory',
            'sourceId': 77,
            'title': 12,
            'summary': null,
            'score': '8',
            'reasons': ['语义相似', 3],
            'matchedTokens': 'bad',
            'rerankSignals': {
              'semantic': '0.75',
              'keyword': 3,
              12: 'ignored',
              'bad': 'x',
            },
          },
          'bad-item',
          {12: 'ignored', 'sourceType': 'segment'},
        ],
      });

      expect(trace.entryId, '42');
      expect(trace.scenario, isNull);
      expect(trace.contextSummary, isNull);
      expect(trace.sourceCount, 3);
      expect(trace.items, hasLength(2));
      expect(trace.items.first.sourceType, 'memory');
      expect(trace.items.first.sourceId, '77');
      expect(trace.items.first.title, '12');
      expect(trace.items.first.score, 8);
      expect(trace.items.first.reasons, ['语义相似', '3']);
      expect(trace.items.first.matchedTokens, isEmpty);
      expect(trace.items.first.rerankSignals, {
        'semantic': 0.75,
        'keyword': 3.0,
      });
      expect(trace.items.last.sourceType, 'segment');
    });

    test('reads malformed prompt trace fields with safe defaults', () {
      final trace = AiPromptTrace.fromJson({
        'id': 42,
        'scenario': <String>['todayInsight'],
        'createdAt': <String>['bad'],
        'contextSummary': 12,
        'systemPromptPreview': null,
        'userPromptPreview': true,
        'systemPromptLength': '128',
        'userPromptLength': 64.8,
        'systemPrompt': ['bad'],
        'userPrompt': '完整 user prompt',
      });

      expect(trace.id, '42');
      expect(trace.scenario, '[todayInsight]');
      expect(trace.contextSummary, '12');
      expect(trace.systemPromptPreview, '');
      expect(trace.userPromptPreview, 'true');
      expect(trace.systemPromptLength, 128);
      expect(trace.userPromptLength, 64);
      expect(trace.systemPrompt, isNull);
      expect(trace.userPrompt, '完整 user prompt');
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

    test('feedback repository keeps malformed field values safely', () async {
      SharedPreferences.setMockInitialValues({
        'ai.feedback.malformed': jsonEncode({
          'entryId': 42,
          'value': ['inaccurate'],
          'createdAt': <String>['bad'],
          'note': {'text': 'bad'},
        }),
      });

      final feedback =
          await const AiFeedbackRepository().getFeedback('malformed');
      final prefs = await SharedPreferences.getInstance();

      expect(feedback?.entryId, '42');
      expect(feedback?.value, AiFeedbackValue.unclear);
      expect(feedback?.note, isNull);
      expect(prefs.getString('ai.feedback.malformed'), isNotNull);
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
      await const InsightRepository().saveInsight(DiaryInsight(
        entryId: entry.id,
        entryDate: entry.date,
        generatedAt: entry.date,
        reflection: '上一版把轻松误读成焦虑。',
        relatedMemories: const [
          RelatedMemoryInsight(
            title: '旧散步记忆',
            reason: '同样提到散步',
            entryId: 'old-walk-entry',
          ),
        ],
        emotion: '焦虑',
        keywords: const ['散步', '焦虑'],
        people: const [],
        stoneTitle: '',
        stoneDescription: '',
        memorySummary: '',
        memoryTags: const [],
        facts: const [
          InsightClaim(
            text: '今天散步了。',
            evidence: [
              InsightEvidence(
                type: 'current_entry',
                id: 'feedback-entry',
              ),
            ],
          ),
        ],
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
      expect(savedFeedback?.previousInsightSummary, contains('上一版把轻松误读成焦虑'));
      expect(savedFeedback?.previousInsightSummary, contains('情绪：焦虑'));
      expect(
          savedFeedback?.previousInsightSources,
          containsAll(
              ['related:old-walk-entry', 'current_entry:feedback-entry']));
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
      expect(job?.stageLogs.last.outputSummary,
          contains('previousInsight=attached'));
      expect(status?.state, DiaryAnalysisState.incomplete);
      expect(status?.message, contains('重新整理队列'));
    });

    test('inaccurate feedback note is included in regenerated insight prompt',
        () async {
      SharedPreferences.setMockInitialValues({});
      const feedbackRepository = AiFeedbackRepository();
      const promptRepository = AiPromptTraceRepository();
      const insightRepository = InsightRepository();
      const preferenceRepository = AiProfilePreferenceRepository();
      const projectionService = ProfileProjectionService();
      final client = _CapturingAiClientService();
      final entry = _entry(
        id: 'feedback-prompt-entry',
        date: DateTime(2026, 7, 3),
        content: '今天散步以后，状态轻松了一些。',
      );
      final recent = _entry(
        id: 'recent-source-entry',
        date: DateTime(2026, 7, 2),
        content: '这是一段很长的最近日记原文，不应该直接进入今日洞察历史上下文。',
      );
      await const DiaryRepository().saveEntry(entry);
      await const DiaryRepository().saveEntry(recent);
      final segments = const EntrySummaryService().buildSegments(entry);
      await const EntrySummaryRepository().saveSummary(
        const EntrySummaryService().buildSummary(entry, segments),
      );
      await const EntrySummaryRepository().saveSegments(entry.id, segments);
      await const EntrySummaryRepository().saveSummary(_summaryForTest(
        entry: recent,
        brief: '昨天也写到散步后的恢复。',
        importance: 0.72,
        topics: const ['散步', '恢复'],
      ));
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
      final visibleInsight = _insight(
        entryId: 'today-visible-profile',
        date: DateTime(2026, 6, 28),
        profileCandidate: const ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步后压力下降',
          confidence: 0.7,
        ),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '妈妈',
          relationship: 'family',
          summary: '晚饭后沟通更平和',
          emotion: '平和',
          confidence: 0.66,
        ),
      );
      final hiddenInsight = _insight(
        entryId: 'today-hidden-profile',
        date: DateTime(2026, 6, 29),
        profileCandidate: const ProfileUpdateCandidate(
          field: 'private_pattern',
          value: '隐藏的压力模式',
          confidence: 0.75,
        ),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '小王',
          relationship: 'coworker',
          summary: '隐藏的协作摩擦',
          emotion: '紧张',
          confidence: 0.72,
        ),
      );
      await insightRepository.saveInsight(visibleInsight);
      await insightRepository.saveInsight(hiddenInsight);
      final projection =
          projectionService.build([visibleInsight, hiddenInsight]);
      final visibleFact = projection.profileFacts
          .firstWhere((fact) => fact.field == 'self_regulation');
      final hiddenFact = projection.profileFacts
          .firstWhere((fact) => fact.field == 'private_pattern');
      await preferenceRepository.setCorrectedValue(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: visibleFact.id,
        correctedValue: '晚饭后散步更容易帮助我卸下压力',
      );
      await preferenceRepository.setHidden(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: hiddenFact.id,
        hidden: true,
      );
      await preferenceRepository.setCorrectedValue(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: '妈妈',
        correctedValue: '家人',
      );
      await preferenceRepository.setHidden(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: '小王',
        hidden: true,
      );
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
        previousInsightSummary: '读后感：上一版把散步后的轻松说成焦虑。\n情绪：焦虑\n建议：立刻处理压力',
        previousInsightSources: const [
          'current_entry:feedback-prompt-entry',
          'memory:memory-walk-source',
        ],
      ));

      await DiaryAnalysisService(client: client).analyzeEntry(entry);

      final trace = await promptRepository.getTrace(entry.id);
      final insight = await const InsightRepository().getInsight(entry.id);
      expect(client.lastUserPrompt, contains('用户反馈：'));
      expect(client.lastUserPrompt, contains('上一版洞察被用户标记为不准确'));
      expect(client.lastUserPrompt, contains('不要把轻松判断成焦虑'));
      expect(client.lastUserPrompt, contains('上一版洞察快照'));
      expect(client.lastUserPrompt, contains('上一版把散步后的轻松说成焦虑'));
      expect(client.lastUserPrompt, contains('上一版使用过的来源'));
      expect(client.lastUserPrompt, contains('memory:memory-walk-source'));
      expect(client.lastUserPrompt, contains('segment:${segments.first.id}'));
      expect(client.lastUserPrompt, contains('entry:recent-source-entry'));
      expect(
          client.lastUserPrompt, contains('entry_summary:recent-source-entry'));
      expect(client.lastUserPrompt, contains('昨天也写到散步后的恢复'));
      expect(client.lastUserPrompt, isNot(contains('很长的最近日记原文')));
      expect(client.lastUserPrompt, contains('memory:memory-walk-source'));
      expect(
          client.lastUserPrompt, contains('sourceEntry:memory-entry-source'));
      expect(client.lastUserPrompt,
          contains('evidenceEntries:memory-entry-source,older-evidence'));
      expect(client.lastUserPrompt, contains('signals:'));
      expect(client.lastUserPrompt, contains('stone:stone-walk-source'));
      expect(client.lastUserPrompt, contains('sourceEntry:stone-entry-source'));
      expect(client.lastUserPrompt, contains('profile:p1'));
      expect(client.lastUserPrompt, contains('relationship:r1'));
      expect(client.lastUserPrompt, contains('晚饭后散步更容易帮助我卸下压力'));
      expect(client.lastUserPrompt, contains('妈妈｜家人'));
      expect(client.lastUserPrompt, isNot(contains('散步后压力下降')));
      expect(client.lastUserPrompt, isNot(contains('private_pattern')));
      expect(client.lastUserPrompt, isNot(contains('隐藏的压力模式')));
      expect(client.lastUserPrompt, isNot(contains('小王')));
      expect(client.lastUserPrompt, isNot(contains('隐藏的协作摩擦')));
      expect(trace?.userPrompt, contains('不要把轻松判断成焦虑'));
      expect(trace?.rawResponse, contains('"reflection"'));
      expect(trace?.rawResponsePreview, contains('"reflection"'));
      expect(trace?.contextSummary, contains('evidenceFiltered=3'));
      expect(trace?.contextSummary, contains('relatedSourceFiltered=1'));
      expect(insight?.relatedMemories.map((item) => item.entryId), [
        'memory-entry-source',
        'recent-source-entry',
        null,
      ]);
      expect(insight?.facts.single.evidence.map((item) => item.id), [
        'feedback-prompt-entry',
        'recent-source-entry',
      ]);
      expect(insight?.hypotheses.single.evidence.map((item) => item.id),
          ['memory-walk-source']);
      expect(insight?.suggestions.single.evidence.map((item) => item.id),
          ['stone-walk-source']);
      final oldMemory = (await const MemoryRepository().listMemories())
          .firstWhere((memory) => memory.id == 'memory-walk-source');
      expect(oldMemory.confidence, lessThan(0.58));
      expect(oldMemory.decay, greaterThan(0));
    });

    test('analysis does not create long term memory without memory update',
        () async {
      SharedPreferences.setMockInitialValues({});
      final entry = _entry(
        id: 'no-memory-update-entry',
        date: DateTime(2026, 7, 3),
        content: '今天只是简单记录一下，没有需要长期记住的内容。',
      );
      await const DiaryRepository().saveEntry(entry);

      await DiaryAnalysisService(client: _NoMemoryUpdateAiClientService())
          .analyzeEntry(entry);

      final insight = await const InsightRepository().getInsight(entry.id);
      final memories = await const MemoryRepository().listMemories();

      expect(insight?.reflection, '今天是普通记录。');
      expect(memories.map((memory) => memory.id), isNot(contains(entry.id)));
    });

    test('analysis tolerates malformed AI response field shapes', () async {
      SharedPreferences.setMockInitialValues({});
      final entry = _entry(
        id: 'malformed-ai-response-entry',
        date: DateTime(2026, 7, 3),
        content: '今天写一点散步后的恢复感。',
      );
      await const DiaryRepository().saveEntry(entry);

      final insight = await DiaryAnalysisService(
        client: const _MalformedAnalysisAiClientService(),
      ).analyzeEntry(entry);
      final saved = await const InsightRepository().getInsight(entry.id);

      expect(insight.entryId, entry.id);
      expect(saved, isNotNull);
      expect(insight.reflection, '42');
      expect(insight.emotion, 'true');
      expect(insight.keywords, isEmpty);
      expect(insight.relatedMemories.single.entryId, entry.id);
      expect(insight.facts, isEmpty);
      expect(insight.hypotheses.single.text, '散步可能帮助恢复。');
      expect(insight.memorySummary, '123');
      expect(insight.memoryTags, isEmpty);
      expect(insight.stoneTitle, '7');
      expect(insight.suggestions.single.text, '7：明天走 10 分钟');
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

  group('AiDataInventoryService', () {
    test('summarizes AI derived local data by category', () async {
      SharedPreferences.setMockInitialValues({
        'ai.entrySummaries.entry-1': jsonEncode({
          'entryId': 'entry-1',
          'date': '2026-07-03T00:00:00.000',
          'entryUpdatedAt': '2026-07-03T00:00:00.000',
          'generatedAt': '2026-07-03T00:00:00.000',
          'title': '散步',
          'brief': '散步。',
          'keyPoints': <String>[],
          'topics': <String>[],
          'people': <String>[],
          'places': <String>[],
          'emotion': '',
          'importance': 0.4,
          'importantQuotes': <String>[],
          'generator': 'test',
          'qualityScore': 0.32,
          'qualityWarnings': <String>['摘要过短', '缺少关键点'],
        }),
        'ai.entrySummaryRevisions.entry-1:r2': jsonEncode(
          EntrySummaryRevision(
            id: 'entry-1:r2',
            entryId: 'entry-1',
            revision: 2,
            createdAt: DateTime(2026, 7, 3, 1),
            previousTitle: '散步',
            updatedTitle: '散步恢复',
            previousBrief: '散步。',
            updatedBrief: '饭后散步帮助恢复状态。',
            previousQualityScore: 0.32,
            updatedQualityScore: 0.72,
          ).toJson(),
        ),
        'ai.entrySummaryRevisions.index.entry-1': <String>['entry-1:r2'],
        'ai.entrySegments.index.entry-1': <String>['entry-1#s1'],
        'ai.embeddings.summary:entry-1': jsonEncode(
          AiEmbedding(
            id: 'summary:entry-1',
            sourceType: AiEmbeddingSourceType.summary,
            sourceId: 'entry-1',
            entryId: 'entry-1',
            modelId: EmbeddingService.modelId,
            modelVersion: EmbeddingService.modelVersion,
            dimensions: EmbeddingService.dimensions,
            vector: List<double>.filled(EmbeddingService.dimensions, 0),
            generatedAt: DateTime(2026, 7, 3),
            textHash: 'current',
          ).toJson(),
        ),
        'ai.embeddings.segment:entry-1#s1': jsonEncode(
          AiEmbedding(
            id: 'segment:entry-1#s1',
            sourceType: AiEmbeddingSourceType.segment,
            sourceId: 'entry-1#s1',
            entryId: 'entry-1',
            modelId: 'legacy-hashing-embedding',
            modelVersion: 'v0',
            dimensions: 64,
            vector: List<double>.filled(64, 0),
            generatedAt: DateTime(2026, 7, 3),
            textHash: 'legacy',
          ).toJson(),
        ),
        'ai.embeddings.entryIndex.entry-1': <String>['summary:entry-1'],
        'ai.embeddings.typeIndex.summary': <String>['summary:entry-1'],
        'ai.embeddings.typeIndex.segment': <String>['segment:entry-1#s1'],
        'diary.insights.index': <String>['entry-1'],
        'diary.insights.latest': 'entry-1',
        'diary.insights.status.entry-1': jsonEncode(
          DiaryAnalysisStatus(
            entryId: 'entry-1',
            state: DiaryAnalysisState.completed,
            updatedAt: DateTime(2026, 7, 3),
            message: '已完成今日洞察',
          ).toJson(),
        ),
        'diary.insights.entry-1': jsonEncode(
          DiaryInsight(
            entryId: 'entry-1',
            entryDate: DateTime(2026, 7, 3),
            generatedAt: DateTime(2026, 7, 3),
            reflection: '今天的饭后散步帮助你从压力里恢复。',
            relatedMemories: const [
              RelatedMemoryInsight(
                title: '饭后散步',
                reason: '相同恢复策略',
                entryId: 'memory-1',
              ),
            ],
            emotion: '平静',
            keywords: const ['散步', '恢复'],
            people: const ['小王'],
            stoneTitle: '饭后散步',
            stoneDescription: '继续用轻量散步恢复状态。',
            memorySummary: '饭后散步有助于恢复状态。',
            memoryTags: const ['恢复'],
            facts: const [
              InsightClaim(
                text: '今天记录了饭后散步。',
                confidence: 0.9,
                evidence: [
                  InsightEvidence(
                    type: 'current_entry',
                    id: 'entry-1',
                    quote: '饭后散步',
                  ),
                ],
              ),
            ],
            signals: const [
              InsightClaim(
                text: '散步与情绪恢复相关。',
                confidence: 0.7,
              ),
            ],
            hypotheses: const [
              InsightClaim(
                text: '短时间活动比强行休息更适合今天。',
                confidence: 0.62,
                evidence: [
                  InsightEvidence(
                    type: 'memory',
                    id: 'memory-1',
                    summary: '饭后散步有助于恢复状态。',
                  ),
                ],
              ),
            ],
            suggestions: const [
              InsightClaim(
                text: '保留 10 分钟低门槛散步。',
                confidence: 0.78,
                evidence: [
                  InsightEvidence(
                    type: 'current_entry',
                    id: 'entry-1',
                    relevance: '延续今日有效行动',
                  ),
                ],
              ),
            ],
            profileUpdateCandidates: const [
              ProfileUpdateCandidate(
                field: '恢复方式',
                value: '饭后散步',
                confidence: 0.72,
              ),
            ],
            relationshipUpdates: const [
              RelationshipUpdateCandidate(
                personName: '小王',
                summary: '一起散步带来支持感',
                confidence: 0.68,
              ),
            ],
            contradictions: const [
              InsightContradiction(
                oldMemoryId: 'memory:old',
                newEvidence: '今天散步后状态变好',
                interpretation: '过去认为散步无效的记忆需要核对',
                confidence: 0.61,
              ),
            ],
          ).toJson(),
        ),
        'memory.entries.memory-1': jsonEncode(
          MemoryEntry(
            id: 'memory-1',
            sourceEntryId: 'entry-1',
            date: DateTime(2026, 7, 3),
            createdAt: DateTime(2026, 7, 3),
            summary: '饭后散步有助于恢复状态。',
            keywords: const ['散步', '恢复'],
            emotion: '平静',
            people: const ['小王'],
            tags: const ['恢复'],
            evidenceEntryIds: const ['entry-1', 'entry-2'],
            importance: 0.8,
            confidence: 0.3,
            referenceCount: 0,
            decay: 0.6,
            archived: true,
          ).toJson(),
        ),
        'ai.profilePreferences.profileFact:1': jsonEncode(
          AiProfilePreference(
            targetType: AiProfilePreferenceTargetType.profileFact,
            targetId: '1',
            updatedAt: DateTime(2026, 7, 3),
            confirmed: true,
            correctedValue: '喜欢饭后散步',
          ).toJson(),
        ),
        'ai.relationshipMergeHistory.merge-1': jsonEncode(
          AiRelationshipMergeEvent(
            id: 'merge-1',
            sourcePersonName: '小王',
            targetPersonName: '王同学',
            action: AiRelationshipMergeEventAction.merge,
            createdAt: DateTime(2026, 7, 3),
          ).toJson(),
        ),
        'ai.analysis.jobs.paused': true,
        'ai.analysis.jobs.index': <String>['entry-1', 'missing-job'],
        'ai.analysis.jobs.entry-1': jsonEncode(
          AiAnalysisJob(
            id: 'entry-1',
            entryId: 'entry-1',
            pipelineVersion: 1,
            state: AiAnalysisJobState.failed,
            currentStage: AiAnalysisStage.generatingInsight,
            createdAt: DateTime(2026, 7, 3),
            updatedAt: DateTime(2026, 7, 3, 0, 2),
            completedStages: const [
              AiAnalysisStage.generatingSummary,
              AiAnalysisStage.segmenting,
            ],
            stageLogs: [
              AiAnalysisStageLog(
                stage: AiAnalysisStage.generatingSummary,
                startedAt: DateTime(2026, 7, 3),
                message: '摘要完成',
                outputSummary: 'summaryId=entry-1',
              ),
              AiAnalysisStageLog(
                stage: AiAnalysisStage.generatingInsight,
                startedAt: DateTime(2026, 7, 3, 0, 1),
                message: '洞察失败',
                error: 'AI unavailable',
                retryCount: 1,
              ),
            ],
            summaryId: 'entry-1',
            segmentIds: const ['entry-1#s1'],
            embeddingIds: const ['summary:entry-1'],
            retrievalTraceId: 'trace-1',
            retryCount: 1,
            lastError: 'AI unavailable',
            batchId: 'batch-import-1',
            batchLabel: '导入补建',
          ).toJson(),
        ),
        'ai.promptTraces.companion:last': jsonEncode(
          AiPromptTrace(
            id: 'companion:last',
            scenario: 'companion',
            createdAt: DateTime(2026, 7, 3),
            contextSummary: 'current_entry:entry-1; memory:memory-1',
            systemPromptPreview: '你是 TraceStone 的陪伴式分析助手。',
            userPromptPreview: '请分析 entry-1。',
            systemPromptLength: 120,
            userPromptLength: 80,
            rawResponsePreview: '{"summary":"ok"}',
            rawResponseLength: 32,
            systemPrompt: 'system prompt full',
            userPrompt: 'user prompt full',
            rawResponse: '{"summary":"ok"}',
          ).toJson(),
        ),
        'ai.retrievalTraces.search:last': jsonEncode(
          AiRetrievalTrace(
            entryId: 'search:last',
            generatedAt: DateTime(2026, 7, 3),
            scenario: 'search',
            contextSummary: 'query=散步',
            sourceCount: 2,
            items: const [
              AiRetrievalTraceItem(
                sourceType: 'memory',
                sourceId: 'memory-1',
                title: '饭后散步',
                summary: '饭后散步有助于恢复。',
                score: 8,
                reasons: ['关键词重合：散步'],
                matchedTokens: ['散步'],
                rerankSignals: {'keyword': 2, 'lifecycle': 1},
              ),
              AiRetrievalTraceItem(
                sourceType: 'entry_summary',
                sourceId: 'entry-1',
                title: '散步',
                summary: '散步恢复。',
                score: 5,
                reasons: ['主题重合'],
                matchedTokens: ['恢复'],
                rerankSignals: {'semantic': 0.42},
              ),
            ],
          ).toJson(),
        ),
        'ai.feedback.entry-1': jsonEncode(
          AiFeedback(
            entryId: 'entry-1',
            value: AiFeedbackValue.inaccurate,
            createdAt: DateTime(2026, 7, 3),
            note: '这条洞察不准确。',
            previousInsightSummary: '上一版把轻松误判成焦虑。',
            previousInsightSources: const [
              'current_entry:entry-1',
              'memory:memory-1',
            ],
          ).toJson(),
        ),
        'ai.periodSummaries.month:2026-07': jsonEncode(
          PeriodSummary(
            id: 'month:2026-07',
            type: PeriodSummaryType.month,
            startDate: DateTime(2026, 7),
            endDate: DateTime(2026, 7, 31, 23, 59, 59),
            generatedAt: DateTime(2026, 7, 4),
            entryCount: 2,
            brief: '7 月主要围绕恢复和散步。',
            themes: const ['恢复', '散步'],
            emotions: const ['平静'],
            representativeEntryIds: const ['entry-1', 'entry-2'],
            generator: 'local-aggregate-v1',
            relationshipHighlights: const ['小王｜一起散步'],
            stoneHighlights: const ['完成：饭后散步'],
            contextDebugSummary: 'period=2026-07 sources=4',
            contextSourceLines: const [
              'period_entry:entry-1 | 2026-07-03 | 散步',
              'memory:memory-1 | 饭后散步有助于恢复状态。',
            ],
          ).toJson(),
        ),
        'calendar.memories.anniversary': jsonEncode({
          'id': 'anniversary',
          'title': '农历家庭日',
          'month': 5,
          'day': 5,
          'createdAt': '2026-07-03T00:00:00.000',
          'updatedAt': '2026-07-03T00:00:00.000',
          'type': 'lunar',
          'note': '家里的重要日子',
          'enabled': false,
        }),
        'stone.tasks.stone:1': jsonEncode({
          'id': 'stone:1',
          'sourceEntryId': 'entry-1',
          'title': '晚饭后散步',
          'description': '走 10 分钟',
          'createdAt': '2026-07-03T00:00:00.000',
          'updatedAt': '2026-07-04T00:00:00.000',
          'status': 'completed',
          'tags': <String>['运动', '恢复'],
          'checkIns': [
            {
              'id': 'checkin:1',
              'createdAt': '2026-07-04T00:00:00.000',
              'note': '完成了',
              'sourceEntryId': 'entry-2',
            }
          ],
        }),
        'diary.entries.entry-1': '{}',
      });

      final inventory = await const AiDataInventoryService().buildInventory();
      final counts = {
        for (final section in inventory.sections) section.label: section.count,
      };

      expect(counts['日记摘要'], 4);
      final summarySection =
          inventory.sections.firstWhere((section) => section.label == '日记摘要');
      expect(summarySection.details, contains('summaryObjects=1'));
      expect(summarySection.details, contains('averageQuality=0.32'));
      expect(summarySection.details, contains('lowQuality=1'));
      expect(summarySection.details, contains('warningSummaries=1'));
      expect(summarySection.details, contains('correctedSummaries=0'));
      expect(summarySection.details, contains('revisionObjects=1'));
      expect(summarySection.details, contains('revisionIndexes=1'));
      expect(summarySection.details, contains('maxRevision=2'));
      expect(summarySection.details, contains('worst=entry-1:0.32'));
      expect(summarySection.details, contains('warnings=摘要过短:1,缺少关键点:1'));
      expect(
          summarySection.details, contains('revisionReasons=user-corrected:1'));
      expect(counts['向量索引'], 5);
      final embeddingSection =
          inventory.sections.firstWhere((section) => section.label == '向量索引');
      expect(embeddingSection.details, contains('objects=2'));
      expect(embeddingSection.details, contains('entryIndexes=1'));
      expect(embeddingSection.details, contains('typeIndexes=2'));
      expect(
        embeddingSection.details,
        contains(
            'models=legacy-hashing-embedding/v0:1,local-hashing-embedding/v1:1'),
      );
      expect(embeddingSection.details, contains('dimensions=128d:1,64d:1'));
      expect(
        embeddingSection.details,
        contains('sourceTypes=segment:1,summary:1'),
      );
      expect(embeddingSection.details, contains('staleModel=1'));
      expect(embeddingSection.details, contains('invalidDimensions=1'));
      expect(
        embeddingSection.details,
        contains('warning=存在非当前模型版本的向量对象'),
      );
      expect(
        embeddingSection.details,
        contains('warning=存在维度不匹配的向量对象'),
      );
      expect(counts['今日洞察'], 4);
      final insightSection =
          inventory.sections.firstWhere((section) => section.label == '今日洞察');
      expect(insightSection.details, contains('objects=1'));
      expect(insightSection.details, contains('indexed=1'));
      expect(insightSection.details, contains('statuses=1'));
      expect(insightSection.details, contains('latestSet=true'));
      expect(insightSection.details, contains('facts=1'));
      expect(insightSection.details, contains('signals=1'));
      expect(insightSection.details, contains('hypotheses=1'));
      expect(insightSection.details, contains('suggestions=1'));
      expect(insightSection.details, contains('evidenceItems=3'));
      expect(insightSection.details, contains('claimsWithoutEvidence=1'));
      expect(insightSection.details, contains('relatedMemories=1'));
      expect(insightSection.details, contains('profileCandidates=1'));
      expect(insightSection.details, contains('relationshipCandidates=1'));
      expect(insightSection.details, contains('contradictions=1'));
      expect(insightSection.details, contains('stoneSuggestions=1'));
      expect(insightSection.details, contains('memoryUpdates=1'));
      expect(insightSection.details, contains('statusStates=completed:1'));
      expect(insightSection.details, contains('topEmotions=平静:1'));
      expect(insightSection.details, contains('topKeywords=恢复:1,散步:1'));
      expect(insightSection.details, contains('topPeople=小王:1'));
      final memorySection =
          inventory.sections.firstWhere((section) => section.label == '长期记忆');
      expect(memorySection.details, contains('objects=1'));
      expect(memorySection.details, contains('indexed=0'));
      expect(memorySection.details, contains('archived=1'));
      expect(memorySection.details, contains('lowConfidence=1'));
      expect(memorySection.details, contains('highDecay=1'));
      expect(memorySection.details, contains('neverReferenced=1'));
      expect(memorySection.details, contains('evidenceSources=2'));
      expect(memorySection.details, contains('references=0'));
      expect(memorySection.details, contains('averageImportance=0.80'));
      expect(memorySection.details, contains('averageConfidence=0.30'));
      expect(memorySection.details, contains('topTags=恢复:1'));
      expect(memorySection.details, contains('topPeople=小王:1'));
      expect(counts['调试记录'], 3);
      final debugSection =
          inventory.sections.firstWhere((section) => section.label == '调试记录');
      expect(debugSection.details, contains('promptTraces=1'));
      expect(debugSection.details, contains('retrievalTraces=1'));
      expect(debugSection.details, contains('feedback=1'));
      expect(debugSection.details, contains('fullPromptStored=1'));
      expect(debugSection.details, contains('rawResponsesStored=1'));
      expect(debugSection.details, contains('averagePromptLength=200'));
      expect(debugSection.details, contains('retrievalItems=2'));
      expect(debugSection.details, contains('retrievalSourceCount=2'));
      expect(debugSection.details, contains('retrievalSignals=3'));
      expect(debugSection.details, contains('feedbackWithNote=1'));
      expect(debugSection.details, contains('feedbackWithPreviousInsight=1'));
      expect(debugSection.details, contains('feedbackPreviousSources=2'));
      expect(debugSection.details, contains('promptScenarios=companion:1'));
      expect(debugSection.details, contains('retrievalScenarios=search:1'));
      expect(
        debugSection.details,
        contains('sourceTypes=entry_summary:1,memory:1'),
      );
      expect(
        debugSection.details,
        contains('signalTypes=keyword:1,lifecycle:1,semantic:1'),
      );
      expect(debugSection.details, contains('feedbackValues=inaccurate:1'));
      expect(counts['后台队列'], 3);
      final queueSection =
          inventory.sections.firstWhere((section) => section.label == '后台队列');
      expect(queueSection.details, contains('objects=1'));
      expect(queueSection.details, contains('indexed=2'));
      expect(queueSection.details, contains('paused=true'));
      expect(queueSection.details, contains('pending=0'));
      expect(queueSection.details, contains('failed=1'));
      expect(queueSection.details, contains('retryableFailed=1'));
      expect(queueSection.details, contains('blockedFailed=0'));
      expect(queueSection.details, contains('retrying=1'));
      expect(queueSection.details, contains('batches=1'));
      expect(queueSection.details, contains('stageLogs=2'));
      expect(queueSection.details, contains('stageLogErrors=1'));
      expect(queueSection.details, contains('jobsWithError=1'));
      expect(queueSection.details, contains('artifactRefs=4'));
      expect(queueSection.details, contains('staleIndex=1'));
      expect(
        queueSection.details,
        contains('topStages=generatingInsight:1'),
      );
      expect(queueSection.details, contains('lastErrorTypes=AI unavailable:1'));
      expect(queueSection.details,
          contains('stageLogErrorTypes=AI unavailable:1'));
      final profilePreferenceSection =
          inventory.sections.firstWhere((section) => section.label == '画像偏好');
      expect(profilePreferenceSection.details, contains('objects=1'));
      expect(profilePreferenceSection.details, contains('indexed=0'));
      expect(profilePreferenceSection.details, contains('profileFacts=1'));
      expect(profilePreferenceSection.details, contains('relationships=0'));
      expect(profilePreferenceSection.details, contains('confirmed=1'));
      expect(profilePreferenceSection.details, contains('corrected=1'));
      expect(counts['关系合并历史'], 1);
      final mergeHistorySection =
          inventory.sections.firstWhere((section) => section.label == '关系合并历史');
      expect(mergeHistorySection.details, contains('objects=1'));
      expect(mergeHistorySection.details, contains('indexed=0'));
      expect(mergeHistorySection.details, contains('merges=1'));
      expect(mergeHistorySection.details, contains('undos=0'));
      expect(
        mergeHistorySection.details,
        contains('topPairs=小王->王同学:1'),
      );
      expect(counts['周期总结'], 1);
      final periodSection =
          inventory.sections.firstWhere((section) => section.label == '周期总结');
      expect(periodSection.details, contains('objects=1'));
      expect(periodSection.details, contains('months=1'));
      expect(periodSection.details, contains('years=0'));
      expect(periodSection.details, contains('entryCount=2'));
      expect(periodSection.details, contains('representativeRefs=2'));
      expect(periodSection.details, contains('contextLines=2'));
      expect(periodSection.details, contains('relationshipHighlights=1'));
      expect(periodSection.details, contains('stoneHighlights=1'));
      expect(
        periodSection.details,
        contains('generators=local-aggregate-v1:1'),
      );
      expect(periodSection.details, contains('topThemes=恢复:1,散步:1'));
      expect(periodSection.details, contains('topEmotions=平静:1'));
      final calendarSection =
          inventory.sections.firstWhere((section) => section.label == '纪念日');
      expect(calendarSection.details, contains('objects=1'));
      expect(calendarSection.details, contains('indexed=0'));
      expect(calendarSection.details, contains('solar=0'));
      expect(calendarSection.details, contains('lunar=1'));
      expect(calendarSection.details, contains('disabled=1'));
      expect(calendarSection.details, contains('topMonths=lunar-5:1'));
      final stoneSection =
          inventory.sections.firstWhere((section) => section.label == '塑石行动');
      expect(stoneSection.details, contains('objects=1'));
      expect(stoneSection.details, contains('indexed=0'));
      expect(stoneSection.details, contains('active=0'));
      expect(stoneSection.details, contains('completed=1'));
      expect(stoneSection.details, contains('checkIns=1'));
      expect(stoneSection.details, contains('sourcedTasks=1'));
      expect(stoneSection.details, contains('sourcedCheckIns=1'));
      expect(stoneSection.details, contains('topTags=恢复:1,运动:1'));
      expect(inventory.totalCount, 25);
      expect(inventory.highSensitivitySectionCount, greaterThanOrEqualTo(6));
      expect(inventory.reviewSectionCount, greaterThanOrEqualTo(4));
      expect(summarySection.needsReview, isTrue);
      expect(summarySection.reviewDetailCount, greaterThanOrEqualTo(1));
      expect(summarySection.isHighSensitivity, isTrue);
      final reviewDebugText = inventory.toDebugText(
        scope: '需核对',
        selectedSections:
            inventory.sections.where((section) => section.needsReview),
      );
      expect(reviewDebugText, contains('scope=需核对'));
      expect(reviewDebugText, contains('### 日记摘要'));
      expect(reviewDebugText, contains('### 向量索引'));
      expect(reviewDebugText, isNot(contains('### 纪念日')));
      expect(inventory.toDebugText(), contains('TraceStone AI Data Inventory'));
      expect(inventory.toDebugText(), contains('AI 衍生数据默认视为日记数据'));
      expect(inventory.toDebugText(), contains('sensitivity=critical'));
      expect(inventory.toDebugText(), contains('averageQuality=0.32'));
      expect(inventory.toDebugText(), contains('revisionObjects=1'));
      expect(inventory.toDebugText(),
          contains('revisionReasons=user-corrected:1'));
      expect(inventory.toDebugText(), contains('staleModel=1'));
      expect(inventory.toDebugText(), contains('invalidDimensions=1'));
      expect(inventory.toDebugText(), contains('warnings=摘要过短:1,缺少关键点:1'));
      expect(inventory.toDebugText(), contains('claimsWithoutEvidence=1'));
      expect(inventory.toDebugText(), contains('statusStates=completed:1'));
      expect(inventory.toDebugText(), contains('averageConfidence=0.30'));
      expect(inventory.toDebugText(), contains('topPeople=小王:1'));
      expect(inventory.toDebugText(), contains('feedbackValues=inaccurate:1'));
      expect(
          inventory.toDebugText(), contains('feedbackWithPreviousInsight=1'));
      expect(inventory.toDebugText(), contains('feedbackPreviousSources=2'));
      expect(inventory.toDebugText(), contains('retrievalSignals=3'));
      expect(inventory.toDebugText(), contains('retryableFailed=1'));
      expect(inventory.toDebugText(), contains('stageLogErrors=1'));
      expect(
          inventory.toDebugText(), contains('lastErrorTypes=AI unavailable:1'));
      expect(inventory.toDebugText(),
          contains('stageLogErrorTypes=AI unavailable:1'));
      expect(inventory.toDebugText(), contains('profileFacts=1'));
      expect(inventory.toDebugText(), contains('topPairs=小王->王同学:1'));
      expect(inventory.toDebugText(), contains('contextLines=2'));
      expect(inventory.toDebugText(), contains('topEmotions=平静:1'));
      expect(inventory.toDebugText(), contains('topMonths=lunar-5:1'));
      expect(inventory.toDebugText(), contains('topTags=恢复:1,运动:1'));
      expect(inventory.toDebugText(), contains('details=objects=1'));
      expect(inventory.toDebugText(), contains('backupPolicy=默认不建议云备份'));
      expect(inventory.toDebugText(), contains('exportPolicy=复制前必须确认'));
    });

    test('flags inaccurate feedback without prior insight context', () async {
      SharedPreferences.setMockInitialValues({
        'ai.feedback.entry-without-context': jsonEncode(
          AiFeedback(
            entryId: 'entry-without-context',
            value: AiFeedbackValue.inaccurate,
            createdAt: DateTime(2026, 7, 3),
            note: '没有保存上一版洞察。',
          ).toJson(),
        ),
      });

      final inventory = await const AiDataInventoryService().buildInventory();
      final debugSection =
          inventory.sections.firstWhere((section) => section.label == '调试记录');

      expect(debugSection.details, contains('feedback=1'));
      expect(debugSection.details, contains('feedbackWithNote=1'));
      expect(debugSection.details, contains('feedbackWithPreviousInsight=0'));
      expect(debugSection.details, contains('feedbackPreviousSources=0'));
      expect(
        debugSection.details,
        contains('inaccurateFeedbackWithoutContext=1'),
      );
      expect(debugSection.needsReview, isTrue);
      expect(
        inventory.toDebugText(),
        contains('inaccurateFeedbackWithoutContext=1'),
      );
    });
  });

  group('AiArtifactRebuildService', () {
    test('rebuilds summary package and multi-level embeddings', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const service = AiArtifactRebuildService();
      final entry = _entry(
        id: 'rebuild-summary-entry',
        date: DateTime(2026, 7, 3),
        content: '上午处理工作压力。\n\n---\n\n晚上散步以后恢复了一点。',
      );
      await diaryRepository.saveEntry(entry);

      final result = await service.rebuildSummaryPackage(entry.id);
      final summary = await summaryRepository.getSummary(entry.id);
      final segments = await summaryRepository.listSegments(entry.id);
      final embeddings = await embeddingRepository.listForEntry(entry.id);
      final job = await queueRepository.getJob(entry.id);

      expect(result?.target, AiArtifactRebuildTarget.summaryPackage);
      expect(summary, isNotNull);
      expect(segments.length, greaterThan(1));
      expect(
          embeddings.map((embedding) => embedding.sourceType),
          containsAll([
            AiEmbeddingSourceType.entry,
            AiEmbeddingSourceType.summary,
            AiEmbeddingSourceType.segment,
          ]));
      expect(job?.state, AiAnalysisJobState.completed);
      expect(job?.stageLogs.last.message, '开发者重建摘要包和日记片段');
      expect(job?.stageLogs.last.outputSummary, contains('embeddings='));
    });

    test('rebuilds embeddings without replacing the summary package', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const summaryService = EntrySummaryService();
      const embeddingService = EmbeddingService();
      const service = AiArtifactRebuildService();
      final entry = _entry(
        id: 'rebuild-embedding-entry',
        date: DateTime(2026, 7, 3),
        content: '今天散步以后，焦虑下降了一些。',
      );
      await diaryRepository.saveEntry(entry);
      final segments = summaryService.buildSegments(entry);
      final summary = summaryService.buildSummary(entry, segments);
      await summaryRepository.saveSegments(entry.id, segments);
      await summaryRepository.saveSummary(summary);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: entry.id,
        text: '旧向量内容',
        generatedAt: DateTime(2026, 7, 1),
      );

      final before = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: entry.id,
      );
      final result = await service.rebuildEmbeddings(entry.id);
      final after = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: entry.id,
      );
      final savedSummary = await summaryRepository.getSummary(entry.id);
      final job = await queueRepository.getJob(entry.id);

      expect(result?.target, AiArtifactRebuildTarget.embeddings);
      expect(savedSummary?.generatedAt, summary.generatedAt);
      expect(after?.textHash, isNot(before?.textHash));
      expect((await embeddingRepository.listForEntry(entry.id)).length,
          2 + segments.length);
      expect(job?.stageLogs.last.message, '开发者重建多级向量');
    });

    test('rebuilds outdated embeddings in bulk and skips missing entries',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const service = AiArtifactRebuildService();
      final staleEntry = _entry(
        id: 'bulk-stale-embedding',
        date: DateTime(2026, 7, 3),
        content: '这篇日记有旧模型向量，需要批量重建。',
      );
      final currentEntry = _entry(
        id: 'bulk-current-embedding',
        date: DateTime(2026, 7, 4),
        content: '这篇日记已经是当前模型向量。',
      );
      await diaryRepository.saveEntry(staleEntry);
      await diaryRepository.saveEntry(currentEntry);
      await embeddingRepository.saveEmbedding(AiEmbedding(
        id: 'entry:${staleEntry.id}',
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: staleEntry.id,
        entryId: staleEntry.id,
        modelId: 'legacy-hashing-embedding',
        modelVersion: 'v0',
        dimensions: 64,
        vector: List<double>.filled(64, 0),
        generatedAt: DateTime(2026, 7, 1),
        textHash: 'stale',
      ));
      await embeddingRepository.saveEmbedding(AiEmbedding(
        id: 'entry:missing-stale-embedding',
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: 'missing-stale-embedding',
        entryId: 'missing-stale-embedding',
        modelId: 'legacy-hashing-embedding',
        modelVersion: 'v0',
        dimensions: 64,
        vector: List<double>.filled(64, 0),
        generatedAt: DateTime(2026, 7, 1),
        textHash: 'missing',
      ));
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: const EmbeddingService(),
        entryId: currentEntry.id,
        sourceType: AiEmbeddingSourceType.entry,
        sourceId: currentEntry.id,
        text: currentEntry.content,
        generatedAt: DateTime(2026, 7, 4),
      );

      final result = await service.rebuildOutdatedEmbeddings();
      final staleEmbeddings =
          await embeddingRepository.listForEntry(staleEntry.id);
      final currentEmbeddings =
          await embeddingRepository.listForEntry(currentEntry.id);
      final job = await queueRepository.getJob(staleEntry.id);

      expect(result.target, AiArtifactRebuildTarget.embeddings);
      expect(result.requestedEntryIds,
          ['bulk-stale-embedding', 'missing-stale-embedding']);
      expect(result.rebuiltEntryIds, [staleEntry.id]);
      expect(result.skippedEntryIds, ['missing-stale-embedding']);
      expect(result.embeddingIds.length, 3);
      expect(result.summary, 'entries=1/2 embeddings=3 skipped=1');
      expect(staleEmbeddings.map((embedding) => embedding.modelId).toSet(),
          {EmbeddingService.modelId});
      expect(staleEmbeddings.map((embedding) => embedding.dimensions).toSet(),
          {EmbeddingService.dimensions});
      expect(currentEmbeddings, hasLength(1));
      expect(currentEmbeddings.single.textHash,
          const EmbeddingService().embed(currentEntry.content).textHash);
      expect(job?.stageLogs.last.message, '开发者重建多级向量');
    });

    test('rebuilds today insight and records the debug action', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const insightRepository = InsightRepository();
      const queueRepository = AiAnalysisQueueRepository();
      final entry = _entry(
        id: 'rebuild-insight-entry',
        date: DateTime(2026, 7, 3),
        content: '今天写了一条适合重新生成洞察的日记。',
      );
      await diaryRepository.saveEntry(entry);

      final result = await const AiArtifactRebuildService(
        analysisService: _FakeDiaryAnalysisService(),
      ).rebuildInsight(entry.id);
      final insight = await insightRepository.getInsight(entry.id);
      final job = await queueRepository.getJob(entry.id);

      expect(result?.target, AiArtifactRebuildTarget.insight);
      expect(insight?.reflection, '本地测试洞察');
      expect(job?.state, AiAnalysisJobState.completed);
      expect(job?.stageLogs.last.message, '开发者重建今日洞察');
      expect(job?.stageLogs.last.outputSummary, contains('facts=1'));
    });
  });

  group('AiProfileDecisionService', () {
    test('summarizes profile fact decisions for developer review', () {
      final date = DateTime(2026, 7, 3);
      final facts = [
        ProfileFact(
          id: 'self_regulation:散步可能帮助恢复状态',
          field: 'self_regulation',
          value: '散步可能帮助恢复状态',
          status: ProfileFactStatus.emerging,
          confidence: 0.63,
          evidenceCount: 2,
          distinctDays: 2,
          firstSeenAt: date,
          lastSeenAt: date,
        ),
        ProfileFact(
          id: 'self_regulation:写计划能缓解焦虑',
          field: 'self_regulation',
          value: '写计划能缓解焦虑',
          status: ProfileFactStatus.weak,
          confidence: 0.52,
          evidenceCount: 1,
          distinctDays: 1,
          firstSeenAt: date,
          lastSeenAt: date,
        ),
        ProfileFact(
          id: 'pressure:工作压力',
          field: 'pressure',
          value: '工作压力近期较明显',
          status: ProfileFactStatus.stable,
          confidence: 0.72,
          evidenceCount: 3,
          distinctDays: 2,
          firstSeenAt: date,
          lastSeenAt: date,
        ),
      ];
      final preferences = [
        AiProfilePreference(
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: facts.last.id,
          correctedValue: '工作压力近期较明显，但运动后会缓解',
          updatedAt: date,
        ),
        AiProfilePreference(
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: 'hidden:old',
          hidden: true,
          updatedAt: date,
        ),
      ];

      final decisions =
          const AiProfileDecisionService().buildProfileFactDecisions(
        facts: facts,
        preferences: preferences,
        conflicts: [
          ProfileConflictNote(
            targetId: 'profile:self_regulation',
            entryId: 'conflict-entry',
            entryDate: DateTime(2026, 7, 3),
            newEvidence: '独处也能帮助恢复',
            interpretation: '恢复方式需要增加条件',
            confidence: 0.7,
          ),
        ],
      );

      expect(decisions.first.kind, AiProfileDecisionKind.conflict);
      expect(decisions.first.actionLabel, '需要核对冲突');
      expect(
          decisions
              .where((item) => item.kind == AiProfileDecisionKind.corrected),
          hasLength(1));
      expect(
        decisions.where((item) => item.kind == AiProfileDecisionKind.hidden),
        hasLength(1),
      );
      expect(
        decisions
            .where((item) => item.actionLabel == '需要核对冲突')
            .map((item) => item.targetId),
        containsAll([facts[0].id, facts[1].id]),
      );
    });

    test('summarizes relationship decisions for developer review', () {
      final date = DateTime(2026, 7, 3);
      final profiles = [
        RelationshipProfile(
          personName: '小李',
          names: const ['小李'],
          status: ProfileFactStatus.stable,
          confidence: 0.7,
          interactionCount: 3,
          distinctDays: 2,
          lastInteractionAt: date,
          relationship: '同事',
        ),
        RelationshipProfile(
          personName: '小王',
          names: const ['小王'],
          status: ProfileFactStatus.weak,
          confidence: 0.5,
          interactionCount: 1,
          distinctDays: 1,
          lastInteractionAt: date,
        ),
      ];
      final preferences = [
        AiProfilePreference(
          targetType: AiProfilePreferenceTargetType.relationship,
          targetId: '小王',
          confirmed: true,
          updatedAt: date,
        ),
        AiProfilePreference(
          targetType: AiProfilePreferenceTargetType.relationship,
          targetId: '李同学',
          mergedInto: '小李',
          updatedAt: date,
        ),
      ];

      final decisions =
          const AiProfileDecisionService().buildRelationshipDecisions(
        profiles: profiles,
        preferences: preferences,
      );

      expect(decisions.first.title, '小王');
      expect(decisions.first.actionLabel, '用户已确认');
      expect(
        decisions.map((item) => item.actionLabel),
        contains('可进入稳定关系档案'),
      );
      expect(
        decisions
            .where((item) => item.kind == AiProfileDecisionKind.merged)
            .single
            .debugLine,
        contains('mergedInto=小李'),
      );
      expect(
        decisions.map((item) => item.reason),
        contains('已合并到 小李'),
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

    test('reads malformed insight fields with safe defaults', () {
      final insight = DiaryInsight.fromJson({
        'entryId': 42,
        'entryDate': <String>['bad'],
        'generatedAt': <String>['bad'],
        'reflection': 123,
        'emotion': true,
        'keywords': ['散步', 7, null],
        'people': 'bad',
        'stoneTitle': 88,
        'stoneDescription': null,
        'memorySummary': ['bad'],
        'memoryTags': ['恢复', 3],
        'relatedMemories': [
          {
            'title': 2025,
            'reason': null,
            'source_id': 'memory-walk',
          },
          'bad',
        ],
        'facts': [
          {
            'text': 12,
            'confidence': '0.7',
            'evidence': [
              {
                'type': 'memory',
                'id': 99,
                'quote': ['bad'],
                'summary': '历史摘要',
              },
              'bad',
            ],
          },
        ],
        'profile_update_candidates': [
          {
            'field': 7,
            'value': true,
            'action': null,
            'confidence': '0.61',
            'evidence': [
              {'type': 'current_entry', 'id': 'entry#s1'}
            ],
          },
        ],
        'relationship_updates': [
          {
            'person': 100,
            'summary': false,
            'relationship': ['bad'],
            'emotion': '平静',
          },
        ],
        'contradictions': [
          {
            'old_memory_id': 55,
            'new_evidence': true,
            'interpretation': 9,
          },
        ],
      });

      expect(insight.entryId, '42');
      expect(insight.reflection, '123');
      expect(insight.emotion, 'true');
      expect(insight.keywords, ['散步', '7']);
      expect(insight.people, isEmpty);
      expect(insight.stoneTitle, '88');
      expect(insight.memorySummary, '[bad]');
      expect(insight.memoryTags, ['恢复', '3']);
      expect(insight.relatedMemories.single.title, '2025');
      expect(insight.relatedMemories.single.entryId, 'memory-walk');
      expect(insight.facts.single.text, '12');
      expect(insight.facts.single.confidence, 0.7);
      expect(insight.facts.single.evidence.single.id, '99');
      expect(insight.facts.single.evidence.single.quote, isNull);
      expect(insight.profileUpdateCandidates.single.field, '7');
      expect(insight.profileUpdateCandidates.single.value, 'true');
      expect(insight.profileUpdateCandidates.single.action, 'candidate');
      expect(insight.relationshipUpdates.single.personName, '100');
      expect(insight.relationshipUpdates.single.summary, 'false');
      expect(insight.relationshipUpdates.single.relationship, isNull);
      expect(insight.contradictions.single.oldMemoryId, '55');
      expect(insight.contradictions.single.newEvidence, 'true');
      expect(insight.contradictions.single.interpretation, '9');
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
        summaryId: 'entry',
        segmentIds: const ['entry#s1', 'entry#s2'],
        embeddingIds: const [
          'entry:entry',
          'summary:entry',
          'segment:entry#s1',
          'segment:entry#s2',
        ],
        insightId: 'entry',
        retrievalTraceId: 'entry',
        batchId: 'batch:1',
        batchLabel: '导入 2026',
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
        'id': 42,
        'entryId': 43,
        'pipelineVersion': '7',
        'state': <String>['pending'],
        'currentStage': 12,
        'createdAt': <String>['bad'],
        'updatedAt': null,
        'completedStages': 'queued',
        'stageLogs': [
          'bad',
          {12: 'ignored'},
          {
            'stage': 'embedding',
            'startedAt': date.toIso8601String(),
            'message': 99,
            'retryCount': '3',
          },
        ],
        'summaryId': 44,
        'segmentIds': ['42#s1', 12, null],
        'embeddingIds': ['entry:42', 13],
        'insightId': ['bad'],
        'retrievalTraceId': '42',
        'retryCount': '2',
        'lastError': <String>['bad'],
      });

      expect(restored.stageLogs.single.stage, AiAnalysisStage.embedding);
      expect(restored.stageLogs.single.outputSummary, 'completed=segmenting');
      expect(restored.summaryId, 'entry');
      expect(restored.segmentIds, ['entry#s1', 'entry#s2']);
      expect(restored.embeddingIds, [
        'entry:entry',
        'summary:entry',
        'segment:entry#s1',
        'segment:entry#s2',
      ]);
      expect(restored.insightId, 'entry');
      expect(restored.retrievalTraceId, 'entry');
      expect(restored.batchId, 'batch:1');
      expect(restored.batchLabel, '导入 2026');
      expect(legacy.stageLogs, isEmpty);
      expect(legacy.summaryId, isNull);
      expect(legacy.segmentIds, isEmpty);
      expect(legacy.embeddingIds, isEmpty);
      expect(legacy.batchId, isNull);
      expect(malformed.id, '42');
      expect(malformed.entryId, '43');
      expect(malformed.pipelineVersion, 7);
      expect(malformed.state, AiAnalysisJobState.pending);
      expect(malformed.currentStage, AiAnalysisStage.queued);
      expect(malformed.completedStages, isEmpty);
      expect(malformed.stageLogs, hasLength(2));
      expect(malformed.stageLogs.first.stage, AiAnalysisStage.queued);
      expect(malformed.stageLogs.last.stage, AiAnalysisStage.embedding);
      expect(malformed.stageLogs.last.message, '99');
      expect(malformed.stageLogs.last.retryCount, 3);
      expect(malformed.summaryId, isNull);
      expect(malformed.segmentIds, ['42#s1']);
      expect(malformed.embeddingIds, ['entry:42']);
      expect(malformed.insightId, isNull);
      expect(malformed.retrievalTraceId, '42');
      expect(malformed.retryCount, 2);
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
        batchId: 'batch:1',
        batchLabel: '批量补建',
      );
      final pending = AiAnalysisJob(
        id: 'pending',
        entryId: 'pending',
        pipelineVersion: 1,
        state: AiAnalysisJobState.pending,
        currentStage: AiAnalysisStage.queued,
        createdAt: date,
        updatedAt: date,
        batchId: 'batch:1',
        batchLabel: '批量补建',
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
      expect(snapshot.remainingStageCount, 21);
      expect(snapshot.estimatedRemainingLabel, '约 2 分钟');
      expect(snapshot.estimateSampleCount, 0);
      expect(snapshot.averageStageDurationLabel, '约 8 秒');
      expect(snapshot.batches, hasLength(1));
      expect(snapshot.batches.single.label, '批量补建');
      expect(snapshot.batches.single.progressLabel, '0/2');
      expect(snapshot.batches.single.runnableCount, 1);
    });

    test('snapshot estimates remaining time from completed stage logs', () {
      final date = DateTime(2026, 7, 3);
      final pending = AiAnalysisJob(
        id: 'pending',
        entryId: 'pending',
        pipelineVersion: 1,
        state: AiAnalysisJobState.pending,
        currentStage: AiAnalysisStage.queued,
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
        updatedAt: date.add(const Duration(seconds: 6)),
        stageLogs: [
          AiAnalysisStageLog(
            stage: AiAnalysisStage.preparing,
            startedAt: date,
            message: '准备',
          ),
          AiAnalysisStageLog(
            stage: AiAnalysisStage.generatingSummary,
            startedAt: date.add(const Duration(seconds: 2)),
            message: '摘要',
          ),
          AiAnalysisStageLog(
            stage: AiAnalysisStage.embedding,
            startedAt: date.add(const Duration(seconds: 4)),
            message: '向量',
          ),
        ],
      );
      final snapshot = AiAnalysisQueueSnapshot(jobs: [pending, completed]);

      expect(snapshot.remainingStageCount, 7);
      expect(snapshot.estimateSampleCount, 3);
      expect(snapshot.averageStageDurationLabel, '约 2 秒');
      expect(snapshot.estimatedRemainingLabel, '约 14 秒');
      expect(snapshot.stageCalibrations, hasLength(3));
      expect(
        snapshot.stageCalibrations.map((item) => item.stage),
        containsAll([
          AiAnalysisStage.preparing,
          AiAnalysisStage.generatingSummary,
          AiAnalysisStage.embedding,
        ]),
      );
      expect(
        snapshot.stageCalibrations.map((item) => item.durationLabel),
        everyElement('约 2 秒'),
      );
      expect(
        snapshot.stageCalibrationSummary,
        contains('embedding=约 2 秒(1)'),
      );
    });

    test('paused queue keeps jobs visible but does not return runnable work',
        () async {
      SharedPreferences.setMockInitialValues({});
      const repository = AiAnalysisQueueRepository();
      final entry = _entry(
        id: 'paused-queue-entry',
        content: '暂停时仍然保留在队列里。',
      );

      await repository.enqueueEntry(entry);
      await repository.setPaused(true);

      final snapshot = await repository.snapshot();
      final runnable = await repository.nextRunnableJob();

      expect(snapshot.isPaused, isTrue);
      expect(snapshot.hasVisibleWork, isTrue);
      expect(snapshot.currentJob, isNull);
      expect(snapshot.runnableCount, 1);
      expect(runnable, isNull);

      await repository.setPaused(false);
      expect((await repository.nextRunnableJob())?.id, entry.id);
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

    test('runner syncs interrupted queue jobs to diary analysis status',
        () async {
      SharedPreferences.setMockInitialValues({});
      const queueRepository = AiAnalysisQueueRepository();
      const insightRepository = InsightRepository();
      final old = DateTime.now().subtract(const Duration(minutes: 11));
      final job = AiAnalysisJob(
        id: 'interrupted-status',
        entryId: 'interrupted-status',
        pipelineVersion: 1,
        state: AiAnalysisJobState.running,
        currentStage: AiAnalysisStage.generatingInsight,
        createdAt: old,
        updatedAt: old,
      );
      await queueRepository.saveJob(job);
      await insightRepository.saveStatus(DiaryAnalysisStatus(
        entryId: job.entryId,
        state: DiaryAnalysisState.analyzing,
        updatedAt: old,
        message: '生成今日洞察',
      ));

      await const AiAnalysisQueueRunner().processUntilIdle(maxJobs: 0);

      final repairedJob = await queueRepository.getJob(job.id);
      final status = await insightRepository.getStatus(job.entryId);

      expect(repairedJob?.state, AiAnalysisJobState.incomplete);
      expect(status?.state, DiaryAnalysisState.incomplete);
      expect(status?.message, '上次整理被系统中断，下次将继续');
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
      expect(job?.completedStages, contains(AiAnalysisStage.updatingMemory));
      expect(job?.stageLogs.map((log) => log.stage),
          contains(AiAnalysisStage.embedding));
      expect(job?.stageLogs.map((log) => log.stage),
          contains(AiAnalysisStage.updatingMemory));
      expect(job?.stageLogs.map((log) => log.message), contains('更新长期记忆和候选资料'));
      expect(job?.stageLogs.map((log) => log.message), contains('整理完成'));
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('segments=2'));
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('embeddings=4'));
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('facts=1'));
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('profileCandidates=1'));
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('memoryUpdate=0'));
      expect(job?.stageLogs.map((log) => log.inputSummary).join('\n'),
          contains('summary='));
      expect(job?.summaryId, entry.id);
      expect(job?.segmentIds, segments.map((segment) => segment.id).toList());
      expect(job?.embeddingIds, [
        'entry:${entry.id}',
        'summary:${entry.id}',
        for (final segment in segments) 'segment:${segment.id}',
      ]);
      expect(job?.insightId, entry.id);
      expect(job?.retrievalTraceId, entry.id);
      expect(entryEmbedding?.generatedAt, oldGeneratedAt);
    });

    test('runner completes new diary pipeline with real analysis artifacts',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const queueRunner = AiAnalysisQueueRunner();
      const queueRepository = AiAnalysisQueueRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const insightRepository = InsightRepository();
      const retrievalRepository = AiRetrievalTraceRepository();
      const promptRepository = AiPromptTraceRepository();
      const memoryRepository = MemoryRepository();
      final entry = _entry(
        id: 'mvp-pipeline-entry',
        date: DateTime(2026, 7, 3),
        content: '今天上午做产品设计。\n\n---\n\n晚上散步以后状态轻松了一些。',
      );
      await diaryRepository.saveEntry(entry);
      await queueRunner.enqueue(entry, start: false);

      await AiAnalysisQueueRunner(
        analysisService: DiaryAnalysisService(
          client: _PipelineAiClientService(entry.id),
        ),
      ).processNext();

      final job = await queueRepository.getJob(entry.id);
      final status = await insightRepository.getStatus(entry.id);
      final summary = await summaryRepository.getSummary(entry.id);
      final segments = await summaryRepository.listSegments(entry.id);
      final embeddings = await embeddingRepository.listForEntry(entry.id);
      final insight = await insightRepository.getInsight(entry.id);
      final trace = await retrievalRepository.getTrace(entry.id);
      final promptTrace = await promptRepository.getTrace(entry.id);
      final memories = await memoryRepository.listMemories();
      final memory = memories.where((item) => item.id == entry.id).single;

      expect(job?.state, AiAnalysisJobState.completed);
      expect(job?.currentStage, AiAnalysisStage.completed);
      expect(
          job?.completedStages,
          containsAll(AiAnalysisStage.values
              .where((stage) => stage != AiAnalysisStage.queued)
              .where((stage) => stage != AiAnalysisStage.completed)));
      expect(job?.summaryId, entry.id);
      expect(job?.segmentIds, segments.map((segment) => segment.id).toList());
      expect(job?.embeddingIds, [
        'entry:${entry.id}',
        'summary:${entry.id}',
        for (final segment in segments) 'segment:${segment.id}',
      ]);
      expect(job?.insightId, entry.id);
      expect(job?.retrievalTraceId, entry.id);
      expect(status?.state, DiaryAnalysisState.completed);
      expect(status?.message, '整理完成');
      expect(summary?.brief, contains('产品设计'));
      expect(segments, hasLength(2));
      expect(embeddings, hasLength(5));
      expect(
        embeddings.map((embedding) => embedding.sourceType),
        containsAll([
          AiEmbeddingSourceType.entry,
          AiEmbeddingSourceType.summary,
          AiEmbeddingSourceType.segment,
          AiEmbeddingSourceType.memory,
        ]),
      );
      expect(trace?.scenario, AiContextScenario.todayInsight.name);
      expect(trace?.contextSummary, contains('sources='));
      expect(promptTrace?.userPrompt, contains('今天日记'));
      expect(promptTrace?.rawResponse, contains('散步后状态更轻松'));
      expect(insight?.reflection, '散步后状态更轻松。');
      expect(insight?.emotion, '轻松');
      expect(insight?.keywords, contains('散步'));
      expect(insight?.facts.single.evidence.single.id, entry.id);
      expect(insight?.suggestions.single.text, contains('散步 10 分钟'));
      expect(insight?.stoneTitle, '散步 10 分钟');
      expect(insight?.memorySummary, '散步后状态更轻松。');
      expect(memory.sourceEntryId, entry.id);
      expect(memory.summary, '散步后状态更轻松。');
    });

    test(
        'runner keeps local artifacts recoverable when insight generation fails',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const insightRepository = InsightRepository();
      final entry = _entry(
        id: 'recoverable-stage-error',
        date: DateTime(2026, 7, 3),
        content: '今天先记录工作压力。\n\n---\n\n晚上散步后恢复了一点。',
      );
      await diaryRepository.saveEntry(entry);
      await queueRepository.enqueueEntry(entry);

      await AiAnalysisQueueRunner(
        analysisService: const _ThrowingDiaryAnalysisService(),
      ).processNext();

      final job = await queueRepository.getJob(entry.id);
      final status = await insightRepository.getStatus(entry.id);
      final summary = await summaryRepository.getSummary(entry.id);
      final segments = await summaryRepository.listSegments(entry.id);
      final embeddings = await embeddingRepository.listForEntry(entry.id);

      expect(job?.state, AiAnalysisJobState.incomplete);
      expect(job?.currentStage, AiAnalysisStage.generatingInsight);
      expect(job?.retryCount, 1);
      expect(job?.lastError, contains('simulated insight failure'));
      expect(job?.completedStages, contains(AiAnalysisStage.embedding));
      expect(job?.summaryId, entry.id);
      expect(job?.segmentIds, segments.map((segment) => segment.id).toList());
      expect(job?.embeddingIds, [
        'entry:${entry.id}',
        'summary:${entry.id}',
        for (final segment in segments) 'segment:${segment.id}',
      ]);
      expect(job?.stageLogs.last.message, '阶段被中断，等待继续');
      expect(job?.stageLogs.last.outputSummary, contains('summaryId='));
      expect(status?.state, DiaryAnalysisState.incomplete);
      expect(status?.message, contains('已保留本地资料'));
      expect(summary?.brief, contains('工作压力'));
      expect(segments, hasLength(2));
      expect(embeddings, hasLength(4));
    });

    test('runner continues with structured summaries when embeddings fail',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const insightRepository = InsightRepository();
      final entry = _entry(
        id: 'embedding-fallback-entry',
        date: DateTime(2026, 7, 3),
        content: '今天工作压力很大。\n\n---\n\n晚上散步后恢复了一些。',
      );
      await diaryRepository.saveEntry(entry);
      await queueRepository.enqueueEntry(entry);

      await AiAnalysisQueueRunner(
        analysisService: const _FakeDiaryAnalysisService(),
        embeddingService: const _ThrowingEmbeddingService(),
      ).processNext();

      final job = await queueRepository.getJob(entry.id);
      final status = await insightRepository.getStatus(entry.id);
      final summary = await summaryRepository.getSummary(entry.id);
      final segments = await summaryRepository.listSegments(entry.id);
      final embeddings = await embeddingRepository.listForEntry(entry.id);
      final insight = await insightRepository.getInsight(entry.id);

      expect(job?.state, AiAnalysisJobState.completed);
      expect(job?.completedStages, contains(AiAnalysisStage.embedding));
      expect(job?.embeddingIds, isEmpty);
      expect(
          job?.stageLogs.map((log) => log.message), contains('向量生成失败，保留结构化摘要'));
      expect(job?.stageLogs.map((log) => log.outputSummary).join('\n'),
          contains('embeddingSkipped=true'));
      expect(status?.state, DiaryAnalysisState.completed);
      expect(summary?.brief, contains('工作压力'));
      expect(segments, hasLength(2));
      expect(embeddings, isEmpty);
      expect(insight?.reflection, '本地测试洞察');
    });

    test('runner uses body preview fallback when summary generation fails',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const queueRepository = AiAnalysisQueueRepository();
      final entry = _entry(
        id: 'summary-fallback-entry',
        date: DateTime(2026, 7, 3),
        content: '今天记录了一次重要对话，后来又去散步恢复状态。',
      );
      await diaryRepository.saveEntry(entry);
      await queueRepository.enqueueEntry(entry);

      await AiAnalysisQueueRunner(
        analysisService: const _FakeDiaryAnalysisService(),
        summaryService: const _ThrowingSummaryService(),
      ).processNext();

      final job = await queueRepository.getJob(entry.id);
      final summary = await summaryRepository.getSummary(entry.id);
      final segments = await summaryRepository.listSegments(entry.id);
      final embeddings = await embeddingRepository.listForEntry(entry.id);

      expect(job?.state, AiAnalysisJobState.completed);
      expect(job?.stageLogs.map((log) => log.message),
          contains('日记片段拆分失败，使用全文片段'));
      expect(
          job?.stageLogs.map((log) => log.message), contains('摘要生成失败，使用正文预览'));
      expect(summary?.generator, 'fallback-local-v1');
      expect(summary?.brief, contains('重要对话'));
      expect(segments.single.boundary, DiarySegmentBoundary.wholeEntry);
      expect(embeddings, hasLength(3));
      expect(job?.embeddingIds, [
        'entry:${entry.id}',
        'summary:${entry.id}',
        'segment:${entry.id}#s1',
      ]);
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
      final backfillJob = jobs.where((job) => job.id == 'missing-ai').single;
      expect(backfillJob.state, AiAnalysisJobState.pending);
      expect(backfillJob.batchId, startsWith('backfill:'));
      expect(backfillJob.batchLabel, startsWith('补建缺失资料 '));
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

    test('manual analysis rerun replaces stale insight output', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const insightRepository = InsightRepository();
      const queueRepository = AiAnalysisQueueRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'manual-rerun-entry',
        date: date,
        content: '今天重新分析这篇日记。',
      );
      await diaryRepository.saveEntry(entry);
      await insightRepository.saveInsight(DiaryInsight(
        entryId: entry.id,
        entryDate: date,
        generatedAt: date,
        reflection: '旧洞察',
        relatedMemories: const [],
        emotion: '',
        keywords: const [],
        people: const [],
        stoneTitle: '',
        stoneDescription: '',
        memorySummary: '',
        memoryTags: const [],
      ));
      await queueRepository.enqueueEntry(entry);

      await AiAnalysisQueueRunner(
        analysisService: const _FakeDiaryAnalysisService(),
      ).processNext();

      final insight = await insightRepository.getInsight(entry.id);
      final job = await queueRepository.getJob(entry.id);

      expect(insight?.reflection, '本地测试洞察');
      expect(job?.state, AiAnalysisJobState.completed);
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

    test('runner fails retryable AI errors after preserving local artifacts',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const queueRepository = AiAnalysisQueueRepository();
      const insightRepository = InsightRepository();
      final entry = _entry(
        id: 'retryable-ai-error',
        date: DateTime(2026, 7, 3),
        content: '今天写了一篇会遇到模型请求错误的日记。',
      );
      await diaryRepository.saveEntry(entry);
      await queueRepository.enqueueEntry(entry);
      final runner = AiAnalysisQueueRunner(
        analysisService: const _RetryableAiErrorAnalysisService(),
      );

      await runner.processNext();
      await runner.processNext();
      await runner.processNext();

      final job = await queueRepository.getJob(entry.id);
      final status = await insightRepository.getStatus(entry.id);

      expect(job?.state, AiAnalysisJobState.failed);
      expect(job?.retryCount, 3);
      expect(job?.currentStage, AiAnalysisStage.generatingInsight);
      expect(job?.lastError, contains('AI 请求失败'));
      expect(job?.summaryId, entry.id);
      expect(job?.segmentIds, isNotEmpty);
      expect(job?.stageLogs.last.message, '阶段失败');
      expect(status?.state, DiaryAnalysisState.failed);
      expect(status?.message, contains('AI 请求失败'));
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

    test('keeps malformed calendar memory fields with safe defaults', () async {
      SharedPreferences.setMockInitialValues({
        'calendar.memories.index': <String>['legacy'],
        'calendar.memories.legacy': jsonEncode({
          'id': 42,
          'title': 99,
          'month': '13',
          'day': '32',
          'createdAt': <String>['bad'],
          'updatedAt': null,
          'type': <String>['bad'],
          'note': 88,
          'enabled': 'yes',
        }),
      });
      const repository = CalendarMemoryRepository();

      final memory = (await repository.listMemories()).single;

      expect(memory.id, '42');
      expect(memory.title, '99');
      expect(memory.month, 12);
      expect(memory.day, 31);
      expect(memory.type, CalendarMemoryType.solar);
      expect(memory.note, '88');
      expect(memory.enabled, isTrue);
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

    test('builds conflict notes from insight contradictions', () {
      final insights = [
        _insight(
          entryId: 'older-change',
          date: DateTime(2026, 7, 1),
          contradictions: const [
            InsightContradiction(
              oldMemoryId: 'memory:stress',
              newEvidence: '今天面对汇报时没有明显紧张。',
              interpretation: '旧压力画像可能需要增加场景条件。',
              confidence: 0.58,
              evidence: [
                InsightEvidence(type: 'current_entry', id: 'older-change'),
              ],
            ),
          ],
        ),
        _insight(
          entryId: 'strong-change',
          date: DateTime(2026, 7, 3),
          contradictions: const [
            InsightContradiction(
              oldMemoryId: 'profile:self_regulation',
              newEvidence: '这次独处比运动更能恢复状态。',
              interpretation: '调节方式画像需要保留情境差异。',
              confidence: 0.72,
            ),
          ],
        ),
      ];

      final conflicts =
          const ProfileProjectionService().buildConflictNotes(insights);

      expect(conflicts, hasLength(2));
      expect(conflicts.first.targetId, 'profile:self_regulation');
      expect(conflicts.first.entryId, 'strong-change');
      expect(conflicts.first.confidence, 0.72);
      expect(conflicts.last.evidence.single.id, 'older-change');
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

    test('keeps malformed profile preferences with safe defaults', () async {
      SharedPreferences.setMockInitialValues({
        'ai.profilePreferences.index': <String>['profileFact:42'],
        'ai.profilePreferences.profileFact:42': jsonEncode({
          'targetType': ['relationship'],
          'targetId': 42,
          'updatedAt': <String>['bad'],
          'confirmed': 'true',
          'hidden': 'false',
          'correctedValue': 99,
        }),
      });
      const repository = AiProfilePreferenceRepository();

      final preferences = await repository.listPreferences();
      final preference = preferences.single;
      final prefs = await SharedPreferences.getInstance();

      expect(preference.targetType, AiProfilePreferenceTargetType.profileFact);
      expect(preference.targetId, '42');
      expect(preference.confirmed, isTrue);
      expect(preference.hidden, isFalse);
      expect(preference.correctedValue, '99');
      expect(
          prefs.getString('ai.profilePreferences.profileFact:42'), isNotNull);
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

    test('deletes individual profile preferences and repairs index', () async {
      SharedPreferences.setMockInitialValues({});
      const preferenceRepository = AiProfilePreferenceRepository();
      await preferenceRepository.setCorrectedValue(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: 'self_regulation:walk',
        correctedValue: '散步有助于恢复',
      );

      await preferenceRepository.deletePreference(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: 'self_regulation:walk',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        await preferenceRepository.getPreference(
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: 'self_regulation:walk',
        ),
        isNull,
      );
      expect(prefs.getStringList('ai.profilePreferences.index'), isEmpty);
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

    test('merges relationship profiles by user preference', () async {
      SharedPreferences.setMockInitialValues({});
      const projectionService = ProfileProjectionService();
      const preferenceRepository = AiProfilePreferenceRepository();
      final first = _insight(
        entryId: 'relationship-merge-first',
        date: DateTime(2026, 7, 3),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '小李',
          relationship: '同事',
          summary: '一起讨论项目推进',
          emotion: '平和',
          confidence: 0.62,
        ),
      );
      final second = _insight(
        entryId: 'relationship-merge-second',
        date: DateTime(2026, 7, 4),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '李同学',
          relationship: '同事',
          summary: '继续沟通方案',
          emotion: '专注',
          confidence: 0.58,
        ),
      );
      final profiles =
          projectionService.buildRelationshipProfiles([first, second]);

      await preferenceRepository.setMergedRelationship(
        sourcePersonName: '李同学',
        targetPersonName: '小李',
      );
      final visible =
          await preferenceRepository.applyToRelationshipProfiles(profiles);
      final history = await preferenceRepository.listRelationshipMergeHistory();

      expect(visible, hasLength(1));
      expect(visible.single.personName, '小李');
      expect(visible.single.names, containsAll(['小李', '李同学']));
      expect(visible.single.interactionCount, 2);
      expect(visible.single.emotions, containsAll(['平和', '专注']));
      expect(history, hasLength(1));
      expect(history.single.sourcePersonName, '李同学');
      expect(history.single.targetPersonName, '小李');
      expect(history.single.action, AiRelationshipMergeEventAction.merge);
    });

    test('records relationship merge undo history', () async {
      SharedPreferences.setMockInitialValues({});
      const preferenceRepository = AiProfilePreferenceRepository();

      await preferenceRepository.setMergedRelationship(
        sourcePersonName: '李同学',
        targetPersonName: '小李',
      );
      await preferenceRepository.recordRelationshipMergeUndo(
        sourcePersonName: '李同学',
        targetPersonName: '小李',
      );

      final history = await preferenceRepository.listRelationshipMergeHistory();

      expect(history, hasLength(2));
      expect(history.first.action, AiRelationshipMergeEventAction.undo);
      expect(history.last.action, AiRelationshipMergeEventAction.merge);
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
            'source_id': 'walk-entry',
            'title': '晚间运动',
            'reason': '裸 ID 也指向检索到的日记摘要',
            'score': 6,
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
            rerankSignals: const {'topic': 2, 'keyword': 2},
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
            rerankSignals: {'keyword': 2},
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
      expect(client.lastUserPrompt, contains('signals:topic:2.00'));
      expect(client.lastUserPrompt, contains('signals:keyword:2.00'));
      expect(client.lastUserPrompt, contains('相关搜索命中'));
      expect(client.lastUserPrompt, isNot(contains('相关日记和片段：')));
      expect(answer.sources, hasLength(2));
      expect(answer.sources.map((source) => source.sourceType),
          ['memory', 'entry_summary']);
      expect(answer.sources.map((source) => source.sourceId),
          ['walk-memory', 'walk-entry']);
      expect(answer.sources.map((source) => source.title), ['运动', '晚间运动']);
      expect(trace?.contextSummary, contains('sourceFiltered=1'));
      expect(trace?.rawResponse, contains('hallucinated'));
      expect(trace?.rawResponsePreview, contains('hallucinated'));
    });

    test('question prompt respects hidden and corrected profile preferences',
        () async {
      SharedPreferences.setMockInitialValues({});
      const insightRepository = InsightRepository();
      const preferenceRepository = AiProfilePreferenceRepository();
      const projectionService = ProfileProjectionService();
      final date = DateTime(2026, 7, 3);
      final visibleInsight = _insight(
        entryId: 'companion-visible-profile',
        date: date,
        profileCandidate: const ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步后压力下降',
          confidence: 0.7,
        ),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '妈妈',
          relationship: 'family',
          summary: '晚饭后沟通更平和',
          emotion: '平和',
          confidence: 0.66,
        ),
      );
      final hiddenInsight = _insight(
        entryId: 'companion-hidden-profile',
        date: date.add(const Duration(days: 1)),
        profileCandidate: const ProfileUpdateCandidate(
          field: 'private_pattern',
          value: '隐藏的压力模式',
          confidence: 0.75,
        ),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '小王',
          relationship: 'coworker',
          summary: '隐藏的协作摩擦',
          emotion: '紧张',
          confidence: 0.72,
        ),
      );
      await insightRepository.saveInsight(visibleInsight);
      await insightRepository.saveInsight(hiddenInsight);
      final projection =
          projectionService.build([visibleInsight, hiddenInsight]);
      final visibleFact = projection.profileFacts
          .firstWhere((fact) => fact.field == 'self_regulation');
      final hiddenFact = projection.profileFacts
          .firstWhere((fact) => fact.field == 'private_pattern');

      await preferenceRepository.setCorrectedValue(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: visibleFact.id,
        correctedValue: '晚饭后散步更容易帮助我卸下压力',
      );
      await preferenceRepository.setHidden(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: hiddenFact.id,
        hidden: true,
      );
      await preferenceRepository.setHidden(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: '小王',
        hidden: true,
      );
      await preferenceRepository.setCorrectedValue(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: '妈妈',
        correctedValue: '家人',
      );

      final client = _CompanionAiClientService(jsonEncode({
        'answer': '散步和晚饭后沟通都是可见线索。',
        'follow_up': '',
        'sources': [],
      }));

      await CompanionAnswerService(client: client).answer('散步 压力 妈妈 协作摩擦');
      final prompt = client.lastUserPrompt ?? '';

      expect(prompt, contains('晚饭后散步更容易帮助我卸下压力'));
      expect(prompt, contains('source_id=profile:p1'));
      expect(prompt, contains('source_id=relationship:r1'));
      expect(prompt, contains('妈妈｜家人'));
      expect(prompt, isNot(contains('散步后压力下降')));
      expect(prompt, isNot(contains('隐藏的压力模式')));
      expect(prompt, isNot(contains('private_pattern')));
      expect(prompt, isNot(contains('小王')));
      expect(prompt, isNot(contains('隐藏的协作摩擦')));
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

    test('splits single paragraph by time markers', () {
      final entry = _entry(
        content: '早上开会有点累，中午吃了火锅有点撑，晚上去健身后状态恢复，睡前简单整理了明天计划。',
      );

      final segments = const EntrySummaryService().buildSegments(entry);

      expect(segments, hasLength(4));
      expect(segments.map((segment) => segment.boundary).toSet(),
          {DiarySegmentBoundary.timeMarker});
      expect(segments[0].text, startsWith('早上'));
      expect(segments[1].text, startsWith('中午'));
      expect(segments[2].text, startsWith('晚上'));
      expect(segments[3].text, startsWith('睡前'));
    });

    test('splits implicit multi-event paragraphs by semantic shifts', () {
      final entry = _entry(
        id: 'semantic-split',
        content:
            '今天工作上一直在改需求，会议结束后还是有点焦虑。午饭吃了火锅，味道不错但有点撑。健身时练了腿，最后拉伸以后身体轻松了一些。回家后简单整理了明天计划。',
      );

      final segments = const EntrySummaryService().buildSegments(entry);

      expect(segments, hasLength(4));
      expect(segments.map((segment) => segment.boundary).toSet(),
          {DiarySegmentBoundary.semanticShift});
      expect(segments[0].text, contains('工作'));
      expect(segments[1].text, contains('火锅'));
      expect(segments[2].text, contains('健身'));
      expect(segments[3].text, contains('计划'));
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
      expect(summary.qualityScore, greaterThan(0.5));
      expect(summary.revision, 1);
      expect(summary.correctedAt, isNull);
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
      expect(summary.qualityScore, 0);
      expect(summary.qualityWarnings, isEmpty);
      expect(summary.revision, 1);
      expect(summary.correctedAt, isNull);
    });

    test('reads malformed summary metadata with safe defaults', () {
      final updatedAt = DateTime(2026, 7, 3);

      final summary = EntrySummary.fromJson({
        'entryId': <String>['bad'],
        'entryUpdatedAt': updatedAt.toIso8601String(),
        'generatedAt': <String>['bad'],
        'brief': <String>['bad'],
        'keyPoints': 'bad',
        'importance': <String>['bad'],
        'generator': <String>['bad'],
        'qualityScore': <String>['bad'],
        'qualityWarnings': 'bad',
        'revision': <String>['bad'],
        'correctedAt': <String>['bad'],
      });

      expect(summary.entryId, isEmpty);
      expect(summary.generatedAt, isNot(updatedAt));
      expect(summary.brief, isEmpty);
      expect(summary.keyPoints, isEmpty);
      expect(summary.importance, 0.5);
      expect(summary.generator, 'unknown');
      expect(summary.qualityScore, 0);
      expect(summary.qualityWarnings, isEmpty);
      expect(summary.revision, 1);
      expect(summary.correctedAt, isNull);
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
      expect(updated?.qualityScore, greaterThan(0.5));
      expect(updated?.revision, summary.revision + 1);
      expect(updated?.correctedAt, isNotNull);
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
      final revisions = await summaryRepository.listSummaryRevisions(entry.id);
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
      expect(updated?.qualityScore, greaterThan(0.6));
      expect(updated?.revision, summary.revision + 2);
      expect(updated?.correctedAt, isNotNull);
      expect(revisions, hasLength(2));
      expect(revisions.first.revision, summary.revision + 2);
      expect(revisions.first.previousBrief, '散步后焦虑下降。');
      expect(revisions.first.updatedBrief, '散步后焦虑下降，并保留关键原文。');
      expect(secondEmbedding?.textHash, isNot(firstEmbedding?.textHash));
    });

    test('replacing segments removes stale segment embeddings', () async {
      SharedPreferences.setMockInitialValues({});
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const embeddingService = EmbeddingService();
      final entry = _entry(
        id: 'segment-replace-cleanup',
        date: DateTime(2026, 7, 3),
        content: '上午开会。\n\n---\n\n晚上散步。',
      );
      final oldSegments = const EntrySummaryService().buildSegments(entry);
      await summaryRepository.saveSegments(entry.id, oldSegments);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.segment,
        sourceId: oldSegments.first.id,
        text: _segmentEmbeddingTextForTest(oldSegments.first),
        generatedAt: DateTime(2026, 7, 3),
      );
      final replacement = [
        DiarySegment(
          id: '${entry.id}#manual',
          entryId: entry.id,
          index: 0,
          text: '晚上散步后状态恢复。',
          summary: '散步恢复状态。',
          topics: const ['运动'],
          people: const [],
          boundary: DiarySegmentBoundary.paragraphGap,
          createdAt: DateTime(2026, 7, 4),
        ),
      ];

      await summaryRepository.saveSegments(entry.id, replacement);

      expect(
        await embeddingRepository.getBySource(
          sourceType: AiEmbeddingSourceType.segment,
          sourceId: oldSegments.first.id,
        ),
        isNull,
      );
      expect(
        (await embeddingRepository.listForEntry(entry.id))
            .where((item) => item.sourceType == AiEmbeddingSourceType.segment),
        isEmpty,
      );
      expect(
        (await summaryRepository.listSegments(entry.id)).map((item) => item.id),
        ['${entry.id}#manual'],
      );
    });

    test('deleting entry summary removes revision history', () async {
      SharedPreferences.setMockInitialValues({});
      const summaryRepository = EntrySummaryRepository();
      final entry = _entry(
        id: 'summary-revision-delete',
        date: DateTime(2026, 7, 3),
        content: '今天散步以后焦虑下降。',
      );
      final summary = _summaryForTest(
        entry: entry,
        brief: '旧摘要',
        importance: 0.5,
      );
      await summaryRepository.saveSummary(summary);
      await summaryRepository.correctBrief(
        entryId: entry.id,
        brief: '晚上散步后焦虑下降。',
      );

      expect(
          await summaryRepository.listSummaryRevisions(entry.id), hasLength(1));

      await summaryRepository.deleteForEntry(entry.id);

      expect(await summaryRepository.listSummaryRevisions(entry.id), isEmpty);
    });

    test('deleting entry summary removes summary and segment embeddings',
        () async {
      SharedPreferences.setMockInitialValues({});
      const summaryRepository = EntrySummaryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const embeddingService = EmbeddingService();
      final entry = _entry(
        id: 'summary-delete-embeddings',
        date: DateTime(2026, 7, 3),
        content: '上午开会。\n\n---\n\n晚上散步。',
      );
      final segments = const EntrySummaryService().buildSegments(entry);
      final summary = const EntrySummaryService().buildSummary(entry, segments);
      await summaryRepository.saveSummary(summary);
      await summaryRepository.saveSegments(entry.id, segments);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.summary,
        sourceId: entry.id,
        text: _summaryEmbeddingTextForTest(summary),
        generatedAt: DateTime(2026, 7, 3),
      );
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: entry.id,
        sourceType: AiEmbeddingSourceType.segment,
        sourceId: segments.first.id,
        text: _segmentEmbeddingTextForTest(segments.first),
        generatedAt: DateTime(2026, 7, 3),
      );

      await summaryRepository.deleteForEntry(entry.id);

      expect(await summaryRepository.getSummary(entry.id), isNull);
      expect(await summaryRepository.listSegments(entry.id), isEmpty);
      expect(
        await embeddingRepository.getBySource(
          sourceType: AiEmbeddingSourceType.summary,
          sourceId: entry.id,
        ),
        isNull,
      );
      expect(
        await embeddingRepository.getBySource(
          sourceType: AiEmbeddingSourceType.segment,
          sourceId: segments.first.id,
        ),
        isNull,
      );
      expect(
        (await embeddingRepository.listForEntry(entry.id)).where((item) =>
            item.sourceType == AiEmbeddingSourceType.summary ||
            item.sourceType == AiEmbeddingSourceType.segment),
        isEmpty,
      );
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

    test('repairs embedding entry and type indexes from stored objects',
        () async {
      final entry = _entry(
        id: 'embedding-repair-entry',
        date: DateTime(2026, 7, 3),
        content: '这篇日记有孤立向量。',
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
        'ai.embeddings.${embedding.id}': jsonEncode(embedding.toJson()),
        'ai.embeddings.entryIndex.${entry.id}': <String>['missing'],
        'ai.embeddings.entryIndex.empty-entry': <String>['missing'],
        'ai.embeddings.typeIndex.summary': <String>['missing'],
        'ai.embeddings.broken': '{broken',
      });
      const repository = AiEmbeddingRepository();

      final result = await repository.repairIndexes();
      final prefs = await SharedPreferences.getInstance();

      expect(result.objectCount, 2);
      expect(result.validObjectCount, 1);
      expect(result.invalidObjectCount, 1);
      expect(result.entryIndexCount, 1);
      expect(result.typeIndexCount, 1);
      expect(result.missingEntryReferences, 1);
      expect(result.missingTypeReferences, 1);
      expect(result.removedIndexReferences, 3);
      expect(prefs.getStringList('ai.embeddings.entryIndex.${entry.id}'),
          [embedding.id]);
      expect(prefs.getStringList('ai.embeddings.typeIndex.summary'),
          [embedding.id]);
      expect(
          prefs.containsKey('ai.embeddings.entryIndex.empty-entry'), isFalse);
      expect(prefs.containsKey('ai.embeddings.broken'), isFalse);
    });

    test('delete for entry removes orphaned embeddings without entry index',
        () async {
      final entry = _entry(
        id: 'embedding-delete-orphan-entry',
        date: DateTime(2026, 7, 3),
        content: '这篇日记删除时索引已经丢失。',
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
        'ai.embeddings.${embedding.id}': jsonEncode(embedding.toJson()),
        'ai.embeddings.typeIndex.summary': <String>[embedding.id],
      });

      await const AiEmbeddingRepository().deleteForEntry(entry.id);
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.containsKey('ai.embeddings.${embedding.id}'), isFalse);
      expect(prefs.getStringList('ai.embeddings.typeIndex.summary'), isEmpty);
      expect(
          await const AiEmbeddingRepository().listForEntry(entry.id), isEmpty);
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

    test('reads malformed embedding json with safe defaults', () async {
      SharedPreferences.setMockInitialValues({
        'ai.embeddings.typeIndex.memory': <String>['memory:bad-vector'],
        'ai.embeddings.entryIndex.entry-1': <String>['memory:bad-vector'],
        'ai.embeddings.memory:bad-vector': jsonEncode({
          'id': 'memory:bad-vector',
          'sourceType': 'memory',
          'sourceId': 'bad-vector',
          'entryId': 'entry-1',
          'modelId': null,
          'modelVersion': 3,
          'dimensions': '4',
          'vector': [0.1, '0.2', 'bad', null, 3],
          'generatedAt': <String>['bad'],
          'textHash': 99,
        }),
      });

      final embedding = await const AiEmbeddingRepository().getBySource(
        sourceType: AiEmbeddingSourceType.memory,
        sourceId: 'bad-vector',
      );
      final byType = await const AiEmbeddingRepository().listByType(
        AiEmbeddingSourceType.memory,
      );

      expect(embedding?.id, 'memory:bad-vector');
      expect(embedding?.sourceType, AiEmbeddingSourceType.memory);
      expect(embedding?.sourceId, 'bad-vector');
      expect(embedding?.entryId, 'entry-1');
      expect(embedding?.modelId, 'unknown');
      expect(embedding?.modelVersion, '3');
      expect(embedding?.dimensions, 4);
      expect(embedding?.vector, [0.1, 0.2, 3.0]);
      expect(embedding?.textHash, '99');
      expect(byType.single.id, 'memory:bad-vector');
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
      expect(matches.first.rerankSignals['semantic'], isNotNull);
      expect(matches.first.rerankSignals.keys, contains('keyword'));
    });

    test('falls back to keyword search when embeddings are unavailable',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      final entry = _entry(
        id: 'search-keyword-fallback',
        date: DateTime(2026, 7, 3),
        content: '晚上散步以后，焦虑明显下降。',
      );
      await diaryRepository.saveEntry(entry);
      await summaryRepository.saveSummary(_summaryForTest(
        entry: entry,
        brief: '晚上散步以后焦虑明显下降',
        importance: 0.5,
        topics: const ['散步'],
      ));

      final matches = await const AiSearchService(
        embeddingService: _ThrowingEmbeddingService(),
      ).search('散步 焦虑');

      expect(matches, isNotEmpty);
      expect(matches.first.entryId, entry.id);
      expect(matches.first.reasons.join(' '), contains('关键词重合'));
      expect(matches.first.reasons.join(' '), isNot(contains('向量相似度')));
      expect(matches.first.rerankSignals.keys, isNot(contains('semantic')));
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
      expect(matches.first.rerankSignals['people'], 3);
      expect(matches.first.rerankSignals['topic'], 2);
      expect(matches.first.rerankSignals['emotion'], 1);
    });

    test('returns long term memory matches from vectors and keywords',
        () async {
      SharedPreferences.setMockInitialValues({});
      const memoryRepository = MemoryRepository();
      const embeddingRepository = AiEmbeddingRepository();
      const embeddingService = EmbeddingService();
      final date = DateTime(2026, 7, 3);
      final memory = MemoryEntry(
        id: 'memory:walk-recovery',
        sourceEntryId: 'memory-source-entry',
        date: date,
        createdAt: date,
        summary: '压力大时散步能帮助用户恢复状态，焦虑会下降。',
        keywords: const ['散步', '焦虑', '恢复'],
        emotion: '放松',
        people: const [],
        tags: const ['自我调节'],
        importance: 0.82,
        confidence: 0.76,
      );
      await memoryRepository.saveMemory(memory);
      await _saveTestEmbedding(
        repository: embeddingRepository,
        service: embeddingService,
        entryId: memory.sourceEntryId,
        sourceType: AiEmbeddingSourceType.memory,
        sourceId: memory.id,
        text: memory.summary,
        generatedAt: date,
      );

      final matches = await const AiSearchService().search('散步后焦虑下降');
      final memoryMatch =
          matches.firstWhere((match) => match.sourceType == 'memory');

      expect(memoryMatch.sourceId, memory.id);
      expect(memoryMatch.entryId, memory.sourceEntryId);
      expect(memoryMatch.reasons.join(' '), contains('向量相似度'));
      expect(memoryMatch.reasons.join(' '), contains('记忆重要度'));
      expect(memoryMatch.reasons.join(' '), contains('记忆置信度'));
      expect(memoryMatch.rerankSignals['confidence'], 0.76);
    });

    test('uses memory lifecycle signals when ranking search matches', () async {
      SharedPreferences.setMockInitialValues({});
      const memoryRepository = MemoryRepository();
      final date = DateTime(2026, 7, 3);
      await memoryRepository.saveMemory(MemoryEntry(
        id: 'memory:lifecycle-low',
        sourceEntryId: 'low-memory-source',
        date: date,
        createdAt: date,
        summary: '散步后焦虑下降。',
        keywords: const ['散步', '焦虑'],
        emotion: '放松',
        people: const [],
        tags: const ['自我调节'],
        importance: 0.6,
        confidence: 0.56,
        decay: 0.8,
      ));
      await memoryRepository.saveMemory(MemoryEntry(
        id: 'memory:lifecycle-high',
        sourceEntryId: 'high-memory-source',
        date: date,
        createdAt: date,
        summary: '散步后焦虑下降。',
        keywords: const ['散步', '焦虑'],
        emotion: '放松',
        people: const [],
        tags: const ['自我调节'],
        importance: 0.6,
        confidence: 0.86,
        referenceCount: 3,
      ));

      final matches = await const AiSearchService().search('散步 焦虑');
      final memoryMatches =
          matches.where((match) => match.sourceType == 'memory').toList();

      expect(memoryMatches.first.sourceId, 'memory:lifecycle-high');
      expect(memoryMatches.first.reasons.join(' '), contains('历史引用 2'));
      expect(memoryMatches.first.rerankSignals['confidence'], 0.86);
      expect(memoryMatches.first.rerankSignals['reference'], 2);
      expect(
        memoryMatches
            .firstWhere((match) => match.sourceId == 'memory:lifecycle-low')
            .rerankSignals['decay'],
        -2,
      );
    });

    test('returns profile and relationship matches with traceable signals',
        () async {
      SharedPreferences.setMockInitialValues({});
      const insightRepository = InsightRepository();
      await insightRepository.saveInsight(_insight(
        entryId: 'profile-search-source',
        date: DateTime(2026, 7, 1),
        profileCandidate: const ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步可能帮助恢复状态',
          confidence: 0.64,
          evidence: [
            InsightEvidence(
              type: 'current_entry',
              id: 'profile-search-source#s1',
              summary: '散步帮助恢复',
            ),
          ],
        ),
      ));
      await insightRepository.saveInsight(_insight(
        entryId: 'relationship-search-source',
        date: DateTime(2026, 7, 2),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '妈妈',
          relationship: 'family',
          summary: '晚饭后沟通更平和',
          emotion: '平和',
          pattern: '晚间沟通更顺畅',
          confidence: 0.66,
          evidence: [
            InsightEvidence(
              type: 'current_entry',
              id: 'relationship-search-source#s1',
              summary: '晚间沟通',
            ),
          ],
        ),
      ));

      final matches = await const AiSearchService().search('妈妈 散步 恢复');
      final profile =
          matches.firstWhere((match) => match.sourceType == 'profile');
      final relationship =
          matches.firstWhere((match) => match.sourceType == 'relationship');
      final profileEmbedding = await const AiEmbeddingRepository().getBySource(
        sourceType: AiEmbeddingSourceType.profile,
        sourceId: profile.sourceId,
      );
      final relationshipEmbedding =
          await const AiEmbeddingRepository().getBySource(
        sourceType: AiEmbeddingSourceType.relationship,
        sourceId: relationship.sourceId,
      );

      expect(profile.sourceId, contains('self_regulation'));
      expect(profile.entryId, 'profile-search-source');
      expect(profile.reasons.join(' '), contains('画像匹配'));
      expect(profile.rerankSignals['confidence'], 0.64);
      expect(profile.rerankSignals['evidence'], 1);
      expect(profileEmbedding?.sourceType, AiEmbeddingSourceType.profile);
      expect(profileEmbedding?.entryId, 'profile-search-source');
      expect(relationship.sourceId, '妈妈');
      expect(relationship.entryId, 'relationship-search-source');
      expect(relationship.reasons.join(' '), contains('关系匹配'));
      expect(relationship.rerankSignals['confidence'], 0.66);
      expect(relationship.rerankSignals['evidence'], 1);
      expect(relationshipEmbedding?.sourceType,
          AiEmbeddingSourceType.relationship);
      expect(relationshipEmbedding?.entryId, 'relationship-search-source');
    });

    test('respects profile and relationship preferences in search', () async {
      SharedPreferences.setMockInitialValues({});
      const insightRepository = InsightRepository();
      const preferenceRepository = AiProfilePreferenceRepository();
      const embeddingRepository = AiEmbeddingRepository();
      await insightRepository.saveInsight(_insight(
        entryId: 'profile-preference-visible',
        date: DateTime(2026, 7, 1),
        profileCandidate: const ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步可能帮助恢复状态',
          confidence: 0.64,
        ),
      ));
      await insightRepository.saveInsight(_insight(
        entryId: 'profile-preference-hidden',
        date: DateTime(2026, 7, 2),
        profileCandidate: const ProfileUpdateCandidate(
          field: 'preference',
          value: '可能喜欢夜间写作',
          confidence: 0.65,
        ),
      ));
      await insightRepository.saveInsight(_insight(
        entryId: 'relationship-preference-hidden',
        date: DateTime(2026, 7, 3),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '小林',
          relationship: '同事',
          summary: '讨论产品方案',
          confidence: 0.66,
        ),
      ));
      final projection = const ProfileProjectionService().build(
        await insightRepository.listInsights(),
      );
      final visibleFact = projection.profileFacts
          .firstWhere((fact) => fact.field == 'self_regulation');
      final hiddenFact = projection.profileFacts
          .firstWhere((fact) => fact.field == 'preference');
      await const AiSearchService().search('夜间 小林');
      expect(
        await embeddingRepository.getBySource(
          sourceType: AiEmbeddingSourceType.profile,
          sourceId: hiddenFact.id,
        ),
        isNotNull,
      );
      expect(
        await embeddingRepository.getBySource(
          sourceType: AiEmbeddingSourceType.relationship,
          sourceId: '小林',
        ),
        isNotNull,
      );
      await preferenceRepository.setCorrectedValue(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: visibleFact.id,
        correctedValue: '晚饭后散步最能帮助恢复状态',
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

      final matches = await const AiSearchService().search('散步 夜间 小林');

      final profile =
          matches.firstWhere((match) => match.sourceType == 'profile');
      expect(profile.sourceId, visibleFact.id);
      expect(profile.summary, '晚饭后散步最能帮助恢复状态');
      expect(profile.rerankSignals['userConfirmed'], 1);
      expect(matches.map((match) => match.sourceId),
          isNot(contains(hiddenFact.id)));
      expect(matches.map((match) => match.sourceId), isNot(contains('小林')));
      expect(
        await embeddingRepository.getBySource(
          sourceType: AiEmbeddingSourceType.profile,
          sourceId: hiddenFact.id,
        ),
        isNull,
      );
      expect(
        await embeddingRepository.getBySource(
          sourceType: AiEmbeddingSourceType.relationship,
          sourceId: '小林',
        ),
        isNull,
      );
    });

    test('returns stone task matches from vectors and keywords', () async {
      SharedPreferences.setMockInitialValues({});
      const stoneRepository = StoneTaskRepository();
      const embeddingRepository = AiEmbeddingRepository();
      final date = DateTime(2026, 7, 3);
      await stoneRepository.saveTask(StoneTask(
        id: 'stone:walk-search',
        sourceEntryId: 'stone-source-entry',
        title: '晚饭后散步 10 分钟',
        description: '走一小圈即可，重点是恢复状态。',
        createdAt: date,
        updatedAt: date,
        tags: const ['散步', '恢复'],
        checkIns: [
          StoneTaskCheckIn(
            id: 'checkin:walk-search',
            createdAt: date,
            note: '完成了 8 分钟，感觉轻松一点。',
            sourceEntryId: 'stone-checkin-entry',
          ),
        ],
      ));

      final matches = await const AiSearchService().search('饭后散步 恢复');
      final stone = matches.firstWhere((match) => match.sourceType == 'stone');
      final embedding = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.stone,
        sourceId: stone.sourceId,
      );

      expect(stone.sourceId, 'stone:walk-search');
      expect(stone.entryId, 'stone-source-entry');
      expect(stone.summary, contains('最近进展'));
      expect(stone.reasons.join(' '), contains('关键词重合'));
      expect(embedding?.sourceType, AiEmbeddingSourceType.stone);
      expect(embedding?.entryId, 'stone-source-entry');

      await stoneRepository.deleteTask('stone:walk-search');
      await const AiSearchService().search('饭后散步 恢复');

      expect(
        await embeddingRepository.getBySource(
          sourceType: AiEmbeddingSourceType.stone,
          sourceId: 'stone:walk-search',
        ),
        isNull,
      );
    });

    test(
        'returns archived long term memories in explicit search with penalties',
        () async {
      SharedPreferences.setMockInitialValues({});
      final date = DateTime(2026, 7, 3);
      await const MemoryRepository().saveMemory(MemoryEntry(
        id: 'memory:archived-search',
        sourceEntryId: 'archived-source-entry',
        date: date,
        createdAt: date,
        summary: '散步后焦虑下降。',
        keywords: const ['散步', '焦虑'],
        emotion: '放松',
        people: const [],
        tags: const ['自我调节'],
        archived: true,
      ));

      final matches = await const AiSearchService().search('散步 焦虑');
      final archived = matches
          .firstWhere((match) => match.sourceId == 'memory:archived-search');

      expect(archived.sourceType, 'memory');
      expect(archived.reasons.join(' '), contains('已归档记忆'));
      expect(archived.rerankSignals['archived'], -1);
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

    test('period summary repository deletes summaries referencing an entry',
        () async {
      SharedPreferences.setMockInitialValues({});
      const repository = PeriodSummaryRepository();
      final date = DateTime(2026, 7, 3);
      await repository.saveSummary(PeriodSummary(
        id: 'month:2026-07',
        type: PeriodSummaryType.month,
        startDate: DateTime(2026, 7),
        endDate: DateTime(2026, 7, 31, 23, 59, 59),
        generatedAt: date,
        entryCount: 1,
        brief: '七月摘要',
        themes: const ['散步'],
        emotions: const [],
        representativeEntryIds: const ['deleted-entry'],
        generator: 'test',
      ));
      await repository.saveSummary(PeriodSummary(
        id: 'year:2026',
        type: PeriodSummaryType.year,
        startDate: DateTime(2026),
        endDate: DateTime(2026, 12, 31, 23, 59, 59),
        generatedAt: date,
        entryCount: 1,
        brief: '全年摘要',
        themes: const [],
        emotions: const [],
        representativeEntryIds: const [],
        generator: 'test',
        contextSourceLines: const [
          'period_entry:deleted-entry | 2026-07-03 | 散步',
        ],
      ));
      await repository.saveSummary(PeriodSummary(
        id: 'month:2026-08',
        type: PeriodSummaryType.month,
        startDate: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 31, 23, 59, 59),
        generatedAt: date,
        entryCount: 1,
        brief: '八月摘要',
        themes: const [],
        emotions: const [],
        representativeEntryIds: const ['kept-entry'],
        generator: 'test',
      ));

      await repository.deleteForEntry('deleted-entry');

      expect(await repository.getSummary('month:2026-07'), isNull);
      expect(await repository.getSummary('year:2026'), isNull);
      expect(await repository.getSummary('month:2026-08'), isNotNull);
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
      const memoryRepository = MemoryRepository();
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
      await memoryRepository.saveMemory(MemoryEntry(
        id: 'memory:period-source',
        sourceEntryId: 'old-period-source',
        date: DateTime(2026, 7, 1),
        createdAt: DateTime(2026, 7, 1),
        summary: '散步后焦虑下降，状态恢复。',
        keywords: const ['散步', '焦虑', '恢复'],
        emotion: '放松',
        people: const [],
        tags: const ['情绪调节'],
        importance: 0.82,
        confidence: 0.76,
      ));

      final summary = await const PeriodSummaryService()
          .buildMonthSummary(DateTime(2026, 7), [entry]);

      expect(summary.contextSourceLines.join('\n'), contains('period_entry'));
      expect(summary.contextSourceLines.join('\n'), contains('entry_summary'));
      expect(summary.contextSourceLines.join('\n'), contains(entry.id));
      expect(summary.contextSourceLines.join('\n'), contains('2026-07-03'));
      expect(
          summary.contextSourceLines.join('\n'), contains('brief=晚上散步以后焦虑下降'));
      expect(
          summary.contextSourceLines.join('\n'), contains('importance=0.82'));
      expect(summary.contextSourceLines.join('\n'),
          contains('memory:period-source'));
      expect(summary.contextSourceLines.join('\n'), contains('signals='));
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
      const preferenceRepository = AiProfilePreferenceRepository();
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
      await insightRepository.saveInsight(_insight(
        entryId: 'period-hidden-relationship',
        date: date.add(const Duration(days: 1)),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '小王',
          relationship: '同事',
          summary: '隐藏的协作摩擦',
          emotion: '紧张',
          pattern: '隐藏的互动模式',
          confidence: 0.7,
        ),
      ));
      await preferenceRepository.setHidden(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: '小王',
        hidden: true,
      );
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
      expect(summary.relationshipHighlights.join(' '), isNot(contains('小王')));
      expect(
          summary.relationshipHighlights.join(' '), isNot(contains('隐藏的协作摩擦')));
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
      expect(
        package.debugSummary,
        contains('budget=periodEntries:50/50,periodSummaries:48/50'),
      );
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
      final traceItem = package.retrievalTrace?.items
          .firstWhere((item) => item.sourceId == 'same-day');
      expect(traceItem?.rerankSignals['calendarScore'], 8);
      expect(traceItem?.rerankSignals['yearDistance'], 1);
      expect(traceItem?.rerankSignals['dayOffset'], 0);
      expect(traceItem?.rerankSignals['usedSummary'], 0);
      expect(traceItem?.rerankSignals['calendarType.solar'], 1);
    });

    test('uses entry summaries for calendar context when available', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const summaryRepository = EntrySummaryRepository();
      final current = _entry(
        id: 'calendar-summary-current',
        date: DateTime(2026, 7, 3),
        content: '今天重新考虑运动习惯。',
      );
      final past = _entry(
        id: 'calendar-summary-past',
        date: DateTime(2025, 7, 3),
        content: '这是一段很长的历史原文，不应该直接进入多年今日上下文。',
      );
      await diaryRepository.saveEntry(current);
      await diaryRepository.saveEntry(past);
      await summaryRepository.saveSummary(_summaryForTest(
        entry: past,
        brief: '去年同日记录了运动恢复状态。',
        importance: 0.8,
        topics: const ['运动', '恢复'],
      ));

      final package =
          await const AiContextBuilder().buildForTodayInsight(current);
      final match = package.calendarMatches.single;
      final traceItem = package.retrievalTrace!.items
          .singleWhere((item) => item.sourceId == past.id);

      expect(match.summary?.brief, '去年同日记录了运动恢复状态。');
      expect(match.contextSummary, contains('去年同日记录了运动恢复状态。'));
      expect(match.contextSummary, isNot(contains('很长的历史原文')));
      expect(traceItem.summary, contains('去年同日记录了运动恢复状态。'));
      expect(traceItem.summary, isNot(contains('很长的历史原文')));
      expect(traceItem.reasons, contains('使用历史摘要包'));
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

    test('labels fixed lunar festival matches', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      final current = _entry(
        id: 'dragon-boat-current',
        date: DateTime(2026, 6, 19),
        content: '今年端午在家吃粽子。',
      );
      final festivalPast = _entry(
        id: 'dragon-boat-past',
        date: DateTime(2025, 5, 31),
        content: '去年端午也写到家庭聚餐。',
      );
      final ordinary = _entry(
        id: 'dragon-boat-ordinary',
        date: DateTime(2025, 6, 19),
        content: '去年同公历日期是普通记录。',
      );
      for (final entry in [current, festivalPast, ordinary]) {
        await diaryRepository.saveEntry(entry);
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(current);
      final festival = package.calendarMatches.first;
      final traceItem = package.retrievalTrace?.items
          .firstWhere((item) => item.sourceId == festivalPast.id);

      expect(festival.entry.id, 'dragon-boat-past');
      expect(festival.label, '端午节');
      expect(festival.calendarType, 'lunar_festival');
      expect(festival.reason, contains('端午节'));
      expect(traceItem?.reasons, contains('农历节日：端午节'));
      expect(traceItem?.matchedTokens, contains('端午节'));
      expect(traceItem?.rerankSignals['calendarType.lunarFestival'], 1);
      expect(traceItem?.rerankSignals['calendarScore'], 10);
      expect(traceItem?.rerankSignals['yearDistance'], 1);
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

    test('uses custom lunar calendar memories for today matches', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const calendarRepository = CalendarMemoryRepository();
      final date = DateTime(2026, 6, 19);
      await calendarRepository.saveMemory(CalendarMemory(
        id: 'lunar-family-day',
        title: '农历家庭日',
        month: 5,
        day: 5,
        createdAt: date,
        updatedAt: date,
        type: CalendarMemoryType.lunar,
      ));
      final current = _entry(
        id: 'lunar-anniversary-current',
        date: date,
        content: '今天又想起家里的农历纪念日。',
      );
      final past = _entry(
        id: 'lunar-anniversary-past',
        date: DateTime(2025, 5, 31),
        content: '去年农历五月初五也写了家里的事。',
      );
      for (final entry in [current, past]) {
        await diaryRepository.saveEntry(entry);
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(current);
      final match = package.calendarMatches.first;

      expect(match.entry.id, past.id);
      expect(match.label, '农历家庭日');
      expect(match.calendarType, 'lunar');
      expect(match.score, 11);
      expect(match.reason, contains('农历家庭日'));
      expect(
          package.retrievalTrace?.items.first.reasons, contains('农历纪念日：农历家庭日'));
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
      expect(
        package.retrievalTrace?.items
            .firstWhere((item) => item.sourceType == 'profile')
            .rerankSignals['confidence'],
        closeTo(0.64, 0.02),
      );
      expect(
        package.retrievalTrace?.items
            .firstWhere((item) => item.sourceType == 'relationship')
            .rerankSignals['evidence'],
        1,
      );
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
      expect(package.debugSummary, contains('budget=searchMatches:'));
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

    test('question context deduplicates memory search matches', () async {
      SharedPreferences.setMockInitialValues({});
      const memoryRepository = MemoryRepository();
      const traceRepository = AiRetrievalTraceRepository();
      final date = DateTime(2026, 7, 3);
      final memory = MemoryEntry(
        id: 'memory:question-dedupe',
        sourceEntryId: 'memory-question-source',
        date: date,
        createdAt: date,
        summary: '散步后焦虑下降，状态更容易恢复。',
        keywords: const ['散步', '焦虑', '恢复'],
        emotion: '放松',
        people: const [],
        tags: const ['自我调节'],
        importance: 0.8,
        confidence: 0.76,
      );
      await memoryRepository.saveMemory(memory);

      final package = await const AiContextBuilder().buildForQuestion('散步 焦虑');
      final savedTrace = await traceRepository.getTrace('question:last');

      expect(package.searchMatches.map((match) => match.sourceType),
          contains('memory'));
      expect(package.searchMatches.map((match) => match.sourceId),
          contains(memory.id));
      expect(
        package.searchMatches
            .firstWhere((match) => match.sourceId == memory.id)
            .rerankSignals,
        isNotEmpty,
      );
      expect(package.relatedMemories.map((result) => result.memory.id),
          isNot(contains(memory.id)));
      expect(
        savedTrace?.items.where((item) => item.sourceId == memory.id).length,
        1,
      );
      expect(
        savedTrace?.items
            .firstWhere((item) => item.sourceId == memory.id)
            .rerankSignals,
        isNotEmpty,
      );
    });

    test('today context persists related memory rerank signals in trace',
        () async {
      SharedPreferences.setMockInitialValues({});
      const memoryRepository = MemoryRepository();
      const traceRepository = AiRetrievalTraceRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'today-memory-rerank-entry',
        date: date,
        content: '今天散步以后焦虑下降，身体放松。',
      );
      await memoryRepository.saveMemory(MemoryEntry(
        id: 'memory:today-rerank',
        sourceEntryId: 'old-walk-entry',
        date: date.subtract(const Duration(days: 2)),
        createdAt: date.subtract(const Duration(days: 2)),
        summary: '散步能帮助用户降低焦虑并恢复状态。',
        keywords: const ['散步', '焦虑', '恢复'],
        emotion: '放松',
        people: const [],
        tags: const ['情绪调节'],
        importance: 0.82,
        confidence: 0.76,
      ));

      final package =
          await const AiContextBuilder().buildForTodayInsight(entry);
      final trace = await traceRepository.getTrace(entry.id);

      expect(package.relatedMemories.single.rerankSignals, isNotEmpty);
      expect(trace?.items.single.rerankSignals, isNotEmpty);
      expect(trace?.items.single.rerankSignals.keys, contains('keyword'));
    });

    test('today context keeps related memory budget within design limit',
        () async {
      SharedPreferences.setMockInitialValues({});
      const memoryRepository = MemoryRepository();
      const traceRepository = AiRetrievalTraceRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'today-memory-budget-entry',
        date: date,
        content: '今天散步以后焦虑下降，状态恢复。',
      );
      for (var index = 0; index < 10; index++) {
        await memoryRepository.saveMemory(MemoryEntry(
          id: 'memory:today-budget-$index',
          sourceEntryId: 'budget-memory-source-$index',
          date: date.subtract(Duration(days: index + 1)),
          createdAt: date.subtract(Duration(days: index + 1)),
          summary: '散步帮助焦虑下降并恢复状态，第 $index 条。',
          keywords: const ['散步', '焦虑', '恢复'],
          emotion: '放松',
          people: const [],
          tags: const ['情绪调节'],
          importance: 0.8,
          confidence: 0.74,
        ));
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(entry);
      final trace = await traceRepository.getTrace(entry.id);

      expect(package.relatedMemories, hasLength(8));
      expect(
        trace?.items.where((item) => item.sourceType == 'memory'),
        hasLength(8),
      );
      expect(package.debugSummary, contains('memories=8'));
      expect(package.debugSummary, contains('budget=memories:8/8'));
    });

    test('today context keeps profile fact budget within design limit',
        () async {
      SharedPreferences.setMockInitialValues({});
      const insightRepository = InsightRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'today-profile-budget-entry',
        date: date,
        content: '今天散步后状态恢复。',
      );
      for (var index = 0; index < 7; index++) {
        await insightRepository.saveInsight(_insight(
          entryId: 'profile-budget-$index',
          date: date.subtract(Duration(days: index)),
          profileCandidate: ProfileUpdateCandidate(
            field: 'profile_budget_$index',
            value: '画像预算测试 $index',
            confidence: 0.66,
          ),
        ));
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(entry);

      expect(package.profileFacts, hasLength(5));
      expect(package.debugSummary, contains('profile=5'));
      expect(package.debugSummary, contains('profile:5/7'));
    });

    test('today context keeps relationship profile budget within design limit',
        () async {
      SharedPreferences.setMockInitialValues({});
      const insightRepository = InsightRepository();
      final date = DateTime(2026, 7, 3);
      final names = List.generate(7, (index) => '人物$index');
      final entry = _entry(
        id: 'today-relationship-budget-entry',
        date: date,
        content: '今天想起了${names.join('、')}这些关系里的互动。',
      );
      for (var index = 0; index < names.length; index++) {
        await insightRepository.saveInsight(_insight(
          entryId: 'relationship-budget-$index',
          date: date.subtract(Duration(days: index)),
          relationshipUpdate: RelationshipUpdateCandidate(
            personName: names[index],
            relationship: '朋友',
            summary: '关系预算测试 $index',
            confidence: 0.66,
          ),
        ));
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(entry);

      expect(package.relationshipProfiles, hasLength(5));
      expect(package.debugSummary, contains('relationships=5'));
      expect(package.retrievalTrace?.sourceCount, package.sourceCount);
      expect(
        package.retrievalTrace?.items
            .where((item) => item.sourceType == 'relationship'),
        hasLength(5),
      );
    });

    test('today context keeps active stone task budget within design limit',
        () async {
      SharedPreferences.setMockInitialValues({});
      const stoneRepository = StoneTaskRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'today-stone-budget-entry',
        date: date,
        content: '今天想看一下最近的塑石行动。',
      );
      for (var index = 0; index < 7; index++) {
        await stoneRepository.saveTask(StoneTask(
          id: 'stone:budget-$index',
          sourceEntryId: 'stone-source-$index',
          title: '塑石行动 $index',
          description: '一个可执行的小行动。',
          createdAt: date.subtract(Duration(days: index)),
          updatedAt: date.subtract(Duration(days: index)),
          status: StoneTaskStatus.active,
        ));
      }

      final package =
          await const AiContextBuilder().buildForTodayInsight(entry);

      expect(package.stoneTasks, hasLength(5));
      expect(package.debugSummary, contains('stone=5'));
      expect(package.retrievalTrace?.sourceCount, package.sourceCount);
      expect(
        package.retrievalTrace?.items
            .where((item) => item.sourceType == 'stone'),
        hasLength(5),
      );
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

    test('purges expired trash with legacy string list item values', () async {
      SharedPreferences.setMockInitialValues({
        'diary.trash.index': <String>['entry-1'],
        'diary.trash.entry-1': <String>['corrupted'],
      });

      await const DiaryRepository().purgeExpiredTrash();
      final prefs = await SharedPreferences.getInstance();

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

    test('falls back when trash metadata has invalid field types', () async {
      final entry = _entry(
        id: 'entry-1',
        date: DateTime(2026, 7, 3),
        content: '回收站元数据类型异常也不能阻断启动。',
      );
      SharedPreferences.setMockInitialValues({
        'diary.trash.index': <String>['entry-1'],
        'diary.trash.entry-1': jsonEncode({
          'entry': entry.toJson(),
          'deletedAt': <String>['corrupted'],
        }),
      });

      final items = await const DiaryRepository().listTrashEntries();

      expect(items, hasLength(1));
      expect(items.single.entry.id, entry.id);
      expect(items.single.deletedAt, entry.updatedAt);
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

    test('move to trash invalidates period summaries referencing the entry',
        () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const periodRepository = PeriodSummaryRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'trash-period-source',
        date: date,
        content: '这篇日记参与了月度和年度总结。',
      );
      await diaryRepository.saveEntry(entry);
      await periodRepository.saveSummary(PeriodSummary(
        id: 'month:2026-07',
        type: PeriodSummaryType.month,
        startDate: DateTime(2026, 7),
        endDate: DateTime(2026, 7, 31, 23, 59, 59),
        generatedAt: date,
        entryCount: 1,
        brief: '七月摘要',
        themes: const [],
        emotions: const [],
        representativeEntryIds: [entry.id],
        generator: 'test',
      ));
      await periodRepository.saveSummary(PeriodSummary(
        id: 'year:2026',
        type: PeriodSummaryType.year,
        startDate: DateTime(2026),
        endDate: DateTime(2026, 12, 31, 23, 59, 59),
        generatedAt: date,
        entryCount: 1,
        brief: '全年摘要',
        themes: const [],
        emotions: const [],
        representativeEntryIds: const [],
        generator: 'test',
        contextSourceLines: [
          'period_entry:${entry.id} | 2026-07-03 | 这篇日记参与总结',
        ],
      ));

      await diaryRepository.moveToTrash(entry.id);

      expect(await periodRepository.getSummary('month:2026-07'), isNull);
      expect(await periodRepository.getSummary('year:2026'), isNull);
    });

    test('move to trash clears debug traces referencing the entry', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const memoryRepository = MemoryRepository();
      const promptRepository = AiPromptTraceRepository();
      const retrievalRepository = AiRetrievalTraceRepository();
      final date = DateTime(2026, 7, 3);
      final entry = _entry(
        id: 'trash-debug-source',
        date: date,
        content: '这篇日记曾经进入搜索和问答调试记录。',
      );
      await diaryRepository.saveEntry(entry);
      await memoryRepository.saveMemory(MemoryEntry(
        id: 'memory:trash-debug-source',
        sourceEntryId: entry.id,
        date: date,
        createdAt: date,
        summary: '这篇日记沉淀成一条长期记忆。',
        keywords: const ['调试'],
        emotion: '',
        people: const [],
        tags: const ['调试'],
      ));
      await promptRepository.saveTrace(AiPromptTrace(
        id: 'companion:last',
        scenario: 'question',
        createdAt: date,
        contextSummary: 'sources=1',
        systemPromptPreview: 'system',
        userPromptPreview: 'entry_summary:${entry.id}',
        systemPromptLength: 6,
        userPromptLength: 24,
        userPrompt:
            'source_id=entry_summary:${entry.id}\nsource_id=memory:trash-debug-source',
      ));
      await retrievalRepository.saveTrace(AiRetrievalTrace(
        entryId: 'search:last',
        generatedAt: date,
        scenario: 'search',
        items: [
          AiRetrievalTraceItem(
            sourceType: 'entry_summary',
            sourceId: entry.id,
            title: '搜索命中',
            summary: '引用了待删除日记',
            score: 8,
            reasons: const ['关键词重合'],
            matchedTokens: const ['搜索'],
          ),
        ],
      ));
      await retrievalRepository.saveTrace(AiRetrievalTrace(
        entryId: 'question:last',
        generatedAt: date,
        scenario: 'question',
        items: const [
          AiRetrievalTraceItem(
            sourceType: 'memory',
            sourceId: 'memory:trash-debug-source',
            title: '长期记忆命中',
            summary: '这条 trace 只记录 memory id，没有直接记录 entry id',
            score: 8,
            reasons: ['语义相似'],
            matchedTokens: ['调试'],
          ),
        ],
      ));

      await diaryRepository.moveToTrash(entry.id);

      expect(await promptRepository.getTrace('companion:last'), isNull);
      expect(await retrievalRepository.getTrace('search:last'), isNull);
      expect(await retrievalRepository.getTrace('question:last'), isNull);
    });

    test('move to trash prunes unsupported profile preferences', () async {
      SharedPreferences.setMockInitialValues({});
      const diaryRepository = DiaryRepository();
      const insightRepository = InsightRepository();
      const preferenceRepository = AiProfilePreferenceRepository();
      const projectionService = ProfileProjectionService();
      final date = DateTime(2026, 7, 3);
      final deletedEntry = _entry(
        id: 'trash-profile-only',
        date: date,
        content: '这篇日记只支撑一条临时画像和一段关系。',
      );
      final sharedEntry = _entry(
        id: 'trash-profile-shared',
        date: date.add(const Duration(days: 1)),
        content: '这篇日记仍然支撑散步恢复状态的画像。',
      );
      await diaryRepository.saveEntry(deletedEntry);
      await diaryRepository.saveEntry(sharedEntry);
      await insightRepository.saveInsight(_insight(
        entryId: deletedEntry.id,
        date: deletedEntry.date,
        profileCandidate: const ProfileUpdateCandidate(
          field: 'preference',
          value: '可能喜欢夜间写作',
          confidence: 0.62,
        ),
        relationshipUpdate: const RelationshipUpdateCandidate(
          personName: '小林',
          relationship: '同事',
          summary: '讨论产品方案',
          confidence: 0.66,
        ),
      ));
      await insightRepository.saveInsight(_insight(
        entryId: sharedEntry.id,
        date: sharedEntry.date,
        profileCandidate: const ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步可能帮助恢复状态',
          confidence: 0.64,
        ),
      ));
      final projection = projectionService.build(
        await insightRepository.listInsights(),
      );
      final unsupportedFact = projection.profileFacts
          .firstWhere((fact) => fact.field == 'preference');
      final supportedFact = projection.profileFacts
          .firstWhere((fact) => fact.field == 'self_regulation');
      await preferenceRepository.setHidden(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: unsupportedFact.id,
        hidden: true,
      );
      await preferenceRepository.setConfirmed(
        targetType: AiProfilePreferenceTargetType.profileFact,
        targetId: supportedFact.id,
        confirmed: true,
      );
      await preferenceRepository.setHidden(
        targetType: AiProfilePreferenceTargetType.relationship,
        targetId: '小林',
        hidden: true,
      );

      await diaryRepository.moveToTrash(deletedEntry.id);

      expect(
        await preferenceRepository.getPreference(
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: unsupportedFact.id,
        ),
        isNull,
      );
      expect(
        await preferenceRepository.getPreference(
          targetType: AiProfilePreferenceTargetType.relationship,
          targetId: '小林',
        ),
        isNull,
      );
      expect(
        await preferenceRepository.getPreference(
          targetType: AiProfilePreferenceTargetType.profileFact,
          targetId: supportedFact.id,
        ),
        isNotNull,
      );
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

    test('retrieval results expose memory rerank signals', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = MemoryRepository();
      final memoryDate = DateTime(2026, 7, 1);
      await repository.saveMemory(MemoryEntry(
        id: 'memory-rerank-signals',
        sourceEntryId: 'memory-source',
        date: memoryDate,
        createdAt: memoryDate,
        summary: '和妈妈散步以后焦虑下降，状态恢复。',
        keywords: const ['散步', '焦虑', '恢复'],
        emotion: '放松',
        people: const ['妈妈'],
        tags: const ['情绪调节'],
        importance: 0.82,
        confidence: 0.76,
        referenceCount: 2,
      ));

      final results = await repository.findRelatedWithReasons(
        entry: _entry(
          id: 'memory-rerank-entry',
          date: DateTime(2026, 7, 3),
          content: '今天和妈妈散步后，焦虑下降了。',
        ),
      );
      final result = results.single;

      expect(result.rerankSignals['keyword'], greaterThan(0));
      expect(result.rerankSignals['time'], 2);
      expect(result.rerankSignals['people'], 2);
      expect(result.rerankSignals['semantic'], isNotNull);
      expect(result.rerankSignals['lifecycle'], greaterThan(0));
      expect(result.rerankSignals['reference'], 2);
    });

    test('memory retrieval falls back when embeddings are unavailable',
        () async {
      SharedPreferences.setMockInitialValues({});
      const repository = MemoryRepository(
        embeddingService: _ThrowingEmbeddingService(),
      );
      final memoryDate = DateTime(2026, 7, 1);
      await repository.saveMemory(MemoryEntry(
        id: 'memory-keyword-fallback',
        sourceEntryId: 'memory-keyword-source',
        date: memoryDate,
        createdAt: memoryDate,
        summary: '散步以后焦虑下降，状态恢复。',
        keywords: const ['散步', '焦虑', '恢复'],
        emotion: '放松',
        people: const [],
        tags: const ['情绪调节'],
        importance: 0.82,
        confidence: 0.76,
      ));

      final results = await repository.findRelatedWithReasons(
        entry: _entry(
          id: 'memory-keyword-query',
          date: DateTime(2026, 7, 3),
          content: '今天散步后焦虑下降了。',
        ),
      );
      final result = results.single;

      expect(result.memory.id, 'memory-keyword-fallback');
      expect(result.reasons.join(' '), contains('关键词重合'));
      expect(result.reasons.join(' '), isNot(contains('语义相似')));
      expect(result.rerankSignals.keys, contains('keyword'));
      expect(result.rerankSignals.keys, isNot(contains('semantic')));
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

    test('contradictions lower old memory confidence without deleting it',
        () async {
      SharedPreferences.setMockInitialValues({});
      const repository = MemoryRepository();
      final date = DateTime(2026, 7, 3);
      await repository.saveMemory(MemoryEntry(
        id: 'contradicted-memory',
        sourceEntryId: 'old-entry',
        date: date,
        createdAt: date,
        summary: '用户一直不喜欢社交。',
        keywords: const ['社交'],
        emotion: '压力',
        people: const [],
        tags: const ['关系'],
        importance: 0.7,
        confidence: 0.7,
      ));

      await repository.applyContradictions(
        contradictions: const [
          InsightContradiction(
            oldMemoryId: 'memory:contradicted-memory',
            newEvidence: '今天和朋友聚会后感觉放松。',
            interpretation: '旧记忆需要增加条件。',
            confidence: 0.8,
          ),
        ],
      );
      final memory = (await repository.listMemories()).single;

      expect(memory.id, 'contradicted-memory');
      expect(memory.confidence, lessThan(0.7));
      expect(memory.importance, lessThan(0.7));
      expect(memory.decay, greaterThan(0));
      expect(memory.archived, isFalse);
    });

    test('generated memory updates content without resetting lifecycle',
        () async {
      SharedPreferences.setMockInitialValues({});
      const repository = MemoryRepository();
      final originalDate = DateTime(2026, 7, 1);
      await repository.saveMemory(MemoryEntry(
        id: 'generated-lifecycle-memory',
        sourceEntryId: 'old-entry',
        date: originalDate,
        createdAt: originalDate,
        summary: '旧摘要。',
        keywords: const ['旧'],
        emotion: '平静',
        people: const [],
        tags: const ['旧标签'],
        importance: 0.31,
        confidence: 0.27,
        referenceCount: 4,
        decay: 0.42,
        archived: true,
      ));

      await repository.saveGeneratedMemory(MemoryEntry(
        id: 'generated-lifecycle-memory',
        sourceEntryId: 'new-entry',
        date: DateTime(2026, 7, 3),
        createdAt: DateTime(2026, 7, 3),
        summary: '新的 AI 摘要。',
        keywords: const ['新'],
        emotion: '轻松',
        people: const ['妈妈'],
        tags: const ['新标签'],
        evidenceEntryIds: const ['new-entry'],
        importance: 0.64,
        confidence: 0.58,
      ));
      final memory = (await repository.listMemories()).single;

      expect(memory.summary, '新的 AI 摘要。');
      expect(memory.keywords, ['新']);
      expect(memory.emotion, '轻松');
      expect(memory.people, ['妈妈']);
      expect(memory.tags, ['新标签']);
      expect(memory.createdAt, originalDate);
      expect(memory.importance, 0.31);
      expect(memory.confidence, 0.27);
      expect(memory.referenceCount, 4);
      expect(memory.decay, 0.42);
      expect(memory.archived, isTrue);
      expect(memory.allSourceEntryIds, containsAll(['old-entry', 'new-entry']));
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
      const embeddingRepository = AiEmbeddingRepository();
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
      final embedding = await embeddingRepository.getBySource(
        sourceType: AiEmbeddingSourceType.memory,
        sourceId: 'shared-memory',
      );

      expect(memories.map((memory) => memory.id), ['shared-memory']);
      expect(shared.sourceEntryId, 'second-entry');
      expect(shared.evidenceEntryIds, ['second-entry']);
      expect(shared.confidence, lessThan(0.72));
      expect(embedding?.entryId, 'second-entry');
      expect(await embeddingRepository.listForEntry('first-entry'), isEmpty);
      expect(
        (await embeddingRepository.listForEntry('second-entry'))
            .map((item) => item.id),
        ['memory:shared-memory'],
      );
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

    test('reads malformed memory fields with safe defaults', () {
      final memory = MemoryEntry.fromJson({
        'id': 42,
        'sourceEntryId': 43,
        'date': <String>['bad'],
        'createdAt': <String>['bad'],
        'updatedAt': null,
        'lastReferencedAt': null,
        'summary': 99,
        'keywords': ['散步', 7, null],
        'emotion': true,
        'people': 'bad',
        'tags': ['恢复', 3],
        'evidenceEntryIds': 'bad',
        'importance': '0.71',
        'confidence': '0.62',
        'referenceCount': '4',
        'decay': '0.2',
        'archived': 'true',
      });

      expect(memory.id, '42');
      expect(memory.sourceEntryId, '43');
      expect(memory.summary, '99');
      expect(memory.keywords, ['散步', '7']);
      expect(memory.emotion, 'true');
      expect(memory.people, isEmpty);
      expect(memory.tags, ['恢复', '3']);
      expect(memory.evidenceEntryIds, ['43']);
      expect(memory.importance, 0.71);
      expect(memory.confidence, 0.62);
      expect(memory.referenceCount, 4);
      expect(memory.decay, 0.2);
      expect(memory.archived, isTrue);
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
  List<InsightContradiction> contradictions = const [],
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
    contradictions: contradictions,
  );
}

class _FakeDiaryAnalysisService extends DiaryAnalysisService {
  const _FakeDiaryAnalysisService();

  @override
  Future<DiaryInsight> analyzeEntry(DiaryEntry entry) async {
    final insight = DiaryInsight(
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
    await const InsightRepository().saveInsight(insight);
    return insight;
  }
}

class _ThrowingDiaryAnalysisService extends DiaryAnalysisService {
  const _ThrowingDiaryAnalysisService();

  @override
  Future<DiaryInsight> analyzeEntry(DiaryEntry entry) async {
    throw StateError('simulated insight failure');
  }
}

class _RetryableAiErrorAnalysisService extends DiaryAnalysisService {
  const _RetryableAiErrorAnalysisService();

  @override
  Future<DiaryInsight> analyzeEntry(DiaryEntry entry) async {
    throw const AiClientException('AI 请求失败：500');
  }
}

class _ThrowingEmbeddingService extends EmbeddingService {
  const _ThrowingEmbeddingService();

  @override
  AiEmbeddingResult embed(String text) {
    throw StateError('simulated embedding failure');
  }
}

class _ThrowingSummaryService extends EntrySummaryService {
  const _ThrowingSummaryService();

  @override
  List<DiarySegment> buildSegments(DiaryEntry entry) {
    throw StateError('simulated segment failure');
  }

  @override
  EntrySummary buildSummary(DiaryEntry entry, List<DiarySegment> segments) {
    throw StateError('simulated summary failure');
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
          'entry_id': 'memory:memory-walk-source',
        },
        {
          'title': '最近散步',
          'reason': '最近日记摘要也提到恢复',
          'entry_id': 'entry_summary:recent-source-entry',
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
            {
              'type': 'entry_summary',
              'id': 'entry_summary:recent-source-entry'
            },
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
      'contradictions': [
        {
          'old_memory_id': 'memory-walk-source',
          'new_evidence': '今天写到散步后状态轻松。',
          'interpretation': '旧记忆需要避免把轻松误判为焦虑。',
          'confidence': 0.7,
          'evidence': [
            {'type': 'current_entry', 'id': 'feedback-prompt-entry'}
          ],
        }
      ],
    });
  }
}

class _PipelineAiClientService extends AiClientService {
  const _PipelineAiClientService(this.entryId);

  final String entryId;

  @override
  Future<String> completeJson({
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    return jsonEncode({
      'reflection': '散步后状态更轻松。',
      'related_memories': [],
      'facts': [
        {
          'text': '今天记录了产品设计和散步。',
          'evidence': [
            {'type': 'current_entry', 'id': entryId}
          ],
        }
      ],
      'signals': [
        {
          'text': '散步后状态更轻松。',
          'evidence': [
            {'type': 'current_entry', 'id': entryId}
          ],
        }
      ],
      'hypotheses': [
        {
          'text': '散步可能帮助从工作状态中恢复。',
          'confidence': 0.62,
          'evidence': [
            {'type': 'current_entry', 'id': entryId}
          ],
        }
      ],
      'suggestions': [
        {
          'text': '明天晚饭后散步 10 分钟。',
          'evidence': [
            {'type': 'current_entry', 'id': entryId}
          ],
        }
      ],
      'emotion': '轻松',
      'keywords': ['产品设计', '散步'],
      'people': [],
      'stone_suggestion': {
        'title': '散步 10 分钟',
        'description': '晚饭后出门走一小圈。',
      },
      'memory_update': {
        'summary': '散步后状态更轻松。',
        'tags': ['散步', '恢复'],
      },
      'profile_update_candidates': [
        {
          'field': 'self_regulation',
          'value': '散步可能帮助用户从工作状态恢复',
          'confidence': 0.58,
          'evidence': [
            {'type': 'current_entry', 'id': entryId}
          ],
        }
      ],
      'relationship_updates': [],
      'contradictions': [],
    });
  }
}

class _NoMemoryUpdateAiClientService extends AiClientService {
  @override
  Future<String> completeJson({
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    return jsonEncode({
      'reflection': '今天是普通记录。',
      'related_memories': [],
      'facts': [],
      'signals': [],
      'hypotheses': [],
      'suggestions': [],
      'emotion': '平静',
      'keywords': ['记录'],
      'people': [],
      'stone_suggestion': {},
      'memory_update': {'summary': '', 'tags': []},
      'profile_update_candidates': [],
      'relationship_updates': [],
      'contradictions': [],
    });
  }
}

class _MalformedAnalysisAiClientService extends AiClientService {
  const _MalformedAnalysisAiClientService();

  @override
  Future<String> completeJson({
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    return jsonEncode({
      'reflection': 42,
      'related_memories': [
        'ignored',
        {
          'title': 7,
          'reason': true,
          'entry_id': 'malformed-ai-response-entry',
        },
      ],
      'facts': 'bad',
      'signals': {'bad': true},
      'hypotheses': [
        {
          'text': '散步可能帮助恢复。',
          'confidence': '0.61',
          'evidence': 'bad',
        },
      ],
      'suggestions': 'bad',
      'emotion': true,
      'keywords': '散步',
      'people': {'bad': true},
      'stone_suggestion': {
        'title': 7,
        'description': '明天走 10 分钟',
      },
      'memory_update': {
        'summary': 123,
        'tags': '散步',
      },
      'profile_update_candidates': {'bad': true},
      'relationship_updates': 'bad',
      'contradictions': [
        'ignored',
        {
          'old_memory_id': 'memory:missing',
          'new_evidence': '今天更放松',
        },
      ],
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
