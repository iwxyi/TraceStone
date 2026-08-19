import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/ai_analysis_job.dart';
import '../../../data/models/diary_analysis_status.dart';
import '../../../data/models/diary_entry.dart';
import '../../../data/models/diary_insight.dart';
import '../../../data/models/period_summary.dart';
import '../../../data/repositories/ai_analysis_queue_bus.dart';
import '../../../data/repositories/ai_analysis_queue_repository.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/repositories/diary_change_bus.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/insight_repository.dart';
import '../../../data/repositories/period_summary_repository.dart';
import '../../../data/services/ai_analysis_queue_runner.dart';
import '../../../data/services/ai_client_service.dart';
import '../../../data/services/location_weather_service.dart';
import '../../ai_insight/presentation/ai_feedback_bar.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.onDiarySaved});

  final ValueChanged<DiaryEntry>? onDiarySaved;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final repository = const DiaryRepository();
  final insightRepository = const InsightRepository();
  final queueRepository = const AiAnalysisQueueRepository();
  final periodSummaryRepository = const PeriodSummaryRepository();
  final queueRunner = const AiAnalysisQueueRunner();
  final locationWeatherService = const LocationWeatherService();
  late Future<List<DiaryEntry>> _entriesFuture =
      repository.getEntriesForDate(DateTime.now());
  late Future<AiAnalysisQueueSnapshot> _queueSnapshotFuture =
      queueRepository.snapshot();
  late Future<_PendingSummaryData> _pendingSummaryFuture =
      _loadPendingSummaryData();
  late Future<_TodayProgressData> _todayProgressFuture =
      _loadTodayProgressData();
  late Future<List<_TodayEchoItem>> _todayEchoFuture = _loadTodayEchoes();
  late final Future<LocationWeather> _locationWeatherFuture =
      locationWeatherService.getCachedCurrent();
  late Future<bool> _developerModeFuture = _loadDeveloperMode();
  bool _isContinuingQueue = false;
  bool _isEnqueueingSummaries = false;
  String? _queueActionDebug;

  @override
  void initState() {
    super.initState();
    DiaryChangeBus.version.addListener(_refreshEntries);
    AiAnalysisQueueBus.version.addListener(_refreshQueue);
    unawaited(_runQueuedAnalysis());
  }

  @override
  void dispose() {
    DiaryChangeBus.version.removeListener(_refreshEntries);
    AiAnalysisQueueBus.version.removeListener(_refreshQueue);
    super.dispose();
  }

  void _refreshEntries() {
    if (!mounted) return;
    setState(() {
      _entriesFuture = repository.getEntriesForDate(DateTime.now());
      _pendingSummaryFuture = _loadPendingSummaryData();
      _todayProgressFuture = _loadTodayProgressData();
      _todayEchoFuture = _loadTodayEchoes();
    });
  }

  void _refreshQueue() {
    if (!mounted) return;
    setState(() {
      _queueSnapshotFuture = queueRepository.snapshot();
      _pendingSummaryFuture = _loadPendingSummaryData();
      _developerModeFuture = _loadDeveloperMode();
    });
  }

  static Future<bool> _loadDeveloperMode() {
    return const DeveloperSettingsRepository().isDeveloperModeEnabled();
  }

  Future<void> _openEditor([String? entryId]) async {
    final result = await Navigator.of(context)
        .pushNamed(AppRoutes.diaryEditPath(entryId), arguments: entryId);
    if (!mounted) return;
    setState(() {
      _entriesFuture = repository.getEntriesForDate(DateTime.now());
      _pendingSummaryFuture = _loadPendingSummaryData();
      _todayProgressFuture = _loadTodayProgressData();
      _todayEchoFuture = _loadTodayEchoes();
    });
    if (result is DiaryEntry) {
      widget.onDiarySaved?.call(result);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_runQueuedAnalysis());
      });
    }
  }

  Future<void> _runQueuedAnalysis({bool rethrowError = false}) async {
    try {
      await queueRunner.processUntilIdle();
    } on Object catch (error, stackTrace) {
      if (rethrowError) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (!mounted) return;
      setState(() {
        _queueActionDebug = '队列执行失败：$error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('整理已停止：$error')),
      );
    }
    if (!mounted) return;
    setState(() {
      _entriesFuture = repository.getEntriesForDate(DateTime.now());
      _queueSnapshotFuture = queueRepository.snapshot();
      _pendingSummaryFuture = _loadPendingSummaryData();
      _todayProgressFuture = _loadTodayProgressData();
      _todayEchoFuture = _loadTodayEchoes();
    });
  }

  Future<void> _retryQueue() async {
    await queueRepository.retryFailedJobs();
    await queueRepository.setPaused(false);
    await _runQueuedAnalysis();
  }

  Future<void> _continueQueue() async {
    if (_isContinuingQueue) return;
    setState(() {
      _isContinuingQueue = true;
      _queueActionDebug = '继续按钮已触发，正在恢复队列...';
      _queueSnapshotFuture = queueRepository.snapshot();
    });
    try {
      await queueRepository.setPaused(false);
      final repaired = await queueRepository.enqueueMissingPeriodDependencies();
      if (!mounted) return;
      if (repaired > 0) {
        setState(() {
          _queueSnapshotFuture = queueRepository.snapshot();
        });
      }
      await _runQueuedAnalysis(rethrowError: true);
      final latest = await queueRepository.snapshot();
      if (!mounted) return;
      setState(() {
        _queueActionDebug = _queueContinueResult(repaired, latest);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _queueActionDebug = '继续失败：$error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('继续整理失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isContinuingQueue = false;
          _queueSnapshotFuture = queueRepository.snapshot();
        });
      }
    }
  }

  String _queueContinueResult(int repaired, AiAnalysisQueueSnapshot snapshot) {
    final firstDependency = snapshot.dependencyReasons.values.firstOrNull;
    final next = snapshot.currentJob;
    final dependencyJob = snapshot.dependencyReasons.keys
        .map((id) => snapshot.jobs.where((job) => job.id == id).firstOrNull)
        .firstOrNull;
    final parts = [
      if (repaired > 0) '已补齐 $repaired 个依赖任务' else '没有新增依赖任务',
      'runnable=${snapshot.runnableCount}',
      'waiting=${snapshot.waitingCount}',
      'blocked=${snapshot.dependencyReasons.length}',
      'runner=${AiAnalysisQueueRunner.debugRunState}',
      'aiRequest=${AiClientService.debugRequestState}',
      if (next != null)
        'next=${next.id}/${next.state.name}/${next.currentStage.name}',
      if (dependencyJob != null) 'blockedJob=${dependencyJob.id}',
      if (firstDependency != null) 'reason=$firstDependency',
    ];
    return parts.join('；');
  }

  Future<void> _toggleQueuePaused(bool paused) async {
    await queueRepository.setPaused(paused);
    if (!paused) {
      await _runQueuedAnalysis();
      return;
    }
    _refreshQueue();
  }

  Future<_AnalysisData> _loadAnalysisData(DiaryEntry entry) async {
    final status = await insightRepository.getStatus(entry.id);
    final insight = await insightRepository.getInsight(entry.id);
    return _AnalysisData(status: status, insight: insight);
  }

  Future<_PendingSummaryData> _loadPendingSummaryData() async {
    final entries = (await repository.listEntries())
        .where((entry) => entry.content.trim().isNotEmpty)
        .toList(growable: false);
    if (entries.isEmpty) return const _PendingSummaryData.empty();

    final summaries = {
      for (final summary in await periodSummaryRepository.listSummaries())
        summary.id: summary,
    };
    final statuses = {
      for (final status in await periodSummaryRepository.listStatuses())
        status.id: status,
    };
    final jobs = {
      for (final job in await queueRepository.listJobs()) job.id: job,
    };
    final months = <String, _PeriodScope>{};
    final years = <String, _PeriodScope>{};
    for (final entry in entries) {
      final monthId = PeriodSummaryRepository.monthId(entry.date);
      months
          .putIfAbsent(
            monthId,
            () =>
                _PeriodScope.month(DateTime(entry.date.year, entry.date.month)),
          )
          .entryIds
          .add(entry.id);
      final yearId = PeriodSummaryRepository.yearId(entry.date.year);
      years
          .putIfAbsent(yearId, () => _PeriodScope.year(entry.date.year))
          .entryIds
          .add(entry.id);
    }

    final actions = <_PeriodSummaryAction>[];
    void collect(_PeriodScope scope) {
      final summary = summaries[scope.id];
      final status = statuses[scope.id];
      final job = jobs[scope.id];
      final hasActiveJob = job != null &&
          job.state != AiAnalysisJobState.completed &&
          job.type == scope.jobType;
      if (summary == null) {
        actions.add(_PeriodSummaryAction(
          scope: scope,
          kind: _PeriodSummaryActionKind.create,
          entryIds: scope.entryIds,
        ));
        return;
      }
      if (status?.needsUpdate ?? false) {
        final changedIds = status!.changedEntryIds
            .where(scope.entryIds.contains)
            .toSet()
            .toList();
        actions.add(_PeriodSummaryAction(
          scope: scope,
          kind: _PeriodSummaryActionKind.update,
          entryIds: changedIds.isEmpty ? scope.entryIds : changedIds,
        ));
        return;
      }
      if (hasActiveJob) {
        actions.add(_PeriodSummaryAction(
          scope: scope,
          kind: _PeriodSummaryActionKind.update,
          entryIds: scope.entryIds,
        ));
      }
    }

    for (final scope in months.values) {
      collect(scope);
    }
    for (final scope in years.values) {
      collect(scope);
    }
    return _PendingSummaryData(actions);
  }

  Future<_TodayProgressData> _loadTodayProgressData() async {
    final now = DateTime.now();
    final entries = await repository.listEntries();
    final monthEntries = entries
        .where((entry) =>
            entry.date.year == now.year && entry.date.month == now.month)
        .toList(growable: false);
    final yearEntries = entries
        .where((entry) => entry.date.year == now.year)
        .toList(growable: false);
    final monthStart = DateTime(now.year, now.month);
    final yearStart = DateTime(now.year);
    return _TodayProgressData(
      now: now,
      monthEntryCount: monthEntries.length,
      monthRecordedDays:
          monthEntries.map((entry) => entry.dayKey).toSet().length,
      monthDiaryMarkers: _recordedDayMarkers(
          monthEntries, monthStart, DateTime(now.year, now.month + 1, 0).day),
      yearEntryCount: yearEntries.length,
      yearRecordedDays: yearEntries.map((entry) => entry.dayKey).toSet().length,
      yearDiaryMarkers: _recordedDayMarkers(
        yearEntries,
        yearStart,
        DateTime(now.year + 1).difference(yearStart).inDays,
      ),
    );
  }

  List<double> _recordedDayMarkers(
    Iterable<DiaryEntry> entries,
    DateTime periodStart,
    int totalDays,
  ) {
    final offsets = entries
        .map((entry) => entry.date.difference(periodStart).inDays)
        .where((offset) => offset >= 0 && offset < totalDays)
        .toSet()
        .toList()
      ..sort();
    return offsets
        .map((offset) => (offset + 0.5) / totalDays)
        .toList(growable: false);
  }

  Future<List<_TodayEchoItem>> _loadTodayEchoes() async {
    final now = DateTime.now();
    final todayKey = DiaryEntry.dateKey(now);
    final entries = (await repository.listEntries())
        .where((entry) => entry.dayKey != todayKey)
        .where((entry) =>
            entry.date.isBefore(DateTime(now.year, now.month, now.day)))
        .toList(growable: false);
    final echoes = <_TodayEchoItem>[];
    for (final entry in entries) {
      final yearDistance = now.year - entry.date.year;
      if (yearDistance <= 0) continue;
      final offset = _monthDayOffset(entry.date, now);
      if (offset.abs() > 3) continue;
      echoes.add(_TodayEchoItem(
        entry: entry,
        dayOffset: offset,
        yearDistance: yearDistance,
      ));
    }
    echoes.sort((a, b) {
      final byOffset = a.dayOffset.abs().compareTo(b.dayOffset.abs());
      if (byOffset != 0) return byOffset;
      return a.yearDistance.compareTo(b.yearDistance);
    });
    return echoes.take(2).toList(growable: false);
  }

  int _monthDayOffset(DateTime entryDate, DateTime now) {
    final anchor = DateTime(now.year, entryDate.month, entryDate.day);
    return anchor.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  Future<void> _summarizeNow(_PendingSummaryData data) async {
    if (_isEnqueueingSummaries || !data.hasWork) return;
    setState(() {
      _isEnqueueingSummaries = true;
    });
    try {
      final version = DateTime.now().microsecondsSinceEpoch;
      final monthActions = data.actions
          .where((action) => action.scope.type == PeriodSummaryType.month)
          .toList()
        ..sort((a, b) => a.scope.start.compareTo(b.scope.start));
      final yearActions = data.actions
          .where((action) => action.scope.type == PeriodSummaryType.year)
          .toList()
        ..sort((a, b) => a.scope.start.compareTo(b.scope.start));
      for (final action in monthActions) {
        await queueRepository.enqueueMonthSummary(
          action.scope.start,
          pipelineVersion: version,
        );
      }
      for (final action in yearActions) {
        await queueRepository.enqueueYearSummary(
          action.scope.start.year,
          pipelineVersion: version,
          includeMonthSummaries: false,
        );
      }
      await queueRepository.setPaused(false);
      unawaited(_runQueuedAnalysis());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入总结队列：${data.periodCountLabel}')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加入总结队列失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isEnqueueingSummaries = false;
          _queueSnapshotFuture = queueRepository.snapshot();
          _pendingSummaryFuture = _loadPendingSummaryData();
        });
      }
    }
  }

  Widget _buildQueueCard() {
    return FutureBuilder<AiAnalysisQueueSnapshot>(
      future: _queueSnapshotFuture,
      builder: (context, snapshot) {
        final queue = snapshot.data;
        if (queue == null || !queue.hasVisibleWork) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: FutureBuilder<bool>(
            future: _developerModeFuture,
            builder: (context, developerSnapshot) => _AiQueueCard(
              snapshot: queue,
              isContinuing: _isContinuingQueue,
              developerMode: developerSnapshot.data ?? false,
              actionDebug: _queueActionDebug,
              onContinue: _continueQueue,
              onRetry: _retryQueue,
              onPauseChanged: _toggleQueuePaused,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingSummaryCard() {
    return FutureBuilder<_PendingSummaryData>(
      future: _pendingSummaryFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || !data.hasWork) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _PendingSummaryCard(
            data: data,
            isWorking: _isEnqueueingSummaries,
            onPressed: () => _summarizeNow(data),
          ),
        );
      },
    );
  }

  Widget _buildProgressCard() {
    return FutureBuilder<_TodayProgressData>(
      future: _todayProgressFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _TodayProgressCard(data: data),
        );
      },
    );
  }

  Widget _buildEchoCard() {
    return FutureBuilder<List<_TodayEchoItem>>(
      future: _todayEchoFuture,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <_TodayEchoItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _TodayEchoCard(
            items: items,
            onTap: (entry) => _openEditor(entry.id),
          ),
        );
      },
    );
  }

  Widget _buildAnalysisCard(DiaryEntry entry) {
    return FutureBuilder<_AnalysisData>(
      future: _loadAnalysisData(entry),
      builder: (context, snapshot) {
        return _TodayAnalysisCard(
          entry: entry,
          data: snapshot.data,
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant TodayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) {
      unawaited(_runQueuedAnalysis());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DiaryEntry>>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: _TodayTitle(
                date: DateTime.now(),
                locationWeatherFuture: _locationWeatherFuture,
              ),
            ),
            body: Center(
              child: FilledButton.icon(
                onPressed: _refreshEntries,
                icon: const Icon(Icons.refresh),
                label: const Text('加载日记失败，点击重试'),
              ),
            ),
          );
        }
        final entries = snapshot.data ?? [];
        final latestEntry = entries.isEmpty ? null : entries.first;

        return Scaffold(
          appBar: AppBar(
            title: _TodayTitle(
              date: DateTime.now(),
              locationWeatherFuture: _locationWeatherFuture,
            ),
            actions: [
              IconButton(
                tooltip: '搜索',
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.search),
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openEditor(),
            child: const Icon(Icons.add),
          ),
          body: ListView(
            key: const PageStorageKey('today-feed'),
            padding: const EdgeInsets.all(20),
            children: [
              _buildQueueCard(),
              if (entries.isEmpty)
                _NewDiaryCard(onTap: () => _openEditor())
              else
                for (final entry in entries) ...[
                  _DiaryPreviewCard(
                    entry: entry,
                    onTap: () => _openEditor(entry.id),
                  ),
                  const SizedBox(height: 10),
                ],
              if (latestEntry != null) ...[
                const SizedBox(height: 16),
                _buildAnalysisCard(latestEntry),
              ],
              const SizedBox(height: 6),
              _buildProgressCard(),
              _buildPendingSummaryCard(),
              _buildEchoCard(),
            ],
          ),
        );
      },
    );
  }
}

