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
    this.retryCount = 0,
    this.lastError,
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
  final int retryCount;
  final String? lastError;

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
    int? retryCount,
    String? lastError,
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
      retryCount: retryCount ?? this.retryCount,
      lastError: clearLastError ? null : lastError ?? this.lastError,
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
        'retryCount': retryCount,
        'lastError': lastError,
      };

  static AiAnalysisJob fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final stateName =
        json['state'] as String? ?? AiAnalysisJobState.pending.name;
    final stageName =
        json['currentStage'] as String? ?? AiAnalysisStage.queued.name;
    return AiAnalysisJob(
      id: json['id'] as String? ?? '',
      entryId: json['entryId'] as String? ?? '',
      pipelineVersion: json['pipelineVersion'] as int? ?? 1,
      state: AiAnalysisJobState.values.firstWhere(
        (item) => item.name == stateName,
        orElse: () => AiAnalysisJobState.pending,
      ),
      currentStage: AiAnalysisStage.values.firstWhere(
        (item) => item.name == stageName,
        orElse: () => AiAnalysisStage.queued,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      completedStages: (json['completedStages'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .map((name) => AiAnalysisStage.values.firstWhere(
                (item) => item.name == name,
                orElse: () => AiAnalysisStage.queued,
              ))
          .toList(),
      stageLogs: (json['stageLogs'] as List<dynamic>? ?? [])
          .map((item) => AiAnalysisStageLog.fromJson(
              item as Map<String, dynamic>? ?? const {}))
          .toList(),
      retryCount: json['retryCount'] as int? ?? 0,
      lastError: json['lastError'] as String?,
    );
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
    final stageName = json['stage'] as String? ?? AiAnalysisStage.queued.name;
    return AiAnalysisStageLog(
      stage: AiAnalysisStage.values.firstWhere(
        (item) => item.name == stageName,
        orElse: () => AiAnalysisStage.queued,
      ),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ?? now,
      message: json['message'] as String? ?? '',
      inputSummary: json['inputSummary'] as String? ?? '',
      outputSummary: json['outputSummary'] as String? ?? '',
      error: json['error'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }
}

class AiAnalysisQueueSnapshot {
  const AiAnalysisQueueSnapshot({
    required this.jobs,
    this.currentJob,
  });

  final List<AiAnalysisJob> jobs;
  final AiAnalysisJob? currentJob;

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
}
