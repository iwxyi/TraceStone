import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trace_stone/app/trace_stone_app.dart';
import 'package:trace_stone/data/models/diary_entry.dart';
import 'package:trace_stone/data/models/diary_insight.dart';
import 'package:trace_stone/data/models/memory_entry.dart';
import 'package:trace_stone/data/models/stone_task.dart';
import 'package:trace_stone/data/repositories/diary_repository.dart';
import 'package:trace_stone/data/repositories/entry_summary_repository.dart';
import 'package:trace_stone/data/repositories/insight_repository.dart';
import 'package:trace_stone/data/repositories/memory_repository.dart';
import 'package:trace_stone/data/repositories/stone_task_repository.dart';
import 'package:trace_stone/data/services/entry_summary_service.dart';
import 'package:trace_stone/features/companion/presentation/companion_page.dart';
import 'package:trace_stone/features/relationships/presentation/relationships_page.dart';
import 'package:trace_stone/features/settings/presentation/calendar_memory_page.dart';
import 'package:trace_stone/features/settings/presentation/custom_ai_page.dart';
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
