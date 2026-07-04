class LunarCalendarService {
  const LunarCalendarService();

  DateTime? resolve({
    required int year,
    required int month,
    required int day,
  }) {
    final key = '$month-$day';
    final date = _knownGregorianDates[year]?[key];
    if (date == null) return null;
    return DateTime(year, date.month, date.day);
  }

  LunarFestival? fixedFestival(DateTime date) {
    for (final entry in _fixedFestivals.entries) {
      final lunar = _parseKey(entry.key);
      final gregorian = resolve(
        year: date.year,
        month: lunar.month,
        day: lunar.day,
      );
      if (gregorian == null) continue;
      if (gregorian.month == date.month && gregorian.day == date.day) {
        return LunarFestival(
          label: entry.value,
          month: lunar.month,
          day: lunar.day,
        );
      }
    }
    return null;
  }

  _LunarDate _parseKey(String key) {
    final parts = key.split('-');
    return _LunarDate(
      month: int.tryParse(parts.first) ?? 1,
      day: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1,
    );
  }

  static const _fixedFestivals = {
    '1-1': '春节',
    '1-15': '元宵节',
    '5-5': '端午节',
    '7-7': '七夕',
    '8-15': '中秋节',
    '9-9': '重阳节',
  };

  static final Map<int, Map<String, _GregorianDate>> _knownGregorianDates = {
    2024: {
      '1-1': const _GregorianDate(2, 10),
      '1-15': const _GregorianDate(2, 24),
      '5-5': const _GregorianDate(6, 10),
      '7-7': const _GregorianDate(8, 10),
      '8-15': const _GregorianDate(9, 17),
      '9-9': const _GregorianDate(10, 11),
    },
    2025: {
      '1-1': const _GregorianDate(1, 29),
      '1-15': const _GregorianDate(2, 12),
      '5-5': const _GregorianDate(5, 31),
      '7-7': const _GregorianDate(8, 29),
      '8-15': const _GregorianDate(10, 6),
      '9-9': const _GregorianDate(10, 29),
    },
    2026: {
      '1-1': const _GregorianDate(2, 17),
      '1-15': const _GregorianDate(3, 3),
      '5-5': const _GregorianDate(6, 19),
      '7-7': const _GregorianDate(8, 19),
      '8-15': const _GregorianDate(9, 25),
      '9-9': const _GregorianDate(10, 18),
    },
    2027: {
      '1-1': const _GregorianDate(2, 6),
      '1-15': const _GregorianDate(2, 20),
      '5-5': const _GregorianDate(6, 9),
      '7-7': const _GregorianDate(8, 8),
      '8-15': const _GregorianDate(9, 15),
      '9-9': const _GregorianDate(10, 8),
    },
  };
}

class LunarFestival {
  const LunarFestival({
    required this.label,
    required this.month,
    required this.day,
  });

  final String label;
  final int month;
  final int day;
}

class _LunarDate {
  const _LunarDate({required this.month, required this.day});

  final int month;
  final int day;
}

class _GregorianDate {
  const _GregorianDate(this.month, this.day);

  final int month;
  final int day;
}
