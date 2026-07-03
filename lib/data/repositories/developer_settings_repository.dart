import 'package:shared_preferences/shared_preferences.dart';

class DeveloperSettingsRepository {
  const DeveloperSettingsRepository();

  static const _developerModeKey = 'settings.developerMode';

  Future<bool> isDeveloperModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final value = prefs.get(_developerModeKey);
      return value is bool ? value : false;
    } on Object {
      return false;
    }
  }

  Future<void> setDeveloperModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_developerModeKey, enabled);
  }
}