class _AnalysisData {
  const _AnalysisData({required this.status, required this.insight});

  final DiaryAnalysisStatus? status;
  final DiaryInsight? insight;
}

class _PendingSummaryData {
  const _PendingSummaryData(this.actions);

  const _PendingSummaryData.empty() : actions = const [];

  final List<_PeriodSummaryAction> actions;

  bool get hasWork => actions.isNotEmpty;

  bool get hasCreate =>
      actions.any((action) => action.kind == _PeriodSummaryActionKind.create);

  int get pendingEntryCount {
    final ids = <String>{};
    for (final action in actions) {
      ids.addAll(action.entryIds);
    }
    return ids.length;
  }

  int get monthCount => actions
      .where((action) => action.scope.type == PeriodSummaryType.month)
      .map((action) => action.scope.id)
      .toSet()
      .length;

  int get yearCount => actions
      .where((action) => action.scope.type == PeriodSummaryType.year)
      .map((action) => action.scope.id)
      .toSet()
      .length;

  String get actionLabel => hasCreate ? '立即总结' : '立即更新总结';

  String get title {
    final count = pendingEntryCount;
    if (hasCreate) return '$count 篇日记待总结';
    return '$count 篇日记待更新总结';
  }

  String get periodCountLabel {
    final parts = [
      if (monthCount > 0) '$monthCount 个月',
      if (yearCount > 0) '$yearCount 年',
    ];
    return parts.isEmpty ? '暂无周期' : parts.join(' · ');
  }
}

