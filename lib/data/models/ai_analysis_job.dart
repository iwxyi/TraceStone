enum AiAnalysisJobState { pending, running, incomplete, failed, completed }

enum AiAnalysisJobType {
  diary,
  embeddingRebuild,
  monthSummary,
  yearSummary,
  userProfile,
}

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
    this.type = AiAnalysisJobType.diary,
    String? targetId,
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
  }) : _targetId = targetId;

  final String id;
  final String entryId;
  final int pipelineVersion;
  final AiAnalysisJobState state;
  final AiAnalysisStage currentStage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final AiAnalysisJobType type;
  String get targetId => _targetId ?? entryId;
  final String? _targetId;
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
      state == AiAnalysisJobState.incomplete;

  bool get canRetry => state == AiAnalysisJobState.failed && retryCount < 3;

  String get stageLabel {
    if (type == AiAnalysisJobType.embeddingRebuild) {
      switch (currentStage) {
        case AiAnalysisStage.queued:
          return '等待重建历史相似度';
        case AiAnalysisStage.preparing:
        case AiAnalysisStage.generatingSummary:
        case AiAnalysisStage.segmenting:
          return '准备索引资料';
        case AiAnalysisStage.embedding:
          return '重建历史相似度';
        case AiAnalysisStage.completed:
          return '历史相似度已更新';
        case AiAnalysisStage.retrieving:
        case AiAnalysisStage.generatingInsight:
        case AiAnalysisStage.updatingMemory:
          return '整理索引上下文';
      }
    }
    if (type == AiAnalysisJobType.monthSummary ||
        type == AiAnalysisJobType.yearSummary) {
      switch (currentStage) {
        case AiAnalysisStage.queued:
          return '等待生成周期总结';
        case AiAnalysisStage.preparing:
          return '准备周期资料';
        case AiAnalysisStage.generatingSummary:
          return type == AiAnalysisJobType.monthSummary ? '生成月度总结' : '生成年度总结';
        case AiAnalysisStage.completed:
          return '周期总结完成';
        case AiAnalysisStage.segmenting:
        case AiAnalysisStage.embedding:
        case AiAnalysisStage.retrieving:
        case AiAnalysisStage.generatingInsight:
        case AiAnalysisStage.updatingMemory:
          return '整理周期上下文';
      }
    }
    if (type == AiAnalysisJobType.userProfile) {
      switch (currentStage) {
        case AiAnalysisStage.queued:
          return '等待更新用户画像';
        case AiAnalysisStage.preparing:
          return '准备画像资料';
        case AiAnalysisStage.generatingSummary:
          return '生成用户画像';
        case AiAnalysisStage.completed:
          return '用户画像已更新';
        case AiAnalysisStage.segmenting:
        case AiAnalysisStage.embedding:
        case AiAnalysisStage.retrieving:
        case AiAnalysisStage.generatingInsight:
        case AiAnalysisStage.updatingMemory:
          return '整理画像上下文';
      }
    }
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
        return '生成今日分析';
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
    AiAnalysisJobType? type,
    String? targetId,
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
      type: type ?? this.type,
      targetId: targetId ?? this.targetId,
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
        'type': type.name,
        'targetId': targetId,
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
    final typeName = _stringValue(json['type']).isEmpty
        ? AiAnalysisJobType.diary.name
        : _stringValue(json['type']);
    return AiAnalysisJob(
      id: _stringValue(json['id']),
      entryId: _stringValue(json['entryId']),
      type: AiAnalysisJobType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => AiAnalysisJobType.diary,
      ),
      targetId: _nullableString(json['targetId']),
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
    this.dependencyReasons = const {},
  });

  final List<AiAnalysisJob> jobs;
  final AiAnalysisJob? currentJob;
  final bool isPaused;
  final Map<String, String> dependencyReasons;

  int get pendingCount => jobs
      .where((job) => job.canRun && !dependencyReasons.containsKey(job.id))
      .length;

  int get runnableCount => jobs
      .where((job) => job.canRun && !dependencyReasons.containsKey(job.id))
      .length;

  int get waitingCount => jobs
      .where((job) =>
          job.canRun &&
          !dependencyReasons.containsKey(job.id) &&
          job.id != currentJob?.id &&
          job.state != AiAnalysisJobState.running)
      .length;

  int get incompleteCount =>
      jobs.where((job) => job.state == AiAnalysisJobState.incomplete).length;

  int get failedCount =>
      jobs.where((job) => job.state == AiAnalysisJobState.failed).length;

  AiAnalysisJob? get firstFailedJob =>
      jobs.where((job) => job.state == AiAnalysisJobState.failed).firstOrNull;

  int get completedCount =>
      jobs.where((job) => job.state == AiAnalysisJobState.completed).length;

  int get totalTrackedCount => jobs.length;

  int get remainingStageCount {
    return jobs
        .where((job) => job.canRun || job.state == AiAnalysisJobState.running)
        .fold(
      0,
      (total, job) {
        final expectedStages = _expectedStagesFor(job.type);
        final completed =
            job.completedStages.where(expectedStages.contains).toSet().length;
        final remaining =
            (expectedStages.length - completed).clamp(1, expectedStages.length);
        return total + remaining.toInt();
      },
    );
  }

  Duration? get estimatedRemainingDuration {
    final activeJobs = jobs
        .where((job) => job.canRun || job.state == AiAnalysisJobState.running)
        .toList(growable: false);
    if (activeJobs.isEmpty) return null;
    var total = Duration.zero;
    for (final job in activeJobs) {
      for (final stage in _remainingStagesFor(job)) {
        total += _estimatedDurationFor(job.type, stage);
      }
    }
    return total;
  }

  Duration get averageStageDuration {
    final stageSamples = _completedStageDurations;
    if (stageSamples.isNotEmpty) {
      final averageMs = stageSamples
              .map((duration) => duration.inMilliseconds)
              .reduce((a, b) => a + b) /
          stageSamples.length;
      final clamped = averageMs.clamp(1000, 10 * 60 * 1000).round();
      return Duration(milliseconds: clamped);
    }
    final jobSamples = _completedJobDurations;
    if (jobSamples.isEmpty) return const Duration(seconds: 8);
    final averageJobMs = jobSamples
            .map((sample) => sample.inMilliseconds)
            .reduce((a, b) => a + b) /
        jobSamples.length;
    final averageStageMs = averageJobMs;
    final clamped = averageStageMs.clamp(1000, 10 * 60 * 1000).round();
    return Duration(milliseconds: clamped);
  }

  int get estimateSampleCount => _completedStageDurations.length;

  String get averageStageDurationLabel => _durationLabel(averageStageDuration);

  Duration get _fallbackAverageStageDuration => averageStageDuration;

  Map<AiAnalysisStage, Duration> get _stageAverageDurations {
    final grouped = <AiAnalysisStage, List<Duration>>{};
    for (final sample in _completedStageDurationSamples) {
      grouped.putIfAbsent(sample.stage, () => []).add(sample.duration);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: Duration(
          milliseconds: (entry.value
                      .map((duration) => duration.inMilliseconds)
                      .reduce((a, b) => a + b) /
                  entry.value.length)
              .round(),
        ),
    };
  }

  List<AiAnalysisStageCalibration> get stageCalibrations {
    final result = _stageAverageDurations.entries.map((entry) {
      return AiAnalysisStageCalibration(
        stage: entry.key,
        sampleCount: _completedStageDurationSamples
            .where((sample) => sample.stage == entry.key)
            .length,
        averageDuration: entry.value,
        durationLabel: _durationLabel(entry.value),
      );
    }).toList()
      ..sort((a, b) {
        final byDuration = b.averageDuration.compareTo(a.averageDuration);
        if (byDuration != 0) return byDuration;
        return a.stage.name.compareTo(b.stage.name);
      });
    return result;
  }

  String get stageCalibrationSummary {
    final items = stageCalibrations.take(4).map((item) {
      return '${item.stage.name}=${item.durationLabel}(${item.sampleCount})';
    }).toList(growable: false);
    return items.join(', ');
  }

  String get estimatedRemainingLabel {
    final duration = estimatedRemainingDuration;
    if (duration == null) return '';
    return _durationLabel(duration);
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
      currentJob != null ||
      pendingCount > 0 ||
      dependencyReasons.isNotEmpty ||
      failedCount > 0;

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

  AiAnalysisBatchSnapshot? batchForJob(String jobId) {
    for (final batch in batches) {
      if (batch.jobs.any((job) => job.id == jobId)) return batch;
    }
    return null;
  }

  List<Duration> get _completedStageDurations {
    return _completedStageDurationSamples
        .map((sample) => sample.duration)
        .toList(growable: false);
  }

  List<_StageDurationSample> get _completedStageDurationSamples {
    final samples = <_StageDurationSample>[];
    for (final job in jobs) {
      if (job.state != AiAnalysisJobState.completed) continue;
      final logs = [...job.stageLogs]
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
      for (var index = 0; index < logs.length - 1; index++) {
        final log = logs[index];
        final duration = logs[index + 1].startedAt.difference(
              log.startedAt,
            );
        if (_isValidCalibrationDuration(duration)) {
          samples.add(_StageDurationSample(log.stage, duration));
        }
      }
      if (logs.isNotEmpty) {
        final log = logs.last;
        final finalDuration = job.updatedAt.difference(logs.last.startedAt);
        if (_isValidCalibrationDuration(finalDuration)) {
          samples.add(_StageDurationSample(log.stage, finalDuration));
        }
      }
    }
    return samples;
  }

  List<Duration> get _completedJobDurations {
    return jobs
        .where((job) => job.state == AiAnalysisJobState.completed)
        .map((job) {
          final duration = job.updatedAt.difference(job.createdAt);
          final stageCount = _expectedStagesFor(job.type).length;
          return Duration(
            milliseconds: (duration.inMilliseconds / stageCount).round(),
          );
        })
        .where(_isValidCalibrationDuration)
        .toList();
  }

  bool _isValidCalibrationDuration(Duration duration) =>
      duration.inMilliseconds > 0 && duration < const Duration(days: 1);

  List<AiAnalysisStage> _remainingStagesFor(AiAnalysisJob job) {
    final expectedStages = _expectedStagesFor(job.type).toList(growable: false);
    final completed = job.completedStages.toSet();
    final remaining = expectedStages
        .where((stage) => !completed.contains(stage))
        .toList(growable: false);
    if (remaining.isNotEmpty) return remaining;
    if (job.currentStage != AiAnalysisStage.queued &&
        job.currentStage != AiAnalysisStage.completed &&
        expectedStages.contains(job.currentStage)) {
      return [job.currentStage];
    }
    return [expectedStages.last];
  }

  Duration _estimatedDurationFor(
    AiAnalysisJobType type,
    AiAnalysisStage stage,
  ) {
    final calibrated = _stageAverageDurations[stage];
    final base = calibrated ?? _fallbackAverageStageDuration;
    final minimum = _minimumStageDuration(type, stage);
    return base < minimum ? minimum : base;
  }

  Duration _minimumStageDuration(
    AiAnalysisJobType type,
    AiAnalysisStage stage,
  ) {
    switch (type) {
      case AiAnalysisJobType.diary:
        switch (stage) {
          case AiAnalysisStage.generatingInsight:
            return const Duration(seconds: 35);
          case AiAnalysisStage.embedding:
            return const Duration(seconds: 12);
          case AiAnalysisStage.generatingSummary:
          case AiAnalysisStage.retrieving:
          case AiAnalysisStage.updatingMemory:
            return const Duration(seconds: 8);
          case AiAnalysisStage.segmenting:
          case AiAnalysisStage.preparing:
            return const Duration(seconds: 2);
          case AiAnalysisStage.queued:
          case AiAnalysisStage.completed:
            return Duration.zero;
        }
      case AiAnalysisJobType.embeddingRebuild:
        switch (stage) {
          case AiAnalysisStage.embedding:
            return const Duration(seconds: 12);
          case AiAnalysisStage.generatingSummary:
            return const Duration(seconds: 5);
          case AiAnalysisStage.preparing:
            return const Duration(seconds: 2);
          case AiAnalysisStage.queued:
          case AiAnalysisStage.segmenting:
          case AiAnalysisStage.retrieving:
          case AiAnalysisStage.generatingInsight:
          case AiAnalysisStage.updatingMemory:
          case AiAnalysisStage.completed:
            return const Duration(seconds: 2);
        }
      case AiAnalysisJobType.monthSummary:
      case AiAnalysisJobType.yearSummary:
        switch (stage) {
          case AiAnalysisStage.generatingSummary:
            return const Duration(seconds: 45);
          case AiAnalysisStage.embedding:
            return const Duration(seconds: 12);
          case AiAnalysisStage.segmenting:
            return const Duration(seconds: 8);
          case AiAnalysisStage.preparing:
            return const Duration(seconds: 5);
          case AiAnalysisStage.queued:
          case AiAnalysisStage.retrieving:
          case AiAnalysisStage.generatingInsight:
          case AiAnalysisStage.updatingMemory:
          case AiAnalysisStage.completed:
            return const Duration(seconds: 5);
        }
      case AiAnalysisJobType.userProfile:
        switch (stage) {
          case AiAnalysisStage.generatingSummary:
            return const Duration(seconds: 60);
          case AiAnalysisStage.preparing:
            return const Duration(seconds: 8);
          case AiAnalysisStage.queued:
          case AiAnalysisStage.segmenting:
          case AiAnalysisStage.embedding:
          case AiAnalysisStage.retrieving:
          case AiAnalysisStage.generatingInsight:
          case AiAnalysisStage.updatingMemory:
          case AiAnalysisStage.completed:
            return const Duration(seconds: 5);
        }
    }
  }

  static Set<AiAnalysisStage> _expectedStagesFor(AiAnalysisJobType type) {
    switch (type) {
      case AiAnalysisJobType.diary:
        return const {
          AiAnalysisStage.preparing,
          AiAnalysisStage.generatingSummary,
          AiAnalysisStage.segmenting,
          AiAnalysisStage.embedding,
          AiAnalysisStage.retrieving,
          AiAnalysisStage.generatingInsight,
          AiAnalysisStage.updatingMemory,
        };
      case AiAnalysisJobType.embeddingRebuild:
        return const {
          AiAnalysisStage.preparing,
          AiAnalysisStage.generatingSummary,
          AiAnalysisStage.embedding,
        };
      case AiAnalysisJobType.monthSummary:
      case AiAnalysisJobType.yearSummary:
        return const {
          AiAnalysisStage.preparing,
          AiAnalysisStage.segmenting,
          AiAnalysisStage.embedding,
          AiAnalysisStage.generatingSummary,
        };
      case AiAnalysisJobType.userProfile:
        return const {
          AiAnalysisStage.preparing,
          AiAnalysisStage.generatingSummary,
        };
    }
  }

  String _durationLabel(Duration duration) {
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
}

class AiAnalysisStageCalibration {
  const AiAnalysisStageCalibration({
    required this.stage,
    required this.sampleCount,
    required this.averageDuration,
    required this.durationLabel,
  });

  final AiAnalysisStage stage;
  final int sampleCount;
  final Duration averageDuration;
  final String durationLabel;
}

class _StageDurationSample {
  const _StageDurationSample(this.stage, this.duration);

  final AiAnalysisStage stage;
  final Duration duration;
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

  int ordinalOf(String jobId) {
    final index = jobs.indexWhere((job) => job.id == jobId);
    return index < 0 ? 1 : index + 1;
  }
}
