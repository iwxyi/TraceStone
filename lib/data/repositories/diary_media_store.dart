import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../models/diary_attachment.dart';

abstract class DiaryMediaStore {
  Future<DiaryAttachment> saveImage({
    required String entryId,
    required XFile file,
  });

  Future<Uint8List?> readAttachment(DiaryAttachment attachment);

  Future<void> saveAttachmentBytes({
    required DiaryAttachment attachment,
    required Uint8List bytes,
  });

  Future<void> deleteForEntry(String entryId);
}
