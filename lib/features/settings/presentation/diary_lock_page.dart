import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/app_lock_settings.dart';
import '../../../data/repositories/app_lock_repository.dart';
import '../../../data/services/app_lock_authenticator.dart';

class DiaryLockPage extends StatefulWidget {
  const DiaryLockPage({
    super.key,
    AppLockRepository? repository,
    AppLockAuthenticator? authenticator,
  })  : _repository = repository ?? const AppLockRepository(),
        _authenticator = authenticator ?? const LocalAppLockAuthenticator();

  final AppLockRepository _repository;
  final AppLockAuthenticator _authenticator;

  @override
  State<DiaryLockPage> createState() => _DiaryLockPageState();
}

class _DiaryLockPageState extends State<DiaryLockPage> {
  _DiaryLockPageData? _data;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<_DiaryLockPageData> _loadData() async {
    final settings = await widget._repository.loadSettings();
    final systemAuthAvailable =
        await widget._authenticator.isSystemAuthAvailable();
    final biometrics = systemAuthAvailable
        ? await widget._authenticator.availableBiometrics()
        : const <String>[];
    return _DiaryLockPageData(
      settings: settings,
      systemAuthAvailable: systemAuthAvailable,
      biometrics: biometrics,
    );
  }

  Future<void> _reload() async {
    final data = await _loadData();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool enabled, _DiaryLockPageData data) async {
    if (_saving) return;
    if (!enabled) {
      await _save(() => widget._repository.disable());
      return;
    }
    await _chooseMethod(data, preferred: data.settings.method);
  }

  void _toggleEnabled(bool enabled, _DiaryLockPageData data) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_setEnabled(enabled, data));
    });
  }

  Future<void> _chooseMethod(
    _DiaryLockPageData data, {
    required AppLockMethod preferred,
  }) async {
    if (_saving) return;
    switch (preferred) {
      case AppLockMethod.pin:
        await _setLocalSecret(AppLockMethod.pin, data.settings);
        break;
      case AppLockMethod.password:
        await _setLocalSecret(AppLockMethod.password, data.settings);
        break;
      case AppLockMethod.system:
        await _setSystemLock(data);
        break;
      case AppLockMethod.none:
        await _setLocalSecret(AppLockMethod.pin, data.settings);
        break;
    }
  }

  Future<void> _setLocalSecret(
    AppLockMethod method,
    AppLockSettings current,
  ) async {
    final secret = await _showSecretDialog(method);
    if (secret == null) return;
    await _save(
      () => widget._repository.setLocalSecret(
        method: method,
        secret: secret,
        requireAfterSeconds: current.requireAfterSeconds,
      ),
    );
  }

  Future<void> _setSystemLock(_DiaryLockPageData data) async {
    if (!data.systemAuthAvailable) {
      _showMessage('当前设备未开启系统认证');
      return;
    }
    final accepted = await widget._authenticator.authenticate(
      reason: '确认启用日记锁',
    );
    if (!accepted) {
      _showMessage('没有完成系统认证');
      return;
    }
    await _save(
      () => widget._repository.setSystemLock(
        requireAfterSeconds: data.settings.requireAfterSeconds,
      ),
    );
  }

  Future<void> _setRequireAfter(
    AppLockSettings settings,
    int seconds,
  ) async {
    if (_saving || settings.requireAfterSeconds == seconds) return;
    await _save(
      () async {
        final next = settings.copyWith(
          requireAfterSeconds: seconds,
          updatedAt: DateTime.now(),
        );
        await widget._repository.saveSettings(next);
        return next;
      },
      message: '锁定时机已更新',
    );
  }

  Future<void> _save(
    Future<AppLockSettings> Function() action, {
    String message = '日记锁已更新',
  }) async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final settings = await action();
      if (!mounted) return;
      final current = _data;
      setState(() {
        _data = current == null
            ? _DiaryLockPageData(
                settings: settings,
                systemAuthAvailable: false,
                biometrics: const <String>[],
              )
            : current.copyWith(settings: settings);
      });
      _showMessage(message);
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _showSecretDialog(AppLockMethod method) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _SecretDialog(method: method),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('日记锁')),
      body: _loading || data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _LockHeroCard(settings: data.settings),
                const SizedBox(height: 16),
                _LockSwitchCard(
                  settings: data.settings,
                  saving: _saving,
                  onChanged: (value) => _toggleEnabled(value, data),
                ),
                const SizedBox(height: 16),
                _LockMethodCard(
                  data: data,
                  saving: _saving,
                  onChoose: (method) => _chooseMethod(data, preferred: method),
                ),
                const SizedBox(height: 16),
                _LockTimingCard(
                  settings: data.settings,
                  saving: _saving,
                  onChanged: (seconds) =>
                      _setRequireAfter(data.settings, seconds),
                ),
                const SizedBox(height: 16),
                const _LockBoundaryCard(),
              ],
            ),
    );
  }
}

class _LockHeroCard extends StatelessWidget {
  const _LockHeroCard({required this.settings});