enum _PeriodSummaryActionKind { create, update }

class _PeriodSummaryAction {
  const _PeriodSummaryAction({
    required this.scope,
    required this.kind,
    required this.entryIds,
  });

  final _PeriodScope scope;
  final _PeriodSummaryActionKind kind;
  final Iterable<String> entryIds;
}

class _PeriodScope {
  _PeriodScope.month(this.start)
      : type = PeriodSummaryType.month,
        id = PeriodSummaryRepository.monthId(start);

  _PeriodScope.year(int year)
      : type = PeriodSummaryType.year,
        start = DateTime(year),
        id = PeriodSummaryRepository.yearId(year);

  final PeriodSummaryType type;
  final DateTime start;
  final String id;
  final Set<String> entryIds = {};

  AiAnalysisJobType get jobType => type == PeriodSummaryType.month
      ? AiAnalysisJobType.monthSummary
      : AiAnalysisJobType.yearSummary;
}

class _PendingSummaryCard extends StatelessWidget {
  const _PendingSummaryCard({
    required this.data,
    required this.isWorking,
    required this.onPressed,
  });

  final _PendingSummaryData data;
  final bool isWorking;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _HomeCard(
      child: Row(
        children: [
          Icon(Icons.auto_stories_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(data.periodCountLabel, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            onPressed: isWorking ? null : onPressed,
            child: isWorking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(data.actionLabel),
          ),
        ],
      ),
    );
  }
}

