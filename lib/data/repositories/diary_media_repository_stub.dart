import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../models/diary_attachment.dart';
import 'diary_media_store.dart';

class DiaryMediaRepository implements DiaryMediaStore {
  const DiaryMediaRepository();

  @override
  Future<DiaryAttachment> saveImage({
    required String entryId,
    required XFile file,
  }) {
    throw UnsupportedError('当前平台暂不支持日记图片存储');
  }

  @override
  Future<Uint8List?> readAttachment(DiaryAttachment attachment) async => null;

  @override
  Future<void> saveAttachmentBytes({
    required DiaryAttachment attachment,
    required Uint8List bytes,
  }) async {}

  @override
  Future<void> deleteForEntry(String entryId) async {}
}
