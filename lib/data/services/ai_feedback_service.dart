import '../models/ai_analysis_job.dart';
import '../models/ai_feedback.dart';
import '../models/diary_analysis_status.dart';
import '../models/diary_insight.dart';
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
    final previousInsight = value == AiFeedbackValue.inaccurate
        ? await _insightRepository.getInsight(entryId)
        : null;
    final feedback = AiFeedback(
      entryId: entryId,
      value: value,
      createdAt: DateTime.now(),
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      previousInsightSummary: previousInsight == null
          ? null
          : _previousInsightSummary(previousInsight),
      previousInsightSources: previousInsight == null
          ? const []
          : _previousInsightSources(previousInsight),
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
          outputSummary: _feedbackOutputSummary(feedback),
        ),
      ],
      lastError: '用户标记洞察不准确，等待重新生成',
    ));
    await _insightRepository.saveStatus(DiaryAnalysisStatus(
      entryId: entry.id,
      state: DiaryAnalysisState.queued,
      updatedAt: now,
      message: '已根据反馈加入重新整理队列',
    ));
  }

  String _compactNote(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 160) return normalized;
    return '${normalized.substring(0, 160)}...';
  }

  String _feedbackOutputSummary(AiFeedback feedback) {
    return [
      'feedback=${feedback.value.name}',
      if (feedback.note != null) 'note=${_compactNote(feedback.note!)}',
      if (feedback.previousInsightSummary != null) 'previousInsight=attached',
      if (feedback.previousInsightSources.isNotEmpty)
        'previousSources=${feedback.previousInsightSources.length}',
    ].join(' ');
  }

  String _previousInsightSummary(DiaryInsight insight) {
    final parts = <String>[
      if (insight.reflection.trim().isNotEmpty)
        '读后感：${insight.reflection.trim()}',
      if (insight.emotion.trim().isNotEmpty) '情绪：${insight.emotion.trim()}',
      if (insight.keywords.isNotEmpty)
        '关键词：${insight.keywords.take(8).join('、')}',
      if (insight.relatedMemories.isNotEmpty)
        '关联记忆：${insight.relatedMemories.take(3).map((item) => [
              item.title,
              item.reason,
              if (item.entryId != null) item.entryId!,
            ].where((part) => part.trim().isNotEmpty).join('/')).join('；')}',
      if (insight.facts.isNotEmpty)
        '事实：${insight.facts.take(3).map((item) => item.text).join('；')}',
      if (insight.signals.isNotEmpty)
        '信号：${insight.signals.take(3).map((item) => item.text).join('；')}',
      if (insight.hypotheses.isNotEmpty)
        '推测：${insight.hypotheses.take(3).map((item) => item.text).join('；')}',
      if (insight.suggestions.isNotEmpty)
        '建议：${insight.suggestions.take(3).map((item) => item.text).join('；')}',
      if (insight.stoneTitle.trim().isNotEmpty)
        '塑石：${[
          insight.stoneTitle.trim(),
          insight.stoneDescription.trim(),
        ].where((part) => part.isNotEmpty).join(' / ')}',
      if (insight.memorySummary.trim().isNotEmpty)
        '记忆更新：${insight.memorySummary.trim()}',
    ];
    final text = parts.join('\n');
    if (text.length <= 1200) return text;
    return '${text.substring(0, 1200)}...';
  }

  List<String> _previousInsightSources(DiaryInsight insight) {
    final sources = <String>{};
    for (final memory in insight.relatedMemories) {
      if (memory.entryId?.trim().isNotEmpty ?? false) {
        sources.add('related:${memory.entryId!.trim()}');
      }
    }
    for (final claim in [
      ...insight.facts,
      ...insight.signals,
      ...insight.hypotheses,
      ...insight.suggestions,
    ]) {
      for (final evidence in claim.evidence) {
        final id = evidence.id.trim();
        if (id.isEmpty) continue;
        sources.add(evidence.type.trim().isEmpty ? id : '${evidence.type}:$id');
      }
    }
    for (final candidate in insight.profileUpdateCandidates) {
      for (final evidence in candidate.evidence) {
        final id = evidence.id.trim();
        if (id.isEmpty) continue;
        sources.add(evidence.type.trim().isEmpty ? id : '${evidence.type}:$id');
      }
    }
    for (final update in insight.relationshipUpdates) {
      for (final evidence in update.evidence) {
        final id = evidence.id.trim();
        if (id.isEmpty) continue;
        sources.add(evidence.type.trim().isEmpty ? id : '${evidence.type}:$id');
      }
    }
    for (final contradiction in insight.contradictions) {
      if (contradiction.oldMemoryId.trim().isNotEmpty) {
        sources.add('contradiction:${contradiction.oldMemoryId.trim()}');
      }
      for (final evidence in contradiction.evidence) {
        final id = evidence.id.trim();
        if (id.isEmpty) continue;
        sources.add(evidence.type.trim().isEmpty ? id : '${evidence.type}:$id');
      }
    }
    return sources.take(20).toList(growable: false);
  }
}
