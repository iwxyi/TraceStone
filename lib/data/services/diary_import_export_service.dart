import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../repositories/ai_analysis_queue_repository.dart';
import '../repositories/diary_repository.dart';

enum DiaryImportFormat {
  shinenText,
  markdownHeading,
  dottedDate,
  dottedDateWithoutYear,
  chineseDate,
  bracketedDottedDate,
  custom,
}

enum DiaryImportMode {
  text,
  json,
  csv,
}

enum DiaryExportFormat {
  shinenText,
  json,
}

class DiaryImportTemplate {
  const DiaryImportTemplate({
    required this.format,
    required this.label,
    required this.description,
    required this.example,
    required this.pattern,
    required this.requiresStartYear,
  });

  final DiaryImportFormat format;
  final String label;
  final String description;
  final String example;
  final String pattern;
  final bool requiresStartYear;
}

class DiaryImportExportService {
  const DiaryImportExportService({
    DiaryRepository? diaryRepository,
    AiAnalysisQueueRepository? queueRepository,
  })  : _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _queueRepository = queueRepository ?? const AiAnalysisQueueRepository();

  final DiaryRepository _diaryRepository;
  final AiAnalysisQueueRepository _queueRepository;

  static const templates = [
    DiaryImportTemplate(
      format: DiaryImportFormat.markdownHeading,
      label: 'Markdown 标题',
      description: '用 # 日期标题分隔日记，正文里的普通 # 标题会保留',
      example: '# 2026.01.01 新年\n今天开始记录。\n\n# 今日感受\n正文里的标题不会分隔日记。',
      pattern:
          r'^\s*#{1,6}\s+【?(?<year>\d{4})(?:[.\-/]|年)(?<month>\d{1,2})(?:[.\-/]|月)(?<day>\d{1,2})日?】?\s*(?<title>.*)$',
      requiresStartYear: false,
    ),
    DiaryImportTemplate(
      format: DiaryImportFormat.dottedDate,
      label: '完整点号日期',
      description: '标题行直接使用 yyyy.MM.dd',
      example: '2026.01.01 新年\n今天开始重新记录。',
      pattern:
          r'^\s*【?(?<year>\d{4})\.(?<month>\d{1,2})\.(?<day>\d{1,2})】?\s*(?<title>.*)$',
      requiresStartYear: false,
    ),
    DiaryImportTemplate(
      format: DiaryImportFormat.dottedDateWithoutYear,
      label: '省略年份日期',
      description: '标题行只有 MM.dd，需要填写起始年份',
      example: '12.31 年末\n旧年的最后一天。\n01.01 新年\n新的开始。',
      pattern: r'^\s*【?(?<month>\d{1,2})\.(?<day>\d{1,2})】?\s*(?<title>.*)$',
      requiresStartYear: true,
    ),
    DiaryImportTemplate(
      format: DiaryImportFormat.chineseDate,
      label: '中文日期',
      description: '标题行使用中文年月日',
      example: '2026年1月1日 新年\n今天开始重新记录。',
      pattern:
          r'^\s*【?(?<year>\d{4})年(?<month>\d{1,2})月(?<day>\d{1,2})日?】?\s*(?<title>.*)$',
      requiresStartYear: false,
    ),
    DiaryImportTemplate(
      format: DiaryImportFormat.bracketedDottedDate,
      label: '方括号日期',
      description: '标题行用方括号包住日期',
      example: '【2026.01.01】新年\n今天开始重新记录。',
      pattern:
          r'^\s*【(?<year>\d{4})\.(?<month>\d{1,2})\.(?<day>\d{1,2})】\s*(?<title>.*)$',
      requiresStartYear: false,
    ),
  ];

  static DiaryImportTemplate templateFor(DiaryImportFormat format) {
    return templates.firstWhere(
      (template) => template.format == format,
      orElse: () => templates.first,
    );
  }

  DiaryImportPreview previewText({
    required String text,
    required String pattern,
    int? startYear,
  }) {
    final lines = const LineSplitter().convert(text);
    return previewLines(
      lines: lines,
      pattern: pattern,
      startYear: startYear,
    );
  }

