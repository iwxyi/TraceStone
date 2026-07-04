import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trace_stone/app/trace_stone_app.dart';
import 'package:trace_stone/data/models/ai_analysis_job.dart';
import 'package:trace_stone/data/models/ai_feedback.dart';
import 'package:trace_stone/data/models/ai_profile_preference.dart';
import 'package:trace_stone/data/models/diary_entry.dart';
import 'package:trace_stone/data/models/diary_insight.dart';
import 'package:trace_stone/data/models/ai_prompt_trace.dart';
import 'package:trace_stone/data/models/ai_retrieval_trace.dart';
import 'package:trace_stone/data/models/memory_entry.dart';
import 'package:trace_stone/data/models/stone_task.dart';
import 'package:trace_stone/data/repositories/ai_analysis_queue_repository.dart';
import 'package:trace_stone/data/repositories/ai_feedback_repository.dart';
import 'package:trace_stone/data/repositories/ai_profile_preference_repository.dart';
import 'package:trace_stone/data/repositories/ai_prompt_trace_repository.dart';
import 'package:trace_stone/data/repositories/ai_retrieval_trace_repository.dart';
import 'package:trace_stone/data/repositories/diary_repository.dart';
import 'package:trace_stone/data/repositories/entry_summary_repository.dart';
import 'package:trace_stone/data/repositories/insight_repository.dart';
import 'package:trace_stone/data/repositories/memory_repository.dart';
import 'package:trace_stone/data/repositories/stone_task_repository.dart';
import 'package:trace_stone/data/services/ai_context_builder.dart';
import 'package:trace_stone/data/services/ai_feedback_service.dart';
import 'package:trace_stone/data/services/app_startup_service.dart';
import 'package:trace_stone/data/services/entry_summary_service.dart';
import 'package:trace_stone/data/services/period_summary_service.dart';
import 'package:trace_stone/features/ai_insight/presentation/ai_feedback_bar.dart';
import 'package:trace_stone/features/ai_insight/presentation/insight_page.dart';
import 'package:trace_stone/features/companion/presentation/companion_page.dart';
import 'package:trace_stone/features/diary/presentation/diary_edit_page.dart';
import 'package:trace_stone/features/diary/presentation/today_page.dart';
import 'package:trace_stone/features/relationships/presentation/relationships_page.dart';
import 'package:trace_stone/features/review/presentation/review_page.dart';
import 'package:trace_stone/features/settings/presentation/calendar_memory_page.dart';
import 'package:trace_stone/features/settings/presentation/custom_ai_page.dart';
import 'package:trace_stone/features/settings/presentation/ai_debug_page.dart';
import 'package:trace_stone/features/settings/presentation/memory_management_page.dart';
import 'package:trace_stone/features/settings/presentation/profile_page.dart';
import 'package:trace_stone/features/search/presentation/search_page.dart';
import 'package:trace_stone/features/shaping_stone/presentation/shaping_stone_page.dart';

