class AppUserProfile {
  const AppUserProfile({
    required this.id,
    required this.mobile,
    required this.status,
    this.username = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.passwordSetAt,
    this.lastLoginAt,
    this.mustChangePassword = false,
  });

  final int id;
  final String mobile;
  final String username;
  final String nickname;
  final String avatarUrl;
  final String status;
  final DateTime? passwordSetAt;
  final DateTime? lastLoginAt;
  final bool mustChangePassword;

  String get displayName {
    if (nickname.trim().isNotEmpty) return nickname.trim();
    if (username.trim().isNotEmpty) return username.trim();
    return mobile;
  }

  static AppUserProfile? fromJson(Map<String, dynamic> json) {
    final id = _intValue(json['id']);
    final mobile = _stringValue(json['mobile']);
    if (id <= 0 || mobile.isEmpty) return null;
    return AppUserProfile(
      id: id,
      mobile: mobile,
      username: _stringValue(json['username']),
      nickname: _stringValue(json['nickname']),
      avatarUrl: _stringValue(json['avatarUrl']),
      status: _stringValue(json['status']),
      passwordSetAt: _dateValue(json['passwordSetAt']),
      lastLoginAt: _dateValue(json['lastLoginAt']),
      mustChangePassword: json['mustChangePassword'] == true,
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _dateValue(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

class AppMemberStatus {
  const AppMemberStatus({
    required this.active,
    this.status = '',
    this.expireAt,
  });

  final bool active;
  final String status;
  final DateTime? expireAt;

  static AppMemberStatus fromJson(Map<String, dynamic> json) {
    return AppMemberStatus(
      active: json['active'] == true,
      status: json['status'] is String ? json['status'] as String : '',
      expireAt: AppUserProfile._dateValue(json['expireAt']),
    );
  }
}