  DiaryImportPreview previewLines({
    required Iterable<String> lines,
    required String pattern,
    int? startYear,
  }) {
    final regex = _compile(pattern);
    final drafts = <DiaryImportDraft>[];
    _PendingImport? pending;
    var inferredYear = startYear;
    int? previousMonth;

    for (final line in lines) {
      final match = regex.firstMatch(line);
      if (match == null) {
        if (line.trim() == '---') continue;
        pending?.lines.add(line);
        continue;
      }
      if (pending != null) {
        drafts.add(pending.toDraft());
      }
      final month = _parseMonth(match);
      final day = _parseDay(match);
      final explicitYear = _parseYear(match);
      if (explicitYear == null && inferredYear == null) {
        throw const DiaryImportException('当前格式没有年份，需要填写起始年份');
      }
      if (explicitYear == null &&
          previousMonth != null &&
          month < previousMonth) {
        inferredYear = inferredYear! + 1;
      }
      previousMonth = month;
      final year = explicitYear ?? inferredYear!;
      final date = _date(year, month, day);
      pending = _PendingImport(
        date: date,
        title: _named(match, 'title')?.trim() ?? '',
        lines: <String>[],
      );
    }
    if (pending != null) {
      drafts.add(pending.toDraft());
    }
    if (drafts.isEmpty) {
      throw const DiaryImportException('没有识别到日记，请检查日期标题或正则表达式');
    }
    return DiaryImportPreview(drafts: drafts);
  }

  DiaryImportPreview previewJson(String source) {
    final decoded = jsonDecode(source);
    final records = _jsonRecords(decoded);
    final drafts = <DiaryImportDraft>[];
    for (final record in records) {
      final date = _parseFlexibleDate(_firstString(record, const [
        'date',
        'creationDate',
        'createdAt',
        'created',
        'timestamp',
      ]));
      if (date == null) continue;
      final title = _firstString(record, const ['title', 'subject']) ?? '';
      final body = _firstString(record, const [
            'content',
            'text',
            'body',
            'note',
            'journalText',
          ]) ??
          '';
      if (body.trim().isEmpty && title.trim().isEmpty) continue;
      drafts.add(_draft(date: date, title: title, body: body));
    }
    if (drafts.isEmpty) {
      throw const DiaryImportException('JSON 中没有识别到可导入的日期和正文');
    }
    return DiaryImportPreview(drafts: drafts);
  }

  DiaryCsvImportData inspectCsv(String source) {
    final rows = _parseCsv(source);
    if (rows.isEmpty) {
      throw const DiaryImportException('CSV 文件为空');
    }
    final headers = rows.first;
    if (headers.isEmpty) {
      throw const DiaryImportException('CSV 缺少表头');
    }
    final mapping = DiaryCsvMapping(
      dateColumn: _findColumn(headers, const [
        'date',
        '日期',
        'created',
        'createdat',
        'timestamp',
      ]),
      contentColumn: _findColumn(headers, const [
        'content',
        'text',
        'body',
        'note',
        '日记',
        '正文',
      ]),
      titleColumn: _findColumn(headers, const ['title', 'subject', '标题']),
    );
    return DiaryCsvImportData(
      headers: headers,
      rows: rows.skip(1).toList(growable: false),
      mapping: mapping,
    );
  }

  DiaryImportPreview previewCsv(
    DiaryCsvImportData data,
    DiaryCsvMapping mapping,
  ) {
    if (mapping.dateColumn == null || mapping.contentColumn == null) {
      throw const DiaryImportException('CSV 至少需要映射日期列和正文列');
    }
    final dateIndex = data.headers.indexOf(mapping.dateColumn!);
    final contentIndex = data.headers.indexOf(mapping.contentColumn!);
    final titleIndex = mapping.titleColumn == null
        ? -1
        : data.headers.indexOf(mapping.titleColumn!);
    final drafts = <DiaryImportDraft>[];
    for (final row in data.rows) {
      final date = _parseFlexibleDate(_cell(row, dateIndex));
      if (date == null) continue;
      final body = _cell(row, contentIndex);
      final title = titleIndex < 0 ? '' : _cell(row, titleIndex);
      if (body.trim().isEmpty && title.trim().isEmpty) continue;
      drafts.add(_draft(date: date, title: title, body: body));
    }
    if (drafts.isEmpty) {
      throw const DiaryImportException('CSV 中没有识别到可导入的日期和正文');
    }
    return DiaryImportPreview(drafts: drafts);
  }

