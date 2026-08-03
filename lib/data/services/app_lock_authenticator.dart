import 'package:local_auth/local_auth.dart';

abstract interface class AppLockAuthenticator {
  const AppLockAuthenticator();

  Future<bool> isSystemAuthAvailable();

  Future<List<String>> availableBiometrics();

  Future<bool> authenticate({required String reason});
}

class LocalAppLockAuthenticator implements AppLockAuthenticator {
  const LocalAppLockAuthenticator();

  static final _auth = LocalAuthentication();

  @override
  Future<bool> isSystemAuthAvailable() async {
    try {
      return await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
    } on Object {
      return false;
    }
  }

  @override
  Future<List<String>> availableBiometrics() async {
    try {
      final values = await _auth.getAvailableBiometrics();
      return values.map(_label).toSet().toList();
    } on Object {
      return const [];
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on Object {
      return false;
    }
  }

  String _label(BiometricType type) {
    return switch (type) {
      BiometricType.face => '面容',
      BiometricType.fingerprint => '指纹',
      BiometricType.iris => '虹膜',
      BiometricType.strong => '强生物认证',
      BiometricType.weak => '生物认证',
    };
  }
}
