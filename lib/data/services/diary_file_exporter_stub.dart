import 'diary_file_exporter.dart';

DiaryFileExporter createPlatformDiaryFileExporter() =>
    const _UnsupportedDiaryFileExporter();

class _UnsupportedDiaryFileExporter implements DiaryFileExporter {
  const _UnsupportedDiaryFileExporter();

  @override
  Future<bool> save({
    required String fileName,
    required String extension,
    required List<int> bytes,
  }) {
    throw UnsupportedError('当前平台暂不支持文件导出');
  }
}
