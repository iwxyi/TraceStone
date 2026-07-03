enum AiFeedbackValue { helpful, inaccurate, unclear }

class AiFeedback {
  const AiFeedback({
    required this.entryId,
    required this.value,
    required this.createdAt,
    this.note,
  });

  final String entryId;
  final AiFeedbackValue value;
  final DateTime createdAt;
  final String? note;

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'value': value.name,
        'createdAt': createdAt.toIso8601String(),
        'note': note,
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
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static String? _nullableString(Object? value) =>
      value is String ? value : null;
}
