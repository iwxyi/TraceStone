import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

import 'diary_file_exporter.dart';

DiaryFileExporter createPlatformDiaryFileExporter() =>
    const IoDiaryFileExporter();

class IoDiaryFileExporter implements DiaryFileExporter {
  const IoDiaryFileExporter();

  @override
  Future<bool> save({
    required String fileName,
    required String extension,
    required List<int> bytes,
  }) async {
    final location = await FileSelectorPlatform.instance.getSaveLocation(
      options: SaveDialogOptions(suggestedName: fileName),
      acceptedTypeGroups: [
        XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
    if (location == null) return false;
    var path = location.path;
    if (!path.split(RegExp(r'[\\/]')).last.contains('.')) {
      path = '$path.$extension';
    }
    final file = XFile.fromData(
      Uint8List.fromList(bytes),
      name: fileName,
      mimeType: _mimeType(extension),
    );
    await file.saveTo(path);
    return true;
  }

  String _mimeType(String extension) {
    return switch (extension.toLowerCase()) {
      'json' => 'application/json',
      'txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }
}
