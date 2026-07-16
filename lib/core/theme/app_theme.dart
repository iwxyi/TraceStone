import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const streamStone = ThemePalette(
    name: '溪石',
    description: '宣纸白、松石绿与岩石棕，温润沉静。',
    seed: Color(0xFF5B8C85),
    accent: Color(0xFFC49B7A),
    lightBackground: Color(0xFFFAF8F5),
    lightSurface: Color(0xFFFFFFFF),
    lightText: Color(0xFF3B3A38),
    lightTextMuted: Color(0xFF8E8C89),
    lightBorder: Color(0xFFEBE7E2),
    darkBackground: Color(0xFF1E1E1C),
    darkSurface: Color(0xFF292826),
    darkPrimary: Color(0xFF7DAEA8),
    darkText: Color(0xFFDCD8D3),
    darkTextMuted: Color(0xFFA9A49D),
    darkBorder: Color(0xFF3A3835),
  );

  static const inkStone = ThemePalette(
    name: '墨砚',
    description: '墨黑、砚灰与低饱和蓝绿，适合沉浸书写。',
    seed: Color(0xFF4E6F73),
    accent: Color(0xFF9C846C),
    lightBackground: Color(0xFFF7F3EC),
    lightSurface: Color(0xFFFFFEFB),
    lightText: Color(0xFF302E2B),
    lightTextMuted: Color(0xFF85807A),
    lightBorder: Color(0xFFE8E0D6),
    darkBackground: Color(0xFF181818),
    darkSurface: Color(0xFF242424),
    darkPrimary: Color(0xFF82A8AD),
    darkText: Color(0xFFE0DDD8),
    darkTextMuted: Color(0xFFA49F98),
    darkBorder: Color(0xFF363432),
  );

  static const morningMist = ThemePalette(
    name: '晨雾',
    description: '雾白、淡紫粉与柔和蓝，轻盈明亮。',
    seed: Color(0xFF9B91C9),
    accent: Color(0xFFD4A5A5),
    lightBackground: Color(0xFFFBFAF7),
    lightSurface: Color(0xFFFFFFFF),
    lightText: Color(0xFF3B3940),
    lightTextMuted: Color(0xFF8B8793),
    lightBorder: Color(0xFFE9E5EE),
    darkBackground: Color(0xFF1D1B22),
    darkSurface: Color(0xFF292631),
    darkPrimary: Color(0xFFB8AFE4),
    darkText: Color(0xFFE2DEE8),
    darkTextMuted: Color(0xFFA8A1B3),
    darkBorder: Color(0xFF3A3543),
  );

  static const emotionCalm = Color(0xFFA3B5A6);
  static const emotionJoy = Color(0xFFE8B87B);
  static const emotionSad = Color(0xFF9BA4B5);
  static const emotionAnxious = Color(0xFFC4A488);
  static const emotionWarm = Color(0xFFD4A5A5);

  static const palettes = [streamStone, inkStone, morningMist];

  static ThemeData get streamStoneLight => themeFrom(streamStone);
  static ThemeData get inkStoneDark => themeFrom(streamStone, dark: true);
  static ThemeData get morningMistLight => themeFrom(morningMist);

  static ThemeData themeFrom(ThemePalette palette, {bool dark = false}) {
    final background = dark ? palette.darkBackground : palette.lightBackground;
    final surface = dark ? palette.darkSurface : palette.lightSurface;
    final primary = dark ? palette.darkPrimary : palette.seed;
    final text = dark ? palette.darkText : palette.lightText;
    final muted = dark ? palette.darkTextMuted : palette.lightTextMuted;
    final border = dark ? palette.darkBorder : palette.lightBorder;

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: primary,
      secondary: palette.accent,
      surface: surface,
      outline: border,
      onSurface: text,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: Typography.material2021().black.apply(
            bodyColor: text,
            displayColor: text,
          ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: background.withValues(alpha: 0.92),
        foregroundColor: text,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: dark ? 0.28 : 0.14),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w500),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? primary : muted);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: primary.withValues(alpha: dark ? 0.18 : 0.08),
        selectedColor: primary.withValues(alpha: dark ? 0.28 : 0.16),
        labelStyle: TextStyle(color: text),
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      extensions: [
        TraceStoneColors(
          textMuted: muted,
          border: border,
          accent: palette.accent,
          paper: background,
          calm: emotionCalm,
          joy: emotionJoy,
          sad: emotionSad,
          anxious: emotionAnxious,
          warm: emotionWarm,
        ),
      ],
    );
  }
}

class ThemePalette {
  const ThemePalette({
    required this.name,
    required this.description,
    required this.seed,
    required this.accent,
    required this.lightBackground,
    required this.lightSurface,
    required this.lightText,
    required this.lightTextMuted,
    required this.lightBorder,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkPrimary,
    required this.darkText,
    required this.darkTextMuted,
    required this.darkBorder,
  });

  final String name;
  final String description;
  final Color seed;
  final Color accent;
  final Color lightBackground;
  final Color lightSurface;
  final Color lightText;
  final Color lightTextMuted;
  final Color lightBorder;
  final Color darkBackground;
  final Color darkSurface;
  final Color darkPrimary;
  final Color darkText;
  final Color darkTextMuted;
  final Color darkBorder;
}

class TraceStoneColors extends ThemeExtension<TraceStoneColors> {
  const TraceStoneColors({
    required this.textMuted,
    required this.border,
    required this.accent,
    required this.paper,
    required this.calm,
    required this.joy,
    required this.sad,
    required this.anxious,
    required this.warm,
  });

  final Color textMuted;
  final Color border;
  final Color accent;
  final Color paper;
  final Color calm;
  final Color joy;
  final Color sad;
  final Color anxious;
  final Color warm;

  @override
  TraceStoneColors copyWith({
    Color? textMuted,
    Color? border,
    Color? accent,
    Color? paper,
    Color? calm,
    Color? joy,
    Color? sad,
    Color? anxious,
    Color? warm,
  }) {
    return TraceStoneColors(
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      paper: paper ?? this.paper,
      calm: calm ?? this.calm,
      joy: joy ?? this.joy,
      sad: sad ?? this.sad,
      anxious: anxious ?? this.anxious,
      warm: warm ?? this.warm,
    );
  }

  @override
  TraceStoneColors lerp(ThemeExtension<TraceStoneColors>? other, double t) {
    if (other is! TraceStoneColors) return this;
    return TraceStoneColors(
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      calm: Color.lerp(calm, other.calm, t)!,
      joy: Color.lerp(joy, other.joy, t)!,
      sad: Color.lerp(sad, other.sad, t)!,
      anxious: Color.lerp(anxious, other.anxious, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
    );
  }
}
