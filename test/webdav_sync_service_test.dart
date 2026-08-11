import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:trace_stone/data/models/diary_attachment.dart';
import 'package:trace_stone/data/models/diary_entry.dart';
import 'package:trace_stone/data/models/webdav_config.dart';
import 'package:trace_stone/data/repositories/diary_repository.dart';
import 'package:trace_stone/data/repositories/diary_media_store.dart';
import 'package:trace_stone/data/repositories/webdav_config_repository.dart';
import 'package:trace_stone/data/services/webdav_client_port.dart';
import 'package:trace_stone/data/services/webdav_sync_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('backs up diary entries as per-entry json files and manifest', () async {
    final remote = _FakeWebDavClient();
    final mediaRepository = _FakeDiaryMediaStore();
    final configRepository = WebDavConfigRepository(
      secretStore: _MemoryWebDavSecretStore(),
    );
    await configRepository.saveConfig(_config());
    final diaryRepository = const DiaryRepository();
    final entry = _entry(
      id: 'entry-1',
      content: '# 新年\n今天开始记录。',
      updatedAt: DateTime(2026, 1, 1, 12),
      attachments: [
        _attachment(entryId: 'entry-1', id: 'image-1'),
        _attachment(entryId: 'entry-1', id: 'image-2'),
      ],
    );
    mediaRepository.seed(entry.attachments[0], [1, 2, 3]);
    mediaRepository.seed(entry.attachments[1], [4, 5, 6]);
    await diaryRepository.saveEntry(entry);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai.entrySummaries.entry-1', '{"summary":"ok"}');
    await prefs.setString('app.auth.session', '{"token":"secret"}');
    final service = WebDavSyncService(
      diaryRepository: diaryRepository,
      mediaRepository: mediaRepository,
      configRepository: configRepository,
      clientFactory: _FakeWebDavClientFactory(remote),
    );

    final result = await service.backupAll();

    expect(result.entryCount, 1);
    expect(remote.directories, contains('/Shinen'));
    expect(remote.directories, contains('/Shinen/entries'));
    expect(remote.directories, contains('/Shinen/media'));
    expect(remote.directories, contains('/Shinen/data'));
    expect(remote.files.keys, contains('/Shinen/entries/entry-1.json'));
    expect(remote.files.keys, contains('/Shinen/media/entry-1/image-1.jpg'));
    expect(remote.files.keys, contains('/Shinen/media/entry-1/image-2.jpg'));
    expect(remote.files.keys, contains('/Shinen/data/preferences.json'));
    expect(remote.files.keys, contains('/Shinen/manifest.json'));
    final payload = jsonDecode(
      utf8.decode(remote.files['/Shinen/entries/entry-1.json']!),
    ) as Map<String, dynamic>;
    expect(payload['entry']['content'], contains('今天开始记录'));
    expect(payload['entry']['attachments'], hasLength(2));
    final manifest = jsonDecode(
      utf8.decode(remote.files['/Shinen/manifest.json']!),
    ) as Map<String, dynamic>;
    expect(manifest['mediaCount'], 2);
    expect(manifest['dataItemCount'], 1);
    final data = jsonDecode(
      utf8.decode(remote.files['/Shinen/data/preferences.json']!),
    ) as Map<String, dynamic>;
    expect(data['items']['ai.entrySummaries.entry-1'], '{"summary":"ok"}');
    expect((data['items'] as Map).keys, isNot(contains('app.auth.session')));
  });

  test('restores only missing or newer remote entries', () async {
    final remote = _FakeWebDavClient();
    final mediaRepository = _FakeDiaryMediaStore();
    final configRepository = WebDavConfigRepository(
      secretStore: _MemoryWebDavSecretStore(),
    );
    await configRepository.saveConfig(_config());
    final diaryRepository = const DiaryRepository();
    await diaryRepository.saveEntry(
      _entry(
        id: 'entry-1',
        content: '本地较旧',
        updatedAt: DateTime(2026, 1, 1, 8),
      ),
    );
    await diaryRepository.saveEntry(
      _entry(
        id: 'entry-2',
        content: '本地较新',
        updatedAt: DateTime(2026, 1, 2, 18),
      ),
    );
    remote.seedEntry(
      _entry(
        id: 'entry-1',
        content: '云端较新',
        updatedAt: DateTime(2026, 1, 1, 12),
      ),
    );
    remote.seedEntry(
      _entry(
        id: 'entry-2',
        content: '云端较旧',
        updatedAt: DateTime(2026, 1, 2, 8),
      ),
    );
    remote.seedEntry(
      _entry(
        id: 'entry-3',
        content: '云端新增',
        updatedAt: DateTime(2026, 1, 3, 8),
        attachments: [_attachment(entryId: 'entry-3', id: 'image-3')],
      ),
    );
    remote.files['/Shinen/media/entry-3/image-3.jpg'] =
        Uint8List.fromList([7, 8, 9]);
    remote.files['/Shinen/data/preferences.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode({
        'schemaVersion': 1,
        'items': {
          'ai.researchSessions.last': 'session-1',
          'webdav.config': '{"password":"secret"}',
        },
      })),
    );
    final service = WebDavSyncService(
      diaryRepository: diaryRepository,
      mediaRepository: mediaRepository,
      configRepository: configRepository,
      clientFactory: _FakeWebDavClientFactory(remote),
    );

    final preview = await service.previewRestore();
    expect(preview.importCount, 1);
    expect(preview.updateCount, 1);
    expect(preview.skippedCount, 1);
    expect(preview.mediaCount, 1);
    expect(preview.dataItemCount, 1);
    expect(preview.localOnlyCount, 0);

    final result = await service.restorePreview(preview);
    final entries = await diaryRepository.listEntries();
    final byId = {for (final entry in entries) entry.id: entry};

    expect(result.scannedCount, 3);
    expect(result.importedCount, 2);
    expect(byId['entry-1']?.content, '云端较新');
    expect(byId['entry-2']?.content, '本地较新');
    expect(byId['entry-3']?.content, '云端新增');
    expect(byId['entry-3']?.attachments, hasLength(1));
    expect(mediaRepository.bytesFor('media/entry-3/image-3.jpg'), [7, 8, 9]);
    expect(result.dataItemCount, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai.researchSessions.last'), 'session-1');
    expect(prefs.getString('webdav.config'), isNot(contains('secret')));
  });

  test('restores from manifest without listing the remote entries directory',
      () async {
    final remote = _FakeWebDavClient()..failReadDir = true;
    final configRepository = WebDavConfigRepository(
      secretStore: _MemoryWebDavSecretStore(),
    );
    await configRepository.saveConfig(_config());
    final diaryRepository = const DiaryRepository();
    final entry = _entry(
      id: 'manifest-entry',
      content: '通过清单恢复',
      updatedAt: DateTime(2026, 2, 1, 10),
    );
    remote.seedEntry(entry);
    remote.files['/Shinen/manifest.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode({
        'schemaVersion': 1,
        'entries': [
          {
            'id': entry.id,
            'path': 'entries/${entry.id}.json',
          },
        ],
      })),
    );
    final service = WebDavSyncService(
      diaryRepository: diaryRepository,
      mediaRepository: _FakeDiaryMediaStore(),
      configRepository: configRepository,
      clientFactory: _FakeWebDavClientFactory(remote),
    );

    final preview = await service.previewRestore();

    expect(preview.importCount, 1);
    expect(preview.importEntries.single.id, entry.id);
  });

  test('overwrite restore replaces local data with remote backup set',
      () async {
    final remote = _FakeWebDavClient();
    final mediaRepository = _FakeDiaryMediaStore();
    final configRepository = WebDavConfigRepository(
      secretStore: _MemoryWebDavSecretStore(),
    );
    await configRepository.saveConfig(_config());
    final diaryRepository = const DiaryRepository();
    await diaryRepository.saveEntry(
      _entry(
        id: 'entry-1',
        content: '本地较新但要被覆盖',
        updatedAt: DateTime(2026, 1, 1, 18),
      ),
    );
    await diaryRepository.saveEntry(
      _entry(
        id: 'local-only',
        content: '云端没有的本地日记',
        updatedAt: DateTime(2026, 1, 4, 8),
      ),
    );
    remote.seedEntry(
      _entry(
        id: 'entry-1',
        content: '云端备份内容',
        updatedAt: DateTime(2026, 1, 1, 8),
      ),
    );
    final service = WebDavSyncService(
      diaryRepository: diaryRepository,
      mediaRepository: mediaRepository,
      configRepository: configRepository,
      clientFactory: _FakeWebDavClientFactory(remote),
    );

    final preview = await service.previewRestore();
    final result = await service.restorePreview(preview, overwriteLocal: true);
    final entries = await diaryRepository.listEntries();
    final byId = {for (final entry in entries) entry.id: entry};

    expect(result.importedCount, 1);
    expect(result.skippedCount, 0);
    expect(byId['entry-1']?.content, '云端备份内容');
    expect(byId.containsKey('local-only'), isFalse);
  });

  test('restore preview applies selected entries and local-only deletions',
      () async {
    final remote = _FakeWebDavClient();
    final configRepository = WebDavConfigRepository(
      secretStore: _MemoryWebDavSecretStore(),
    );
    await configRepository.saveConfig(_config());
    final diaryRepository = const DiaryRepository();
    await diaryRepository.saveEntry(
      _entry(
        id: 'entry-1',
        content: '本地较旧',
        updatedAt: DateTime(2026, 1, 1, 8),
      ),
    );
    await diaryRepository.saveEntry(
      _entry(
        id: 'local-only',
        content: '云端没有',
        updatedAt: DateTime(2026, 1, 5, 8),
      ),
    );
    remote.seedEntry(
      _entry(
        id: 'entry-1',
        content: '云端更新但未选择',
        updatedAt: DateTime(2026, 1, 1, 12),
      ),
    );
    remote.seedEntry(
      _entry(
        id: 'entry-2',
        content: '云端新增且选择',
        updatedAt: DateTime(2026, 1, 2, 12),
      ),
    );
    final service = WebDavSyncService(
      diaryRepository: diaryRepository,
      mediaRepository: _FakeDiaryMediaStore(),
      configRepository: configRepository,
      clientFactory: _FakeWebDavClientFactory(remote),
    );

    final preview = await service.previewRestore();
    await service.restorePreview(
      preview,
      overwriteLocal: true,
      selectedEntryIds: {'entry-2'},
      selectedLocalOnlyIds: const {},
    );
    final entries = await diaryRepository.listEntries();
    final byId = {for (final entry in entries) entry.id: entry};

    expect(byId['entry-1']?.content, '本地较旧');
    expect(byId['entry-2']?.content, '云端新增且选择');
    expect(byId.containsKey('local-only'), isTrue);
  });
}

