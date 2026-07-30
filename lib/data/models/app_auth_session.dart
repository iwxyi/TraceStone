import 'dart:convert';

class AppAuthSession {
  const AppAuthSession({
    required this.token,
    required this.userId,
    required this.mobile,
    required this.appId,
  });

  final String token;
  final int userId;
  final String mobile;
  final String appId;

  bool get isValid =>
      token.isNotEmpty && userId > 0 && appId.isNotEmpty && !isExpired;

  bool get isExpired {
    final expiresAt = this.expiresAt;
    if (expiresAt == null) return false;
    return !DateTime.now().isBefore(expiresAt);
  }

  DateTime? get issuedAt => _jwtTimestamp('iat');

  DateTime? get expiresAt => _jwtTimestamp('exp');

  Map<String, dynamic> toJson() => {
        'token': token,
        'userId': userId,
        'mobile': mobile,
        'appId': appId,
      };

  static AppAuthSession? fromJson(Map<String, dynamic> json) {
    final token = _stringValue(json['token']);
    final userId = _intValue(json['userId']);
    final appId = _stringValue(json['appId']);
    if (token.isEmpty || userId <= 0 || appId.isEmpty) return null;
    return AppAuthSession(
      token: token,
      userId: userId,
      mobile: _stringValue(json['mobile']),
      appId: appId,
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _jwtTimestamp(String key) {
    final payload = _jwtPayload();
    final seconds = _intValue(payload[key]);
    if (seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  Map<String, dynamic> _jwtPayload() {
    final parts = token.split('.');
    if (parts.length < 2) return const {};
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is Map<String, dynamic>) return decoded;
    } on Object {
      // Non-JWT tokens are still accepted; they just do not expose expiry.
    }
    return const {};
  }
}
