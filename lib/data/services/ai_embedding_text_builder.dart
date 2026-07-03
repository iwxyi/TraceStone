import '../models/diary_entry.dart';
import '../models/diary_segment.dart';
import '../models/entry_summary.dart';

class AiEmbeddingTextBuilder {
  const AiEmbeddingTextBuilder();

  String entryText(DiaryEntry entry, EntrySummary summary) {
    return '${summary.brief}\n${entry.bodyPreview}';
  }

  String summaryText(EntrySummary summary) {
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

  String segmentText(DiarySegment segment) {
    return '${segment.summary}\n${segment.text}';
  }
}