void main() {
  testWidgets('shows simplified main tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const TraceStoneApp());

    expect(find.text('今日'), findsWidgets);
    expect(find.text('回顾'), findsOneWidget);
    expect(find.text('洞察'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('resumes AI queue when app returns to foreground',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var resumeCount = 0;
    final startupService = AppStartupService(
      resumeAiQueue: () async {
        resumeCount += 1;
      },
    );
    await tester.pumpWidget(TraceStoneApp(startupService: startupService));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(resumeCount, 1);
  });

  testWidgets('review page ignores invalid stored tab preference',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'review.selectedIndex': <String>['bad'],
    });
    await tester.pumpWidget(const TraceStoneApp());

    expect(find.text('回顾'), findsOneWidget);
  });

  testWidgets('review period summary shows developer source lines',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'review.selectedIndex': 1,
      'settings.developerMode': true,
    });
    final date = DateTime(2026, 7, 4);
    await const DiaryRepository().saveEntry(DiaryEntry(
      id: 'review-period-source',
      date: date,
      createdAt: date,
      content: '今天只保存了原始日记，还没有摘要。',
      location: '未选择地点',
      weather: '晴',
      temperature: '26',
      updatedAt: date,
    ));

    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();

    expect(find.text('月度总结'), findsOneWidget);
    expect(find.text('开发者来源'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('开发者来源'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开发者来源'));
    await tester.pumpAndSettle();

    expect(find.textContaining('context: periodSummary'), findsOneWidget);
    expect(
      find.textContaining('source: period_entry:review-period-source'),
      findsOneWidget,
    );
  });

  testWidgets('shows profile candidates on profile tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'entry',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '运动可能帮助恢复状态',
          confidence: 0.62,
        ),
      ],
    ));

    await tester.pumpWidget(const TraceStoneApp());
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('成长画像'), findsOneWidget);
    expect(find.text('画像候选'), findsNothing);
    expect(find.text('self_regulation'), findsOneWidget);
    expect(find.textContaining('运动可能帮助恢复状态'), findsOneWidget);
  });

  testWidgets('today insight developer structure respects developer mode',
      (tester) async {
    final now = DateTime.now();
    final entry = DiaryEntry(
      id: 'today-dev-entry',
      date: now,
      createdAt: now,
      content: '今天散步以后，焦虑下降了一些。',
      location: '未选择地点',
      weather: '晴',
      temperature: '26',
      updatedAt: now,
    );
    final insight = DiaryInsight(
      entryId: entry.id,
      entryDate: now,
      generatedAt: now,
      reflection: '散步后状态有所恢复。',
      relatedMemories: const [],
      emotion: '放松',
      keywords: const ['散步'],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      facts: const [
        InsightClaim(
          text: '今天记录了散步。',
          evidence: [
            InsightEvidence(type: 'current_entry', id: 'today-dev-entry#s1'),
          ],
        ),
      ],
      hypotheses: const [
        InsightClaim(
          text: '散步可能帮助恢复状态。',
          confidence: 0.62,
          evidence: [
            InsightEvidence(type: 'memory', id: 'memory-walk'),
          ],
        ),
      ],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步可能帮助恢复状态',
          confidence: 0.58,
        ),
      ],
      suggestions: const [
        InsightClaim(text: '明天晚饭后散步 10 分钟。'),
      ],
    );

    SharedPreferences.setMockInitialValues({});
    await const DiaryRepository().saveEntry(entry);
    await const InsightRepository().saveInsight(insight);
    await tester.pumpWidget(const MaterialApp(home: TodayPage()));
    await tester.pumpAndSettle();
    expect(find.text('给我的建议'), findsOneWidget);
    expect(find.textContaining('明天晚饭后散步 10 分钟'), findsOneWidget);
    expect(find.text('开发者洞察结构'), findsNothing);

    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    await const DiaryRepository().saveEntry(entry);
    await const InsightRepository().saveInsight(insight);
    await tester.pumpWidget(const MaterialApp(home: TodayPage()));
    await tester.pumpAndSettle();
    expect(find.text('开发者洞察结构'), findsOneWidget);
    expect(find.textContaining('facts=1'), findsOneWidget);
    await tester.tap(find.text('开发者洞察结构'));
    await tester.pumpAndSettle();
    expect(find.textContaining('evidence=current_entry:today-dev-entry#s1'),
        findsOneWidget);
    expect(find.textContaining('confidence=0.62'), findsOneWidget);
    expect(find.textContaining('profile self_regulation=散步可能帮助恢复状态'),
        findsOneWidget);
  });

  testWidgets('today queue card shows resumable batch progress',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const queueRepository = AiAnalysisQueueRepository();
    final date = DateTime(2026, 7, 3);
    await queueRepository.saveJob(AiAnalysisJob(
      id: 'queued-home-entry',
      entryId: 'queued-home-entry',
      pipelineVersion: 1,
      state: AiAnalysisJobState.incomplete,
      currentStage: AiAnalysisStage.embedding,
      createdAt: date,
      updatedAt: date,
      completedStages: const [
        AiAnalysisStage.preparing,
        AiAnalysisStage.segmenting,
      ],
      lastError: '上次整理被中断，等待继续',
    ));

    await tester.pumpWidget(const MaterialApp(home: TodayPage()));
    await tester.pump();

    expect(find.text('继续整理记忆'), findsOneWidget);
    expect(find.textContaining('正在整理 1/1 篇'), findsOneWidget);
    expect(find.textContaining('已完成 2/7 个阶段'), findsOneWidget);
    expect(find.textContaining('预计剩余 约 40 秒'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '暂停'), findsOneWidget);
  });

  testWidgets('today queue card shows paused state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const queueRepository = AiAnalysisQueueRepository();
    await queueRepository.setPaused(true);
    final date = DateTime(2026, 7, 3);
    await queueRepository.saveJob(AiAnalysisJob(
      id: 'paused-home-entry',
      entryId: 'paused-home-entry',
      pipelineVersion: 1,
      state: AiAnalysisJobState.pending,
      currentStage: AiAnalysisStage.queued,
      createdAt: date,
      updatedAt: date,
    ));

    await tester.pumpWidget(const MaterialApp(home: TodayPage()));
    await tester.pump();

    expect(find.text('记忆整理已暂停'), findsOneWidget);
    expect(find.textContaining('已暂停，继续后会从当前队列位置整理'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '继续'), findsOneWidget);
  });

  testWidgets('insight page exports insight package in developer mode',
      (tester) async {
    final date = DateTime(2026, 7, 3);
    final insight = DiaryInsight(
      entryId: 'insight-export-entry',
      entryDate: date,
      generatedAt: date,
      reflection: '散步以后状态变轻松。',
      relatedMemories: const [
        RelatedMemoryInsight(
          title: '去年夏天的散步',
          reason: '同样提到散步后状态恢复',
          entryId: 'entry-2025-walk',
        ),
        RelatedMemoryInsight(
          title: '未验证的旧记忆',
          reason: 'AI 没有返回有效来源',
        ),
      ],
      emotion: '放松',
      keywords: const ['散步'],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      facts: [
        InsightClaim(
          text: '今天记录了散步。',
          evidence: [
            InsightEvidence(
              type: 'current_entry',
              id: 'insight-export-entry',
              date: date,
              summary: '晚饭后散步，状态变轻松。',
              quote: '走完以后轻松一点',
              relevance: '当前日记事实来源',
            ),
          ],
        ),
        InsightClaim(text: '这条结论没有有效来源。'),
      ],
      suggestions: const [
        InsightClaim(text: '明天晚饭后散步 10 分钟。'),
      ],
    );
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    await const InsightRepository().saveInsight(insight);
    await tester.pumpWidget(const MaterialApp(home: InsightPage()));
    await tester.pumpAndSettle();
    expect(find.text('今日洞察'), findsWidgets);
    expect(find.text('今日洞察包'), findsNothing);
    expect(find.text('证据来源'), findsOneWidget);
    expect(
      find.textContaining(
          'current_entry:insight-export-entry｜2026-07-03｜晚饭后散步，状态变轻松。'),
      findsOneWidget,
    );
    expect(find.textContaining('证据缺失：结论没有有效来源'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('去年夏天的散步'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('来源 entry=entry-2025-walk'), findsOneWidget);
    expect(find.textContaining('来源未验证'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('复制洞察包'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('复制洞察包'), findsOneWidget);
    await tester.tap(find.text('复制洞察包'));
    await tester.pumpAndSettle();
    expect(find.text('复制洞察包？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, contains('## Diary Insight'));
    expect(copiedText, contains('entryId=insight-export-entry'));
    expect(copiedText, contains('## Raw JSON'));
    expect(copiedText, contains('"facts"'));
    expect(copiedText, contains('明天晚饭后散步 10 分钟'));
  });

  testWidgets('insight page edits entry summary', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final date = DateTime(2026, 7, 3);
    final entry = DiaryEntry(
      id: 'insight-summary-edit-entry',
      date: date,
      createdAt: date,
      content: '晚上散步以后，焦虑下降了一些，也整理了明天计划。',
      location: '未选择地点',
      weather: '晴',
      temperature: '26',
      updatedAt: date,
    );
    final summaryService = const EntrySummaryService();
    final segments = summaryService.buildSegments(entry);
    final summary = summaryService.buildSummary(entry, segments);
    await const EntrySummaryRepository().saveSummary(summary);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: entry.id,
      entryDate: date,
      generatedAt: date,
      reflection: '散步后状态轻了一点。',
      relatedMemories: const [],
      emotion: '放松',
      keywords: const ['散步'],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
    ));

    await tester.pumpWidget(const MaterialApp(home: InsightPage()));
    await tester.pumpAndSettle();

    expect(find.text('日记摘要'), findsOneWidget);
    await tester.tap(find.byTooltip('修正摘要'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '摘要标题'),
      '散步恢复',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '更准确的日记摘要'),
      '晚上散步后，焦虑感有所下降，也简单安排了明天。',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '关键要点，每行一条'),
      '散步后焦虑下降\n整理明天计划',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('散步恢复'), findsOneWidget);
    expect(
      find.textContaining(
        '晚上散步后，焦虑感有所下降',
        findRichText: true,
      ),
      findsWidgets,
    );
    expect(find.text('• 散步后焦虑下降'), findsOneWidget);
    final updated = await const EntrySummaryRepository()
        .getSummary('insight-summary-edit-entry');
    expect(updated?.generator, 'user-corrected');
    expect(updated?.qualityScore, greaterThan(0.5));
    expect(updated?.keyPoints, ['散步后焦虑下降', '整理明天计划']);
    expect(find.text('修订历史 1'), findsOneWidget);
    expect(find.textContaining('r2'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '复制修订'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, contains('## Entry Summary Revision Audit'));
    expect(copiedText, contains('entryId=insight-summary-edit-entry'));
    expect(copiedText, contains('currentRevision=2'));
    expect(copiedText, contains('previousBrief='));
    expect(copiedText, contains('updatedBrief=晚上散步后，焦虑感有所下降，也简单安排了明天。'));
  });

  testWidgets('insight feedback dialog keeps debug copy developer-only',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AiFeedbackBar(entryId: 'feedback-copy-entry')),
    ));
    await tester.tap(find.text('不准确'));
    await tester.pumpAndSettle();

    expect(find.text('哪里不准确？'), findsOneWidget);
    expect(find.textContaining('帮我重新核对这篇日记'), findsOneWidget);
    expect(find.textContaining('调试'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AiFeedbackBar(entryId: 'feedback-copy-entry')),
    ));
    await tester.tap(find.text('不准确'));
    await tester.pumpAndSettle();

    expect(find.textContaining('帮我重新核对这篇日记'), findsOneWidget);
    expect(find.textContaining('写入 AI 调试记录'), findsOneWidget);
  });

  testWidgets('corrects profile candidate text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'profile-correct',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '运动一定能解决压力',
          confidence: 0.62,
        ),
      ],
    ));

    await tester.pumpWidget(const TraceStoneApp());
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('画像操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('修正'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '更准确的说法'),
      '运动有时能帮助我从压力中恢复',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('运动有时能帮助我从压力中恢复'), findsOneWidget);
    expect(find.text('已确认'), findsOneWidget);
  });

  testWidgets('profile page shows evidence sources in developer mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'profile-evidence',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步可能帮助恢复状态',
          confidence: 0.62,
        ),
      ],
    ));

    await tester.pumpWidget(const TraceStoneApp());
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('证据来源'), findsOneWidget);
    expect(
        find.textContaining('current_entry:profile-evidence'), findsOneWidget);
  });

  testWidgets('profile page shows conflict notes in developer mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'profile-conflict-entry',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步可能帮助恢复状态',
          confidence: 0.62,
        ),
      ],
      contradictions: const [
        InsightContradiction(
          oldMemoryId: 'profile:self_regulation',
          newEvidence: '这次独处比散步更能恢复状态。',
          interpretation: '调节方式画像需要保留情境差异。',
          confidence: 0.72,
          evidence: [
            InsightEvidence(
              type: 'current_entry',
              id: 'profile-conflict-entry',
            ),
          ],
        ),
      ],
    ));

    await tester.pumpWidget(const TraceStoneApp());
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('需要核对的变化'), findsOneWidget);
    expect(find.text('这次独处比散步更能恢复状态。'), findsOneWidget);
    expect(find.text('调节方式画像需要保留情境差异。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '采纳变化'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '保持原画像'), findsOneWidget);
    expect(find.text('target: profile:self_regulation'), findsOneWidget);
    expect(find.text('entry: profile-conflict-entry'), findsOneWidget);
    expect(find.textContaining('source: current_entry:profile-conflict-entry'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '采纳变化'));
    await tester.pumpAndSettle();

    final preference = await const AiProfilePreferenceRepository()
        .getPreference(
            targetType: AiProfilePreferenceTargetType.profileFact,
            targetId: 'self_regulation:散步可能帮助恢复状态');
    expect(preference?.correctedValue, '这次独处比散步更能恢复状态。');
    expect(preference?.confirmed, isTrue);
    expect(find.text('已采纳这条变化并更新画像'), findsOneWidget);
  });

  testWidgets('profile page shows developer decision review', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final date = DateTime(2026, 7, 3);
    const preferenceRepository = AiProfilePreferenceRepository();
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'profile-decision-entry',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步可能帮助恢复状态',
          confidence: 0.62,
        ),
        ProfileUpdateCandidate(
          field: 'work_pattern',
          value: '项目推进时容易进入专注状态',
          confidence: 0.54,
        ),
      ],
    ));
    await preferenceRepository.setCorrectedValue(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: 'self_regulation:散步可能帮助恢复状态',
      correctedValue: '散步有时能帮助恢复状态',
    );

    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pumpAndSettle();

    expect(find.text('画像决策'), findsOneWidget);
    expect(find.text('全部 2'), findsOneWidget);
    expect(find.text('已修正 1'), findsOneWidget);
    expect(find.text('使用用户修正'), findsOneWidget);
    expect(find.text('散步有时能帮助恢复状态'), findsWidgets);
    expect(find.textContaining('preference=corrected'), findsOneWidget);
    await tester.tap(find.text('已修正 1'));
    await tester.pumpAndSettle();
    expect(find.text('显示 1/1'), findsOneWidget);
    expect(find.text('继续观察'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, '复制审计'));
    await tester.pumpAndSettle();

    expect(find.text('已复制画像决策审计'), findsOneWidget);
    expect(copiedText, contains('## Profile Decision Audit'));
    expect(copiedText, contains('kind=corrected'));
    expect(copiedText, contains('targetId=self_regulation:散步可能帮助恢复状态'));
    expect(copiedText, contains('preference=corrected'));
  });

  testWidgets('profile page merges same-field profile candidates',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'profile-merge-first',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步有助于恢复状态',
          confidence: 0.62,
        ),
      ],
    ));
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'profile-merge-second',
      entryDate: date.add(const Duration(days: 1)),
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '独处也能恢复状态',
          confidence: 0.58,
        ),
      ],
    ));

    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pumpAndSettle();

    expect(find.text('同字段 2 条'), findsWidgets);

    await tester.tap(find.byTooltip('画像操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('合并同类画像'));
    await tester.pumpAndSettle();

    expect(find.text('合并同类画像'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '合并后的画像'),
      '散步和独处都可能帮助我恢复状态',
    );
    await tester.tap(find.widgetWithText(FilledButton, '合并'));
    await tester.pumpAndSettle();

    final primary = await const AiProfilePreferenceRepository().getPreference(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: 'self_regulation:散步有助于恢复状态',
    );
    final hidden = await const AiProfilePreferenceRepository().getPreference(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: 'self_regulation:独处也能恢复状态',
    );
    expect(primary?.correctedValue, '散步和独处都可能帮助我恢复状态');
    expect(primary?.confirmed, isTrue);
    expect(hidden?.hidden, isTrue);
    expect(find.text('已合并同字段画像候选'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    final restoredPrimary =
        await const AiProfilePreferenceRepository().getPreference(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: 'self_regulation:散步有助于恢复状态',
    );
    final restoredHidden =
        await const AiProfilePreferenceRepository().getPreference(
      targetType: AiProfilePreferenceTargetType.profileFact,
      targetId: 'self_regulation:独处也能恢复状态',
    );
    expect(restoredPrimary, isNull);
    expect(restoredHidden, isNull);
    expect(find.text('同字段 2 条'), findsWidgets);
  });

  testWidgets('relationships page shows developer decision review',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final date = DateTime(2026, 7, 3);
    const preferenceRepository = AiProfilePreferenceRepository();
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'relationship-decision-entry',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const ['小李'],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      relationshipUpdates: const [
        RelationshipUpdateCandidate(
          personName: '小李',
          relationship: '同事',
          summary: '一起讨论了项目推进。',
          confidence: 0.62,
        ),
        RelationshipUpdateCandidate(
          personName: '小王',
          relationship: '朋友',
          summary: '简单聊了近况。',
          confidence: 0.54,
        ),
      ],
    ));
    await preferenceRepository.setConfirmed(
      targetType: AiProfilePreferenceTargetType.relationship,
      targetId: '小李',
      confirmed: true,
    );

    await tester.pumpWidget(const MaterialApp(home: RelationshipsPage()));
    await tester.pumpAndSettle();

    expect(find.text('关系决策'), findsOneWidget);
    expect(find.text('全部 2'), findsOneWidget);
    expect(find.text('已确认 1'), findsOneWidget);
    expect(find.text('用户已确认'), findsOneWidget);
    expect(find.text('小李'), findsWidgets);
    expect(find.textContaining('preference=confirmed'), findsOneWidget);
    await tester.tap(find.text('已确认 1'));
    await tester.pumpAndSettle();
    expect(find.text('显示 1/1'), findsOneWidget);
    expect(find.text('继续观察'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, '复制审计'));
    await tester.pumpAndSettle();

    expect(find.text('已复制关系决策审计'), findsOneWidget);
    expect(copiedText, contains('## Relationship Decision Audit'));
    expect(copiedText, contains('kind=confirmed'));
    expect(copiedText, contains('targetId=小李'));
    expect(copiedText, contains('preference=confirmed'));
  });

  testWidgets('relationships page merges people and supports undo',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'relationship-merge-first',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const ['小李'],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      relationshipUpdates: const [
        RelationshipUpdateCandidate(
          personName: '小李',
          relationship: '同事',
          summary: '一起讨论项目推进。',
          emotion: '平和',
          confidence: 0.62,
        ),
      ],
    ));
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'relationship-merge-second',
      entryDate: date.add(const Duration(days: 1)),
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const ['李同学'],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      relationshipUpdates: const [
        RelationshipUpdateCandidate(
          personName: '李同学',
          relationship: '同事',
          summary: '继续沟通方案。',
          emotion: '专注',
          confidence: 0.58,
        ),
      ],
    ));

    await tester.pumpWidget(const MaterialApp(home: RelationshipsPage()));
    await tester.pumpAndSettle();

    expect(find.text('小李'), findsWidgets);
    expect(find.text('李同学'), findsWidgets);

    await tester.ensureVisible(find.byTooltip('关系操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关系操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('合并人物'));
    await tester.pumpAndSettle();

    expect(find.text('合并人物'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '合并'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已将'), findsOneWidget);
    expect(find.text('已合并人物'), findsOneWidget);
    expect(find.textContaining('preference=merged'), findsOneWidget);
    expect(find.text('合并历史'), findsOneWidget);
    expect(find.textContaining('合并：'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '复制审计'));
    await tester.pumpAndSettle();
    expect(copiedText, contains('## Relationship Decision Audit'));
    expect(copiedText, contains('### Merge History'));
    expect(copiedText, contains('action=merge'));
    await tester.scrollUntilVisible(
      find.text('别名 2 个'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('别名 2 个'), findsOneWidget);
    expect(find.textContaining('也包括：'), findsOneWidget);
    expect(find.byTooltip('关系操作'), findsOneWidget);

    await tester.ensureVisible(find.text('最近互动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近互动'));
    await tester.pumpAndSettle();

    expect(find.text('合并依据'), findsOneWidget);
    expect(find.textContaining('aliases='), findsOneWidget);
    expect(find.textContaining('小李'), findsWidgets);
    expect(find.textContaining('李同学'), findsWidgets);
    expect(find.textContaining('| interactions=2 |'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    final preferences =
        await const AiProfilePreferenceRepository().listPreferences();
    final mergeHistory = await const AiProfilePreferenceRepository()
        .listRelationshipMergeHistory();
    expect(preferences.where((item) => item.mergedInto.isNotEmpty), isEmpty);
    expect(mergeHistory.map((item) => item.action),
        contains(AiRelationshipMergeEventAction.merge));
    expect(mergeHistory.map((item) => item.action),
        contains(AiRelationshipMergeEventAction.undo));
    expect(find.text('小李'), findsWidgets);
    expect(find.text('李同学'), findsWidgets);
  });

  testWidgets('corrects long term memory summary', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const MemoryRepository().saveMemory(MemoryEntry(
      id: 'memory-correct-widget',
      sourceEntryId: 'entry',
      date: date,
      createdAt: date,
      summary: '散步一定能解决所有压力。',
      keywords: const ['散步'],
      emotion: '',
      people: const [],
      tags: const ['运动'],
    ));

    await tester.pumpWidget(
      const MaterialApp(home: MemoryManagementPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('记忆操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('修正'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '更准确的记忆摘要'),
      '散步有时能帮助缓解压力。',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('散步有时能帮助缓解压力。'), findsOneWidget);
  });

  testWidgets('memory page keeps lifecycle metrics out of normal mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const MemoryRepository().saveMemory(MemoryEntry(
      id: 'memory-normal-lifecycle',
      sourceEntryId: 'normal-entry',
      evidenceEntryIds: const ['normal-entry', 'older-entry'],
      date: date,
      createdAt: date,
      summary: '散步有时能帮助缓解压力。',
      keywords: const ['散步'],
      emotion: '',
      people: const [],
      tags: const ['运动'],
      importance: 0.72,
      confidence: 0.16,
      referenceCount: 3,
      decay: 0.4,
    ));

    await tester.pumpWidget(
      const MaterialApp(home: MemoryManagementPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('来自 2 篇日记'), findsOneWidget);
    expect(find.text('低置信'), findsOneWidget);
    expect(find.textContaining('重要度'), findsNothing);
    expect(find.textContaining('置信度'), findsNothing);
    expect(find.textContaining('引用'), findsNothing);
    expect(find.textContaining('衰减'), findsNothing);
  });

  testWidgets('memory page shows source entries in developer mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    final date = DateTime(2026, 7, 3);
    await const MemoryRepository().saveMemory(MemoryEntry(
      id: 'memory-source-widget',
      sourceEntryId: 'first-entry',
      evidenceEntryIds: const ['first-entry', 'second-entry'],
      date: date,
      createdAt: date,
      summary: '散步有时能帮助缓解压力。',
      keywords: const ['散步'],
      emotion: '',
      people: const [],
      tags: const ['运动'],
    ));

    await tester.pumpWidget(
      const MaterialApp(home: MemoryManagementPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('证据来源'), findsOneWidget);
    expect(find.text('调试信息'), findsOneWidget);
    expect(find.text('memory:memory-source-widget'), findsOneWidget);
    expect(find.text('sourceEntry:first-entry'), findsOneWidget);
    expect(find.text('updatedAt:${date.toIso8601String()}'), findsOneWidget);
    expect(find.text('lastReferencedAt:${date.toIso8601String()}'),
        findsOneWidget);
    expect(find.text('entry:first-entry'), findsOneWidget);
    expect(find.text('entry:second-entry'), findsOneWidget);
  });

  testWidgets('memory page copies lifecycle audit in developer mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final date = DateTime(2026, 7, 3);
    await const MemoryRepository().saveMemory(MemoryEntry(
      id: 'memory-audit-widget',
      sourceEntryId: 'audit-entry',
      evidenceEntryIds: const ['audit-entry', 'older-audit-entry'],
      date: date,
      createdAt: date,
      lastReferencedAt: DateTime(2026, 7, 4),
      summary: '散步有时能帮助缓解压力。',
      keywords: const ['散步', '压力'],
      emotion: '放松',
      people: const ['小李'],
      tags: const ['运动'],
      importance: 0.72,
      confidence: 0.64,
      referenceCount: 5,
      decay: 0.18,
    ));

    await tester.pumpWidget(
      const MaterialApp(home: MemoryManagementPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '复制审计'));
    await tester.pumpAndSettle();

    expect(find.text('已复制记忆审计'), findsOneWidget);
    expect(copiedText, contains('# Memory Audit'));
    expect(copiedText, contains('id=memory-audit-widget'));
    expect(copiedText, contains('source=memory:memory-audit-widget'));
    expect(copiedText, contains('sourceEntry=audit-entry'));
    expect(copiedText, contains('importance=0.720'));
    expect(copiedText, contains('confidence=0.640'));
    expect(copiedText, contains('referenceCount=5'));
    expect(copiedText, contains('decay=0.180'));
    expect(copiedText, contains('- entry:older-audit-entry'));
    expect(copiedText, contains('keywords=散步, 压力'));
    expect(copiedText, contains('people=小李'));
  });

  testWidgets('shows shaping stone candidates', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'entry',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '平静',
      keywords: const ['散步'],
      people: const [],
      stoneTitle: '晚饭后散步 10 分钟',
      stoneDescription: '不用追求速度，走一小圈即可。',
      memorySummary: '',
      memoryTags: const [],
    ));

    await tester.pumpWidget(
      const MaterialApp(home: ShapingStonePage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('塑石'), findsOneWidget);
    expect(find.text('建议'), findsOneWidget);
    expect(find.text('候选'), findsNothing);
    expect(find.text('晚饭后散步 10 分钟'), findsOneWidget);
    expect(find.text('散步'), findsOneWidget);
  });

  testWidgets('shows shaping stone progress hints from later diaries',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const StoneTaskRepository().saveTask(StoneTask(
      id: 'stone:walk',
      sourceEntryId: 'source-entry',
      title: '晚饭后散步 10 分钟',
      description: '焦虑时走一小圈即可。',
      createdAt: date,
      updatedAt: date,
      tags: const ['散步', '焦虑'],
    ));
    await const DiaryRepository().saveEntry(DiaryEntry(
      id: 'later-entry',
      date: DateTime(2026, 7, 4),
      createdAt: DateTime(2026, 7, 4),
      content: '晚上真的去散步了，焦虑下降了一些。',
      location: '未选择地点',
      weather: '晴',
      temperature: '26',
      updatedAt: DateTime(2026, 7, 4),
    ));

    await tester.pumpWidget(
      const MaterialApp(home: ShapingStonePage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近日记可能提到了这一步'), findsOneWidget);
    expect(find.text('标记完成'), findsOneWidget);
  });

  testWidgets('edits shaping stone task title', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const StoneTaskRepository().saveTask(StoneTask(
      id: 'stone:edit',
      sourceEntryId: 'entry',
      title: '散步 10 分钟',
      description: '走一小圈即可。',
      createdAt: date,
      updatedAt: date,
    ));

    await tester.pumpWidget(
      const MaterialApp(home: ShapingStonePage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '散步 10 分钟'), '散步 15 分钟');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('散步 15 分钟'), findsOneWidget);
  });

  testWidgets('records shaping stone check-in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const StoneTaskRepository().saveTask(StoneTask(
      id: 'stone:checkin',
      sourceEntryId: 'entry',
      title: '散步 10 分钟',
      description: '走一小圈即可。',
      createdAt: date,
      updatedAt: date,
    ));

    await tester.pumpWidget(
      const MaterialApp(home: ShapingStonePage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录进展'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '今天散步了 8 分钟');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('进展 1 次'), findsOneWidget);
    expect(find.textContaining('今天散步了 8 分钟'), findsOneWidget);
  });

  testWidgets('adds calendar memory from settings page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: CalendarMemoryPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), '外婆生日');
    await tester.enterText(find.widgetWithText(TextField, '备注'), '重要家庭纪念日');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('外婆生日'), findsOneWidget);
    expect(find.text('重要家庭纪念日'), findsOneWidget);
  });

  testWidgets('adds lunar calendar memory from settings page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: CalendarMemoryPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), '农历生日');
    await tester.tap(find.text('农历'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('农历生日'), findsOneWidget);
    expect(find.textContaining('农历'), findsWidgets);
  });

  testWidgets('custom ai requires privacy confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: CustomAiPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(find.textContaining('自定义 AI 会把当前日记'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '接口 URL'),
      'https://api.example.com/v1',
    );
    await tester.enterText(find.widgetWithText(TextField, '秘钥'), 'test-key');
    await tester.enterText(find.widgetWithText(TextField, '模型'), 'test-model');
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();

    expect(find.text('使用第三方 AI？'), findsOneWidget);
    expect(find.textContaining('日记原文'), findsOneWidget);

    await tester.tap(find.text('我理解并继续'));
    await tester.pumpAndSettle();

    expect(find.text('已保存 AI 设置'), findsOneWidget);
  });

  testWidgets('custom ai settings ignore invalid stored preference types',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai.useOfficial': <String>['bad'],
      'ai.platform': <String>['OpenAI'],
      'ai.baseUrl': <String>['https://bad.example'],
      'ai.apiKey': <String>['bad-key'],
      'ai.model': <String>['bad-model'],
      'ai.customPrivacyAccepted': <String>['bad'],
    });

    await tester.pumpWidget(
      const MaterialApp(home: CustomAiPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('自定义 AI'), findsOneWidget);
    expect(find.text('使用官方 AI'), findsOneWidget);
    expect(find.text('gpt-4.1-mini'), findsOneWidget);
  });

  testWidgets('diary editor ignores invalid stored preference types',
      (tester) async {
    final date = DateTime(2026, 7, 3);
    SharedPreferences.setMockInitialValues({
      'diary.headingLevel': <String>['bad'],
      'diary.listStyle': <String>['bad'],
      'diary.autoSave': <String>['bad'],
      'diary.aiFix.useCustom': <String>['bad'],
      'diary.aiFix.customRule': <String>['bad'],
      'diary.recentLocations': 'bad',
    });
    await const DiaryRepository().saveEntry(DiaryEntry(
      id: 'editor-invalid-prefs',
      date: date,
      createdAt: date,
      content: '已有日记内容',
      location: '家',
      weather: '晴',
      temperature: '26',
      updatedAt: date,
    ));

    await tester.pumpWidget(MaterialApp(
      onGenerateRoute: (_) => MaterialPageRoute(
        settings: const RouteSettings(arguments: 'editor-invalid-prefs'),
        builder: (_) => const DiaryEditPage(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('日记'), findsWidgets);
    expect(find.textContaining('已有日记内容'), findsOneWidget);
  });

  testWidgets('diary editor queues AI pipeline when leaving with saved content',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'diary.autoSave': true,
    });
    const queueRepository = AiAnalysisQueueRepository();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const DiaryEditPage(),
          )),
          child: const Text('open editor'),
        ),
      ),
    ));
    await tester.tap(find.text('open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField).first, '今天散步后状态恢复。');
    await tester.pump();

    expect((await queueRepository.listJobs()), isEmpty);

    await tester.tap(find.byTooltip('返回'));
    await tester.pump(const Duration(milliseconds: 100));
    final jobs = await queueRepository.listJobs();
    final entries = await const DiaryRepository().listEntries();

    expect(entries.single.content, '今天散步后状态恢复。');
    expect(jobs.single.entryId, entries.single.id);
    expect(jobs.single.canRun, isTrue);
    expect(jobs.single.state, isNot(AiAnalysisJobState.completed));
  });

  testWidgets('relationships page filters and asks about a person',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'relationship-mom',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const ['妈妈'],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      relationshipUpdates: const [
        RelationshipUpdateCandidate(
          personName: '妈妈',
          relationship: 'family',
          summary: '晚饭后沟通更平和',
          emotion: '平和',
          pattern: '晚间沟通更顺畅',
          confidence: 0.64,
        ),
      ],
    ));
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'relationship-coworker',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const ['小林'],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      relationshipUpdates: const [
        RelationshipUpdateCandidate(
          personName: '小林',
          relationship: '同事',
          summary: '讨论产品方案',
          confidence: 0.58,
        ),
      ],
    ));

    await tester.pumpWidget(
      const MaterialApp(home: RelationshipsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('妈妈'), findsOneWidget);
    expect(find.text('小林'), findsOneWidget);
    expect(find.text('最近互动'), findsWidgets);
    expect(find.text('候选记录'), findsNothing);

    await tester.enterText(find.byType(SearchBar), '妈妈');
    await tester.pumpAndSettle();

    expect(find.text('找到 1 位相关人物'), findsOneWidget);
    expect(find.text('妈妈'), findsWidgets);
    expect(find.text('小林'), findsNothing);

    await tester.tap(find.text('询问这段关系'));
    await tester.pumpAndSettle();

    expect(find.byType(RelationshipsPage), findsNothing);
    expect(find.byType(CompanionPage), findsOneWidget);
  });

  testWidgets('corrects relationship type', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'relationship-correct',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const ['阿姨'],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      relationshipUpdates: const [
        RelationshipUpdateCandidate(
          personName: '阿姨',
          relationship: '未知',
          summary: '聊了身体情况',
          confidence: 0.58,
        ),
      ],
    ));

    await tester.pumpWidget(
      const MaterialApp(home: RelationshipsPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关系操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('修正关系'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '关系类型'), '家人');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('家人'), findsOneWidget);
    expect(find.text('已确认'), findsOneWidget);
  });

  testWidgets('relationships page shows evidence sources in developer mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'relationship-evidence',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '',
      keywords: const [],
      people: const ['妈妈'],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      relationshipUpdates: const [
        RelationshipUpdateCandidate(
          personName: '妈妈',
          relationship: 'family',
          summary: '晚饭后沟通更平和',
          confidence: 0.64,
        ),
      ],
    ));

    await tester.pumpWidget(
      const MaterialApp(home: RelationshipsPage()),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('最近互动'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近互动'));
    await tester.pumpAndSettle();

    expect(find.text('证据来源'), findsOneWidget);
    expect(find.textContaining('current_entry:relationship-evidence'),
        findsOneWidget);
  });

  testWidgets('search hides debug scores outside developer mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _seedSearchEntry();

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(SearchBar), '妈妈 散步');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('晚上散步'), findsWidgets);
    expect(find.textContaining('score'), findsNothing);
    expect(find.textContaining('entry_summary:search-entry'), findsNothing);
  });

  testWidgets('search shows profile relationship and stone sources',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: 'search-context',
      entryDate: date,
      generatedAt: date,
      reflection: '洞察',
      relatedMemories: const [],
      emotion: '平和',
      keywords: const ['散步'],
      people: const ['妈妈'],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
      profileUpdateCandidates: const [
        ProfileUpdateCandidate(
          field: 'self_regulation',
          value: '散步可能帮助恢复状态',
          confidence: 0.64,
        ),
      ],
      relationshipUpdates: const [
        RelationshipUpdateCandidate(
          personName: '妈妈',
          relationship: 'family',
          summary: '晚饭后沟通更平和',
          confidence: 0.64,
        ),
      ],
    ));
    await const StoneTaskRepository().saveTask(StoneTask(
      id: 'stone:search',
      sourceEntryId: 'search-context',
      title: '晚饭后散步 10 分钟',
      description: '走一小圈即可。',
      createdAt: date,
      updatedAt: date,
      tags: const ['散步'],
    ));

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(SearchBar), '妈妈 散步');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('self_regulation'), findsOneWidget);
    expect(find.text('妈妈'), findsOneWidget);
    expect(find.text('晚饭后散步 10 分钟'), findsOneWidget);

    await tester.tap(find.text('关系'));
    await tester.pumpAndSettle();

    expect(find.text('妈妈'), findsOneWidget);
    expect(find.text('self_regulation'), findsNothing);
    expect(find.text('晚饭后散步 10 分钟'), findsNothing);
  });

  testWidgets('search places long term memory matches under memory filter',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const MemoryRepository().saveMemory(MemoryEntry(
      id: 'memory-search-widget',
      sourceEntryId: 'memory-search-source',
      date: date,
      createdAt: date,
      summary: '骑车以后压力下降，整个人更放松。',
      keywords: const ['骑车', '压力', '放松'],
      emotion: '放松',
      people: const [],
      tags: const ['运动恢复'],
      importance: 0.78,
      confidence: 0.74,
    ));

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(SearchBar), '骑车 压力');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('运动恢复'), findsOneWidget);
    expect(find.text('长期记忆'), findsOneWidget);

    await tester.tap(find.text('日记'));
    await tester.pumpAndSettle();
    expect(find.text('运动恢复'), findsNothing);
    expect(find.text('暂时没有找到相关记录。'), findsOneWidget);

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    expect(find.text('运动恢复'), findsOneWidget);
  });

  testWidgets('search shows archived memory status in normal mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 7, 3);
    await const MemoryRepository().saveMemory(MemoryEntry(
      id: 'memory-archived-widget',
      sourceEntryId: 'memory-archived-source',
      date: date,
      createdAt: date,
      summary: '散步后焦虑下降，但这条记忆已归档。',
      keywords: const ['散步', '焦虑'],
      emotion: '放松',
      people: const [],
      tags: const ['运动恢复'],
      archived: true,
    ));

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(SearchBar), '散步 焦虑');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('运动恢复'), findsOneWidget);
    expect(find.text('已归档记忆'), findsOneWidget);
    expect(find.textContaining('score'), findsNothing);
  });

  testWidgets('search shows debug scores in developer mode', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    await _seedSearchEntry();

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(SearchBar), '妈妈 散步');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('晚上散步'), findsWidgets);
    expect(find.textContaining('score'), findsWidgets);
    expect(find.textContaining('entry_summary:search-entry'), findsWidgets);
    expect(find.textContaining('matched='), findsWidgets);
  });

  testWidgets('search developer mode copies debug context', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await _seedSearchEntry();

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(SearchBar), '散步 焦虑');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    expect(find.text('复制上下文'), findsOneWidget);
    await tester.tap(find.text('复制上下文'));
    await tester.pumpAndSettle();
    expect(find.text('复制搜索调试上下文？'), findsOneWidget);
    expect(copiedText, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, contains('## Summary'));
    expect(copiedText, contains('query=散步 焦虑'));
    expect(copiedText, contains('entry_summary:search-entry'));
    expect(copiedText, contains('evidence=current_entry:search-context'));
    expect(copiedText, contains('晚饭后散步后状态恢复'));
    expect(copiedText, contains('interaction=search-context'));
    expect(copiedText, contains('stone:search-debug'));
    expect(copiedText, contains('sourceEntry=search-context'));
    expect(copiedText, contains('checkIn=checkin:search-debug'));
    expect(copiedText, contains('## Retrieval Trace'));
  });

  testWidgets('AI debug page shows recent search and question retrieval traces',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await _seedSearchEntry();
    const builder = AiContextBuilder();
    await builder.buildForSearch('散步 焦虑');
    await builder.buildForQuestion('为什么散步后焦虑会下降');
    await builder.buildForPeriodSummary(
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 7, 31, 23, 59, 59),
    );
    final entries = await const DiaryRepository().listEntriesForMonth(
      DateTime(2026, 7),
    );
    await const PeriodSummaryService().buildMonthSummary(
      DateTime(2026, 7),
      entries,
    );

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();

    expect(find.text('最近检索上下文'), findsOneWidget);
    expect(find.textContaining('搜索:'), findsOneWidget);
    expect(find.textContaining('问答:'), findsOneWidget);
    expect(find.textContaining('周期总结:'), findsOneWidget);
    expect(find.textContaining('entry_summary:search-entry'), findsWidgets);
    expect(find.textContaining('segment:'), findsWidgets);
    expect(find.textContaining('entry_summary:'), findsWidgets);
    expect(find.textContaining('avg='), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, '复制').first);
    await tester.pumpAndSettle();
    expect(find.text('复制调试上下文？'), findsOneWidget);
    expect(copiedText, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(copiedText, contains('## Recent Retrieval Traces'));
    expect(copiedText, contains('### 搜索'));
    expect(copiedText, contains('### 问答'));
    expect(copiedText, contains('### 周期总结'));
    expect(copiedText, contains('entry_summary:search-entry'));
    expect(copiedText, contains('sources='));
    expect(copiedText, contains('signals='));
    expect(copiedText, contains('avg='));
    expect(copiedText, contains('max='));

    await tester.scrollUntilVisible(
      find.text('最近周期总结'),
      520,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('最近周期总结'), findsOneWidget);
    expect(find.textContaining('月度总结 2026-07'), findsOneWidget);
    expect(find.textContaining('context=periodSummary'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '复制总结'));
    await tester.pumpAndSettle();
    expect(find.text('复制调试上下文？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(copiedText, contains('## Recent Period Summaries'));
    expect(copiedText, contains('### 月度总结 2026-07'));
    expect(copiedText, contains('context=periodSummary'));
    expect(copiedText, contains('source=entry_summary:search-entry'));

    await tester.scrollUntilVisible(
      find.text('最近检索上下文'),
      -520,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '清除').first);
    await tester.pumpAndSettle();

    expect(find.text('最近检索上下文'), findsNothing);
  });

  testWidgets('AI debug page copies companion prompt trace', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await const AiPromptTraceRepository().saveTrace(AiPromptTrace(
      id: 'companion:last',
      scenario: 'question',
      createdAt: DateTime(2026, 7, 3),
      contextSummary: 'question sources=3',
      systemPromptPreview: 'system preview',
      userPromptPreview: 'user preview',
      systemPromptLength: 13,
      userPromptLength: 11,
      rawResponsePreview: '{"answer":"preview"}',
      rawResponseLength: 16,
      systemPrompt: '完整 system prompt',
      userPrompt: '完整 user prompt',
      rawResponse: '{"answer":"raw"}',
    ));

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();
    expect(find.text('最近陪伴问答'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '复制'));
    await tester.pumpAndSettle();
    expect(find.text('复制调试上下文？'), findsOneWidget);
    expect(copiedText, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, contains('## Companion Prompt Trace'));
    expect(copiedText, contains('context=question sources=3'));
    expect(copiedText, contains('SYSTEM:'));
    expect(copiedText, contains('完整 system prompt'));
    expect(copiedText, contains('USER:'));
    expect(copiedText, contains('完整 user prompt'));
    expect(copiedText, contains('RAW RESPONSE:'));
    expect(copiedText, contains('{"answer":"raw"}'));

    await tester.tap(find.widgetWithText(TextButton, '清除'));
    await tester.pumpAndSettle();

    expect(find.text('最近陪伴问答'), findsNothing);
  });

  testWidgets('AI debug page clears debug records without deleting artifacts',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const promptRepository = AiPromptTraceRepository();
    const retrievalRepository = AiRetrievalTraceRepository();
    const feedbackRepository = AiFeedbackRepository();
    const summaryRepository = EntrySummaryRepository();
    final date = DateTime(2026, 7, 3);
    final entry = DiaryEntry(
      id: 'debug-clear-entry',
      date: date,
      createdAt: date,
      content: '今天散步后状态放松了一些。',
      location: '',
      weather: '',
      temperature: null,
      updatedAt: date,
    );
    await const DiaryRepository().saveEntry(entry);
    final segments = const EntrySummaryService().buildSegments(entry);
    await summaryRepository.saveSummary(
      const EntrySummaryService().buildSummary(entry, segments),
    );
    await promptRepository.saveTrace(AiPromptTrace(
      id: 'companion:last',
      scenario: 'question',
      createdAt: date,
      contextSummary: 'question sources=1 sourceFiltered=1',
      systemPromptPreview: 'system',
      userPromptPreview: 'user',
      systemPromptLength: 6,
      userPromptLength: 4,
    ));
    await retrievalRepository.saveTrace(AiRetrievalTrace(
      entryId: 'search:last',
      generatedAt: date,
      scenario: 'search',
      contextSummary: 'search sources=1',
      sourceCount: 1,
      items: const [],
    ));
    await feedbackRepository.saveFeedback(AiFeedback(
      entryId: entry.id,
      value: AiFeedbackValue.inaccurate,
      createdAt: date,
      note: '来源不对',
    ));

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();
    expect(find.text('最近检索上下文'), findsOneWidget);
    expect(find.text('最近陪伴问答'), findsOneWidget);

    await tester.tap(find.byTooltip('清除调试记录'));
    await tester.pumpAndSettle();
    expect(find.text('清除 AI 调试记录？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '清除'));
    await tester.pumpAndSettle();

    expect(await promptRepository.getTrace('companion:last'), isNull);
    expect(await retrievalRepository.getTrace('search:last'), isNull);
    expect(await feedbackRepository.getFeedback(entry.id), isNull);
    expect(await summaryRepository.getSummary(entry.id), isNotNull);
    expect(find.text('最近检索上下文'), findsNothing);
    expect(find.text('最近陪伴问答'), findsNothing);
  });

  testWidgets('AI debug page copies AI data inventory', (tester) async {
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
      'ai.embeddings.summary:entry-1': '{}',
      'ai.promptTraces.companion:last': '{}',
      'ai.retrievalTraces.search:last': '{}',
      'ai.analysis.jobs.entry-1': '{}',
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
    });
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('AI 数据清单'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('AI 数据清单'), findsOneWidget);
    expect(find.text('日记摘要 1'), findsOneWidget);
    expect(find.text('向量索引 1'), findsOneWidget);
    expect(find.text('调试记录 2'), findsOneWidget);
    expect(find.text('纪念日 1'), findsOneWidget);
    expect(find.text('塑石行动 1'), findsOneWidget);
    expect(find.text('日记摘要'), findsOneWidget);
    expect(find.text('summaryObjects=1'), findsOneWidget);
    expect(find.textContaining('averageQuality=0.32'), findsOneWidget);
    expect(find.textContaining('lowQuality=1'), findsOneWidget);
    expect(find.text('warningSummaries=1'), findsOneWidget);
    expect(find.text('向量索引'), findsOneWidget);
    expect(find.text('objects=1'), findsWidgets);
    expect(find.text('纪念日'), findsOneWidget);
    expect(find.textContaining('lunar=1'), findsOneWidget);
    expect(find.text('塑石行动'), findsOneWidget);
    expect(find.textContaining('completed=1'), findsOneWidget);
    expect(find.textContaining('缺少 entry/type 索引'), findsOneWidget);
    expect(find.textContaining('高敏感类别'), findsOneWidget);
    expect(find.textContaining('调试记录可能包含 prompt'), findsOneWidget);
    await tester.tap(find.byTooltip('复制日记摘要清单'));
    await tester.pumpAndSettle();
    expect(find.text('复制调试上下文？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(copiedText, contains('### 日记摘要'));
    expect(copiedText, contains('summaryObjects=1'));
    expect(copiedText, isNot(contains('### 向量索引')));
    expect(find.text('已复制日记摘要清单'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('copy-ai-data-inventory')));
    await tester.pumpAndSettle();
    expect(find.text('复制调试上下文？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, contains('TraceStone AI Data Inventory'));
    expect(copiedText, contains('policy=AI 衍生数据默认视为日记数据的一部分'));
    expect(copiedText, contains('### 日记摘要'));
    expect(copiedText, contains('summaryObjects=1'));
    expect(copiedText, contains('warningSummaries=1'));
    expect(copiedText, contains('warnings=摘要过短:1,缺少关键点:1'));
    expect(copiedText, contains('### 向量索引'));
    expect(copiedText, contains('details=objects=1'));
    expect(copiedText, contains('warning=存在缺少 entry/type 索引的向量对象'));
    expect(copiedText, contains('### 纪念日'));
    expect(copiedText, contains('lunar=1'));
    expect(copiedText, contains('disabled=1'));
    expect(copiedText, contains('topMonths=lunar-5:1'));
    expect(copiedText, contains('### 塑石行动'));
    expect(copiedText, contains('completed=1'));
    expect(copiedText, contains('checkIns=1'));
    expect(copiedText, contains('topTags=恢复:1,运动:1'));
    expect(copiedText, contains('sensitivity=critical'));
    expect(copiedText, contains('backupPolicy=默认不建议云备份'));
  });

  testWidgets('AI debug page repairs embedding indexes', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai.embeddings.summary:entry-1': jsonEncode({
        'id': 'summary:entry-1',
        'sourceType': 'summary',
        'sourceId': 'entry-1',
        'entryId': 'entry-1',
        'modelId': 'test',
        'modelVersion': '1',
        'dimensions': 2,
        'vector': [0.1, 0.2],
        'generatedAt': '2026-07-03T00:00:00.000',
        'textHash': 'hash',
      }),
    });

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('AI 数据清单'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('缺少 entry/type 索引'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('repair-embedding-indexes')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('ai.embeddings.entryIndex.entry-1'),
        ['summary:entry-1']);
    expect(prefs.getStringList('ai.embeddings.typeIndex.summary'),
        ['summary:entry-1']);
    expect(find.textContaining('已修复向量索引'), findsOneWidget);
    expect(find.textContaining('缺少 entry/type 索引'), findsNothing);
    expect(find.text('向量索引 3'), findsOneWidget);
  });

  testWidgets('AI debug queue overview separates recoverable job states',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    const queueRepository = AiAnalysisQueueRepository();
    final date = DateTime(2026, 7, 3);
    await queueRepository.saveJob(AiAnalysisJob(
      id: 'debug-pending',
      entryId: 'debug-pending',
      pipelineVersion: 1,
      state: AiAnalysisJobState.pending,
      currentStage: AiAnalysisStage.queued,
      createdAt: date,
      updatedAt: date,
      batchId: 'batch-debug',
      batchLabel: '导入 2026 年日记',
    ));
    await queueRepository.saveJob(AiAnalysisJob(
      id: 'debug-incomplete',
      entryId: 'debug-incomplete',
      pipelineVersion: 1,
      state: AiAnalysisJobState.incomplete,
      currentStage: AiAnalysisStage.embedding,
      createdAt: date,
      updatedAt: date,
      batchId: 'batch-debug',
      batchLabel: '导入 2026 年日记',
      stageLogs: [
        AiAnalysisStageLog(
          stage: AiAnalysisStage.embedding,
          startedAt: date,
          message: '上次整理被系统中断',
          inputSummary: 'entry=debug-incomplete',
          outputSummary: 'summaryId=debug-incomplete',
          error: '超过 10 分钟未更新',
          retryCount: 1,
        ),
      ],
    ));
    await queueRepository.saveJob(AiAnalysisJob(
      id: 'debug-retryable-failed',
      entryId: 'debug-retryable-failed',
      pipelineVersion: 1,
      state: AiAnalysisJobState.failed,
      currentStage: AiAnalysisStage.retrieving,
      createdAt: date,
      updatedAt: date,
      retryCount: 2,
    ));
    await queueRepository.saveJob(AiAnalysisJob(
      id: 'debug-blocked-failed',
      entryId: 'debug-blocked-failed',
      pipelineVersion: 1,
      state: AiAnalysisJobState.failed,
      currentStage: AiAnalysisStage.generatingInsight,
      createdAt: date,
      updatedAt: date,
      retryCount: 3,
    ));

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();

    expect(find.text('队列概览'), findsOneWidget);
    expect(find.text('待开始 1'), findsOneWidget);
    expect(find.text('待恢复 1'), findsOneWidget);
    expect(find.text('可重试失败 1'), findsOneWidget);
    expect(find.text('失败 1'), findsOneWidget);
    expect(find.text('paused: false'), findsOneWidget);
    expect(find.text('remainingStages: 21'), findsOneWidget);
    expect(find.text('estimatedRemaining: 约 2 分钟'), findsOneWidget);
    expect(find.text('estimateSamples: 0'), findsOneWidget);
    expect(find.text('avgStageDuration: 约 8 秒'), findsOneWidget);
    expect(find.text('批次进度'), findsOneWidget);
    expect(find.text('导入 2026 年日记'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('待处理 2｜运行中 0｜失败 0'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '复制队列'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '继续队列'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '暂停队列'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '复制队列'));
    await tester.pumpAndSettle();
    expect(find.text('复制调试上下文？'), findsOneWidget);
    expect(copiedText, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('已复制队列审计'), findsOneWidget);
    expect(copiedText, contains('## AI Analysis Queue Audit'));
    expect(copiedText, contains('paused=false'));
    expect(copiedText, contains('states=pending:1,running:0,incomplete:1'));
    expect(copiedText, contains('## Batches'));
    expect(copiedText, contains('batch-debug 导入 2026 年日记'));
    expect(copiedText, contains('debug-incomplete'));
    expect(copiedText, contains('stageLogs=1'));
    expect(copiedText, contains('上次整理被系统中断'));
    expect(copiedText, contains('error=超过 10 分钟未更新'));
  });

  testWidgets('AI debug page shows inaccurate feedback and requeue trace',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final date = DateTime(2026, 7, 3);
    final entry = DiaryEntry(
      id: 'debug-feedback-entry',
      date: date,
      createdAt: date,
      content: '今天的洞察判断不太准确。',
      location: '未选择地点',
      weather: '晴',
      temperature: '26',
      updatedAt: date,
    );
    await const DiaryRepository().saveEntry(entry);
    await const InsightRepository().saveInsight(DiaryInsight(
      entryId: entry.id,
      entryDate: date,
      generatedAt: date,
      reflection: '旧洞察',
      relatedMemories: const [],
      emotion: '平静',
      keywords: const [],
      people: const [],
      stoneTitle: '',
      stoneDescription: '',
      memorySummary: '',
      memoryTags: const [],
    ));
    await const AiFeedbackService().submitInsightFeedback(
      entryId: entry.id,
      value: AiFeedbackValue.inaccurate,
      note: '把情绪判断错了',
    );

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('用户标记洞察不准确'), findsWidgets);
    expect(find.textContaining('value=inaccurate'), findsOneWidget);
    expect(find.textContaining('note=把情绪判断错了'), findsWidgets);

    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, '复制上下文').first,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '复制上下文').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, contains('## AI Pipeline Job'));
    expect(copiedText, contains('用户标记洞察不准确，重新生成今日洞察'));
    expect(copiedText, contains('value=inaccurate'));
    expect(copiedText, contains('note=把情绪判断错了'));
  });

  testWidgets('AI debug page rebuilds embeddings from job actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const diaryRepository = DiaryRepository();
    const summaryRepository = EntrySummaryRepository();
    const queueRepository = AiAnalysisQueueRepository();
    final date = DateTime(2026, 7, 3);
    final entry = DiaryEntry(
      id: 'debug-partial-rebuild-entry',
      date: date,
      createdAt: date,
      content: '今天散步以后，焦虑下降了一些。',
      location: '未选择地点',
      weather: '晴',
      temperature: '26',
      updatedAt: date,
    );
    await diaryRepository.saveEntry(entry);
    final segments = const EntrySummaryService().buildSegments(entry);
    await summaryRepository.saveSegments(entry.id, segments);
    await summaryRepository.saveSummary(
      const EntrySummaryService().buildSummary(entry, segments),
    );
    await queueRepository.enqueueEntry(entry);

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('局部重建'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '局部重建'));
    await tester.pumpAndSettle();

    expect(find.text('局部重建本篇资料'), findsOneWidget);
    expect(find.text('摘要和片段'), findsOneWidget);
    expect(find.text('多级向量'), findsOneWidget);
    expect(find.text('今日洞察'), findsOneWidget);
    await tester.tap(find.text('多级向量'));
    await tester.pumpAndSettle();

    final job = await queueRepository.getJob(entry.id);
    expect(find.text('已重建多级向量'), findsOneWidget);
    expect(job?.stageLogs.last.message, '开发者重建多级向量');
    expect(job?.embeddingIds, contains('entry:${entry.id}'));
  });

  testWidgets('corrects entry summary from AI debug page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    const diaryRepository = DiaryRepository();
    const summaryRepository = EntrySummaryRepository();
    const queueRepository = AiAnalysisQueueRepository();
    final date = DateTime(2026, 7, 3);
    final entry = DiaryEntry(
      id: 'debug-summary-entry',
      date: date,
      createdAt: date,
      content: '今天散步以后，焦虑下降了一些。',
      location: '未选择地点',
      weather: '晴',
      temperature: '26',
      updatedAt: date,
    );
    await diaryRepository.saveEntry(entry);
    final segments = const EntrySummaryService().buildSegments(entry);
    await summaryRepository.saveSummary(
      const EntrySummaryService().buildSummary(entry, segments),
    );
    await queueRepository.enqueueEntry(entry);

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('修正摘要'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修正摘要'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '更准确的日记摘要'),
      '晚上散步后，焦虑感有所下降。',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '摘要标题'),
      '散步恢复',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '情绪'),
      '放松',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '重要度 0-1'),
      '0.91',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '关键点（每行一条）'),
      '完成散步\n焦虑下降',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '重要原文短句（每行一条）'),
      '走完以后轻松一点',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final summary = await summaryRepository.getSummary(entry.id);
    final job = await queueRepository.getJob(entry.id);
    expect(summary?.brief, '晚上散步后，焦虑感有所下降。');
    expect(summary?.title, '散步恢复');
    expect(summary?.emotion, '放松');
    expect(summary?.importance, 0.91);
    expect(summary?.keyPoints, ['完成散步', '焦虑下降']);
    expect(summary?.importantQuotes, ['走完以后轻松一点']);
    expect(summary?.generator, 'user-corrected');
    expect(job?.stageLogs.map((log) => log.message), contains('用户修正摘要包'));

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('详情').first,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('详情').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('summary keyPoints'), findsOneWidget);
    expect(find.textContaining('summary quality:'), findsOneWidget);
    expect(find.textContaining('summary revisionHistory'), findsOneWidget);
    expect(find.textContaining('完成散步；焦虑下降'), findsOneWidget);
    expect(find.textContaining('summary quotes'), findsOneWidget);
    expect(find.textContaining('summary:debug-summary-entry'), findsWidgets);
    expect(find.textContaining('entry:debug-summary-entry'), findsWidgets);
    expect(find.textContaining('hash='), findsWidgets);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '复制上下文').first);
    await tester.pumpAndSettle();
    expect(find.text('复制调试上下文？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, contains('## AI Pipeline Job'));
    expect(copiedText, contains('entryId=debug-summary-entry'));
    expect(copiedText, contains('## Stage Logs'));
    expect(copiedText, contains('用户修正摘要包'));
    expect(copiedText, contains('## Context'));
    expect(copiedText, contains('summary:debug-summary-entry'));
    expect(copiedText, contains('entry:debug-summary-entry'));
  });
}

