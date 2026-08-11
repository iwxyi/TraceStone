import 'dart:typed_data';

import '../models/webdav_config.dart';

abstract interface class WebDavClientFactory {
  const WebDavClientFactory();

  WebDavClient create(WebDavConfig config);
}

abstract interface class WebDavClient {
  void setTimeouts(Duration timeout);

  Future<void> ping();

  Future<void> mkdirAll(String path);

  Future<List<WebDavRemoteFile>> readDir(String path);

  Future<List<int>> read(String path);

  Future<void> write(String path, Uint8List data);
}

class WebDavRemoteFile {
  const WebDavRemoteFile({
    required this.path,
    required this.name,
    required this.isDir,
  });

  final String path;
  final String name;
  final bool isDir;
}
