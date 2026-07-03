import '../models/ai_analysis_job.dart';
import '../models/ai_feedback.dart';
import '../models/diary_analysis_status.dart';
import '../repositories/ai_analysis_queue_repository.dart';
import '../repositories/ai_feedback_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/insight_repository.dart';
import '../repositories/memory_repository.dart';

class AiFeedbackService {
  const AiFeedbackService({
    AiFeedbackRepository? feedbackRepository,
    MemoryRepository? memoryRepository,
    DiaryRepository? diaryRepository,
    InsightRepository? insightRepository,
    AiAnalysisQueueRepository? queueRepository,
  })  : _feedbackRepository =
            feedbackRepository ?? const AiFeedbackRepository(),
        _memoryRepository = memoryRepository ?? const MemoryRepository(),
        _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _queueRepository = queueRepository ?? const AiAnalysisQueueRepository();

  final AiFeedbackRepository _feedbackRepository;
  final MemoryRepository _memoryRepository;
  final DiaryRepository _diaryRepository;
  final InsightRepository _insightRepository;
  final AiAnalysisQueueRepository _queueRepository;

  Future<AiFeedback> submitInsightFeedback({
    required String entryId,
    required AiFeedbackValue value,
    String? note,
  }) async {
    final feedback = AiFeedback(
      entryId: entryId,
      value: value,
      createdAt: DateTime.now(),
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
    );
    await _feedbackRepository.saveFeedback(feedback);
    await _memoryRepository.applyFeedback(
      sourceEntryId: entryId,
      value: value,
    );

    if (value == AiFeedbackValue.inaccurate) {
      await _enqueueInsightRegeneration(feedback);
    }
    return feedback;
  }

  Future<void> _enqueueInsightRegeneration(AiFeedback feedback) async {
    final entry = await _diaryRepository.getEntryById(feedback.entryId);
    if (entry == null) return;

    await _insightRepository.deleteForEntry(entry.id);
    await _queueRepository.enqueueEntry(entry);
    final job = await _queueRepository.getJob(entry.id);
    if (job == null) return;

    final now = DateTime.now();
    await _queueRepository.saveJob(job.copyWith(
      state: AiAnalysisJobState.incomplete,
      currentStage: AiAnalysisStage.generatingInsight,
      updatedAt: now,
      completedStages: const [
        AiAnalysisStage.preparing,
        AiAnalysisStage.segmenting,
        AiAnalysisStage.generatingSummary,
        AiAnalysisStage.embedding,
        AiAnalysisStage.retrieving,
      ],
      stageLogs: [
        ...job.stageLogs,
        AiAnalysisStageLog(
          stage: AiAnalysisStage.generatingInsight,
          startedAt: now,
          message: '用户标记洞察不准确，重新生成今日洞察',
          inputSummary: 'entryId=${entry.id}',
          outputSummary: feedback.note == null
              ? 'feedback=inaccurate'
              : 'feedback=inaccurate note=${_compactNote(feedback.note!)}',
        ),
      ],
      lastError: '用户标记洞察不准确，等待重新生成',
    ));
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: entry.id,
      state: DiaryAnalysisState.incomplete,
      updatedAt: now,
      message: '已根据反馈加入重新整理队列',
    ));
  }

  String _compactNote(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 160) return normalized;
    return '${normalized.substring(0, 160)}...';
  }
}
