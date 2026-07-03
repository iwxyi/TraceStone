import 'package:shared_preferences/shared_preferences.dart';

class DeveloperSettingsRepository {
  const DeveloperSettingsRepository();

  static const _developerModeKey = 'settings.developerMode';

  Future<bool> isDeveloperModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_developerModeKey) ?? false;
  }

  Future<void> setDeveloperModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_developerModeKey, enabled);
  }
}
