import 'dart:async';

import '../repositories/diary_repository.dart';
import 'ai_analysis_queue_runner.dart';

typedef StartupTask = Future<void> Function();

class AppStartupService {
  const AppStartupService({
    StartupTask? purgeExpiredTrash,
    StartupTask? resumeAiQueue,
  })  : _purgeExpiredTrash = purgeExpiredTrash,
        _resumeAiQueue = resumeAiQueue;

  final StartupTask? _purgeExpiredTrash;
  final StartupTask? _resumeAiQueue;

  Future<void> runBeforeApp() async {
    final task = _purgeExpiredTrash;
    if (task != null) {
      await task();
      return;
    }
    await const DiaryRepository().purgeExpiredTrash();
  }

  void runAfterAppStart() {
    unawaited(resumeAiQueue());
  }

  Future<void> resumeAiQueue() async {
    final task = _resumeAiQueue;
    if (task != null) {
      await task();
      return;
    }
    await const AiAnalysisQueueRunner().processUntilIdle(maxJobs: 1);
  }
}
