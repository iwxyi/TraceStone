import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class ThemeController extends ChangeNotifier {
  ThemePalette _palette = AppTheme.streamStone;
  ThemeMode _themeMode = ThemeMode.system;

  ThemePalette get palette => _palette;
  ThemeMode get themeMode => _themeMode;

  ThemeData get lightTheme => AppTheme.themeFrom(_palette);
  ThemeData get darkTheme => AppTheme.themeFrom(_palette, dark: true);

  void setPalette(ThemePalette palette) {
    _palette = palette;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}

final themeController = ThemeController();
