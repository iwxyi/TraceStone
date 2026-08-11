import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/diary_attachment.dart';
import 'diary_media_store.dart';

class DiaryMediaRepository implements DiaryMediaStore {
  const DiaryMediaRepository();

  @override
  Future<DiaryAttachment> saveImage({
    required String entryId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final id = const Uuid().v4();
    final extension = _extensionFor(file.name, file.mimeType);
    final relativePath = 'media/$entryId/$id$extension';
    final target = await _fileFor(relativePath);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
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
    final file = await _fileFor(attachment.relativePath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> saveAttachmentBytes({
    required DiaryAttachment attachment,
    required Uint8List bytes,
  }) async {
    final file = await _fileFor(attachment.relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> deleteForEntry(String entryId) async {
    final root = await _mediaRoot();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}media${Platform.pathSeparator}$entryId',
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<File> _fileFor(String relativePath) async {
    final root = await _mediaRoot();
    final safeRelativePath = relativePath
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '..')
        .join(Platform.pathSeparator);
    return File('${root.path}${Platform.pathSeparator}$safeRelativePath');
  }

  Future<Directory> _mediaRoot() async {
    final appDir = await getApplicationDocumentsDirectory();
    final root = Directory('${appDir.path}${Platform.pathSeparator}shinen');
    await root.create(recursive: true);
    return root;
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
