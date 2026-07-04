enum AiProfilePreferenceTargetType { profileFact, relationship }

class AiProfilePreference {
  const AiProfilePreference({
    required this.targetType,
    required this.targetId,
    required this.updatedAt,
    this.confirmed = false,
    this.hidden = false,
    this.correctedValue = '',
    this.mergedInto = '',
  });

  final AiProfilePreferenceTargetType targetType;
  final String targetId;
  final DateTime updatedAt;
  final bool confirmed;
  final bool hidden;
  final String correctedValue;
  final String mergedInto;

  String get id => keyFor(targetType: targetType, targetId: targetId);

  AiProfilePreference copyWith({
    bool? confirmed,
    bool? hidden,
    String? correctedValue,
    String? mergedInto,
    DateTime? updatedAt,
  }) {
    return AiProfilePreference(
      targetType: targetType,
      targetId: targetId,
      updatedAt: updatedAt ?? this.updatedAt,
      confirmed: confirmed ?? this.confirmed,
      hidden: hidden ?? this.hidden,
      correctedValue: correctedValue ?? this.correctedValue,
      mergedInto: mergedInto ?? this.mergedInto,
    );
  }

  Map<String, dynamic> toJson() => {
        'targetType': targetType.name,
        'targetId': targetId,
        'updatedAt': updatedAt.toIso8601String(),
        'confirmed': confirmed,
        'hidden': hidden,
        'correctedValue': correctedValue,
        'mergedInto': mergedInto,
      };

  factory AiProfilePreference.fromJson(Map<String, dynamic> json) {
    final targetTypeName = _stringValue(json['targetType']);
    final targetType = AiProfilePreferenceTargetType.values.firstWhere(
      (value) => value.name == targetTypeName,
      orElse: () => AiProfilePreferenceTargetType.profileFact,
    );
    return AiProfilePreference(
      targetType: targetType,
      targetId: _stringValue(json['targetId']).trim(),
      updatedAt: DateTime.tryParse(_stringValue(json['updatedAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      confirmed: _boolValue(json['confirmed']),
      hidden: _boolValue(json['hidden']),
      correctedValue: _stringValue(json['correctedValue']),
      mergedInto: _stringValue(json['mergedInto']).trim(),
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static bool _boolValue(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase().trim();
    return text == 'true';
  }

  static String keyFor({
    required AiProfilePreferenceTargetType targetType,
    required String targetId,
  }) =>
      '${targetType.name}:${targetId.trim().toLowerCase()}';
}
