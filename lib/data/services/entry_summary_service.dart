import '../models/diary_entry.dart';
import '../models/diary_segment.dart';
import '../models/entry_summary.dart';
import 'package:characters/characters.dart';

class EntrySummaryService {
  const EntrySummaryService();

  EntrySummary buildSummary(DiaryEntry entry, List<DiarySegment> segments) {
    final body = entry.bodyPreview;
    final keyPoints = segments
        .map((segment) => segment.summary)
        .where((summary) => summary.isNotEmpty)
        .take(6)
        .toList();
    return EntrySummary(
      entryId: entry.id,
      date: entry.date,
      entryUpdatedAt: entry.updatedAt,
      generatedAt: DateTime.now(),
      title: entry.title ?? _truncate(body, 28),
      brief: _truncate(body, 120),
      keyPoints: keyPoints.isEmpty ? [_truncate(body, 80)] : keyPoints,
      topics: _topics(entry.content),
      people: _people(entry.content),
      places: [
        if (entry.location.trim().isNotEmpty &&
            entry.location.trim() != '未选择地点')
          entry.location.trim(),
      ],
      emotion: _emotion(entry.content),
      importance: _importance(entry, segments),
      importantQuotes: _importantQuotes(entry.content),
      generator: 'local-rule-v1',
    );
  }

  List<DiarySegment> buildSegments(DiaryEntry entry) {
    final blocks = _splitBlocks(entry.content);
    final now = DateTime.now();
    final segments = <DiarySegment>[];
    for (final block in blocks) {
      final text = block.text.trim();
      if (text.isEmpty) continue;
      final pieces = _splitLongBlock(text);
      for (final piece in pieces) {
        final index = segments.length;
        segments.add(DiarySegment(
          id: '${entry.id}#s${index + 1}',
          entryId: entry.id,
          index: index,
          text: piece,
          summary: _truncate(_plainText(piece), 80),
          topics: _topics(piece).take(5).toList(),
          people: _people(piece),
          boundary: pieces.length > 1
              ? DiarySegmentBoundary.lengthSplit
              : block.boundary,
          createdAt: now,
        ));
      }
    }
    if (segments.isNotEmpty) return segments;
    return [
      DiarySegment(
        id: '${entry.id}#s1',
        entryId: entry.id,
        index: 0,
        text: entry.content,
        summary: entry.excerpt,
        topics: _topics(entry.content).take(5).toList(),
        people: _people(entry.content),
        boundary: DiarySegmentBoundary.wholeEntry,
        createdAt: now,
      ),
    ];
  }