WebDavConfig _config() => const WebDavConfig(
      url: 'https://dav.example.com',
      username: 'user',
      password: 'pass',
      remoteRoot: '/Shinen',
    );

DiaryEntry _entry({
  required String id,
  required String content,
  required DateTime updatedAt,
  List<DiaryAttachment> attachments = const [],
}) {
  return DiaryEntry(
    id: id,
    date: DateTime(updatedAt.year, updatedAt.month, updatedAt.day),
    createdAt: updatedAt,
    content: content,
    location: '未选择地点',
    weather: '天气',
    temperature: null,
    updatedAt: updatedAt,
    attachments: attachments,
  );
}

DiaryAttachment _attachment({
  required String entryId,
  required String id,
}) {
  return DiaryAttachment(
    id: id,
    entryId: entryId,
    type: DiaryAttachmentType.image,
    fileName: '$id.jpg',
    mimeType: 'image/jpeg',
    relativePath: 'media/$entryId/$id.jpg',
    createdAt: DateTime(2026, 1, 1),
    sizeBytes: 3,
  );
}

class _FakeWebDavClientFactory implements WebDavClientFactory {
  const _FakeWebDavClientFactory(this.client);

  final _FakeWebDavClient client;

  @override
  WebDavClient create(WebDavConfig config) => client;
}

