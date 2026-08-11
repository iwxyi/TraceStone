import 'package:flutter_test/flutter_test.dart';
import 'package:trace_stone/data/models/diary_attachment.dart';
import 'package:trace_stone/data/models/diary_entry.dart';

void main() {
  test('serializes and restores attachments', () {
    final entry = DiaryEntry(
      id: 'entry-1',
      date: DateTime(2026, 8, 3),
      createdAt: DateTime(2026, 8, 3, 9),
      content: 'hello',
      location: '上海',
      weather: '晴',
      temperature: '33',
      updatedAt: DateTime(2026, 8, 3, 10),
      attachments: [
        DiaryAttachment(
          id: 'att-1',
          entryId: 'entry-1',
          type: DiaryAttachmentType.image,
          fileName: 'a.jpg',
          mimeType: 'image/jpeg',
          relativePath: 'media/entry-1/att-1.jpg',
          createdAt: DateTime(2026, 8, 3, 10),
          sizeBytes: 123,
        ),
      ],
    );

    final restored = DiaryEntry.fromJson(entry.toJson());

    expect(restored.attachments, hasLength(1));
    expect(restored.attachments.first.relativePath, 'media/entry-1/att-1.jpg');
  });
}
