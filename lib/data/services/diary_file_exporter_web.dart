import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'diary_file_exporter.dart';

DiaryFileExporter createPlatformDiaryFileExporter() =>
    const WebDiaryFileExporter();

class WebDiaryFileExporter implements DiaryFileExporter {
  const WebDiaryFileExporter();

  @override
  Future<bool> save({
    required String fileName,
    required String extension,
    required List<int> bytes,
  }) async {
    final blob = web.Blob(
      [Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(type: _mimeType(extension)),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = fileName;
    anchor.style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  }

  String _mimeType(String extension) {
    return switch (extension.toLowerCase()) {
      'json' => 'application/json;charset=utf-8',
      'txt' => 'text/plain;charset=utf-8',
      _ => 'application/octet-stream',
    };
  }
}
