import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/ai_analysis_queue_repository.dart';
import '../repositories/ai_embedding_repository.dart';
import '../models/diary_entry.dart';
import '../models/webdav_config.dart';
import '../repositories/diary_media_repository.dart';
import '../repositories/diary_media_store.dart';
import '../repositories/diary_repository.dart';
import '../repositories/entry_summary_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/webdav_config_repository.dart';
import 'ai_analysis_queue_runner.dart';
import 'webdav_client_factory.dart';
import 'webdav_client_port.dart';

class WebDavSyncService {
  const WebDavSyncService({
    DiaryRepository? diaryRepository,
    DiaryMediaStore? mediaRepository,
    WebDavConfigRepository? configRepository,
    WebDavClientFactory? clientFactory,
  })  : _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _mediaRepository = mediaRepository ?? const DiaryMediaRepository(),
        _configRepository = configRepository ?? const WebDavConfigRepository(),
        _clientFactory = clientFactory ?? const PackageWebDavClientFactory();

  final DiaryRepository _diaryRepository;
  final DiaryMediaStore _mediaRepository;
  final WebDavConfigRepository _configRepository;
  final WebDavClientFactory _clientFactory;

  Future<void> testConnection(WebDavConfig config) async {
    _requireConfigured(config);
    final client = _clientFactory.create(config);
    client.setTimeouts(const Duration(seconds: 12));
    await client.ping();
    await client.mkdirAll(config.normalizedRoot);
    await client.mkdirAll(_entriesPath(config));
    await client.mkdirAll(_mediaPath(config));
    await client.mkdirAll(_dataPath(config));
  }