class _FakeWebDavClient implements WebDavClient {
  final directories = <String>{};
  final files = <String, Uint8List>{};
  bool failReadDir = false;

  void seedEntry(DiaryEntry entry) {
    mkdirAll('/Shinen/entries');
    files['/Shinen/entries/${entry.id}.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode({
        'schemaVersion': 1,
        'entry': entry.toJson(),
      })),
    );
  }

  @override
  void setTimeouts(Duration timeout) {}

  @override
  Future<void> ping() async {}

  @override
  Future<void> mkdirAll(String path) async {
    directories.add(path);
  }

  @override
  Future<List<WebDavRemoteFile>> readDir(String path) async {
    if (failReadDir) {
      throw StateError('directory listing should not be used');
    }
    final prefix = path.endsWith('/') ? path : '$path/';
    return files.keys
        .where((key) => key.startsWith(prefix))
        .map(
          (key) => WebDavRemoteFile(
            path: key,
            name: key.substring(prefix.length),
            isDir: false,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<int>> read(String path) async => files[path] ?? Uint8List(0);

  @override
  Future<void> write(String path, Uint8List data) async {
    files[path] = data;
  }
}

class _FakeDiaryMediaStore implements DiaryMediaStore {
  final _bytes = <String, Uint8List>{};

  void seed(DiaryAttachment attachment, List<int> bytes) {
    _bytes[attachment.relativePath] = Uint8List.fromList(bytes);
  }

  List<int>? bytesFor(String relativePath) => _bytes[relativePath]?.toList();

  @override
  Future<void> deleteForEntry(String entryId) async {
    _bytes.removeWhere((key, _) => key.startsWith('media/$entryId/'));
  }

  @override
  Future<Uint8List?> readAttachment(DiaryAttachment attachment) async =>
      _bytes[attachment.relativePath];

  @override
  Future<void> saveAttachmentBytes({
    required DiaryAttachment attachment,
    required Uint8List bytes,
  }) async {
    _bytes[attachment.relativePath] = bytes;
  }

  @override
  Future<DiaryAttachment> saveImage({
    required String entryId,
    required XFile file,
  }) {
    throw UnimplementedError();
  }
}

class _MemoryWebDavSecretStore implements WebDavSecretStore {
  final _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
