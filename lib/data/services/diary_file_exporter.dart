import 'diary_file_exporter_stub.dart'
    if (dart.library.io) 'diary_file_exporter_io.dart'
    if (dart.library.js_interop) 'diary_file_exporter_web.dart';

abstract interface class DiaryFileExporter {
  Future<bool> save({
    required String fileName,
    required String extension,
    required List<int> bytes,
  });
}

DiaryFileExporter createDiaryFileExporter() =>
    createPlatformDiaryFileExporter();