  final AppLockSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Icon(
                settings.enabled
                    ? Icons.lock_outline
                    : Icons.lock_open_outlined,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.enabled ? '已保护' : '未启用',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    settings.enabled
                        ? '${settings.methodLabel}，${settings.requireAfterLabel}'
                        : '保护本机日记，不影响账号登录',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecretDialog extends StatefulWidget {
  const _SecretDialog({required this.method});

  final AppLockMethod method;

  @override
  State<_SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<_SecretDialog> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  String _error = '';

  bool get _isPin => widget.method == AppLockMethod.pin;

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final secret = _controller.text.trim();
    final confirm = _confirmController.text.trim();
    final error = _validate(secret, confirm);
    if (error.isNotEmpty) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(secret);
  }

  String _validate(String secret, String confirm) {
    if (_isPin && !RegExp(r'^\d{4,6}$').hasMatch(secret)) {
      return 'PIN 需要 4-6 位数字';
    }
    if (!_isPin && secret.length < 6) {
      return '密码至少需要 6 位';
    }
    if (secret != confirm) return '两次输入不一致';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isPin ? '设置独立 PIN' : '设置独立密码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: _isPin ? TextInputType.number : TextInputType.text,
            maxLength: _isPin ? 6 : null,
            decoration: InputDecoration(
              labelText: _isPin ? '4-6 位数字' : '至少 6 位',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: true,
            keyboardType: _isPin ? TextInputType.number : TextInputType.text,
            maxLength: _isPin ? 6 : null,
            decoration: const InputDecoration(
              labelText: '再次输入',
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

class _LockSwitchCard extends StatelessWidget {
  const _LockSwitchCard({
    required this.settings,
    required this.saving,
    required this.onChanged,
  });

  final AppLockSettings settings;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: SwitchListTile(
        secondary: const Icon(Icons.shield_outlined),
        title: const Text('启用日记锁'),
        subtitle: const Text('保护当前设备上的日记和本地 AI 数据'),
        value: settings.enabled,
        onChanged: saving ? null : onChanged,
      ),
    );
  }
}

class _LockMethodCard extends StatelessWidget {
  const _LockMethodCard({
    required this.data,
    required this.saving,
    required this.onChoose,
  });

  final _DiaryLockPageData data;
  final bool saving;
  final ValueChanged<AppLockMethod> onChoose;

  @override
  Widget build(BuildContext context) {
    final settings = data.settings;
    return Card(
      elevation: 0,
      child: Column(
        children: [
          _MethodTile(
            icon: Icons.pin_outlined,
            title: '独立 PIN',
            subtitle: '4-6 位数字，快速解锁',
            selected: settings.enabled && settings.method == AppLockMethod.pin,
            enabled: !saving,
            onTap: () => onChoose(AppLockMethod.pin),
          ),
          const Divider(height: 1),
          _MethodTile(
            icon: Icons.password_outlined,
            title: '独立密码',
            subtitle: '适合更强保护，不与账号密码绑定',
            selected:
                settings.enabled && settings.method == AppLockMethod.password,
            enabled: !saving,
            onTap: () => onChoose(AppLockMethod.password),
          ),
          const Divider(height: 1),
          _MethodTile(
            icon: Icons.fingerprint_outlined,
            title: '系统认证',
            subtitle: data.systemAuthAvailable
                ? data.biometricLabel
                : '请先在系统中开启指纹、面容或设备锁',
            selected:
                settings.enabled && settings.method == AppLockMethod.system,
            enabled: !saving && data.systemAuthAvailable,
            onTap: () => onChoose(AppLockMethod.system),
          ),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? const Icon(Icons.check_circle_outline)
          : const Icon(Icons.chevron_right),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}

class _LockTimingCard extends StatelessWidget {
  const _LockTimingCard({
    required this.settings,
    required this.saving,
    required this.onChanged,
  });

  final AppLockSettings settings;
  final bool saving;
  final ValueChanged<int> onChanged;

  static const _options = [0, 60, 300, 900, 1800];

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('锁定时机', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final seconds in _options)
                  ChoiceChip(
                    label: Text(_label(seconds)),
                    selected: settings.requireAfterSeconds == seconds,
                    onSelected: saving ? null : (_) => onChanged(seconds),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _label(int seconds) {
    return switch (seconds) {
      0 => '每次',
      60 => '1 分钟',
      300 => '5 分钟',
      900 => '15 分钟',
      1800 => '30 分钟',
      _ => '${seconds ~/ 60} 分钟',
    };
  }
}

class _LockBoundaryCard extends StatelessWidget {
  const _LockBoundaryCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.phone_android_outlined),
            title: Text('只保护本机'),
            subtitle: Text('不会上传密码，也不会影响 WebDAV 备份文件'),
          ),
          Divider(height: 1),
          ListTile(
            leading: Icon(Icons.key_outlined),
            title: Text('密钥单独保存'),
            subtitle: Text('PIN 和密码只保存加盐哈希'),
          ),
        ],
      ),
    );
  }
}

class _DiaryLockPageData {
  const _DiaryLockPageData({
    required this.settings,
    required this.systemAuthAvailable,
    required this.biometrics,
  });

  final AppLockSettings settings;
  final bool systemAuthAvailable;
  final List<String> biometrics;

  _DiaryLockPageData copyWith({
    AppLockSettings? settings,
    bool? systemAuthAvailable,
    List<String>? biometrics,
  }) {
    return _DiaryLockPageData(
      settings: settings ?? this.settings,
      systemAuthAvailable: systemAuthAvailable ?? this.systemAuthAvailable,
      biometrics: biometrics ?? this.biometrics,
    );
  }

  String get biometricLabel {
    if (biometrics.isEmpty) return '使用系统指纹、面容或设备锁';
    return '可用：${biometrics.join('、')}';
  }
}