  Future<DiaryImportResult> importDrafts(List<DiaryImportDraft> drafts) async {
    final now = DateTime.now();
    final batchId = 'import:${now.microsecondsSinceEpoch}';
    final batchLabel = '导入 ${drafts.length} 篇日记';
    final entries = drafts
        .map(
          (draft) => DiaryEntry(
            id: const Uuid().v4(),
            date: draft.date,
            createdAt: now,
            content: draft.content,
            location: '未选择地点',
            weather: '天气',
            temperature: null,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    await _diaryRepository.saveImportedEntries(entries);
    await _queueRepository.enqueueEntries(
      entries,
      batchId: batchId,
      batchLabel: batchLabel,
    );
    return DiaryImportResult(importedCount: entries.length, batchId: batchId);
  }

  Future<DiaryExportPayload> buildExport(DiaryExportFormat format) async {
    final entries = await _diaryRepository.listEntries();
    final ordered = entries.toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.createdAt.compareTo(b.createdAt);
      });
    final now = DateTime.now();
    return switch (format) {
      DiaryExportFormat.shinenText => DiaryExportPayload(
          fileName: 'shinen-diaries-${DiaryEntry.dateKey(now)}.txt',
          extension: 'txt',
          bytes: utf8.encode(_buildTextExport(ordered)),
        ),
      DiaryExportFormat.json => DiaryExportPayload(
          fileName: 'shinen-diaries-${DiaryEntry.dateKey(now)}.json',
          extension: 'json',
          bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert({
            'app': 'Shinen',
            'exportedAt': now.toIso8601String(),
            'entries': ordered.map((entry) => entry.toJson()).toList(),
          })),
        ),
    };
  }

  RegExp _compile(String pattern) {
    try {
      final regex = RegExp(pattern, multiLine: false);
      final test = regex.firstMatch('2026.01.01');
      test?.namedGroup('month');
      test?.namedGroup('day');
      return regex;
    } on Object catch (error) {
      throw DiaryImportException('正则表达式不可用：$error');
    }
  }

  int? _parseYear(RegExpMatch match) {
    final raw = _named(match, 'year');
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  int _parseMonth(RegExpMatch match) {
    final raw = _named(match, 'month');
    final value = int.tryParse(raw ?? '');
    if (value == null) throw const DiaryImportException('正则缺少 month 分组');
    return value;
  }

  int _parseDay(RegExpMatch match) {
    final raw = _named(match, 'day');
    final value = int.tryParse(raw ?? '');
    if (value == null) throw const DiaryImportException('正则缺少 day 分组');
    return value;
  }

  DateTime _date(int year, int month, int day) {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw DiaryImportException('日期无效：$year-$month-$day');
    }
    return date;
  }

  String? _named(RegExpMatch match, String name) {
    try {
      return match.namedGroup(name);
    } on Object {
      return null;
    }
  }

  String _buildTextExport(List<DiaryEntry> entries) {
    return entries.map((entry) {
      final month = entry.date.month.toString().padLeft(2, '0');
      final day = entry.date.day.toString().padLeft(2, '0');
      return '【${entry.date.year}.$month.$day】\n\n${entry.content.trim()}';
    }).join('\n\n---\n\n');
  }

  List<Map<String, dynamic>> _jsonRecords(Object? value) {
    if (value is List) {
      return value.whereType<Map>().map(_mapJson).toList(growable: false);
    }
    if (value is Map) {
      for (final key in const ['entries', 'data', 'items', 'journals']) {
        final nested = value[key];
        if (nested is List) return _jsonRecords(nested);
      }
      return [_mapJson(value)];
    }
    throw const DiaryImportException('JSON 顶层必须是对象或数组');
  }

  Map<String, dynamic> _mapJson(Map value) =>
      value.map((key, value) => MapEntry('$key', value));

  String? _firstString(Map<String, dynamic> value, List<String> keys) {
    for (final key in keys) {
      final candidate = value[key];
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
      if (candidate is num) return candidate.toString();
    }
    return null;
  }

  DateTime? _parseFlexibleDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = raw.trim().replaceAll('/', '-');
    final parsed = DateTime.tryParse(normalized);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    final match = RegExp(
      r'^(\d{4})[年.\-](\d{1,2})[月.\-](\d{1,2})日?$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    return _date(year, month, day);
  }

  DiaryImportDraft _draft({
    required DateTime date,
    required String title,
    required String body,
  }) {
    final content = title.trim().isEmpty
        ? body.trim()
        : [
            '# ${title.trim()}',
            if (body.trim().isNotEmpty) '',
            if (body.trim().isNotEmpty) body.trim(),
          ].join('\n');
    return DiaryImportDraft(
      date: date,
      title: title.trim(),
      content: content.trim(),
    );
  }

  List<List<String>> _parseCsv(String source) {
    final rows = <List<String>>[];
    final row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    final text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (var index = 0; index < text.length; index++) {
      final character = text[index];
      if (character == '"') {
        if (quoted && index + 1 < text.length && text[index + 1] == '"') {
          cell.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (character == ',' && !quoted) {
        row.add(cell.toString());
        cell.clear();
      } else if (character == '\n' && !quoted) {
        row.add(cell.toString());
        cell.clear();
        if (row.any((value) => value.trim().isNotEmpty)) {
          rows.add(List<String>.from(row));
        }
        row.clear();
      } else {
        cell.write(character);
      }
    }
    row.add(cell.toString());
    if (row.any((value) => value.trim().isNotEmpty)) {
      rows.add(List<String>.from(row));
    }
    return rows;
  }

  String? _findColumn(List<String> headers, List<String> aliases) {
    for (final header in headers) {
      final normalized =
          header.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
      if (aliases.any((alias) =>
          normalized ==
          alias.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), ''))) {
        return header;
      }
    }
    return null;
  }

  String _cell(List<String> row, int index) =>
      index >= 0 && index < row.length ? row[index].trim() : '';
}