class _TodayProgressData {
  const _TodayProgressData({
    required this.now,
    required this.monthEntryCount,
    required this.monthRecordedDays,
    required this.monthDiaryMarkers,
    required this.yearEntryCount,
    required this.yearRecordedDays,
    required this.yearDiaryMarkers,
  });

  final DateTime now;
  final int monthEntryCount;
  final int monthRecordedDays;
  final List<double> monthDiaryMarkers;
  final int yearEntryCount;
  final int yearRecordedDays;
  final List<double> yearDiaryMarkers;

  int get daysInMonth => DateTime(now.year, now.month + 1, 0).day;

  int get dayOfYear => now.difference(DateTime(now.year)).inDays + 1;

  int get daysInYear =>
      DateTime(now.year + 1).difference(DateTime(now.year)).inDays;

  double get monthProgress => (now.day / daysInMonth).clamp(0.0, 1.0);

  double get yearProgress => (dayOfYear / daysInYear).clamp(0.0, 1.0);

  List<double> get monthWeekMarkers => List<int>.generate(
        daysInMonth - 1,
        (index) => index + 2,
        growable: false,
      )
          .where((day) =>
              DateTime(now.year, now.month, day).weekday == DateTime.monday)
          // A divider at the start of Monday separates the prior Sunday.
          .map((day) => (day - 1) / daysInMonth)
          .toList(growable: false);

