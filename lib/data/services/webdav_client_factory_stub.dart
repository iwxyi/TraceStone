import 'dart:typed_data';

import '../models/webdav_config.dart';
import 'webdav_client_port.dart';

class PackageWebDavClientFactory implements WebDavClientFactory {
  const PackageWebDavClientFactory();

  @override
  WebDavClient create(WebDavConfig config) => const UnsupportedWebDavClient();
}

class UnsupportedWebDavClient implements WebDavClient {
  const UnsupportedWebDavClient();

  @override
  void setTimeouts(Duration timeout) {}

  @override
  Future<void> ping() => _unsupported();

  @override
  Future<void> mkdirAll(String path) => _unsupported();

  @override
  Future<List<WebDavRemoteFile>> readDir(String path) => _unsupported();

  @override
  Future<List<int>> read(String path) => _unsupported();

  @override
  Future<void> write(String path, Uint8List data) => _unsupported();

  Never _unsupported() {
    throw const WebDavUnsupportedException('当前平台暂不支持 WebDAV 备份');
  }
}

class WebDavUnsupportedException implements Exception {
  const WebDavUnsupportedException(this.message);

  final String message;

  @override
  String toString() => message;
}
