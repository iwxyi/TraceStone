import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trace_stone/data/models/ai_analysis_job.dart';
import 'package:trace_stone/data/services/diary_import_export_service.dart';
import 'package:trace_stone/data/repositories/ai_analysis_queue_repository.dart';
import 'package:trace_stone/data/repositories/diary_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('parses full date headings with titles', () {
    final service = const DiaryImportExportService();
    final template = DiaryImportExportService.templateFor(
      DiaryImportFormat.dottedDate,
    );

    final preview = service.previewText(
      text: '2026.01.01 新年\n今天开始写。\n\n2026.01.02\n继续记录。',
      pattern: template.pattern,
    );

    expect(preview.drafts, hasLength(2));
    expect(preview.drafts.first.date.year, 2026);
    expect(preview.drafts.first.title, '新年');
    expect(preview.drafts.first.content, contains('# 新年'));
    expect(preview.drafts.last.content, '继续记录。');
  });

  test('infers year for month-day headings when month rolls over', () {
    final service = const DiaryImportExportService();
    final template = DiaryImportExportService.templateFor(
      DiaryImportFormat.dottedDateWithoutYear,
    );

    final preview = service.previewText(
      text: '12.31 年末\n旧年的最后一天。\n01.01 新年\n新的开始。',
      pattern: template.pattern,
      startYear: 2025,
    );

    expect(preview.drafts.first.date.year, 2025);
    expect(preview.drafts.first.date.month, 12);
    expect(preview.drafts.last.date.year, 2026);
    expect(preview.drafts.last.date.month, 1);
  });

  test('parses markdown date headings without splitting body headings', () {
    final service = const DiaryImportExportService();
    final template = DiaryImportExportService.templateFor(
      DiaryImportFormat.markdownHeading,
    );

    final preview = service.previewText(
      text: '# 2026.01.01 新年\n今天开始。\n\n# 今日感受\n这个标题属于正文。\n\n'
          '## 2026年1月2日\n继续写。',
      pattern: template.pattern,
    );

    expect(preview.drafts, hasLength(2));
    expect(preview.drafts.first.date.day, 1);
    expect(preview.drafts.first.title, '新年');
    expect(preview.drafts.first.content, contains('今天开始。'));
    expect(preview.drafts.first.content, contains('# 今日感受'));
    expect(preview.drafts.last.date.day, 2);
    expect(preview.drafts.last.title, isEmpty);
  });

  test('parses json arrays and wrapped entry lists', () {
    final service = const DiaryImportExportService();

    final arrayPreview = service.previewJson(jsonEncode([
      {
        'date': '2026-01-01',
        'title': '新年',
        'content': '今天开始记录。',
      },
      {
        'creationDate': '2026-01-02T08:30:00',
        'text': '继续写。',
      },
    ]));
    final wrappedPreview = service.previewJson(jsonEncode({
      'entries': [
        {
          'createdAt': '2026年1月3日',
          'body': '第三篇。',
        }
      ],
    }));

    expect(arrayPreview.drafts, hasLength(2));
    expect(arrayPreview.drafts.first.title, '新年');
    expect(arrayPreview.drafts.last.date.day, 2);
    expect(wrappedPreview.drafts.single.date.day, 3);
  });

  test('parses csv with automatic and manual column mapping', () {
    final service = const DiaryImportExportService();
    final data = service.inspectCsv(
      'date,title,content\n'
      '2026-01-01,新年,"今天吃了饭, 也去散步。"\n'
      '2026-01-02,,继续写。\n',
    );

    expect(data.mapping.dateColumn, 'date');
    expect(data.mapping.contentColumn, 'content');
    final preview = service.previewCsv(data, data.mapping);

    expect(preview.drafts, hasLength(2));
    expect(preview.drafts.first.content, contains('今天吃了饭, 也去散步。'));
    expect(preview.drafts.last.title, isEmpty);
  });

  test('imports drafts and queues diary analysis jobs', () async {
    final diaryRepository = const DiaryRepository();
    final queueRepository = const AiAnalysisQueueRepository();
    final service = DiaryImportExportService(
      diaryRepository: diaryRepository,
      queueRepository: queueRepository,
    );
    final preview = service.previewText(
      text: '【2026.01.01】第一天\n吃了早饭。\n【2026.01.02】第二天\n去散步。',
      pattern: DiaryImportExportService.templateFor(
        DiaryImportFormat.bracketedDottedDate,
      ).pattern,
    );

    final result = await service.importDrafts(preview.drafts);
    final entries = await diaryRepository.listEntries();
    final jobs = await queueRepository.listJobs();

    expect(result.importedCount, 2);
    expect(entries, hasLength(2));
    expect(
        jobs.where((job) => job.type == AiAnalysisJobType.diary), hasLength(2));
  });

  test('imports large batches through bulk save and queue path', () async {
    final diaryRepository = const DiaryRepository();
    final queueRepository = const AiAnalysisQueueRepository();
    final service = DiaryImportExportService(
      diaryRepository: diaryRepository,
      queueRepository: queueRepository,
    );
    final buffer = StringBuffer();
    final start = DateTime(2026);
    for (var index = 1; index <= 1200; index++) {
      final date = start.add(Duration(days: index - 1));
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      buffer.writeln('${date.year}.$month.$day 第 $index 篇');
      buffer.writeln('这是第 $index 篇批量导入测试日记。');
    }

    final preview = service.previewText(
      text: buffer.toString(),
      pattern: DiaryImportExportService.templateFor(
        DiaryImportFormat.dottedDate,
      ).pattern,
    );
    final result = await service.importDrafts(preview.drafts);
    final entries = await diaryRepository.listEntries();
    final jobs = await queueRepository.listJobs();

    expect(preview.drafts, hasLength(1200));
    expect(result.importedCount, 1200);
    expect(entries, hasLength(1200));
    expect(
      jobs.where((job) => job.type == AiAnalysisJobType.diary),
      hasLength(1200),
    );
  });

  test('exports text and json payloads', () async {
    final diaryRepository = const DiaryRepository();
    final service = DiaryImportExportService(diaryRepository: diaryRepository);
    final preview = service.previewText(
      text: '2026年1月1日 元旦\n记录一句话。',
      pattern: DiaryImportExportService.templateFor(
        DiaryImportFormat.chineseDate,
      ).pattern,
    );
    await service.importDrafts(preview.drafts);

    final text = await service.buildExport(DiaryExportFormat.shinenText);
    final json = await service.buildExport(DiaryExportFormat.json);

    expect(utf8.decode(text.bytes), contains('【2026.01.01】'));
    final decoded = jsonDecode(utf8.decode(json.bytes)) as Map<String, dynamic>;
    expect(decoded['app'], 'Shinen');
    expect(decoded['entries'], isA<List<dynamic>>());
  });
}
