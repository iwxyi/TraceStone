import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

import '../models/webdav_config.dart';
import 'webdav_client_port.dart';

class PackageWebDavClientFactory implements WebDavClientFactory {
  const PackageWebDavClientFactory();

  @override
  WebDavClient create(WebDavConfig config) => WebHttpDavClient(config);
}

class WebHttpDavClient implements WebDavClient {
  WebHttpDavClient(this._config, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final WebDavConfig _config;
  final http.Client _httpClient;
  Duration _timeout = const Duration(seconds: 30);

  @override
  void setTimeouts(Duration timeout) {
    _timeout = timeout;
  }

  @override
  Future<void> ping() async {
    final response = await _send('OPTIONS', '/');
    _expect(response, const [200, 204, 207], '连接测试失败');
  }

  @override
  Future<void> mkdirAll(String path) async {
    final normalized = _normalizePath(path);
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    var current = '';
    for (final segment in segments) {
      current = '$current/$segment';
      final response = await _send('MKCOL', current);
      _expect(response, const [201, 405], '创建远端目录失败');
    }
  }

  @override
  Future<List<WebDavRemoteFile>> readDir(String path) async {
    final normalized = _normalizePath(path);
    final response = await _send(
      'PROPFIND',
      normalized,
      headers: const {
        'Depth': '1',
        'Content-Type': 'application/xml;charset=UTF-8',
        'Accept': 'application/xml,text/xml',
      },
      body: utf8.encode(_propfindBody),
    );
    _expect(response, const [207], '读取远端目录失败');
    return _parseFiles(normalized, response.body);
  }

  @override
  Future<List<int>> read(String path) async {
    final response = await _send('GET', path);
    _expect(response, const [200], '读取远端文件失败');
    return response.bodyBytes;
  }

  @override
  Future<void> write(String path, Uint8List data) async {
    final response = await _send(
      'PUT',
      path,
      headers: const {'Content-Type': 'application/json;charset=UTF-8'},
      body: data,
    );
    _expect(response, const [200, 201, 204], '写入远端文件失败');
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, _uri(path));
    request.headers.addAll({
      if (_config.username.trim().isNotEmpty ||
          _config.password.trim().isNotEmpty)
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${_config.username.trim()}:${_config.password}'))}',
      ...headers,
    });
    if (body != null) request.bodyBytes = body;
    try {
      final streamed = await _httpClient.send(request).timeout(_timeout);
      return http.Response.fromStream(streamed);
    } on TimeoutException {
      throw WebDavWebException('WebDAV 请求超时：$method ${_normalizePath(path)}');
    } on http.ClientException catch (error) {
      throw WebDavWebException(
        'WebDAV 网络请求失败：$error。Web 端还需要服务端允许跨域访问。',
      );
    }
  }

  Uri _uri(String path) {
    final base = Uri.parse(_config.normalizedUrl);
    final basePath = base.path.replaceAll(RegExp(r'/+$'), '');
    final remotePath = _normalizePath(path);
    return base.replace(path: '$basePath$remotePath');
  }

  String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == '/') return '/';
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  void _expect(http.Response response, List<int> accepted, String message) {
    if (accepted.contains(response.statusCode)) return;
    final reason =
        response.reasonPhrase == null || response.reasonPhrase!.isEmpty
            ? ''
            : ' ${response.reasonPhrase}';
    throw WebDavWebException('$message：HTTP ${response.statusCode}$reason');
  }

  List<WebDavRemoteFile> _parseFiles(String directoryPath, String source) {
    final document = xml.XmlDocument.parse(source);
    final directory = _normalizePath(directoryPath);
    return document.descendants
        .whereType<xml.XmlElement>()
        .where((element) => element.name.local == 'response')
        .map((response) => _fileFromResponse(directory, response))
        .whereType<WebDavRemoteFile>()
        .where((file) => _normalizePath(file.path) != directory)
        .toList(growable: false);
  }

  WebDavRemoteFile? _fileFromResponse(
    String directory,
    xml.XmlElement response,
  ) {
    final href = response.descendants
        .whereType<xml.XmlElement>()
        .where((element) => element.name.local == 'href')
        .firstOrNull
        ?.innerText
        .trim();
    if (href == null || href.isEmpty) return null;
    final path = _remotePathFromHref(href);
    final isDir = response.descendants
        .whereType<xml.XmlElement>()
        .any((element) => element.name.local == 'collection');
    final name = _nameFromPath(path, directory, isDir);
    if (name.isEmpty) return null;
    return WebDavRemoteFile(path: path, name: name, isDir: isDir);
  }

  String _remotePathFromHref(String href) {
    final parsed = Uri.tryParse(href);
    final hrefPath = parsed == null
        ? href
        : parsed.hasScheme
            ? parsed.path
            : href;
    final decoded = Uri.decodeFull(hrefPath);
    final basePath =
        Uri.parse(_config.normalizedUrl).path.replaceAll(RegExp(r'/+$'), '');
    if (basePath.isNotEmpty && decoded.startsWith('$basePath/')) {
      return _normalizePath(decoded.substring(basePath.length));
    }
    if (basePath.isNotEmpty && decoded == basePath) {
      return '/';
    }
    return _normalizePath(decoded);
  }

  String _nameFromPath(String path, String directory, bool isDir) {
    var normalized = _normalizePath(path);
    if (isDir) {
      normalized = normalized.replaceAll(RegExp(r'/+$'), '');
    }
    final prefix = directory.endsWith('/') ? directory : '$directory/';
    if (normalized.startsWith(prefix)) {
      return normalized.substring(prefix.length);
    }
    return normalized.split('/').where((part) => part.isNotEmpty).lastOrNull ??
        '';
  }
}

class WebDavWebException implements Exception {
  const WebDavWebException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _propfindBody = '''
<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:displayname/>
    <D:resourcetype/>
    <D:getcontentlength/>
    <D:getlastmodified/>
  </D:prop>
</D:propfind>
''';
