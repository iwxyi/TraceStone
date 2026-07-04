enum AiAnalysisJobState { pending, running, incomplete, failed, completed }

enum AiAnalysisStage {
  queued,
  preparing,
  generatingSummary,
  segmenting,
  embedding,
  retrieving,
  generatingInsight,
  updatingMemory,
  completed,
}

class AiAnalysisJob {
  const AiAnalysisJob({
    required this.id,
    required this.entryId,
    required this.pipelineVersion,
    required this.state,
    required this.currentStage,
    required this.createdAt,
    required this.updatedAt,
    this.completedStages = const [],
    this.stageLogs = const [],
    this.summaryId,
    this.segmentIds = const [],
    this.embeddingIds = const [],
    this.insightId,
    this.retrievalTraceId,
    this.retryCount = 0,
    this.lastError,
    this.batchId,
    this.batchLabel,
  });

  final String id;
  final String entryId;
  final int pipelineVersion;
  final AiAnalysisJobState state;
  final AiAnalysisStage currentStage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AiAnalysisStage> completedStages;
  final List<AiAnalysisStageLog> stageLogs;
  final String? summaryId;
  final List<String> segmentIds;
  final List<String> embeddingIds;
  final String? insightId;
  final String? retrievalTraceId;
  final int retryCount;
  final String? lastError;
  final String? batchId;
  final String? batchLabel;

  bool get canRun =>
      state == AiAnalysisJobState.pending ||
      state == AiAnalysisJobState.incomplete ||
      (state == AiAnalysisJobState.failed && retryCount < 3);

  String get stageLabel {
    switch (currentStage) {
      case AiAnalysisStage.queued:
        return '等待整理';
      case AiAnalysisStage.preparing:
        return '准备日记内容';
      case AiAnalysisStage.generatingSummary:
        return '生成摘要包';
      case AiAnalysisStage.segmenting:
        return '拆分日记片段';
      case AiAnalysisStage.embedding:
        return '生成多级向量';
      case AiAnalysisStage.retrieving:
        return '关联历史记录';
      case AiAnalysisStage.generatingInsight:
        return '生成今日洞察';
      case AiAnalysisStage.updatingMemory:
        return '更新长期记忆';
      case AiAnalysisStage.completed:
        return '整理完成';
    }
  }

