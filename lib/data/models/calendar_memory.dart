enum CalendarMemoryType { solar, lunar }

class CalendarMemory {
  const CalendarMemory({
    required this.id,
    required this.title,
    required this.month,
    required this.day,
    required this.createdAt,
    required this.updatedAt,
    this.type = CalendarMemoryType.solar,
    this.note = '',
    this.enabled = true,
  });

  final String id;
  final String title;
  final int month;
  final int day;
  final DateTime createdAt;
  final DateTime updatedAt;
  final CalendarMemoryType type;
  final String note;
  final bool enabled;

  CalendarMemory copyWith({
    String? title,
    int? month,
    int? day,
    DateTime? updatedAt,
    CalendarMemoryType? type,
    String? note,
    bool? enabled,
  }) {
    return CalendarMemory(
      id: id,
      title: title ?? this.title,
      month: month ?? this.month,
      day: day ?? this.day,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      type: type ?? this.type,
      note: note ?? this.note,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'month': month,
        'day': day,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'type': type.name,
        'note': note,
        'enabled': enabled,
      };

  static CalendarMemory fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final typeName = json['type'] as String? ?? CalendarMemoryType.solar.name;
    return CalendarMemory(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      month: (json['month'] as num?)?.toInt() ?? 1,
      day: (json['day'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      type: CalendarMemoryType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => CalendarMemoryType.solar,
      ),
      note: json['note'] as String? ?? '',
      enabled: json['enabled'] != false,
    );
  }
}
