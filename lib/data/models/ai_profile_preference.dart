enum AiProfilePreferenceTargetType { profileFact, relationship }

class AiProfilePreference {
  const AiProfilePreference({
    required this.targetType,
    required this.targetId,
    required this.updatedAt,
    this.confirmed = false,
    this.hidden = false,
    this.correctedValue = '',
  });

  final AiProfilePreferenceTargetType targetType;
  final String targetId;
  final DateTime updatedAt;
  final bool confirmed;
  final bool hidden;
  final String correctedValue;

  String get id => keyFor(targetType: targetType, targetId: targetId);

  AiProfilePreference copyWith({
    bool? confirmed,
    bool? hidden,
    String? correctedValue,
    DateTime? updatedAt,
  }) {
    return AiProfilePreference(
      targetType: targetType,
      targetId: targetId,
      updatedAt: updatedAt ?? this.updatedAt,
      confirmed: confirmed ?? this.confirmed,
      hidden: hidden ?? this.hidden,
      correctedValue: correctedValue ?? this.correctedValue,
    );
  }

  Map<String, dynamic> toJson() => {
        'targetType': targetType.name,
        'targetId': targetId,
        'updatedAt': updatedAt.toIso8601String(),
        'confirmed': confirmed,
        'hidden': hidden,
        'correctedValue': correctedValue,
      };

  factory AiProfilePreference.fromJson(Map<String, dynamic> json) {
    final targetType = AiProfilePreferenceTargetType.values.firstWhere(
      (value) => value.name == json['targetType'],
      orElse: () => AiProfilePreferenceTargetType.profileFact,
    );
    return AiProfilePreference(
      targetType: targetType,
      targetId: (json['targetId'] as String? ?? '').trim(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      confirmed: json['confirmed'] == true,
      hidden: json['hidden'] == true,
      correctedValue: json['correctedValue'] as String? ?? '',
    );
  }

  static String keyFor({
    required AiProfilePreferenceTargetType targetType,
    required String targetId,
  }) =>
      '${targetType.name}:${targetId.trim().toLowerCase()}';
}