  List<double> get yearMonthMarkers {
    final yearStart = DateTime(now.year);
    return List<double>.generate(
      11,
      (index) =>
          DateTime(now.year, index + 2).difference(yearStart).inDays /
          daysInYear,
      growable: false,
    );
  }
}

class _TodayProgressCard extends StatelessWidget {
  const _TodayProgressCard({required this.data});

  final _TodayProgressData data;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('时光刻度',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          _ProgressLine(
            label: '本月',
            progress: data.monthProgress,
            percent: '${(data.monthProgress * 100).round()}%',
            meta: '${data.monthRecordedDays} 天 · ${data.monthEntryCount} 篇',
            markers: data.monthWeekMarkers,
            diaryMarkers: data.monthDiaryMarkers,
          ),
          const SizedBox(height: 14),
          _ProgressLine(
            label: '今年',
            progress: data.yearProgress,
            percent: '${(data.yearProgress * 100).round()}%',
            meta: '${data.yearRecordedDays} 天 · ${data.yearEntryCount} 篇',
            markers: data.yearMonthMarkers,
            diaryMarkers: data.yearDiaryMarkers,
          ),
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.progress,
    required this.percent,
    required this.meta,
    required this.markers,
    required this.diaryMarkers,
  });

  final String label;
  final double progress;
  final String percent;
  final String meta;
  final List<double> markers;
  final List<double> diaryMarkers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Expanded(
              child: Text(meta, style: theme.textTheme.bodySmall),
            ),
            Text(percent, style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        _SegmentedProgressBar(
          progress: progress,
          markers: markers,
          diaryMarkers: diaryMarkers,
        ),
      ],
    );
  }
}

class _SegmentedProgressBar extends StatelessWidget {
  const _SegmentedProgressBar({
    required this.progress,
    required this.markers,
    required this.diaryMarkers,
  });

