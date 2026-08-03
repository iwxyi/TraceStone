import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/routing/app_routes.dart';
import '../../../data/models/app_auth_session.dart';
import '../../../data/models/app_user_profile.dart';
import '../../../data/repositories/app_auth_repository.dart';
import '../../../data/services/app_account_service.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _service = const AppAccountService();
  final _authRepository = const AppAuthRepository();
  Future<AppAccountSnapshot>? _loadingFuture;
  AppAccountSnapshot _snapshot = const AppAccountSnapshot(
    session: null,
    profile: null,
    memberStatus: null,
  );
  bool _loadingInitial = true;
  bool _loggingOut = false;
  bool _settingPassword = false;
  bool _savingProfile = false;

  @override
  void initState() {
    super.initState();
    _refreshNow();
  }

  void _refreshNow() {
    _loadLocalSession();
    final future = _service.loadSnapshot();
    _loadingFuture = future;
    if (_snapshot.session == null) {
      setState(() => _loadingInitial = true);
    }
    future.then((snapshot) {
      if (!mounted || _loadingFuture != future) return;
      setState(() {
        _snapshot = snapshot;
        _loadingInitial = false;
      });
    }).catchError((Object error) {
      if (!mounted || _loadingFuture != future) return;
      setState(() {
        _loadingInitial = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载账号信息失败：$error')),
      );
    });
  }

  Future<void> _loadLocalSession() async {
    final session = await _authRepository.loadSession();
    if (!mounted || session == null || !session.isValid) return;
    setState(() {
      _snapshot = AppAccountSnapshot(
        session: session,
        profile: _snapshot.profile,
        memberStatus: _snapshot.memberStatus,
        remoteError: _snapshot.remoteError,
      );
      _loadingInitial = false;
    });
  }

  Future<void> _refresh() async {
    _refreshNow();
    await _loadingFuture;
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await _authRepository.clearSession();
      if (!mounted) return;
      _refreshNow();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已退出登录')),
      );
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _openLogin() async {
    final changed = await Navigator.of(context).pushNamed(AppRoutes.login);
    if (changed == true) _refreshNow();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  Future<void> _setPassword() async {
    if (_settingPassword || _snapshot.session == null) return;
    final password = await _showSetPasswordDialog();
    if (password == null) return;
    setState(() => _settingPassword = true);
    try {
      await _service.setPassword(password);
      if (!mounted) return;
      _refreshNow();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已设置')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置密码失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _settingPassword = false);
    }
  }

  Future<void> _editNickname() async {
    if (_savingProfile || _snapshot.session == null) return;
    final nickname = await _showNicknameDialog(_snapshot.profile?.nickname);
    if (nickname == null) return;
    setState(() => _savingProfile = true);
    try {
      final profile = await _service.updateProfile(nickname: nickname);
      if (!mounted) return;
      setState(() {
        if (profile != null) {
          _snapshot = AppAccountSnapshot(
            session: _snapshot.session,
            profile: profile,
            memberStatus: _snapshot.memberStatus,
            remoteError: _snapshot.remoteError,
          );
        }
      });
      _refreshNow();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('昵称已保存')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存昵称失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<String?> _showNicknameDialog(String? current) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _NicknameDialog(current: current),
    );
  }

  Future<String?> _showSetPasswordDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => const _SetPasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _snapshot.session;
    final profile = _snapshot.profile;
    final memberStatus = _snapshot.memberStatus;
    return Scaffold(
      appBar: AppBar(title: const Text('账号')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _AccountHeaderCard(
              session: session,
              profile: profile,
              onCopyUserId:
                  profile == null ? null : () => _copy(profile.id.toString()),
              onLogin: session == null ? _openLogin : null,
              onLogout: session == null ? null : _logout,
              loggingOut: _loggingOut,
            ),
            const SizedBox(height: 16),
            _AccountInfoCard(
              session: session,
              profile: profile,
              memberStatus: memberStatus,
              savingProfile: _savingProfile,
              onEditNickname:
                  session == null || _savingProfile ? null : _editNickname,
            ),
            if (_snapshot.remoteError.isNotEmpty) ...[
              const SizedBox(height: 16),
              _RemoteErrorCard(message: _snapshot.remoteError),
            ],
            const SizedBox(height: 16),
            _AccountActionCard(
              loggedIn: session != null,
              settingPassword: _settingPassword,
              onSetPassword: _setPassword,
            ),
            const SizedBox(height: 16),
            const _DataBoundaryCard(),
            if (_loadingInitial) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountHeaderCard extends StatelessWidget {
  const _AccountHeaderCard({
    required this.session,
    required this.profile,
    required this.onCopyUserId,
    required this.onLogin,
    required this.onLogout,
    required this.loggingOut,
  });

  final AppAuthSession? session;
  final AppUserProfile? profile;
  final VoidCallback? onCopyUserId;
  final VoidCallback? onLogin;
  final VoidCallback? onLogout;
  final bool loggingOut;

  @override
  Widget build(BuildContext context) {
    final loggedIn = session?.isValid ?? false;
    final title = profile?.displayName ?? session?.mobile ?? '未登录用户';
    final subtitle = loggedIn ? '拾年账号' : '登录后可查看账号与会员状态';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircleAvatar(radius: 28, child: Icon(Icons.person_outline)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                  if (loggedIn) ...[
                    const SizedBox(height: 8),
                    Text(
                      '手机号 ${_maskMobile(session!.mobile)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (onLogin != null)
              FilledButton(
                onPressed: onLogin,
                child: const Text('登录'),
              )
            else
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) {
                  switch (value) {
                    case 'copy':
                      onCopyUserId?.call();
                      break;
                    case 'logout':
                      onLogout?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (onCopyUserId != null)
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('复制用户ID'),
                    ),
                  if (onLogout != null)
                    const PopupMenuItem(
                      value: 'logout',
                      child: Text('退出登录'),
                    ),
                ],
                child: loggingOut
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.more_vert),
              ),
          ],
        ),
      ),
    );
  }

  String _maskMobile(String mobile) {
    if (mobile.length < 7) return mobile;
    return '${mobile.substring(0, 3)}****${mobile.substring(mobile.length - 4)}';
  }
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.current});

  final String? current;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller =
      TextEditingController(text: widget.current?.trim() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑昵称'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: '昵称',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog();

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();
    if (password.length < 6) {
      setState(() => _error = '密码至少需要 6 位');
      return;
    }
    if (password != confirm) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置密码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '新密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '确认密码',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _RemoteErrorCard extends StatelessWidget {
  const _RemoteErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.cloud_off_outlined),
        title: const Text('远端信息未更新'),
        subtitle: Text(message),
      ),
    );
  }
}

