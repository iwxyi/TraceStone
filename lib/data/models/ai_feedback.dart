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
    final valueName = json['value'] as String? ?? AiFeedbackValue.unclear.name;
    return AiFeedback(
      entryId: json['entryId'] as String? ?? '',
      value: AiFeedbackValue.values.firstWhere(
        (item) => item.name == valueName,
        orElse: () => AiFeedbackValue.unclear,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      note: json['note'] as String?,
    );
  }
}