  Future<WebDavBackupResult> backupAll({
    WebDavProgressCallback? onProgress,
  }) async {
    final config = await _configRepository.loadConfig();
    _requireConfigured(config);
    final client = _clientFactory.create(config);
    client.setTimeouts(const Duration(seconds: 30));
    await client.mkdirAll(config.normalizedRoot);
    await client.mkdirAll(_entriesPath(config));
    await client.mkdirAll(_mediaPath(config));
    await client.mkdirAll(_dataPath(config));

    final entries = await _diaryRepository.listEntries();
    final dataSnapshot = await _recoverablePreferencesSnapshot();
    final ordered = entries.toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.createdAt.compareTo(b.createdAt);
      });
    final mediaTotal = ordered.fold<int>(
      0,
      (total, entry) => total + entry.attachments.length,
    );
    final total = ordered.length + mediaTotal + (dataSnapshot.isEmpty ? 0 : 1);
    var completed = 0;
    for (final entry in ordered) {
      await client.write(
        _entryPath(config, entry.id),
        _jsonBytes(_entryPayload(entry)),
      );
      completed++;
      onProgress?.call(
        WebDavSyncProgress(
          stage: '备份日记',
          completed: completed,
          total: total,
        ),
      );
      for (final attachment in entry.attachments) {
        final bytes = await _mediaRepository.readAttachment(attachment);
        if (bytes == null) continue;
        await client.write(_remoteMediaPath(config, attachment.relativePath),
            Uint8List.fromList(bytes));
        completed++;
        onProgress?.call(
          WebDavSyncProgress(
            stage: '备份图片',
            completed: completed,
            total: total,
          ),
        );
      }
    }
    if (dataSnapshot.isNotEmpty) {
      await client.write(
        _recoverablePreferencesPath(config),
        _jsonBytes({
          'schemaVersion': 1,
          'generatedAt': DateTime.now().toIso8601String(),
          'items': dataSnapshot,
        }),
      );
      completed++;
      onProgress?.call(
        WebDavSyncProgress(
          stage: '备份数据',
          completed: completed,
          total: total,
        ),
      );
    }
    final now = DateTime.now();
    await client.write(
      _manifestPath(config),
      _jsonBytes({
        'app': 'Shinen',
        'schemaVersion': 1,
        'generatedAt': now.toIso8601String(),
        'entryCount': ordered.length,
        'mediaCount': mediaTotal,
        'dataItemCount': dataSnapshot.length,
        'entries': ordered
            .map((entry) => {
                  'id': entry.id,
                  'date': DiaryEntry.dateKey(entry.date),
                  'updatedAt': entry.updatedAt.toIso8601String(),
                  'path': 'entries/${entry.id}.json',
                  'attachments': entry.attachments
                      .map((attachment) => {
                            'id': attachment.id,
                            'path': attachment.relativePath,
                            'mimeType': attachment.mimeType,
                            'sizeBytes': attachment.sizeBytes,
                          })
                      .toList(),
                })
            .toList(),
      }),
    );
    await _configRepository.saveLastBackupAt(now);
    return WebDavBackupResult(
      entryCount: ordered.length,
      mediaCount: mediaTotal,
      dataItemCount: dataSnapshot.length,
      completedAt: now,
    );
  }

  Future<WebDavRestoreResult> restoreNewer({
    WebDavProgressCallback? onProgress,
  }) async {
    final plan = await previewRestore(onProgress: onProgress);
    return restorePreview(plan, onProgress: onProgress);
  }

  Future<WebDavRestorePreview> previewRestore({
    WebDavProgressCallback? onProgress,
  }) async {
    final config = await _configRepository.loadConfig();
    _requireConfigured(config);
    final client = _clientFactory.create(config);
    client.setTimeouts(const Duration(seconds: 30));
    final entryFiles = await _entryFilesForRestore(client, config);
    final localEntries = await _diaryRepository.listEntries();
    final localById = {for (final entry in localEntries) entry.id: entry};
    final importEntries = <DiaryEntry>[];
    final updateEntries = <WebDavRestoreEntryChange>[];
    final skippedEntries = <DiaryEntry>[];
    final invalidFiles = <String>[];
    final remoteIds = <String>{};
    var scanned = 0;
    for (final file in entryFiles) {
      final bytes = await client.read(file.path);
      scanned++;
      final entry = _decodeEntry(bytes);
      if (entry == null) {
        invalidFiles.add(file.name);
      } else {
        remoteIds.add(entry.id);
        final local = localById[entry.id];
        if (local == null) {
          importEntries.add(entry);
        } else if (entry.updatedAt.isAfter(local.updatedAt)) {
          updateEntries.add(WebDavRestoreEntryChange(
            remote: entry,
            local: local,
          ));
        } else {
          skippedEntries.add(entry);
        }
      }
      onProgress?.call(
        WebDavSyncProgress(
          stage: '读取备份',
          completed: scanned,
          total: entryFiles.length,
        ),
      );
    }
    final restoreEntries = [
      ...importEntries,
      for (final item in updateEntries) item.remote,
    ];
    final mediaCount = restoreEntries.fold<int>(
      0,
      (total, entry) => total + entry.attachments.length,
    );
    final dataItemCount = await _previewRecoverablePreferences(client, config);
    return WebDavRestorePreview(
      scannedCount: entryFiles.length,
      importEntries: importEntries,
      updateEntries: updateEntries,
      skippedEntries: skippedEntries,
      localOnlyEntries: localEntries
          .where((entry) => !remoteIds.contains(entry.id))
          .toList(growable: false),
      invalidFiles: invalidFiles,
      mediaCount: mediaCount,
      dataItemCount: dataItemCount,
      config: config,
    );
  }

  Future<WebDavRestoreResult> restorePreview(
    WebDavRestorePreview preview, {
    WebDavProgressCallback? onProgress,
    bool overwriteLocal = false,
    Set<String>? selectedEntryIds,
    Set<String>? selectedLocalOnlyIds,
  }) async {
    final config = await _configRepository.loadConfig();
    _requireConfigured(config);
    final client = _clientFactory.create(config);
    client.setTimeouts(const Duration(seconds: 30));
    final selected = selectedEntryIds?.toSet();
    final allRemoteEntries = preview.allRemoteEntries;
    final toSave = (selected == null
            ? (overwriteLocal ? allRemoteEntries : preview.entriesToRestore)
            : allRemoteEntries.where((entry) => selected.contains(entry.id)))
        .toList(growable: false);
    final queue = const AiAnalysisQueueRepository();
    final queueWasPaused = await queue.isPaused();
    await queue.setPaused(true);
    await AiAnalysisQueueRunner.waitUntilIdle();
    try {
      return await _restoreSelected(
        preview,
        config,
        client,
        toSave,
        overwriteLocal: overwriteLocal,
        selectedLocalOnlyIds: selectedLocalOnlyIds,
        onProgress: onProgress,
        queueWasPaused: queueWasPaused,
      );
    } catch (_) {
      if (!queueWasPaused) await queue.setPaused(false);
      rethrow;
    }
  }

  Future<WebDavRestoreResult> _restoreSelected(
    WebDavRestorePreview preview,
    WebDavConfig config,
    WebDavClient client,
    List<DiaryEntry> toSave, {
    required bool overwriteLocal,
    required Set<String>? selectedLocalOnlyIds,
    required WebDavProgressCallback? onProgress,
    required bool queueWasPaused,
  }) async {
    final queue = const AiAnalysisQueueRepository();
    final localOnlyIds = selectedLocalOnlyIds ??
        preview.localOnlyEntries.map((entry) => entry.id).toSet();
    if (overwriteLocal) {
      final localEntries = await _diaryRepository.listEntries();
      for (final entry in localEntries) {
        if (!localOnlyIds.contains(entry.id)) continue;
        await _diaryRepository.moveToTrash(entry.id);
        await _diaryRepository.permanentlyDeleteFromTrash(entry.id);
      }
    }
    final remoteMedia = toSave
        .where((entry) => entry.attachments.isNotEmpty)
        .toList(growable: false);
    for (final entry in toSave) {
      await _mediaRepository.deleteForEntry(entry.id);
    }
    var mediaCompleted = 0;
    var restoredMedia = 0;
    final mediaTotal = remoteMedia.fold<int>(
      0,
      (total, entry) => total + entry.attachments.length,
    );
    for (final entry in remoteMedia) {
      await _mediaRepository.deleteForEntry(entry.id);
      for (final attachment in entry.attachments) {
        final bytes = await client
            .read(_remoteMediaPath(config, attachment.relativePath));
        if (bytes.isNotEmpty) {
          await _mediaRepository.saveAttachmentBytes(
            attachment: attachment,
            bytes: Uint8List.fromList(bytes),
          );
          restoredMedia++;
        }
        mediaCompleted++;
        onProgress?.call(
          WebDavSyncProgress(
            stage: '恢复图片',
            completed: mediaCompleted,
            total: mediaTotal,
          ),
        );
      }
    }
    await _diaryRepository.saveImportedEntries(toSave);
    final restoredDataCount = await _restoreRecoverablePreferences(
      client,
      config,
      replaceExisting: overwriteLocal,
    );
    final now = DateTime.now();
    await _configRepository.saveLastRestoreAt(now);
    await _reconcileAiJobsAfterRestore(toSave);
    if (!queueWasPaused) {
      await queue.setPaused(false);
      await const AiAnalysisQueueRunner().processNext();
    }
    return WebDavRestoreResult(
      scannedCount: preview.scannedCount,
      importedCount: toSave.length,
      mediaCount: restoredMedia,
      dataItemCount: restoredDataCount,
      skippedCount: overwriteLocal
          ? preview.invalidFiles.length
          : preview.skippedEntries.length +
              preview.invalidFiles.length +
              preview.allRemoteEntries
                  .where((entry) => !toSave.any((item) => item.id == entry.id))
                  .length,
      completedAt: now,
    );
  }

  Future<void> _reconcileAiJobsAfterRestore(
    Iterable<DiaryEntry> entries,
  ) async {
    const queue = AiAnalysisQueueRepository();
    const summaryRepository = EntrySummaryRepository();
    const insightRepository = InsightRepository();
    const embeddingRepository = AiEmbeddingRepository();
    for (final entry in entries) {
      final summary = await summaryRepository.getSummary(entry.id);
      final segments = await summaryRepository.listSegments(entry.id);
      final insight = await insightRepository.getInsight(entry.id);
      await queue.deleteJob(entry.id);
      if (summary != null && segments.isNotEmpty && insight != null) {
        await queue.deleteJob('embedding:${entry.id}');
        await queue.enqueueEmbeddingRebuildEntry(
          entry,
          batchId: 'restore:${DateTime.now().microsecondsSinceEpoch}',
          batchLabel: '恢复后重建历史相似度',
        );
        continue;
      }
      final embeddings = await embeddingRepository.listForEntry(entry.id);
      if (embeddings.isEmpty) {
        await queue.enqueueEntry(
          entry,
          batchId: 'restore:${DateTime.now().microsecondsSinceEpoch}',
          batchLabel: '恢复后继续整理日记',
        );
      }
    }
  }

  void _requireConfigured(WebDavConfig config) {
    if (!config.isConfigured) {
      throw const WebDavSyncException('请先填写 WebDAV 地址、账号和密码');
    }
  }

  String _entriesPath(WebDavConfig config) =>
      '${config.normalizedRoot}/entries';

  Future<List<WebDavRemoteFile>> _entryFilesForRestore(
    WebDavClient client,
    WebDavConfig config,
  ) async {
    final manifestFiles = await _entryFilesFromManifest(client, config);
    if (manifestFiles != null) return manifestFiles;

    final files = await client.readDir(_entriesPath(config));
    return files
        .where((file) => !file.isDir && file.name.endsWith('.json'))
        .toList(growable: false);
  }

  Future<List<WebDavRemoteFile>?> _entryFilesFromManifest(
    WebDavClient client,
    WebDavConfig config,
  ) async {
    try {
      final bytes = await client.read(_manifestPath(config));
      if (bytes.isEmpty) return null;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return null;
      final rawEntries = decoded['entries'];
      if (rawEntries is! List) return null;

      final files = <WebDavRemoteFile>[];
      for (final rawEntry in rawEntries) {
        if (rawEntry is! Map) continue;
        final rawPath = rawEntry['path'];
        if (rawPath is! String) continue;
        final path = _manifestEntryPath(config, rawPath);
        if (path == null) continue;
        files.add(
          WebDavRemoteFile(
            path: path,
            name: _fileName(path),
            isDir: false,
          ),
        );
      }
      return files;
    } on Object {
      return null;
    }
  }

  String? _manifestEntryPath(WebDavConfig config, String rawPath) {
    final normalizedPath = rawPath.replaceAll('\\', '/');
    if (normalizedPath.isEmpty) return null;
    final root = config.normalizedRoot;
    final path = normalizedPath.startsWith('/')
        ? normalizedPath
        : '$root/$normalizedPath';
    final entriesPrefix = '${_entriesPath(config)}/';
    if (!path.startsWith(entriesPrefix) ||
        !path.endsWith('.json') ||
        path.contains('/../') ||
        path.endsWith('/..')) {
      return null;
    }
    return path;
  }

  String _fileName(String path) {
    final separator = path.lastIndexOf('/');
    return separator < 0 ? path : path.substring(separator + 1);
  }

  String _mediaPath(WebDavConfig config) => '${config.normalizedRoot}/media';

  String _dataPath(WebDavConfig config) => '${config.normalizedRoot}/data';

  String _manifestPath(WebDavConfig config) =>
      '${config.normalizedRoot}/manifest.json';

  String _entryPath(WebDavConfig config, String id) =>
      '${_entriesPath(config)}/$id.json';

  String _recoverablePreferencesPath(WebDavConfig config) =>
      '${_dataPath(config)}/preferences.json';

  String _remoteMediaPath(WebDavConfig config, String relativePath) {
    final normalized = relativePath
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '..')
        .join('/');
    return '${config.normalizedRoot}/$normalized';
  }

  Map<String, dynamic> _entryPayload(DiaryEntry entry) => {
        'schemaVersion': 1,
        'entry': entry.toJson(),
      };

  Uint8List _jsonBytes(Map<String, dynamic> value) => Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(value)));

  Future<Map<String, Object?>> _recoverablePreferencesSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final items = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      if (!_isRecoverablePreferenceKey(key)) continue;
      final value = prefs.get(key);
      if (value is String ||
          value is bool ||
          value is int ||
          value is double ||
          value is List<String>) {
        items[key] = value;
      }
    }
    return items;
  }

  Future<int> _restoreRecoverablePreferences(
      WebDavClient client, WebDavConfig config,
      {bool replaceExisting = false}) async {
    final bytes = await client.read(_recoverablePreferencesPath(config));
    if (bytes.isEmpty) return 0;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return 0;
      final rawItems = decoded['items'];
      if (rawItems is! Map) return 0;
      final prefs = await SharedPreferences.getInstance();
      final remoteKeys = rawItems.keys.map((key) => key.toString()).toSet();
      if (replaceExisting) {
        for (final key in prefs.getKeys().where(_isRecoverablePreferenceKey)) {
          if (!remoteKeys.contains(key)) {
            await prefs.remove(key);
          }
        }
      }
      var restored = 0;
      for (final item in rawItems.entries) {
        final key = item.key.toString();
        if (!_isRecoverablePreferenceKey(key)) continue;
        final value = item.value;
        if (value is String) {
          await prefs.setString(key, value);
        } else if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is List) {
          await prefs.setStringList(key, value.whereType<String>().toList());
        } else {
          continue;
        }
        restored++;
      }
      return restored;
    } on Object {
      return 0;
    }
  }

  Future<int> _previewRecoverablePreferences(
    WebDavClient client,
    WebDavConfig config,
  ) async {
    final bytes = await client.read(_recoverablePreferencesPath(config));
    if (bytes.isEmpty) return 0;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return 0;
      final rawItems = decoded['items'];
      if (rawItems is! Map) return 0;
      return rawItems.keys
          .map((key) => key.toString())
          .where(_isRecoverablePreferenceKey)
          .length;
    } on Object {
      return 0;
    }
  }

  bool _isRecoverablePreferenceKey(String key) {
    const exactKeys = {
      'memory.entries.index',
      'calendar.memories.index',
      'diary.insights.index',
      'diary.insights.latest',
      'ai.profilePreferences.index',
      'ai.relationshipMergeHistory.index',
      'ai.researchSessions.index',
      'ai.researchSessions.last',
      'stone.tasks.index',
    };
    const prefixes = [
      'memory.entries.',
      'calendar.memories.',
      'diary.insights.',
      'ai.entrySummaries.',
      'ai.entrySummaryRevisions.',
      'ai.entrySegments.',
      'ai.periodSummaries.',
      'ai.periodSummaryStatuses.',
      'ai.profilePreferences.',
      'ai.relationshipMergeHistory.',
      'ai.researchSessions.',
      'stone.tasks.',
    ];
    if (exactKeys.contains(key)) return true;
    return prefixes.any(key.startsWith);
  }

  DiaryEntry? _decodeEntry(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return null;
      final entryJson = decoded['entry'];
      if (entryJson is Map<String, dynamic>) {
        return DiaryEntry.fromJson(entryJson);
      }
      return DiaryEntry.fromJson(decoded);
    } on Object {
      return null;
    }
  }
}