  AiAnalysisJob copyWith({
    AiAnalysisJobState? state,
    AiAnalysisStage? currentStage,
    DateTime? updatedAt,
    List<AiAnalysisStage>? completedStages,
    List<AiAnalysisStageLog>? stageLogs,
    String? summaryId,
    List<String>? segmentIds,
    List<String>? embeddingIds,
    String? insightId,
    String? retrievalTraceId,
    int? retryCount,
    String? lastError,
    String? batchId,
    String? batchLabel,
    bool clearLastError = false,
  }) {
    return AiAnalysisJob(
      id: id,
      entryId: entryId,
      pipelineVersion: pipelineVersion,
      state: state ?? this.state,
      currentStage: currentStage ?? this.currentStage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedStages: completedStages ?? this.completedStages,
      stageLogs: stageLogs ?? this.stageLogs,
      summaryId: summaryId ?? this.summaryId,
      segmentIds: segmentIds ?? this.segmentIds,
      embeddingIds: embeddingIds ?? this.embeddingIds,
      insightId: insightId ?? this.insightId,
      retrievalTraceId: retrievalTraceId ?? this.retrievalTraceId,
      retryCount: retryCount ?? this.retryCount,
      lastError: clearLastError ? null : lastError ?? this.lastError,
      batchId: batchId ?? this.batchId,
      batchLabel: batchLabel ?? this.batchLabel,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryId': entryId,
        'pipelineVersion': pipelineVersion,
        'state': state.name,
        'currentStage': currentStage.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'completedStages': completedStages.map((item) => item.name).toList(),
        'stageLogs': stageLogs.map((item) => item.toJson()).toList(),
        'summaryId': summaryId,
        'segmentIds': segmentIds,
        'embeddingIds': embeddingIds,
        'insightId': insightId,
        'retrievalTraceId': retrievalTraceId,
        'retryCount': retryCount,
        'lastError': lastError,
        'batchId': batchId,
        'batchLabel': batchLabel,
      };

  static AiAnalysisJob fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final stateName = _stringValue(json['state']).isEmpty
        ? AiAnalysisJobState.pending.name
        : _stringValue(json['state']);
    final stageName = _stringValue(json['currentStage']).isEmpty
        ? AiAnalysisStage.queued.name
        : _stringValue(json['currentStage']);
    return AiAnalysisJob(
      id: _stringValue(json['id']),
      entryId: _stringValue(json['entryId']),
      pipelineVersion: _intValue(json['pipelineVersion'], fallback: 1),
      state: AiAnalysisJobState.values.firstWhere(
        (item) => item.name == stateName,
        orElse: () => AiAnalysisJobState.pending,
      ),
      currentStage: AiAnalysisStage.values.firstWhere(
        (item) => item.name == stageName,
        orElse: () => AiAnalysisStage.queued,
      ),
      createdAt: DateTime.tryParse(_stringValue(json['createdAt'])) ?? now,
      updatedAt: DateTime.tryParse(_stringValue(json['updatedAt'])) ?? now,
      completedStages: _listValue(json['completedStages'])
          .map((item) => item.toString())
          .map((name) => AiAnalysisStage.values.firstWhere(
                (item) => item.name == name,
                orElse: () => AiAnalysisStage.queued,
              ))
          .toList(),
      stageLogs:
          _mapList(json['stageLogs']).map(AiAnalysisStageLog.fromJson).toList(),
      summaryId: _nullableString(json['summaryId']),
      segmentIds: _stringList(json['segmentIds']),
      embeddingIds: _stringList(json['embeddingIds']),
      insightId: _nullableString(json['insightId']),
      retrievalTraceId: _nullableString(json['retrievalTraceId']),
      retryCount: _intValue(json['retryCount']),
      lastError: _nullableString(json['lastError']),
      batchId: _nullableString(json['batchId']),
      batchLabel: _nullableString(json['batchLabel']),
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static String? _nullableString(Object? value) =>
      value is String ? value : null;

  static int _intValue(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<dynamic> _listValue(Object? value) =>
      value is List ? value : const [];

  static List<String> _stringList(Object? value) =>
      _listValue(value).whereType<String>().toList();

  static List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => {
              for (final entry in item.entries)
                if (entry.key is String) entry.key as String: entry.value,
            })
        .toList();
  }
}

class AiAnalysisStageLog {
  const AiAnalysisStageLog({
    required this.stage,
    required this.startedAt,
    required this.message,
    this.inputSummary = '',
    this.outputSummary = '',
    this.error,
    this.retryCount = 0,
  });

  final AiAnalysisStage stage;
  final DateTime startedAt;
  final String message;
  final String inputSummary;
  final String outputSummary;
  final String? error;
  final int retryCount;

  Map<String, dynamic> toJson() => {
        'stage': stage.name,
        'startedAt': startedAt.toIso8601String(),
        'message': message,
        'inputSummary': inputSummary,
        'outputSummary': outputSummary,
        'error': error,
        'retryCount': retryCount,
      };

