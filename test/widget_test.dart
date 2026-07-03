import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trace_stone/app/trace_stone_app.dart';
import 'package:trace_stone/data/models/diary_entry.dart';
import 'package:trace_stone/data/models/diary_insight.dart';
import 'package:trace_stone/data/models/ai_prompt_trace.dart';
import 'package:trace_stone/data/models/memory_entry.dart';
import 'package:trace_stone/data/models/stone_task.dart';
import 'package:trace_stone/data/repositories/ai_analysis_queue_repository.dart';
import 'package:trace_stone/data/repositories/ai_prompt_trace_repository.dart';
import 'package:trace_stone/data/repositories/diary_repository.dart';
import 'package:trace_stone/data/repositories/entry_summary_repository.dart';
import 'package:trace_stone/data/repositories/insight_repository.dart';
import 'package:trace_stone/data/repositories/memory_repository.dart';
import 'package:trace_stone/data/repositories/stone_task_repository.dart';
import 'package:trace_stone/data/services/ai_context_builder.dart';
import 'package:trace_stone/data/services/entry_summary_service.dart';
import 'package:trace_stone/data/services/period_summary_service.dart';
import 'package:trace_stone/features/companion/presentation/companion_page.dart';
import 'package:trace_stone/features/relationships/presentation/relationships_page.dart';
import 'package:trace_stone/features/settings/presentation/calendar_memory_page.dart';
import 'package:trace_stone/features/settings/presentation/custom_ai_page.dart';
import 'package:trace_stone/features/settings/presentation/ai_debug_page.dart';
import 'package:trace_stone/features/settings/presentation/memory_management_page.dart';
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

    expect(find.text('画像候选'), findsOneWidget);
    expect(find.text('self_regulation'), findsOneWidget);
    expect(find.textContaining('运动可能帮助恢复状态'), findsOneWidget);
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

  testWidgets('search hides debug scores outside developer mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _seedSearchEntry();

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(SearchBar), '散步 焦虑');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('晚上散步'), findsWidgets);
    expect(find.textContaining('score'), findsNothing);
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

  testWidgets('search shows debug scores in developer mode', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.developerMode': true,
    });
    await _seedSearchEntry();

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(SearchBar), '散步 焦虑');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining('晚上散步'), findsWidgets);
    expect(find.textContaining('score'), findsWidgets);
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
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, contains('## Summary'));
    expect(copiedText, contains('query=散步 焦虑'));
    expect(copiedText, contains('entry_summary:search-entry'));
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
    await tester.tap(find.widgetWithText(TextButton, '复制').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(copiedText, contains('## Recent Retrieval Traces'));
    expect(copiedText, contains('### 搜索'));
    expect(copiedText, contains('### 问答'));
    expect(copiedText, contains('### 周期总结'));
    expect(copiedText, contains('entry_summary:search-entry'));

    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('最近周期总结'), findsOneWidget);
    expect(find.textContaining('月度总结 2026-07'), findsOneWidget);
    expect(find.textContaining('context=periodSummary'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '复制总结'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(copiedText, contains('## Recent Period Summaries'));
    expect(copiedText, contains('### 月度总结 2026-07'));
    expect(copiedText, contains('context=periodSummary'));

    await tester.drag(find.byType(ListView), const Offset(0, 520));
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
      systemPrompt: '完整 system prompt',
      userPrompt: '完整 user prompt',
    ));

    await tester.pumpWidget(const MaterialApp(home: AiDebugPage()));
    await tester.pumpAndSettle();
    expect(find.text('最近陪伴问答'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '复制'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, contains('## Companion Prompt Trace'));
    expect(copiedText, contains('context=question sources=3'));
    expect(copiedText, contains('SYSTEM:'));
    expect(copiedText, contains('完整 system prompt'));
    expect(copiedText, contains('USER:'));
    expect(copiedText, contains('完整 user prompt'));

    await tester.tap(find.widgetWithText(TextButton, '清除'));
    await tester.pumpAndSettle();

    expect(find.text('最近陪伴问答'), findsNothing);
  });

  testWidgets('corrects entry summary from AI debug page', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
    expect(find.textContaining('完成散步；焦虑下降'), findsOneWidget);
    expect(find.textContaining('summary quotes'), findsOneWidget);
    expect(find.textContaining('summary:debug-summary-entry'), findsWidgets);
    expect(find.textContaining('entry:debug-summary-entry'), findsWidgets);
    expect(find.textContaining('hash='), findsWidgets);
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
}
