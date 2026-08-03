import 'package:flutter_test/flutter_test.dart';
import 'package:trace_stone/data/models/app_lock_settings.dart';
import 'package:trace_stone/data/repositories/app_lock_repository.dart';

class _FakeAppLockSecureStore implements AppLockSecureStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('stores local lock secret as salted hash', () async {
    final store = _FakeAppLockSecureStore();
    final repository = AppLockRepository(secureStore: store);

    final settings = await repository.setLocalSecret(
      method: AppLockMethod.pin,
      secret: '123456',
      requireAfterSeconds: 60,
    );

    expect(settings.enabled, isTrue);
    expect(settings.method, AppLockMethod.pin);
    expect(settings.secretHash, isNot(contains('123456')));
    expect(settings.secretSalt, isNotEmpty);
    expect(store.values.values.single, isNot(contains('123456')));
    expect(await repository.verifySecret('123456'), isTrue);
    expect(await repository.verifySecret('000000'), isFalse);
  });

  test('disables lock without deleting timing preference', () async {
    final store = _FakeAppLockSecureStore();
    final repository = AppLockRepository(secureStore: store);
    await repository.setLocalSecret(
      method: AppLockMethod.password,
      secret: 'secret-password',
      requireAfterSeconds: 900,
    );

    final settings = await repository.disable();

    expect(settings.enabled, isFalse);
    expect(settings.method, AppLockMethod.none);
    expect(settings.requireAfterSeconds, 900);
  });
}
