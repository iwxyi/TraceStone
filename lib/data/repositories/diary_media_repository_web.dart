import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/diary_attachment.dart';
import 'diary_media_store.dart';

class DiaryMediaRepository implements DiaryMediaStore {
  const DiaryMediaRepository();

  static const _prefix = 'diary.media.';

  @override
  Future<DiaryAttachment> saveImage({
    required String entryId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final id = const Uuid().v4();
    final extension = _extensionFor(file.name, file.mimeType);
    final relativePath = 'media/$entryId/$id$extension';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$relativePath', base64Encode(bytes));
    return DiaryAttachment(
      id: id,
      entryId: entryId,
      type: DiaryAttachmentType.image,
      fileName: file.name.isEmpty ? 'image$extension' : file.name,
      mimeType: file.mimeType ?? _mimeFor(extension),
      relativePath: relativePath,
      createdAt: DateTime.now(),
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<Uint8List?> readAttachment(DiaryAttachment attachment) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix${attachment.relativePath}');
    if (raw == null || raw.isEmpty) return null;
    return Uint8List.fromList(base64Decode(raw));
  }

  @override
  Future<void> saveAttachmentBytes({
    required DiaryAttachment attachment,
    required Uint8List bytes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix${attachment.relativePath}',
      base64Encode(bytes),
    );
  }

  @override
  Future<void> deleteForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '${_prefix}media/$entryId/';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      await prefs.remove(key);
    }
  }

  String _extensionFor(String name, String? mimeType) {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot >= 0 && dot < lower.length - 1 && lower.length - dot <= 6) {
      return lower.substring(dot);
    }
    if (mimeType == 'image/png') return '.png';
    if (mimeType == 'image/webp') return '.webp';
    return '.jpg';
  }

  String _mimeFor(String extension) => switch (extension.toLowerCase()) {
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
