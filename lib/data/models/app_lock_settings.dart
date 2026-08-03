enum AppLockMethod {
  none,
  pin,
  password,
  system,
}

class AppLockSettings {
  const AppLockSettings({
    required this.enabled,
    required this.method,
    required this.requireAfterSeconds,
    this.secretHash = '',
    this.secretSalt = '',
    this.updatedAt,
  });

  final bool enabled;
  final AppLockMethod method;
  final int requireAfterSeconds;
  final String secretHash;
  final String secretSalt;
  final DateTime? updatedAt;

  bool get hasLocalSecret => secretHash.isNotEmpty && secretSalt.isNotEmpty;

  String get methodLabel {
    return switch (method) {
      AppLockMethod.none => '未启用',
      AppLockMethod.pin => '独立 PIN',
      AppLockMethod.password => '独立密码',
      AppLockMethod.system => '系统认证',
    };
  }

  String get requireAfterLabel {
    return switch (requireAfterSeconds) {
      0 => '每次打开',
      60 => '离开 1 分钟后',
      300 => '离开 5 分钟后',
      900 => '离开 15 分钟后',
      1800 => '离开 30 分钟后',
      _ => '离开 ${requireAfterSeconds ~/ 60} 分钟后',
    };
  }

  AppLockSettings copyWith({
    bool? enabled,
    AppLockMethod? method,
    int? requireAfterSeconds,
    String? secretHash,
    String? secretSalt,
    DateTime? updatedAt,
  }) {
    return AppLockSettings(
      enabled: enabled ?? this.enabled,
      method: method ?? this.method,
      requireAfterSeconds: requireAfterSeconds ?? this.requireAfterSeconds,
      secretHash: secretHash ?? this.secretHash,
      secretSalt: secretSalt ?? this.secretSalt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'method': method.name,
        'requireAfterSeconds': requireAfterSeconds,
        'secretHash': secretHash,
        'secretSalt': secretSalt,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static AppLockSettings fromJson(Map<String, dynamic> json) {
    return AppLockSettings(
      enabled: json['enabled'] == true,
      method: _methodValue(json['method']),
      requireAfterSeconds: _intValue(
        json['requireAfterSeconds'],
        fallback: 300,
      ),
      secretHash: _stringValue(json['secretHash']),
      secretSalt: _stringValue(json['secretSalt']),
      updatedAt: DateTime.tryParse(_stringValue(json['updatedAt'])),
    );
  }

  static const disabled = AppLockSettings(
    enabled: false,
    method: AppLockMethod.none,
    requireAfterSeconds: 300,
  );

  static AppLockMethod _methodValue(Object? value) {
    final text = _stringValue(value);
    for (final method in AppLockMethod.values) {
      if (method.name == text) return method;
    }
    return AppLockMethod.none;
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static int _intValue(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