  final double progress;
  final List<double> markers;
  final List<double> diaryMarkers;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 5,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: progress, minHeight: 5),
              ),
              IgnorePointer(
                child: Stack(
                  children: [
                    for (final marker in markers)
                      Positioned(
                        left: (constraints.maxWidth * marker - 0.5)
                            .clamp(0.0, constraints.maxWidth - 1),
                        top: 0,
                        bottom: 0,
                        child: Container(width: 1, color: colorScheme.surface),
                      ),
                    for (final marker in diaryMarkers)
                      Positioned(
                        left: (constraints.maxWidth * marker - 2.5)
                            .clamp(0.0, constraints.maxWidth - 5),
                        top: 0,
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.primary,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TodayEchoItem {
  const _TodayEchoItem({
    required this.entry,
    required this.dayOffset,
    required this.yearDistance,
  });

  final DiaryEntry entry;
  final int dayOffset;
  final int yearDistance;

  String get label {
    final dayText = dayOffset == 0
        ? '今日'
        : dayOffset > 0
            ? '后 $dayOffset 天'
            : '前 ${dayOffset.abs()} 天';
    return '$yearDistance 年前$dayText';
  }
}

class _TodayEchoCard extends StatelessWidget {
  const _TodayEchoCard({required this.items, required this.onTap});

  final List<_TodayEchoItem> items;
  final ValueChanged<DiaryEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('今日回声',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          for (var index = 0; index < items.length; index++) ...[
            _TodayEchoTile(item: items[index], onTap: onTap),
            if (index != items.length - 1)
              Divider(
                height: 18,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
          ],
        ],
      ),
    );
  }
}

class _TodayEchoTile extends StatelessWidget {
  const _TodayEchoTile({required this.item, required this.onTap});

  final _TodayEchoItem item;
  final ValueChanged<DiaryEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onTap(item.entry),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(item.label,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.primary)),
                const Spacer(),
                Text(
                  '${item.entry.date.year}.${item.entry.date.month.toString().padLeft(2, '0')}.${item.entry.date.day.toString().padLeft(2, '0')}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.entry.title ?? item.entry.bodyPreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayTitle extends StatelessWidget {
  const _TodayTitle({required this.date, required this.locationWeatherFuture});

  final DateTime date;
  final Future<LocationWeather> locationWeatherFuture;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final title = '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';

    return FutureBuilder<LocationWeather>(
      future: locationWeatherFuture,
      initialData: LocationWeatherService.cachedCurrent,
      builder: (context, snapshot) {
        final hasData = snapshot.hasData;
        final metaLabel = !hasData &&
                (snapshot.connectionState == ConnectionState.waiting ||
                    snapshot.connectionState == ConnectionState.active)
            ? '定位中'
            : _locationWeatherLabel(snapshot.data);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            if (metaLabel != null) ...[
              const SizedBox(height: 2),
              Text(metaLabel, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        );
      },
    );
  }

  String? _locationWeatherLabel(LocationWeather? value) {
    if (value == null || value.isMissing) return '地点天气未获取';
    final location = value.locationName.trim();
    final weather = [
      value.weather.trim(),
      if (value.temperature.trim().isNotEmpty) value.temperature.trim(),
    ].where((item) => item.isNotEmpty && item != '天气').join(' ');
    final parts = [
      if (location.isNotEmpty && location != '未选择地点') location,
      if (weather.isNotEmpty) weather,
    ];
    if (parts.isEmpty) return '地点天气未获取';
    return parts.join(' · ');
  }
}

class _NewDiaryCard extends StatelessWidget {
  const _NewDiaryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      onTap: onTap,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('留下今天',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          SizedBox(height: 10),
          Text('写几句话就好，不用完整，也不用漂亮。'),
          SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _DiaryPreviewCard extends StatelessWidget {
  const _DiaryPreviewCard({required this.entry, required this.onTap});

  final DiaryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.title != null) ...[
            Text(entry.title!,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
          ],
          Text(
            entry.bodyPreview,
            maxLines: AppConstants.diaryPreviewMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _AiQueueCard extends StatelessWidget {
  const _AiQueueCard({
    required this.snapshot,
    required this.isContinuing,
    required this.developerMode,
    required this.actionDebug,
    required this.onContinue,
    required this.onRetry,
    required this.onPauseChanged,
  });

  final AiAnalysisQueueSnapshot snapshot;
  final bool isContinuing;
  final bool developerMode;
  final String? actionDebug;
  final Future<void> Function() onContinue;
  final VoidCallback onRetry;
  final Future<void> Function(bool paused) onPauseChanged;

  @override
  Widget build(BuildContext context) {
    final job = snapshot.currentJob;
    final theme = Theme.of(context);
    final hasRunning = AiAnalysisQueueRunner.isRunning ||
        job?.state == AiAnalysisJobState.running;
    final hasFailed = snapshot.failedCount > 0 && !hasRunning;
    final failedJob = hasFailed ? snapshot.firstFailedJob : null;
    final isResuming = job?.state == AiAnalysisJobState.incomplete;
    final hasVisibleWork = snapshot.hasVisibleWork;
    final dependencyReason = snapshot.dependencyReasons.values.firstOrNull;
    final hasFailedDependency = dependencyReason?.contains('整理失败') ?? false;
    final title = snapshot.isPaused
        ? '记忆整理已暂停'
        : hasFailed
            ? '有日记整理失败'
            : isResuming
                ? '继续整理记忆'
                : job == null
                    ? (hasVisibleWork ? '记忆整理等待继续' : '暂无待整理记忆')
                    : '正在整理记忆';
    final stage = hasFailedDependency
        ? dependencyReason
        : job?.stageLabel ??
            failedJob?.stageLabel ??
            dependencyReason ??
            (hasVisibleWork ? '等待继续' : '当前没有新的整理任务');
    final errorText = job?.lastError ?? failedJob?.lastError;
    final waiting = snapshot.waitingCount;
    final currentBatch = job == null ? null : snapshot.batchForJob(job.id);
    final continueOnly = !snapshot.isPaused && !hasRunning && hasVisibleWork;
    final canPauseRunningQueue =
        isContinuing && hasRunning && !snapshot.isPaused;
    final primaryActionLabel = canPauseRunningQueue
        ? '暂停'
        : isContinuing
            ? '继续中'
            : snapshot.isPaused || continueOnly
                ? '继续'
                : '暂停';
    final primaryAction = canPauseRunningQueue
        ? () => onPauseChanged(true)
        : snapshot.isPaused || continueOnly
            ? onContinue
            : () => onPauseChanged(true);
    final totalActive = snapshot.runnableCount +
        (job?.state == AiAnalysisJobState.running ? 1 : 0);
    final batchProgress = job == null
        ? ''
        : currentBatch != null
            ? '已完成 ${currentBatch.completedCount}/${currentBatch.totalCount} 篇'
            : totalActive <= 0
                ? ''
                : '已完成 ${snapshot.completedCount}/${snapshot.totalTrackedCount} 篇';
    final progress = job == null
        ? 0.0
        : (job.completedStages.length / _pipelineStageCount).clamp(0.0, 1.0);
    final metrics = _pendingMetrics();

    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasFailed
                    ? Icons.error_outline
                    : Icons.auto_awesome_motion_outlined,
                color: hasFailed
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: isContinuing && !canPauseRunningQueue
                    ? null
                    : primaryAction,
                child: isContinuing && !canPauseRunningQueue
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          Text(primaryActionLabel),
                        ],
                      )
                    : Text(primaryActionLabel),
              ),
              if (hasFailed)
                TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final metric in metrics)
                  _AiQueueMetricChip(metric: metric),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (job != null) ...[
            LinearProgressIndicator(value: progress, minHeight: 3),
            const SizedBox(height: 10),
          ],
          if (batchProgress.isNotEmpty) ...[
            Text(batchProgress, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
          ],
          Text(snapshot.isPaused
              ? '已暂停，继续后会从当前队列位置整理：${stage ?? '等待处理'}'
              : isResuming
                  ? '上次整理被中断，将从已完成阶段继续：${stage ?? '等待处理'}'
                  : stage ?? '等待处理'),
          if (snapshot.estimatedRemainingLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('预计剩余 ${snapshot.estimatedRemainingLabel}',
                style: theme.textTheme.bodySmall),
          ],
          if (job != null && job.completedStages.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '已完成 ${job.completedStages.length}/$_pipelineStageCount 个阶段',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (snapshot.incompleteCount > 0 && !isResuming) ...[
            const SizedBox(height: 4),
            Text('有 ${snapshot.incompleteCount} 篇会从中断处恢复。',
                style: theme.textTheme.bodySmall),
          ],
          if (waiting > 0) ...[
            const SizedBox(height: 4),
            Text('还有 $waiting 篇等待后台串行继续。', style: theme.textTheme.bodySmall),
          ],
          if (errorText != null && errorText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(errorText,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
          if (developerMode) ...[
            const SizedBox(height: 10),
            _HomeQueueDebug(
              snapshot: snapshot,
              actionDebug: actionDebug,
            ),
          ],
        ],
      ),
    );
  }

  int get _pipelineStageCount => AiAnalysisStage.values
      .where((stage) =>
          stage != AiAnalysisStage.queued && stage != AiAnalysisStage.completed)
      .length;

  List<_AiQueueMetric> _pendingMetrics() {
    final activeJobs = snapshot.jobs
        .where((job) => job.state != AiAnalysisJobState.completed)
        .toList(growable: false);
    int count(bool Function(AiAnalysisJob job) test) =>
        activeJobs.where(test).length;
    return [
      _AiQueueMetric('日记', count((job) => job.type == AiAnalysisJobType.diary)),
      _AiQueueMetric('相似度',
          count((job) => job.type == AiAnalysisJobType.embeddingRebuild)),
      _AiQueueMetric(
        '总结',
        count((job) =>
            job.type == AiAnalysisJobType.monthSummary ||
            job.type == AiAnalysisJobType.yearSummary),
      ),
      _AiQueueMetric(
          '画像', count((job) => job.type == AiAnalysisJobType.userProfile)),
    ].where((metric) => metric.count > 0).toList(growable: false);
  }
}

class _AiQueueMetric {
  const _AiQueueMetric(this.label, this.count);

  final String label;
  final int count;
}

class _AiQueueMetricChip extends StatelessWidget {
  const _AiQueueMetricChip({required this.metric});

  final _AiQueueMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          '${metric.label} ${metric.count}',
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
  }
}

class _HomeQueueDebug extends StatelessWidget {
  const _HomeQueueDebug({required this.snapshot, required this.actionDebug});

  final AiAnalysisQueueSnapshot snapshot;
  final String? actionDebug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _debugLines();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('开发者队列诊断', style: theme.textTheme.labelMedium),
                ),
                IconButton(
                  tooltip: '复制诊断',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: () => _copyDebug(context, lines),
                  icon: const Icon(Icons.copy_all_outlined),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(line, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _debugLines() {
    final job = snapshot.currentJob ?? snapshot.jobs.firstOrNull;
    final dependency = snapshot.dependencyReasons.entries.firstOrNull;
    final dependencyJob = dependency == null ? null : _jobById(dependency.key);
    final lastLog = job?.stageLogs.lastOrNull;
    return [
      if ((actionDebug ?? '').isNotEmpty) 'action: $actionDebug',
      'queue: paused=${snapshot.isPaused} jobs=${snapshot.jobs.length} runnable=${snapshot.runnableCount} waiting=${snapshot.waitingCount} blocked=${snapshot.dependencyReasons.length} failed=${snapshot.failedCount}',
      if (job != null)
        'job: ${job.id} type=${job.type.name} state=${job.state.name} stage=${job.currentStage.name} canRun=${job.canRun} retry=${job.retryCount}',
      if ((job?.lastError ?? '').isNotEmpty) 'error: ${job!.lastError}',
      if (dependency != null)
        'dependency: ${dependency.key}=${dependency.value}${dependencyJob == null ? '' : ' state=${dependencyJob.state.name} type=${dependencyJob.type.name} canRun=${dependencyJob.canRun}'}',
      if (lastLog != null)
        'lastLog: ${lastLog.stage.name} ${lastLog.message}${(lastLog.error ?? '').isEmpty ? '' : ' error=${lastLog.error}'}',
    ];
  }

  AiAnalysisJob? _jobById(String id) {
    for (final job in snapshot.jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  Future<void> _copyDebug(BuildContext context, List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制队列诊断')),
    );
  }
}

class _TodayAnalysisCard extends StatelessWidget {
  const _TodayAnalysisCard({
    required this.entry,
    required this.data,
  });

  final DiaryEntry entry;
  final _AnalysisData? data;

  @override
  Widget build(BuildContext context) {
    final status = data?.status;
    final insight = data?.insight;
    if (status?.state == DiaryAnalysisState.queued ||
        status?.state == DiaryAnalysisState.analyzing ||
        status?.state == DiaryAnalysisState.incomplete) {
      return _AnalysisLoadingCard(message: status?.message);
    }
    if (status?.state == DiaryAnalysisState.failed) {
      return _AnalysisErrorCard(message: status?.message ?? '分析失败');
    }
    if (insight == null) return const _AnalysisEmptyCard();
    return _AnalysisResultCard(insight: insight);
  }
}

class _AnalysisEmptyCard extends StatelessWidget {
  const _AnalysisEmptyCard();

  @override
  Widget build(BuildContext context) {
    return const _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日日记分析',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          SizedBox(height: 10),
          Text('等待分析'),
        ],
      ),
    );
  }
}

class _AnalysisErrorCard extends StatelessWidget {
  const _AnalysisErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('分析失败',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(message),
        ],
      ),
    );
  }
}