  List<_SegmentBlock> _splitBlocks(String content) {
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_SegmentBlock>[];
    final buffer = <String>[];
    var boundary = DiarySegmentBoundary.wholeEntry;
    var blankCount = 0;

    void flush() {
      final text = buffer.join('\n').trim();
      if (text.isNotEmpty) {
        blocks.add(_SegmentBlock(text, boundary));
      }
      buffer.clear();
      boundary = DiarySegmentBoundary.paragraphGap;
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final trimmed = line.trim();
      if (RegExp(r'^#{1,6}\s+').hasMatch(trimmed)) {
        flush();
        boundary = DiarySegmentBoundary.markdownHeading;
        buffer.add(line);
        blankCount = 0;
        continue;
      }
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        flush();
        boundary = DiarySegmentBoundary.divider;
        blankCount = 0;
        continue;
      }
      if (trimmed.isEmpty) {
        blankCount++;
        if (blankCount >= 2) flush();
        continue;
      }
      blankCount = 0;
      buffer.add(line);
    }
    flush();
    return blocks;
  }

  List<String> _splitLongBlock(String text) {
    const maxLength = 500;
    if (text.characters.length <= maxLength) return [text];
    final paragraphs = text.split(RegExp(r'\n+'));
    final pieces = <String>[];
    final buffer = StringBuffer();
    for (final paragraph in paragraphs) {
      if (buffer.isNotEmpty &&
          buffer.length + paragraph.length + 1 > maxLength) {
        pieces.add(buffer.toString().trim());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(paragraph);
    }
    if (buffer.isNotEmpty) pieces.add(buffer.toString().trim());
    return pieces;
  }

  List<String> _topics(String text) {
    final cleaned = _plainText(text)
        .replaceAll(RegExp(r'[\s，。！？；：、“”‘’（）《》【】,.!?;:/\\]+'), ' ')
        .trim();
    final counts = <String, int>{};
    for (final part in cleaned.split(' ')) {
      final value = part.trim();
      if (value.length < 2) continue;
      if (_stopWords.contains(value)) continue;
      counts[value] = (counts[value] ?? 0) + 1;
      if (value.length >= 4) {
        for (var i = 0; i <= value.length - 2; i++) {
          final token = value.substring(i, i + 2);
          if (!_stopWords.contains(token)) {
            counts[token] = (counts[token] ?? 0) + 1;
          }
        }
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return b.key.length.compareTo(a.key.length);
      });
    return entries.map((entry) => entry.key).take(8).toList();
  }

  List<String> _people(String text) {
    final matches = RegExp(r'(@[\u4e00-\u9fa5A-Za-z0-9_\-]{1,20})')
        .allMatches(text)
        .map((match) => match.group(0)!.substring(1))
        .toSet()
        .toList();
    return matches.take(8).toList();
  }

  List<String> _importantQuotes(String text) {
    final lines = text
        .split('\n')
        .map((line) => _plainText(line).trim())
        .where((line) => line.length >= 8)
        .toList();
    lines.sort((a, b) => b.length.compareTo(a.length));
    return lines.take(3).map((line) => _truncate(line, 60)).toList();
  }

  String _emotion(String text) {
    final normalized = _plainText(text);
    const rules = {
      '疲惫': ['累', '疲惫', '困', '撑不住'],
      '焦虑': ['焦虑', '紧张', '担心', '压力'],
      '放松': ['放松', '轻松', '舒服', '恢复'],
      '开心': ['开心', '高兴', '快乐', '兴奋'],
      '低落': ['难过', '低落', '沮丧', '委屈'],
      '平静': ['平静', '稳定', '还好'],
    };
    final scores = <String, int>{};
    for (final entry in rules.entries) {
      for (final keyword in entry.value) {
        if (normalized.contains(keyword)) {
          scores[entry.key] = (scores[entry.key] ?? 0) + 1;
        }
      }
    }
    if (scores.isEmpty) return '';
    final sorted = scores.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        if (byScore != 0) return byScore;
        return a.key.compareTo(b.key);
      });
    return sorted.take(2).map((entry) => entry.key).join('、');
  }

  double _importance(DiaryEntry entry, List<DiarySegment> segments) {
    var score = 0.42;
    final contentLength = entry.bodyPreview.characters.length;
    if (contentLength >= 80) score += 0.08;
    if (contentLength >= 240) score += 0.08;
    if (segments.length >= 2) score += 0.06;
    if (_people(entry.content).isNotEmpty) score += 0.06;
    if (_importantQuotes(entry.content).isNotEmpty) score += 0.04;
    if (_emotion(entry.content).isNotEmpty) score += 0.04;
    return score.clamp(0.2, 0.95).toDouble();
  }

  String _plainText(String text) =>
      text.replaceAll(RegExp(r'[#>*_`\[\]\(\)!-]'), '');

  String _truncate(String text, int maxLength) {
    final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.characters.length <= maxLength) return value;
    return '${value.characters.take(maxLength).toString()}…';
  }
}

class _SegmentBlock {
  const _SegmentBlock(this.text, this.boundary);

  final String text;
  final DiarySegmentBoundary boundary;
}

const _stopWords = {
  '今天',
  '然后',
  '因为',
  '所以',
  '但是',
  '感觉',
  '还是',
  '一个',
  '这个',
  '那个',
  '自己',
  '没有',
  '什么',
  '一下',
};
