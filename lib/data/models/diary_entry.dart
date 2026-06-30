class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.date,
    required this.createdAt,
    required this.content,
    required this.location,
    required this.weather,
    required this.temperature,
    required this.updatedAt,
  });

  final String id;
  final DateTime date;
  final DateTime createdAt;
  final String content;
  final String location;
  final String weather;
  final String? temperature;
  final DateTime updatedAt;

  String get dayKey => dateKey(date);

  List<String> get _nonEmptyLines => content
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .toList();

  String? get title {
    final lines = _nonEmptyLines;
    if (lines.isEmpty) return null;
    final first = lines.first.trimLeft();
    if (first.startsWith('#')) {
      final value =
          _plainText(first.replaceFirst(RegExp(r'^#+\s*'), '')).trim();
      return value.isEmpty ? null : value;
    }
    if (lines.length >= 2 && RegExp(r'^=+$').hasMatch(lines[1].trim())) {
      final value = _plainText(lines[0]).trim();
      return value.isEmpty ? null : value;
    }
    return null;
  }

  String get bodyPreview {
    final lines = [..._nonEmptyLines];
    if (lines.isNotEmpty && lines.first.trimLeft().startsWith('#')) {
      lines.removeAt(0);
    } else if (lines.length >= 2 && RegExp(r'^=+$').hasMatch(lines[1].trim())) {
      lines.removeAt(0);
      lines.removeAt(0);
    }
    final plain = lines
        .map(_plainText)
        .where((line) => line.trim().isNotEmpty)
        .join('\n')
        .trim();
    return plain.isEmpty ? '空白日记' : plain;
  }

  String _plainText(String text) =>
      text.replaceAll(RegExp(r'[#>*_`\[\]\(\)!-]'), '');

  String get excerpt {
    final plain = bodyPreview.replaceAll('\n', ' ').trim();
    return plain.length > 80 ? '${plain.substring(0, 80)}…' : plain;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'content': content,
        'location': location,
        'weather': weather,
        'temperature': temperature,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static DiaryEntry fromJson(Map<String, dynamic> json) {
    final date = DateTime.parse(json['date'] as String);
    final updatedAt =
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    return DiaryEntry(
      id: json['id'] as String? ??
          '${dateKey(date)}-${updatedAt.microsecondsSinceEpoch}',
      date: date,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updatedAt,
      content: json['content'] as String? ?? '',
      location: json['location'] as String? ?? '未选择地点',
      weather: json['weather'] as String? ?? '天气',
      temperature: json['temperature'] as String?,
      updatedAt: updatedAt,
    );
  }

  static String dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
