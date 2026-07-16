import '../models/ai_profile.dart';
import '../models/diary_insight.dart';
import 'ai_source_formatter.dart';

String profileFieldLabel(String field) {
  final normalized = field.trim().toLowerCase();
  const labels = {
    'self_regulation': '自我调节',
    'self regulation': '自我调节',
    'emotion_regulation': '情绪调节',
    'emotional_regulation': '情绪调节',
    'stress_trigger': '压力来源',
    'stress_triggers': '压力来源',
    'work_pattern': '工作模式',
    'learning_pattern': '学习模式',
    'social_pattern': '社交模式',
    'relationship_pattern': '关系模式',
    'health_pattern': '健康习惯',
    'exercise_pattern': '运动习惯',
    'sleep_pattern': '睡眠习惯',
    'food_pattern': '饮食习惯',
    'motivation': '动力来源',
    'values': '价值观',
    'goal': '目标',
    'goals': '目标',
    'strength': '优势',
    'strengths': '优势',
    'risk': '风险点',
    'risks': '风险点',
    'preference': '偏好',
    'preferences': '偏好',
    'identity': '自我认同',
    'growth': '成长线索',
  };
  final mapped = labels[normalized];
  if (mapped != null) return mapped;
  if (field.trim().isEmpty) return '未分类画像';
  return field
      .trim()
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
}

String profileStatusLabel(ProfileFactStatus status) {
  switch (status) {
    case ProfileFactStatus.stable:
      return '稳定画像';
    case ProfileFactStatus.emerging:
      return '待更多证据';
    case ProfileFactStatus.weak:
      return '待确认';
  }
}

String profileEvidenceLine(
  InsightEvidence evidence, {
  required bool developerMode,
}) {
  final summary = evidence.summary ?? '';
  final quote = evidence.quote ?? '';
  final relevance = evidence.relevance ?? '';
  if (!developerMode) {
    return [
      if (summary.isNotEmpty) summary,
      if (quote.isNotEmpty) '“$quote”',
      if (relevance.isNotEmpty) relevance,
    ].where((item) => item.trim().isNotEmpty).join(' | ');
  }
  return [
    formatInsightEvidenceId(evidence),
    if (summary.isNotEmpty) summary,
    if (quote.isNotEmpty) quote,
    if (relevance.isNotEmpty) relevance,
  ].join(' | ');
}
