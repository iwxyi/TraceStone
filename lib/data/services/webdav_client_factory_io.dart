import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart' as webdav;

import '../models/webdav_config.dart';
import 'webdav_client_port.dart';

class PackageWebDavClientFactory implements WebDavClientFactory {
  const PackageWebDavClientFactory();

  @override
  WebDavClient create(WebDavConfig config) {
    return PackageWebDavClient(
      webdav.newClient(
        config.normalizedUrl,
        user: config.username.trim(),
        password: config.password,
      ),
    );
  }
}

class PackageWebDavClient implements WebDavClient {
  const PackageWebDavClient(this._client);

  final webdav.Client _client;

  @override
  void setTimeouts(Duration timeout) {
    final milliseconds = timeout.inMilliseconds;
    _client.setConnectTimeout(milliseconds);
    _client.setSendTimeout(milliseconds);
    _client.setReceiveTimeout(milliseconds);
  }

  @override
  Future<void> ping() => _client.ping();

  @override
  Future<void> mkdirAll(String path) => _client.mkdirAll(path);

  @override
  Future<List<WebDavRemoteFile>> readDir(String path) async {
    final files = await _client.readDir(path);
    return files
        .map(
          (file) => WebDavRemoteFile(
            path: file.path ?? '',
            name: file.name ?? '',
            isDir: file.isDir ?? false,
          ),
        )
        .where((file) => file.path.isNotEmpty && file.name.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<int>> read(String path) => _client.read(path);

  @override
  Future<void> write(String path, Uint8List data) => _client.write(path, data);
}