  static AiAnalysisStageLog fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final stageName = _stringValue(json['stage']).isEmpty
        ? AiAnalysisStage.queued.name
        : _stringValue(json['stage']);
    return AiAnalysisStageLog(
      stage: AiAnalysisStage.values.firstWhere(
        (item) => item.name == stageName,
        orElse: () => AiAnalysisStage.queued,
      ),
      startedAt: DateTime.tryParse(_stringValue(json['startedAt'])) ?? now,
      message: _stringValue(json['message']),
      inputSummary: _stringValue(json['inputSummary']),
      outputSummary: _stringValue(json['outputSummary']),
      error: _nullableString(json['error']),
      retryCount: _intValue(json['retryCount']),
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static String? _nullableString(Object? value) =>
      value is String ? value : null;

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class AiAnalysisQueueSnapshot {
  const AiAnalysisQueueSnapshot({
    required this.jobs,
    this.currentJob,
    this.isPaused = false,
  });

  final List<AiAnalysisJob> jobs;
  final AiAnalysisJob? currentJob;
  final bool isPaused;

  int get pendingCount => jobs.where((job) => job.canRun).length;

  int get runnableCount => jobs.where((job) => job.canRun).length;

  int get waitingCount => jobs
      .where((job) =>
          job.canRun &&
          job.id != currentJob?.id &&
          job.state != AiAnalysisJobState.running)
      .length;

  int get incompleteCount =>
      jobs.where((job) => job.state == AiAnalysisJobState.incomplete).length;

  int get failedCount =>
      jobs.where((job) => job.state == AiAnalysisJobState.failed).length;

  int get completedCount =>
      jobs.where((job) => job.state == AiAnalysisJobState.completed).length;

  int get totalTrackedCount => jobs.length;

  int get remainingStageCount {
    return jobs
        .where((job) => job.canRun || job.state == AiAnalysisJobState.running)
        .fold(
      0,
      (total, job) {
        final completed = job.completedStages
            .where((stage) =>
                stage != AiAnalysisStage.queued &&
                stage != AiAnalysisStage.completed)
            .toSet()
            .length;
        final remaining =
            (_pipelineStageCount - completed).clamp(1, _pipelineStageCount);
        return total + remaining.toInt();
      },
    );
  }

  Duration? get estimatedRemainingDuration {
    final stages = remainingStageCount;
    if (stages <= 0) return null;
    return _averageStageDuration * stages;
  }

  String get estimatedRemainingLabel {
    final duration = estimatedRemainingDuration;
    if (duration == null) return '';
    if (duration.inMinutes < 1) {
      return '约 ${duration.inSeconds.clamp(1, 59)} 秒';
    }
    if (duration.inHours < 1) {
      return '约 ${duration.inMinutes} 分钟';
    }
    final minutes = duration.inMinutes.remainder(60);
    if (minutes == 0) return '约 ${duration.inHours} 小时';
    return '约 ${duration.inHours} 小时 $minutes 分钟';
  }

  int get activeOrdinal {
    final job = currentJob;
    if (job == null) return 0;
    final activeJobs = jobs
        .where((item) =>
            item.canRun ||
            item.state == AiAnalysisJobState.running ||
            item.state == AiAnalysisJobState.completed)
        .toList();
    final index = activeJobs.indexWhere((item) => item.id == job.id);
    return index < 0 ? 1 : index + 1;
  }

  bool get hasVisibleWork =>
      currentJob != null || pendingCount > 0 || failedCount > 0;

  List<AiAnalysisBatchSnapshot> get batches {
    final grouped = <String, List<AiAnalysisJob>>{};
    for (final job in jobs) {
      final batchId = job.batchId?.trim();
      if (batchId == null || batchId.isEmpty) continue;
      grouped.putIfAbsent(batchId, () => []).add(job);
    }
    final result = grouped.entries.map((entry) {
      final items = entry.value;
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final label = items
          .map((job) => job.batchLabel?.trim() ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => entry.key);
      return AiAnalysisBatchSnapshot(
        id: entry.key,
        label: label,
        jobs: items,
      );
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Duration get _averageStageDuration {
    final completedDurations = jobs
        .where((job) => job.state == AiAnalysisJobState.completed)
        .map((job) => job.updatedAt.difference(job.createdAt))
        .where((duration) =>
            duration.inMilliseconds > 0 && duration < const Duration(days: 1))
        .toList();
    if (completedDurations.isEmpty) return const Duration(seconds: 8);
    final averageJobMs = completedDurations
            .map((duration) => duration.inMilliseconds)
            .reduce((a, b) => a + b) /
        completedDurations.length;
    final averageStageMs = averageJobMs / _pipelineStageCount;
    final clamped = averageStageMs.clamp(1000, 10 * 60 * 1000).round();
    return Duration(milliseconds: clamped);
  }

  static final int _pipelineStageCount = AiAnalysisStage.values
      .where((stage) =>
          stage != AiAnalysisStage.queued && stage != AiAnalysisStage.completed)
      .length;
}

class AiAnalysisBatchSnapshot {
  const AiAnalysisBatchSnapshot({
    required this.id,
    required this.label,
    required this.jobs,
  });

  final String id;
  final String label;
  final List<AiAnalysisJob> jobs;

  DateTime get createdAt => jobs.isEmpty ? DateTime(0) : jobs.first.createdAt;

  int get totalCount => jobs.length;

  int get runningCount =>
      jobs.where((job) => job.state == AiAnalysisJobState.running).length;

  int get runnableCount => jobs.where((job) => job.canRun).length;

  int get completedCount =>
      jobs.where((job) => job.state == AiAnalysisJobState.completed).length;

  int get failedCount =>
      jobs.where((job) => job.state == AiAnalysisJobState.failed).length;

  int get remainingCount => jobs
      .where((job) =>
          job.canRun ||
          job.state == AiAnalysisJobState.running ||
          job.state == AiAnalysisJobState.failed)
      .length;

  double get progress {
    if (totalCount <= 0) return 0;
    return (completedCount / totalCount).clamp(0.0, 1.0).toDouble();
  }

  String get progressLabel => '$completedCount/$totalCount';
}