class DiaryImportPreview {
  const DiaryImportPreview({required this.drafts});

  final List<DiaryImportDraft> drafts;
}

class DiaryImportDraft {
  const DiaryImportDraft({
    required this.date,
    required this.title,
    required this.content,
  });

  final DateTime date;
  final String title;
  final String content;

  String get dateLabel => DiaryEntry.dateKey(date);
}

class DiaryImportResult {
  const DiaryImportResult({
    required this.importedCount,
    required this.batchId,
  });

  final int importedCount;
  final String batchId;
}

class DiaryCsvMapping {
  const DiaryCsvMapping({
    required this.dateColumn,
    required this.contentColumn,
    required this.titleColumn,
  });

  final String? dateColumn;
  final String? contentColumn;
  final String? titleColumn;
}

class DiaryCsvImportData {
  const DiaryCsvImportData({
    required this.headers,
    required this.rows,
    required this.mapping,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final DiaryCsvMapping mapping;
}

class DiaryExportPayload {
  const DiaryExportPayload({
    required this.fileName,
    required this.extension,
    required this.bytes,
  });

  final String fileName;
  final String extension;
  final List<int> bytes;
}

class DiaryImportException implements Exception {
  const DiaryImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PendingImport {
  _PendingImport({
    required this.date,
    required this.title,
    required this.lines,
  });

  final DateTime date;
  final String title;
  final List<String> lines;

  DiaryImportDraft toDraft() {
    final body = lines.join('\n').trim();
    final content = title.isEmpty
        ? body
        : [
            '# $title',
            if (body.isNotEmpty) '',
            if (body.isNotEmpty) body,
          ].join('\n');
    return DiaryImportDraft(
      date: date,
      title: title,
      content: content.trim(),
    );
  }
}
