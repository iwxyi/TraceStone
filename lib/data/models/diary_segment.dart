enum DiarySegmentBoundary {
  wholeEntry,
  markdownHeading,
  divider,
  paragraphGap,
  timeMarker,
  semanticShift,
  lengthSplit,
}

class DiarySegment {
  const DiarySegment({
    required this.id,
    required this.entryId,
    required this.index,
    required this.text,
    required this.summary,
    required this.topics,
    required this.people,
    required this.boundary,
    required this.createdAt,
  });

  final String id;
  final String entryId;
  final int index;
  final String text;
  final String summary;
  final List<String> topics;
  final List<String> people;
  final DiarySegmentBoundary boundary;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryId': entryId,
        'index': index,
        'text': text,
        'summary': summary,
        'topics': topics,
        'people': people,
        'boundary': boundary.name,
        'createdAt': createdAt.toIso8601String(),
      };

  static DiarySegment fromJson(Map<String, dynamic> json) {
    final boundaryName =
        json['boundary'] as String? ?? DiarySegmentBoundary.wholeEntry.name;
    return DiarySegment(
      id: json['id'] as String? ?? '',
      entryId: json['entryId'] as String? ?? '',
      index: json['index'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      topics: _stringList(json['topics']),
      people: _stringList(json['people']),
      boundary: DiarySegmentBoundary.values.firstWhere(
        (item) => item.name == boundaryName,
        orElse: () => DiarySegmentBoundary.wholeEntry,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
}
