import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trace_stone/data/repositories/app_auth_repository.dart';

class _FakeSecureSessionStore implements AppSecureSessionStore {
  _FakeSecureSessionStore(this._values);

  final Map<String, String> _values;

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

void main() {
  test('migrates legacy session into secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'app.auth.session':
          '{"token":"legacy-token","userId":7,"mobile":"13800138000","appId":"1003"}',
    });
    final secureStore = _FakeSecureSessionStore({});
    final repository = AppAuthRepository(secureStore: secureStore);

    final session = await repository.loadSession();

    expect(session?.token, 'legacy-token');
    expect(secureStore._values['app.auth.secureSession'], isNotNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.auth.session'), isNull);
  });

  test('treats expired jwt session as invalid', () async {
    SharedPreferences.setMockInitialValues({});
    final expiredToken =
        'eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3ODA2MjQwMDB9.signature';
    final secureStore = _FakeSecureSessionStore({
      'app.auth.secureSession':
          '{"token":"$expiredToken","userId":7,"mobile":"13800138000","appId":"1003"}',
    });
    final repository = AppAuthRepository(secureStore: secureStore);

    final session = await repository.loadSession();

    expect(session, isNull);
    expect(secureStore._values, isEmpty);
  });

  test('saves normalized backend base url and resets default', () async {
    SharedPreferences.setMockInitialValues({});
    const repository = AppAuthRepository();

    expect(await repository.loadBaseUrl(), AppAuthRepository.defaultBaseUrl);

    await repository.saveBaseUrl('http://127.0.0.1:8888///');
    expect(await repository.loadBaseUrl(), 'http://127.0.0.1:8888');

    await repository.saveBaseUrl(AppAuthRepository.defaultBaseUrl);
    expect(await repository.loadBaseUrl(), AppAuthRepository.defaultBaseUrl);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.backend.baseUrl'), isNull);
  });
}