class _AccountInfoCard extends StatelessWidget {
  const _AccountInfoCard({
    required this.session,
    required this.profile,
    required this.memberStatus,
    required this.savingProfile,
    required this.onEditNickname,
  });

  final AppAuthSession? session;
  final AppUserProfile? profile;
  final AppMemberStatus? memberStatus;
  final bool savingProfile;
  final VoidCallback? onEditNickname;

  @override
  Widget build(BuildContext context) {
    final member = memberStatus;
    final items = <Widget>[
      _InfoRow(label: '账号状态', value: profile?.status ?? '未获取'),
      _InfoRow(
        label: '昵称',
        value: profile?.nickname.trim().isNotEmpty == true
            ? profile!.nickname.trim()
            : '未设置',
        action: savingProfile
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: '编辑昵称',
                onPressed: onEditNickname,
                icon: const Icon(Icons.edit_outlined),
              ),
      ),
      _InfoRow(label: '账号ID', value: profile?.id.toString() ?? '未登录'),
      _InfoRow(label: '登录手机号', value: session?.mobile ?? '未登录'),
      _InfoRow(
        label: '最后登录',
        value: _formatDate(profile?.lastLoginAt) ?? '未记录',
      ),
      _InfoRow(
        label: '会员状态',
        value: member == null
            ? '未获取'
            : member.active
                ? '有效'
                : (member.status.isNotEmpty ? member.status : '未开通'),
      ),
      _InfoRow(
        label: '会员到期',
        value: _formatDate(member?.expireAt) ?? '未记录',
      ),
    ];
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '账号信息',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final item in items) ...[
              item,
              const Divider(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  String? _formatDate(DateTime? value) {
    if (value == null) return null;
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.action});

  final String label;
  final String value;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          SizedBox(width: 40, height: 40, child: Center(child: action)),
        ],
      ],
    );
  }
}

class _AccountActionCard extends StatelessWidget {
  const _AccountActionCard({
    required this.loggedIn,
    required this.settingPassword,
    required this.onSetPassword,
  });

  final bool loggedIn;
  final bool settingPassword;
  final VoidCallback onSetPassword;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('设置密码'),
            subtitle: Text(loggedIn ? '用于密码登录' : '请先登录'),
            trailing: settingPassword
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            enabled: loggedIn && !settingPassword,
            onTap: loggedIn && !settingPassword ? onSetPassword : null,
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.sync_outlined),
            title: Text('WebDAV 备份'),
            subtitle: Text('日记只通过 WebDAV 备份'),
            trailing: Icon(Icons.chevron_right),
            enabled: false,
          ),
        ],
      ),
    );
  }
}

class _DataBoundaryCard extends StatelessWidget {
  const _DataBoundaryCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.account_circle_outlined),
            title: Text('拾年账号'),
            subtitle: Text('登录、会员、额度'),
          ),
          Divider(height: 1),
          ListTile(
            leading: Icon(Icons.cloud_upload_outlined),
            title: Text('WebDAV'),
            subtitle: Text('日记、附件、AI 总结备份'),
          ),
          Divider(height: 1),
          ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('本机安全存储'),
            subtitle: Text('API Key、密码、登录凭证'),
          ),
        ],
      ),
    );
  }
}
