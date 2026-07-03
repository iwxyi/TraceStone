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
    final typeName = _stringValue(json['type']).isEmpty
        ? CalendarMemoryType.solar.name
        : _stringValue(json['type']);
    final type = CalendarMemoryType.values.firstWhere(
      (item) => item.name == typeName,
      orElse: () => CalendarMemoryType.solar,
    );
    final month = _intValue(json['month'], fallback: 1).clamp(1, 12).toInt();
    final maxDay = type == CalendarMemoryType.lunar ? 30 : _daysInMonth(month);
    return CalendarMemory(
      id: _stringValue(json['id']),
      title: _stringValue(json['title']),
      month: month,
      day: _intValue(json['day'], fallback: 1).clamp(1, maxDay).toInt(),
      createdAt: DateTime.tryParse(_stringValue(json['createdAt'])) ?? now,
      updatedAt: DateTime.tryParse(_stringValue(json['updatedAt'])) ?? now,
      type: type,
      note: _stringValue(json['note']),
      enabled: json['enabled'] != false,
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static int _intValue(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int _daysInMonth(int month) {
    const days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return days[month - 1];
  }
}