class _AnalysisLoadingCard extends StatefulWidget {
  const _AnalysisLoadingCard({this.message});

  final String? message;

  @override
  State<_AnalysisLoadingCard> createState() => _AnalysisLoadingCardState();
}

class _AnalysisLoadingCardState extends State<_AnalysisLoadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final opacity = 0.45 + _controller.value * 0.35;
          return Opacity(
            opacity: opacity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('正在分析今天',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(widget.message ?? '分析中'),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AnalysisResultCard extends StatelessWidget {
  const _AnalysisResultCard({required this.insight});

  final DiaryInsight insight;

  @override
  Widget build(BuildContext context) {
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('今日日记分析',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (insight.reflection.isNotEmpty)
            SimpleMarkdownText(text: insight.reflection),
          if (insight.relatedMemories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('和过去的关联', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final memory in insight.relatedMemories.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                    '· ${memory.title}${memory.reason.isEmpty ? '' : '：${memory.reason}'}'),
              ),
          ],
          if (insight.stoneTitle.isNotEmpty ||
              insight.stoneDescription.isNotEmpty ||
              insight.suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('给我的建议', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (insight.stoneTitle.isNotEmpty)
              Text(insight.stoneTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            if (insight.stoneDescription.isNotEmpty)
              SimpleMarkdownText(text: insight.stoneDescription),
            for (final suggestion in insight.suggestions.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('· ${suggestion.text}'),
              ),
          ],
          FutureBuilder<bool>(
            future:
                const DeveloperSettingsRepository().isDeveloperModeEnabled(),
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return _DeveloperInsightPanel(insight: insight);
            },
          ),
          const SizedBox(height: 12),
          AiFeedbackBar(entryId: insight.entryId),
        ],
      ),
    );
  }
}

