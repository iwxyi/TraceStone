class WebDavConfig {
  const WebDavConfig({
    required this.url,
    required this.username,
    required this.password,
    required this.remoteRoot,
    this.lastBackupAt,
    this.lastRestoreAt,
  });

  final String url;
  final String username;
  final String password;
  final String remoteRoot;
  final DateTime? lastBackupAt;
  final DateTime? lastRestoreAt;

  bool get isConfigured =>
      url.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.trim().isNotEmpty;

  String get normalizedUrl => url.trim().replaceAll(RegExp(r'/+$'), '');

  String get normalizedRoot {
    final trimmed = remoteRoot.trim();
    if (trimmed.isEmpty || trimmed == '/') return '/Shinen';
    final withPrefix = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return withPrefix.replaceAll(RegExp(r'/+$'), '');
  }

  WebDavConfig copyWith({
    String? url,
    String? username,
    String? password,
    String? remoteRoot,
    DateTime? lastBackupAt,
    DateTime? lastRestoreAt,
    bool clearLastBackupAt = false,
    bool clearLastRestoreAt = false,
  }) {
    return WebDavConfig(
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteRoot: remoteRoot ?? this.remoteRoot,
      lastBackupAt:
          clearLastBackupAt ? null : lastBackupAt ?? this.lastBackupAt,
      lastRestoreAt:
          clearLastRestoreAt ? null : lastRestoreAt ?? this.lastRestoreAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'remoteRoot': remoteRoot,
        'lastBackupAt': lastBackupAt?.toIso8601String(),
        'lastRestoreAt': lastRestoreAt?.toIso8601String(),
      };

  static WebDavConfig fromJson(
    Map<String, dynamic> json, {
    required String password,
  }) {
    return WebDavConfig(
      url: json['url'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: password,
      remoteRoot: json['remoteRoot'] as String? ?? '/Shinen',
      lastBackupAt: DateTime.tryParse(json['lastBackupAt'] as String? ?? ''),
      lastRestoreAt: DateTime.tryParse(json['lastRestoreAt'] as String? ?? ''),
    );
  }

  static const empty = WebDavConfig(
    url: '',
    username: '',
    password: '',
    remoteRoot: '/Shinen',
  );
}