Future<void> _seedSearchEntry() async {
  const diaryRepository = DiaryRepository();
  const summaryRepository = EntrySummaryRepository();
  final date = DateTime(2026, 7, 3);
  final entry = DiaryEntry(
    id: 'search-entry',
    date: date,
    createdAt: date,
    content: '晚上散步以后，焦虑下降了一些。',
    location: '未选择地点',
    weather: '晴',
    temperature: '26',
    updatedAt: date,
  );
  await diaryRepository.saveEntry(entry);
  final segments = const EntrySummaryService().buildSegments(entry);
  await summaryRepository.saveSegments(entry.id, segments);
  await summaryRepository.saveSummary(
    const EntrySummaryService().buildSummary(entry, segments),
  );
  await const InsightRepository().saveInsight(DiaryInsight(
    entryId: 'search-context',
    entryDate: date,
    generatedAt: date,
    reflection: '搜索调试上下文',
    relatedMemories: const [],
    emotion: '放松',
    keywords: const ['散步', '焦虑'],
    people: const ['妈妈'],
    stoneTitle: '',
    stoneDescription: '',
    memorySummary: '',
    memoryTags: const [],
    profileUpdateCandidates: const [
      ProfileUpdateCandidate(
        field: 'self_regulation',
        value: '散步可能帮助恢复状态',
        confidence: 0.64,
        evidence: [
          InsightEvidence(
            type: 'current_entry',
            id: 'search-context',
            summary: '晚饭后散步后状态恢复',
          ),
        ],
      ),
    ],
    relationshipUpdates: const [
      RelationshipUpdateCandidate(
        personName: '妈妈',
        relationship: 'family',
        summary: '晚饭后沟通更平和',
        confidence: 0.64,
        evidence: [
          InsightEvidence(
            type: 'current_entry',
            id: 'search-context',
            summary: '和妈妈晚饭后沟通更平和',
          ),
        ],
      ),
    ],
  ));
  await const StoneTaskRepository().saveTask(StoneTask(
    id: 'stone:search-debug',
    sourceEntryId: 'search-context',
    title: '晚饭后散步 10 分钟',
    description: '走一小圈即可。',
    createdAt: date,
    updatedAt: date,
    tags: const ['散步'],
    checkIns: [
      StoneTaskCheckIn(
        id: 'checkin:search-debug',
        createdAt: date,
        note: '完成了一次散步',
        sourceEntryId: 'search-context',
      ),
    ],
  ));
}