typedef WebDavProgressCallback = void Function(WebDavSyncProgress progress);

class WebDavSyncProgress {
  const WebDavSyncProgress({
    required this.stage,
    required this.completed,
    required this.total,
  });

  final String stage;
  final int completed;
  final int total;

  double? get fraction => total <= 0 ? null : completed / total;
}

class WebDavBackupResult {
  const WebDavBackupResult({
    required this.entryCount,
    this.mediaCount = 0,
    this.dataItemCount = 0,
    required this.completedAt,
  });

  final int entryCount;
  final int mediaCount;
  final int dataItemCount;
  final DateTime completedAt;
}

class WebDavRestorePreview {
  const WebDavRestorePreview({
    required this.scannedCount,
    required this.importEntries,
    required this.updateEntries,
    required this.skippedEntries,
    required this.localOnlyEntries,
    required this.invalidFiles,
    required this.mediaCount,
    required this.dataItemCount,
    required this.config,
  });

  final int scannedCount;
  final List<DiaryEntry> importEntries;
  final List<WebDavRestoreEntryChange> updateEntries;
  final List<DiaryEntry> skippedEntries;
  final List<DiaryEntry> localOnlyEntries;
  final List<String> invalidFiles;
  final int mediaCount;
  final int dataItemCount;
  final WebDavConfig config;

