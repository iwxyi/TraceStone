import '../models/app_auth_session.dart';
import '../models/app_user_profile.dart';
import '../repositories/app_auth_repository.dart';
import 'app_backend_client.dart';

class AppAccountSnapshot {
  const AppAccountSnapshot({
    required this.session,
    required this.profile,
    required this.memberStatus,
    this.remoteError = '',
  });

  final AppAuthSession? session;
  final AppUserProfile? profile;
  final AppMemberStatus? memberStatus;
  final String remoteError;

  bool get hasRemoteProfile => profile != null;
}

class AppAccountService {
  const AppAccountService({
    AppBackendClient? client,
  }) : _client = client ?? const AppBackendClient();

  final AppBackendClient _client;

  Future<AppAccountSnapshot> loadSnapshot() async {
    final session = await const AppAuthRepository().loadSession();
    if (session == null || !session.isValid) {
      return const AppAccountSnapshot(
        session: null,
        profile: null,
        memberStatus: null,
      );
    }
    AppUserProfile? profile;
    AppMemberStatus? memberStatus;
    var remoteError = '';
    try {
      profile = await _loadProfile();
    } on Object catch (error) {
      remoteError = error.toString();
    }
    try {
      memberStatus = await _loadMemberStatus(session);
    } on Object catch (error) {
      remoteError = [
        if (remoteError.isNotEmpty) remoteError,
        error.toString(),
      ].join('\n');
    }
    final currentSession = await const AppAuthRepository().loadSession();
    if (currentSession == null || !currentSession.isValid) {
      return AppAccountSnapshot(
        session: null,
        profile: null,
        memberStatus: null,
        remoteError: remoteError,
      );
    }
    return AppAccountSnapshot(
      session: currentSession,
      profile: profile,
      memberStatus: memberStatus,
      remoteError: remoteError,
    );
  }

  Future<void> setPassword(String password) async {
    final value = password.trim();
    if (value.length < 6) {
      throw const AppBackendException('密码至少需要 6 位');
    }
    await _client.post(
      '/api/user/password/set',
      authenticated: true,
      body: {'password': value},
    );
  }

  Future<AppUserProfile?> updateProfile({
    required String nickname,
  }) async {
    final value = nickname.trim();
    if (value.length > 24) {
      throw const AppBackendException('昵称最多 24 个字');
    }
    final data = await _client.put(
      '/api/user/profile',
      authenticated: true,
      body: {
        'nickname': value,
      },
    );
    return AppUserProfile.fromJson(data);
  }

  Future<AppUserProfile?> _loadProfile() async {
    final data = await _client.get(
      '/api/user/profile',
      authenticated: true,
    );
    return AppUserProfile.fromJson(data);
  }

  Future<AppMemberStatus?> _loadMemberStatus(AppAuthSession session) async {
    final data = await _client.get(
      '/api/member/status',
      authenticated: true,
      query: {
        'appId': session.appId,
        'userId': session.userId,
      },
    );
    return AppMemberStatus.fromJson(data);
  }
}
