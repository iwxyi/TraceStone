import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/services/app_auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _authService = const AppAuthService();
  final _mobileController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  Timer? _countdownTimer;
  int _countdown = 0;
  bool _sendingCode = false;
  bool _loggingIn = false;
  bool _passwordMode = false;
  String _debugCode = '';

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _mobileController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_sendingCode || _countdown > 0) return;
    setState(() {
      _sendingCode = true;
      _debugCode = '';
    });
    try {
      final result = await _authService.sendCode(_mobileController.text);
      if (!mounted) return;
      _startCountdown(result.expireSeconds <= 0 ? 60 : result.expireSeconds);
      setState(() => _debugCode = result.debugCode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.sent ? '验证码已发送' : '验证码发送已受理')),
      );
    } on AppAuthException catch (error) {
      _showError(error.message);
    } on Object catch (error) {
      _showError('$error');
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _login() async {
    if (_loggingIn) return;
    setState(() => _loggingIn = true);
    try {
      await _authService.login(
        mobile: _mobileController.text,
        code: _codeController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppAuthException catch (error) {
      _showError(error.message);
    } on Object catch (error) {
      _showError('$error');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _passwordLogin() async {
    if (_loggingIn) return;
    setState(() => _loggingIn = true);
    try {
      await _authService.passwordLogin(
        account: _mobileController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppAuthException catch (error) {
      _showError(error.message);
    } on Object catch (error) {
      _showError('$error');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    setState(() => _countdown = seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _sendingCode || _loggingIn;
    return Scaffold(
      appBar: AppBar(title: const Text('登录 / 注册')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          Text('拾年账号', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('登录后可查看账号与会员状态。日记备份只通过你配置的 WebDAV 进行。',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('验证码')),
              ButtonSegment(value: true, label: Text('密码')),
            ],
            selected: {_passwordMode},
            onSelectionChanged: busy
                ? null
                : (value) => setState(() => _passwordMode = value.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _mobileController,
            enabled: !busy,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '手机号',
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_passwordMode)
            TextField(
              controller: _passwordController,
              enabled: !busy,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _passwordLogin(),
              decoration: const InputDecoration(
                labelText: '密码',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      prefixIcon: Icon(Icons.password_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: busy || _countdown > 0 ? null : _sendCode,
                    child: Text(_countdown > 0 ? '${_countdown}s' : '获取验证码'),
                  ),
                ),
              ],
            ),
          if (!_passwordMode && _debugCode.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('调试验证码：$_debugCode', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed:
                _loggingIn ? null : (_passwordMode ? _passwordLogin : _login),
            child: _loggingIn
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_passwordMode ? '密码登录' : '登录 / 注册'),
          ),
        ],
      ),
    );
  }
}
