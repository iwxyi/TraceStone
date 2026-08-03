import 'package:flutter/material.dart';

import '../data/models/app_lock_settings.dart';
import '../data/repositories/app_lock_repository.dart';
import '../data/services/app_lock_authenticator.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    this.repository = const AppLockRepository(),
    this.authenticator = const LocalAppLockAuthenticator(),
  });

  final Widget child;
  final AppLockRepository repository;
  final AppLockAuthenticator authenticator;

  @override
  State<AppLockGate> createState() => AppLockGateState();
}

class AppLockGateState extends State<AppLockGate> {
  AppLockSettings _settings = AppLockSettings.disabled;
  bool _locked = false;
  bool _loading = true;
  bool _authenticating = false;
  String _error = '';
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    reload(lockIfNeeded: true);
  }

  Future<void> reload({bool lockIfNeeded = false}) async {
    final settings = await widget.repository.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
      if (!settings.enabled) {
        _locked = false;
      } else if (lockIfNeeded) {
        _locked = true;
      }
    });
  }

  void markBackgrounded(DateTime now) {
    _backgroundedAt = now;
  }

  Future<void> handleResumed(DateTime now) async {
    await reload();
    final settings = _settings;
    if (!settings.enabled) return;
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt == null) {
      setState(() => _locked = true);
      return;
    }
    final elapsed = now.difference(backgroundedAt).inSeconds;
    if (elapsed >= settings.requireAfterSeconds) {
      setState(() => _locked = true);
    }
  }

  Future<void> _unlockWithSystemAuth() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = '';
    });
    final ok = await widget.authenticator.authenticate(reason: '解锁拾年日记');
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      _locked = !ok;
      _error = ok ? '' : '没有完成系统认证';
    });
  }

  Future<void> _unlockWithSecret(String secret) async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = '';
    });
    final ok = await widget.repository.verifySecret(secret);
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      _locked = !ok;
      _error = ok ? '' : '密码不正确';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) {
            return Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                if (!_loading && _locked)
                  _AppLockOverlay(
                    settings: _settings,
                    error: _error,
                    authenticating: _authenticating,
                    onSystemAuth: _unlockWithSystemAuth,
                    onSecret: _unlockWithSecret,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AppLockOverlay extends StatefulWidget {
  const _AppLockOverlay({
    required this.settings,
    required this.error,
    required this.authenticating,
    required this.onSystemAuth,
    required this.onSecret,
  });

  final AppLockSettings settings;
  final String error;
  final bool authenticating;
  final VoidCallback onSystemAuth;
  final ValueChanged<String> onSecret;

  @override
  State<_AppLockOverlay> createState() => _AppLockOverlayState();
}

class _AppLockOverlayState extends State<_AppLockOverlay> {
  final _controller = TextEditingController();

  bool get _usesSecret =>
      widget.settings.method == AppLockMethod.pin ||
      widget.settings.method == AppLockMethod.password;

  bool get _isPin => widget.settings.method == AppLockMethod.pin;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final secret = _controller.text.trim();
    if (secret.isEmpty) return;
    widget.onSecret(secret);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 34,
                    child: Icon(
                      _usesSecret
                          ? Icons.lock_outline
                          : Icons.fingerprint_outlined,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('拾年已锁定', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    widget.settings.methodLabel,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 22),
                  if (_usesSecret)
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      obscureText: true,
                      enabled: !widget.authenticating,
                      keyboardType:
                          _isPin ? TextInputType.number : TextInputType.text,
                      maxLength: _isPin ? 6 : null,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: _isPin ? '输入 PIN' : '输入密码',
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submit(),
                    )
                  else
                    FilledButton.icon(
                      onPressed:
                          widget.authenticating ? null : widget.onSystemAuth,
                      icon: widget.authenticating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fingerprint_outlined),
                      label: const Text('系统认证'),
                    ),
                  if (widget.error.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      widget.error,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  if (_usesSecret) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: widget.authenticating ? null : _submit,
                      child: widget.authenticating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('解锁'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
