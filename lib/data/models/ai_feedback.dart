enum AiFeedbackValue { helpful, inaccurate, unclear }

class AiFeedback {
  const AiFeedback({
    required this.entryId,
    required this.value,
    required this.createdAt,
    this.note,
    this.previousInsightSummary,
    this.previousInsightSources = const [],
  });

  final String entryId;
  final AiFeedbackValue value;
  final DateTime createdAt;
  final String? note;
  final String? previousInsightSummary;
  final List<String> previousInsightSources;

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'value': value.name,
        'createdAt': createdAt.toIso8601String(),
        'note': note,
        'previousInsightSummary': previousInsightSummary,
        'previousInsightSources': previousInsightSources,
      };

  static AiFeedback fromJson(Map<String, dynamic> json) {
    final valueName = _stringValue(json['value']).isEmpty
        ? AiFeedbackValue.unclear.name
        : _stringValue(json['value']);
    return AiFeedback(
      entryId: _stringValue(json['entryId']),
      value: AiFeedbackValue.values.firstWhere(
        (item) => item.name == valueName,
        orElse: () => AiFeedbackValue.unclear,
      ),
      createdAt:
          DateTime.tryParse(_stringValue(json['createdAt'])) ?? DateTime.now(),
      note: _nullableString(json['note']),
      previousInsightSummary: _nullableString(json['previousInsightSummary']),
      previousInsightSources: _stringList(json['previousInsightSources']),
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static String? _nullableString(Object? value) =>
      value is String ? value : null;

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .where((item) => item != null)
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