class _DeveloperInsightPanel extends StatelessWidget {
  const _DeveloperInsightPanel({required this.insight});

  final DiaryInsight insight;

  @override
  Widget build(BuildContext context) {
    final lines = [
      _countLine('facts', insight.facts.length),
      _countLine('signals', insight.signals.length),
      _countLine('hypotheses', insight.hypotheses.length),
      _countLine('suggestions', insight.suggestions.length),
      _countLine('profileCandidates', insight.profileUpdateCandidates.length),
      _countLine('relationshipUpdates', insight.relationshipUpdates.length),
      _countLine('contradictions', insight.contradictions.length),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: const Text('开发者分析结构'),
        subtitle: Text(lines.join(' · '),
            style: Theme.of(context).textTheme.bodySmall),
        children: [
          _ClaimDebugGroup(title: 'Facts', claims: insight.facts),
          _ClaimDebugGroup(title: 'Signals', claims: insight.signals),
          _ClaimDebugGroup(title: 'Hypotheses', claims: insight.hypotheses),
          _ClaimDebugGroup(title: 'Suggestions', claims: insight.suggestions),
          _UpdateDebugGroup(insight: insight),
        ],
      ),
    );
  }

  String _countLine(String label, int count) => '$label=$count';
}

class _ClaimDebugGroup extends StatelessWidget {
  const _ClaimDebugGroup({required this.title, required this.claims});

  final String title;
  final List<InsightClaim> claims;

  @override
  Widget build(BuildContext context) {
    if (claims.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final claim in claims)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_claimLine(claim)),
            ),
        ],
      ),
    );
  }

  String _claimLine(InsightClaim claim) {
    final evidence = claim.evidence.map((item) {
      final id = item.id.isEmpty ? '' : ':${item.id}';
      return '${item.type}$id';
    }).join(',');
    return [
      claim.text,
      if (claim.confidence != null)
        'confidence=${claim.confidence!.toStringAsFixed(2)}',
      if (evidence.isNotEmpty) 'evidence=$evidence',
    ].join(' | ');
  }
}

class _UpdateDebugGroup extends StatelessWidget {
  const _UpdateDebugGroup({required this.insight});

  final DiaryInsight insight;

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final item in insight.profileUpdateCandidates)
        'profile ${item.field}=${item.value} confidence=${_confidence(item.confidence)}',
      for (final item in insight.relationshipUpdates)
        'relationship ${item.personName} ${item.summary} confidence=${_confidence(item.confidence)}',
      for (final item in insight.contradictions)
        'contradiction ${item.oldMemoryId} ${item.newEvidence} confidence=${_confidence(item.confidence)}',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Update Candidates',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line),
            ),
        ],
      ),
    );
  }

  String _confidence(double? value) =>
      value == null ? '' : value.toStringAsFixed(2);
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shinen = theme.shinenColors;
    return Card(
      elevation: theme.cardTheme.elevation ?? 0,
      color: theme.cardTheme.color,
      clipBehavior: Clip.antiAlias,
      shape: theme.cardTheme.shape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(shinen.cardRadius),
            side: shinen.cardBorderSide(theme.colorScheme.outline),
          ),
      child: InkWell(
        borderRadius: BorderRadius.circular(shinen.cardRadius),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      ),
    );
  }
}
