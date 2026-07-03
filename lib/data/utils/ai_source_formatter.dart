import '../models/diary_insight.dart';

const _knownSourceTypes = {
  'current_entry',
  'entry',
  'entry_summary',
  'segment',
  'memory',
  'profile',
  'relationship',
  'stone',
  'calendar',
  'period_entry',
};

String formatAiSourceId(String sourceType, String sourceId) {
  final type = sourceType.trim();
  final id = sourceId.trim();
  if (type.isEmpty) return id;
  if (id.isEmpty) return type;
  if (id == type || id.startsWith('$type:')) return id;
  if (_hasKnownSourcePrefix(id)) return id;
  return '$type:$id';
}

String formatInsightEvidenceId(InsightEvidence evidence) {
  return formatAiSourceId(evidence.type, evidence.id);
}

bool _hasKnownSourcePrefix(String sourceId) {
  final separator = sourceId.indexOf(':');
  if (separator <= 0) return false;
  return _knownSourceTypes.contains(sourceId.substring(0, separator));
}
