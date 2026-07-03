import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trace_stone/data/models/diary_entry.dart';
import 'package:trace_stone/data/models/diary_segment.dart';
import 'package:trace_stone/data/models/period_summary.dart';
import 'package:trace_stone/data/repositories/diary_repository.dart';
import 'package:trace_stone/data/services/embedding_service.dart';
import 'package:trace_stone/data/services/entry_summary_service.dart';
import 'package:trace_stone/data/services/period_summary_service.dart';

void main() {
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
        content: '今天跑步，也整理了产品计划。',
        location: '上海',
      );
      final segments = const EntrySummaryService().buildSegments(entry);

      final summary = const EntrySummaryService().buildSummary(entry, segments);

      expect(summary.entryId, entry.id);
      expect(summary.brief, contains('今天跑步'));
      expect(summary.keyPoints, isNotEmpty);
      expect(summary.places, contains('上海'));
      expect(summary.generator, 'local-rule-v1');
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
  });

  group('DiaryRepository trash', () {
    test('ignores trash index key when scanning trash items', () async {
      SharedPreferences.setMockInitialValues({
        'diary.trash.index': <String>['index'],
      });

      final items = await const DiaryRepository().listTrashEntries();

      expect(items, isEmpty);
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
