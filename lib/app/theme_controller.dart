import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';

class ThemeController extends ChangeNotifier {
  static const _paletteKey = 'theme.palette';
  static const _themeModeKey = 'theme.mode';

  ThemePalette _palette = AppTheme.decadePaper;
  ThemeMode _themeMode = ThemeMode.system;
  bool _loaded = false;

  ThemePalette get palette => _palette;
  ThemeMode get themeMode => _themeMode;
  bool get isLoaded => _loaded;

  ThemeController() {
    unawaited(_load());
  }

  ThemeData get lightTheme => AppTheme.themeFrom(_palette);
  ThemeData get darkTheme => AppTheme.themeFrom(_palette, dark: true);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final paletteName = prefs.getString(_paletteKey);
    final modeName = prefs.getString(_themeModeKey);

    final palette = _paletteByName(paletteName) ?? AppTheme.decadePaper;
    final mode = _modeByName(modeName) ?? ThemeMode.system;
    _palette = palette;
    _themeMode = mode;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPalette(ThemePalette palette) async {
    _palette = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paletteKey, palette.name);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
    notifyListeners();
  }

  ThemePalette? _paletteByName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final palette in AppTheme.palettes) {
      if (palette.name == name) return palette;
    }
    return switch (name) {
      '溪石' => AppTheme.decadePaper,
      '墨砚' => AppTheme.rainyNight,
      '晨雾' => AppTheme.morningWindow,
      _ => null,
    };
  }

  ThemeMode? _modeByName(String? name) {
    return switch (name) {
      'system' => ThemeMode.system,
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
  }
}

final themeController = ThemeController();