  int get importCount => importEntries.length;
  int get updateCount => updateEntries.length;
  int get skippedCount => skippedEntries.length + invalidFiles.length;
  int get localOnlyCount => localOnlyEntries.length;
  int get restoreEntryCount => importCount + updateCount;
  bool get hasChanges =>
      restoreEntryCount > 0 || mediaCount > 0 || dataItemCount > 0;

  List<DiaryEntry> get entriesToRestore => [
        ...importEntries,
        for (final item in updateEntries) item.remote,
      ];

  List<DiaryEntry> get allRemoteEntries => [
        ...importEntries,
        for (final item in updateEntries) item.remote,
        ...skippedEntries,
      ];
}

class WebDavRestoreEntryChange {
  const WebDavRestoreEntryChange({
    required this.remote,
    required this.local,
  });

  final DiaryEntry remote;
  final DiaryEntry local;
}

class WebDavRestoreResult {
  const WebDavRestoreResult({
    required this.scannedCount,
    required this.importedCount,
    this.mediaCount = 0,
    this.dataItemCount = 0,
    required this.skippedCount,
    required this.completedAt,
  });

  final int scannedCount;
  final int importedCount;
  final int mediaCount;
  final int dataItemCount;
  final int skippedCount;
  final DateTime completedAt;
}

class WebDavSyncException implements Exception {
  const WebDavSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
