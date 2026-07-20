import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const decadePaper = ThemePalette(
    name: '十年纸页',
    description: '暖纸、墨字与青绿，适合长期默认使用。',
    seed: Color(0xFF4F7D73),
    accent: Color(0xFFC9824A),
    darkAccent: Color(0xFFD7A06C),
    lightBackground: Color(0xFFFAF7F0),
    lightSurface: Color(0xFFFFFDF8),
    lightText: Color(0xFF2F302D),
    lightTextMuted: Color(0xFF7E8179),
    lightBorder: Color(0xFFE7DED2),
    darkBackground: Color(0xFF171A18),
    darkSurface: Color(0xFF222622),
    darkPrimary: Color(0xFF8CBDB2),
    darkText: Color(0xFFE2DED6),
    darkTextMuted: Color(0xFFA7A197),
    darkBorder: Color(0xFF3A3F39),
    cardStyle: ShinenCardStyle.paper,
    chipStyle: ShinenChipStyle.softFill,
    inputStyle: ShinenInputStyle.paper,
    navStyle: ShinenNavStyle.underline,
    shapeScale: ShinenShapeScale.medium,
  );

  static const morningWindow = ThemePalette(
    name: '清晨窗光',
    description: '浅青白、湖蓝与晨光黄，明亮轻盈。',
    seed: Color(0xFF3F7F8C),
    accent: Color(0xFFD8A93B),
    darkAccent: Color(0xFFE0BE65),
    lightBackground: Color(0xFFF6FAF8),
    lightSurface: Color(0xFFFFFFFF),
    lightText: Color(0xFF263033),
    lightTextMuted: Color(0xFF748184),
    lightBorder: Color(0xFFDDE8E6),
    darkBackground: Color(0xFF101A1D),
    darkSurface: Color(0xFF1A262A),
    darkPrimary: Color(0xFF7EC1CF),
    darkText: Color(0xFFDCE7EA),
    darkTextMuted: Color(0xFF9FAFB4),
    darkBorder: Color(0xFF314047),
    cardStyle: ShinenCardStyle.clean,
    chipStyle: ShinenChipStyle.tinted,
    inputStyle: ShinenInputStyle.filled,
    navStyle: ShinenNavStyle.pill,
    shapeScale: ShinenShapeScale.large,
  );

  static const oldAlbum = ThemePalette(
    name: '旧相册',
    description: '淡米纸、橄榄灰与胶片红，适合回顾。',
    seed: Color(0xFF6F7658),
    accent: Color(0xFFB06452),
    darkAccent: Color(0xFFD28C78),
    lightBackground: Color(0xFFFBF4E7),
    lightSurface: Color(0xFFFFF9EF),
    lightText: Color(0xFF342E28),
    lightTextMuted: Color(0xFF81756A),
    lightBorder: Color(0xFFE9DCC8),
    darkBackground: Color(0xFF1C1713),
    darkSurface: Color(0xFF2A211A),
    darkPrimary: Color(0xFFAEB789),
    darkText: Color(0xFFE9DED0),
    darkTextMuted: Color(0xFFB2A292),
    darkBorder: Color(0xFF463A2E),
    cardStyle: ShinenCardStyle.archive,
    chipStyle: ShinenChipStyle.outline,
    inputStyle: ShinenInputStyle.underlined,
    navStyle: ShinenNavStyle.underline,
    shapeScale: ShinenShapeScale.small,
  );

  static const rainyNight = ThemePalette(
    name: '雨夜灯下',
    description: '深墨蓝、雨色灰与暖灯琥珀，适合夜间书写。',
    seed: Color(0xFF607D9A),
    accent: Color(0xFFD6A85C),
    darkAccent: Color(0xFFE4BE7A),
    lightBackground: Color(0xFFF6F7F9),
    lightSurface: Color(0xFFFFFFFF),
    lightText: Color(0xFF2A2D33),
    lightTextMuted: Color(0xFF737985),
    lightBorder: Color(0xFFDEE2E8),
    darkBackground: Color(0xFF11151D),
    darkSurface: Color(0xFF1B2230),
    darkPrimary: Color(0xFF9CB9D6),
    darkText: Color(0xFFE0E6EF),
    darkTextMuted: Color(0xFFA6B0BE),
    darkBorder: Color(0xFF303A4B),
    cardStyle: ShinenCardStyle.glass,
    chipStyle: ShinenChipStyle.ghost,
    inputStyle: ShinenInputStyle.glow,
    navStyle: ShinenNavStyle.dot,
    shapeScale: ShinenShapeScale.large,
  );

  static const seaSalt = ThemePalette(
    name: '海盐蓝图',
    description: '冷白、海盐蓝与珊瑚色，清爽理性。',
    seed: Color(0xFF2F7C9B),
    accent: Color(0xFFE07A5F),
    darkAccent: Color(0xFFF19A82),
    lightBackground: Color(0xFFF4F8FA),
    lightSurface: Color(0xFFFFFFFF),
    lightText: Color(0xFF243039),
    lightTextMuted: Color(0xFF71808A),
    lightBorder: Color(0xFFDCE7EC),
    darkBackground: Color(0xFF0F1A21),
    darkSurface: Color(0xFF172631),
    darkPrimary: Color(0xFF7CBBD2),
    darkText: Color(0xFFDCE8EE),
    darkTextMuted: Color(0xFF9CAEB7),
    darkBorder: Color(0xFF2D4250),
    cardStyle: ShinenCardStyle.clean,
    chipStyle: ShinenChipStyle.outline,
    inputStyle: ShinenInputStyle.filled,
    navStyle: ShinenNavStyle.pill,
    shapeScale: ShinenShapeScale.small,
  );

  static const osmanthusYard = ThemePalette(
    name: '桂花庭院',
    description: '庭院绿、桂花金与灰白墙面，温暖有生活感。',
    seed: Color(0xFF657A43),
    accent: Color(0xFFD79A2B),
    darkAccent: Color(0xFFE3B957),
    lightBackground: Color(0xFFFAF8EE),
    lightSurface: Color(0xFFFFFCF4),
    lightText: Color(0xFF303225),
    lightTextMuted: Color(0xFF7E806C),
    lightBorder: Color(0xFFE8E1C8),
    darkBackground: Color(0xFF17190F),
    darkSurface: Color(0xFF232616),
    darkPrimary: Color(0xFFA7BA72),
    darkText: Color(0xFFE5E2D0),
    darkTextMuted: Color(0xFFA9A58D),
    darkBorder: Color(0xFF3C4128),
    cardStyle: ShinenCardStyle.paper,
    chipStyle: ShinenChipStyle.tinted,
    inputStyle: ShinenInputStyle.paper,
    navStyle: ShinenNavStyle.softBlock,
    shapeScale: ShinenShapeScale.medium,
  );

  static const camelliaLetter = ThemePalette(
    name: '山茶信笺',
    description: '信笺白、山茶红与墨绿，细腻但克制。',
    seed: Color(0xFF8E4A55),
    accent: Color(0xFF2F6F61),
    darkAccent: Color(0xFF7FC2B1),
    lightBackground: Color(0xFFFCF6F4),
    lightSurface: Color(0xFFFFFFFF),
    lightText: Color(0xFF342B2E),
    lightTextMuted: Color(0xFF83777A),
    lightBorder: Color(0xFFEBDCDC),
    darkBackground: Color(0xFF1C1316),
    darkSurface: Color(0xFF2A1D21),
    darkPrimary: Color(0xFFD18B96),
    darkText: Color(0xFFE9DDE0),
    darkTextMuted: Color(0xFFB4A0A5),
    darkBorder: Color(0xFF463036),
    cardStyle: ShinenCardStyle.letter,
    chipStyle: ShinenChipStyle.ghost,
    inputStyle: ShinenInputStyle.underlined,
    navStyle: ShinenNavStyle.dot,
    shapeScale: ShinenShapeScale.medium,
  );

  static const frostGinkgo = ThemePalette(
    name: '霜晨银杏',
    description: '霜灰、银杏黄与深蓝灰，清冷中带一点光。',
    seed: Color(0xFF66768A),
    accent: Color(0xFFC9A227),
    darkAccent: Color(0xFFE1C65C),
    lightBackground: Color(0xFFF7F8F3),
    lightSurface: Color(0xFFFFFFFF),
    lightText: Color(0xFF2B3036),
    lightTextMuted: Color(0xFF737C82),
    lightBorder: Color(0xFFE0E4E0),
    darkBackground: Color(0xFF12161A),
    darkSurface: Color(0xFF1E242A),
    darkPrimary: Color(0xFFA3B4C8),
    darkText: Color(0xFFE2E6EA),
    darkTextMuted: Color(0xFFA4ADB5),
    darkBorder: Color(0xFF343C44),
    cardStyle: ShinenCardStyle.outline,
    chipStyle: ShinenChipStyle.softFill,
    inputStyle: ShinenInputStyle.outline,
    navStyle: ShinenNavStyle.pill,
    shapeScale: ShinenShapeScale.small,
  );

  static const streamStone = decadePaper;
  static const inkStone = rainyNight;
  static const morningMist = morningWindow;

  static const emotionCalm = Color(0xFFA3B5A6);
  static const emotionJoy = Color(0xFFE8B87B);
  static const emotionSad = Color(0xFF9BA4B5);
  static const emotionAnxious = Color(0xFFC4A488);
  static const emotionWarm = Color(0xFFD4A5A5);

  static const palettes = [
    decadePaper,
    morningWindow,
    oldAlbum,
    rainyNight,
    seaSalt,
    osmanthusYard,
    camelliaLetter,
    frostGinkgo,
  ];

  static ThemeData get streamStoneLight => themeFrom(streamStone);
  static ThemeData get inkStoneDark => themeFrom(inkStone, dark: true);
  static ThemeData get morningMistLight => themeFrom(morningMist);

  static ThemeData themeFrom(ThemePalette palette, {bool dark = false}) {
    final background = dark ? palette.darkBackground : palette.lightBackground;
    final surface = dark ? palette.darkSurface : palette.lightSurface;
    final primary = dark ? palette.darkPrimary : palette.seed;
    final accent = dark ? palette.darkAccent : palette.accent;
    final text = dark ? palette.darkText : palette.lightText;
    final muted = dark ? palette.darkTextMuted : palette.lightTextMuted;
    final border = dark ? palette.darkBorder : palette.lightBorder;
    final card = _cardTheme(
      palette: palette,
      dark: dark,
      surface: surface,
      border: border,
    );
    final input = _inputTheme(
      palette: palette,
      dark: dark,
      background: background,
      surface: surface,
      primary: primary,
      muted: muted,
      border: border,
    );
    final chip = _chipTheme(
      palette: palette,
      dark: dark,
      primary: primary,
      text: text,
      border: border,
    );
    final nav = _navTheme(
      palette: palette,
      dark: dark,
      primary: primary,
      muted: muted,
      surface: surface,
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: primary,
      secondary: accent,
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
          letterSpacing: 0,
        ),
      ),
      cardTheme: card,
      inputDecorationTheme: input,
      navigationBarTheme: nav,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              palette.shapeScale == ShinenShapeScale.large
                  ? 14
                  : palette.shapeScale == ShinenShapeScale.small
                      ? 8
                      : 10,
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: palette.shapeScale == ShinenShapeScale.large ? 20 : 18,
            vertical: palette.shapeScale == ShinenShapeScale.large ? 15 : 14,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: palette.cardStyle == ShinenCardStyle.glass ? 1 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            palette.shapeScale == ShinenShapeScale.large
                ? 18
                : palette.shapeScale == ShinenShapeScale.small
                    ? 10
                    : 14,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      chipTheme: chip,
      extensions: [
        TraceStoneColors(
          textMuted: muted,
          border: border,
          accent: accent,
          paper: background,
          cardStyle: palette.cardStyle,
          chipStyle: palette.chipStyle,
          inputStyle: palette.inputStyle,
          navStyle: palette.navStyle,
          shapeScale: palette.shapeScale,
          calm: emotionCalm,
          joy: emotionJoy,
          sad: emotionSad,
          anxious: emotionAnxious,
          warm: emotionWarm,
        ),
      ],
    );
  }

  static CardThemeData _cardTheme({
    required ThemePalette palette,
    required bool dark,
    required Color surface,
    required Color border,
  }) {
    final radius = switch (palette.cardStyle) {
      ShinenCardStyle.paper => 8.0,
      ShinenCardStyle.clean => 12.0,
      ShinenCardStyle.archive => 10.0,
      ShinenCardStyle.glass => 16.0,
      ShinenCardStyle.outline => 10.0,
      ShinenCardStyle.letter => 12.0,
    };
    final alpha = switch (palette.cardStyle) {
      ShinenCardStyle.paper => 1.0,
      ShinenCardStyle.clean => 1.0,
      ShinenCardStyle.archive => dark ? 0.92 : 0.96,
      ShinenCardStyle.glass => dark ? 0.66 : 0.82,
      ShinenCardStyle.outline => dark ? 0.18 : 0.06,
      ShinenCardStyle.letter => dark ? 0.9 : 1.0,
    };
    final elevation = switch (palette.cardStyle) {
      ShinenCardStyle.glass => 0.5,
      ShinenCardStyle.paper => 0.0,
      ShinenCardStyle.clean => 0.0,
      ShinenCardStyle.archive => 0.0,
      ShinenCardStyle.outline => 0.0,
      ShinenCardStyle.letter => 0.0,
    };
    final cardBorder = switch (palette.cardStyle) {
      ShinenCardStyle.outline => border,
      ShinenCardStyle.glass => border.withValues(alpha: 0.7),
      ShinenCardStyle.clean => border.withValues(alpha: 0.75),
      ShinenCardStyle.archive => border.withValues(alpha: 0.9),
      ShinenCardStyle.paper => border,
      ShinenCardStyle.letter => border.withValues(alpha: 0.9),
    };
    return CardThemeData(
      color: palette.cardStyle == ShinenCardStyle.outline
          ? Colors.transparent
          : surface.withValues(alpha: alpha),
      elevation: elevation,
      margin: EdgeInsets.zero,
      shadowColor: dark ? Colors.black.withValues(alpha: 0.22) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: cardBorder),
      ),
    );
  }

  static InputDecorationTheme _inputTheme({
    required ThemePalette palette,
    required bool dark,
    required Color background,
    required Color surface,
    required Color primary,
    required Color muted,
    required Color border,
  }) {
    return switch (palette.inputStyle) {
      ShinenInputStyle.paper => InputDecorationTheme(
          filled: true,
          fillColor: surface,
          hintStyle: TextStyle(color: muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: primary, width: 1.4),
          ),
        ),
      ShinenInputStyle.filled => InputDecorationTheme(
          filled: true,
          fillColor: primary.withValues(alpha: dark ? 0.1 : 0.05),
          hintStyle: TextStyle(color: muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary, width: 1.4),
          ),
        ),
      ShinenInputStyle.underlined => InputDecorationTheme(
          filled: false,
          hintStyle: TextStyle(color: muted),
          border: UnderlineInputBorder(
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: primary, width: 1.4),
          ),
        ),
      ShinenInputStyle.glow => InputDecorationTheme(
          filled: true,
          fillColor: background,
          hintStyle: TextStyle(color: muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: border.withValues(alpha: 0.9)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: border.withValues(alpha: 0.9)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: primary, width: 1.6),
          ),
        ),
      ShinenInputStyle.outline => InputDecorationTheme(
          filled: false,
          hintStyle: TextStyle(color: muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: primary, width: 1.4),
          ),
        ),
    };
  }

  static ChipThemeData _chipTheme({
    required ThemePalette palette,
    required bool dark,
    required Color primary,
    required Color text,
    required Color border,
  }) {
    final radius = switch (palette.chipStyle) {
      ShinenChipStyle.softFill => 8.0,
      ShinenChipStyle.tinted => 14.0,
      ShinenChipStyle.outline => 10.0,
      ShinenChipStyle.ghost => 999.0,
    };
    final backgroundColor = switch (palette.chipStyle) {
      ShinenChipStyle.softFill => primary.withValues(alpha: dark ? 0.16 : 0.08),
      ShinenChipStyle.tinted => primary.withValues(alpha: dark ? 0.22 : 0.12),
      ShinenChipStyle.outline => Colors.transparent,
      ShinenChipStyle.ghost => Colors.transparent,
    };
    final selectedColor = switch (palette.chipStyle) {
      ShinenChipStyle.softFill => primary.withValues(alpha: dark ? 0.28 : 0.16),
      ShinenChipStyle.tinted => primary.withValues(alpha: dark ? 0.34 : 0.22),
      ShinenChipStyle.outline => primary.withValues(alpha: dark ? 0.18 : 0.1),
      ShinenChipStyle.ghost => primary.withValues(alpha: dark ? 0.18 : 0.08),
    };
    final side = switch (palette.chipStyle) {
      ShinenChipStyle.softFill => BorderSide(color: border),
      ShinenChipStyle.tinted => BorderSide(color: border),
      ShinenChipStyle.outline =>
        BorderSide(color: primary.withValues(alpha: 0.5)),
      ShinenChipStyle.ghost => BorderSide(color: Colors.transparent),
    };
    return ChipThemeData(
      backgroundColor: backgroundColor,
      selectedColor: selectedColor,
      labelStyle: TextStyle(color: text),
      side: side,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static NavigationBarThemeData _navTheme({
    required ThemePalette palette,
    required bool dark,
    required Color primary,
    required Color muted,
    required Color surface,
  }) {
    final indicator = switch (palette.navStyle) {
      ShinenNavStyle.underline => primary.withValues(alpha: dark ? 0.3 : 0.16),
      ShinenNavStyle.pill => primary.withValues(alpha: dark ? 0.34 : 0.18),
      ShinenNavStyle.dot => primary.withValues(alpha: dark ? 0.26 : 0.14),
      ShinenNavStyle.softBlock => primary.withValues(alpha: dark ? 0.2 : 0.12),
    };
    return NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: indicator,
      indicatorShape: switch (palette.navStyle) {
        ShinenNavStyle.underline => const StadiumBorder(),
        ShinenNavStyle.pill => const StadiumBorder(),
        ShinenNavStyle.dot => const CircleBorder(),
        ShinenNavStyle.softBlock => RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
      },
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 12,
          color: muted,
          fontWeight: palette.navStyle == ShinenNavStyle.pill
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? primary : muted);
      }),
    );
  }
}

class ThemePalette {
  const ThemePalette({
    required this.name,
    required this.description,
    required this.seed,
    required this.accent,
    required this.darkAccent,
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
    required this.cardStyle,
    required this.chipStyle,
    required this.inputStyle,
    required this.navStyle,
    required this.shapeScale,
  });

  final String name;
  final String description;
  final Color seed;
  final Color accent;
  final Color darkAccent;
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
  final ShinenCardStyle cardStyle;
  final ShinenChipStyle chipStyle;
  final ShinenInputStyle inputStyle;
  final ShinenNavStyle navStyle;
  final ShinenShapeScale shapeScale;
}

enum ShinenCardStyle { paper, clean, archive, glass, outline, letter }

enum ShinenChipStyle { softFill, tinted, outline, ghost }

enum ShinenInputStyle { paper, filled, underlined, glow, outline }

enum ShinenNavStyle { underline, pill, dot, softBlock }

enum ShinenShapeScale { small, medium, large }

class TraceStoneColors extends ThemeExtension<TraceStoneColors> {
  const TraceStoneColors({
    required this.textMuted,
    required this.border,
    required this.accent,
    required this.paper,
    required this.cardStyle,
    required this.chipStyle,
    required this.inputStyle,
    required this.navStyle,
    required this.shapeScale,
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
  final ShinenCardStyle cardStyle;
  final ShinenChipStyle chipStyle;
  final ShinenInputStyle inputStyle;
  final ShinenNavStyle navStyle;
  final ShinenShapeScale shapeScale;
  final Color calm;
  final Color joy;
  final Color sad;
  final Color anxious;
  final Color warm;

  double get cardRadius {
    return switch (cardStyle) {
      ShinenCardStyle.paper => 8,
      ShinenCardStyle.clean => 12,
      ShinenCardStyle.archive => 10,
      ShinenCardStyle.glass => 16,
      ShinenCardStyle.outline => 10,
      ShinenCardStyle.letter => 12,
    };
  }

  double get controlRadius {
    return switch (shapeScale) {
      ShinenShapeScale.small => 8,
      ShinenShapeScale.medium => 10,
      ShinenShapeScale.large => 14,
    };
  }

  double cardAlpha(bool dark) {
    return switch (cardStyle) {
      ShinenCardStyle.paper => 1,
      ShinenCardStyle.clean => 1,
      ShinenCardStyle.archive => dark ? 0.92 : 0.96,
      ShinenCardStyle.glass => dark ? 0.66 : 0.82,
      ShinenCardStyle.outline => 0,
      ShinenCardStyle.letter => dark ? 0.9 : 1,
    };
  }

  Color cardColor(Color surface, bool dark) {
    if (cardStyle == ShinenCardStyle.outline) return Colors.transparent;
    return surface.withValues(alpha: cardAlpha(dark));
  }

  BorderSide cardBorderSide(Color fallback) {
    return BorderSide(
      color: switch (cardStyle) {
        ShinenCardStyle.clean => fallback.withValues(alpha: 0.75),
        ShinenCardStyle.glass => fallback.withValues(alpha: 0.7),
        ShinenCardStyle.outline => fallback,
        ShinenCardStyle.archive => fallback.withValues(alpha: 0.9),
        ShinenCardStyle.paper => fallback,
        ShinenCardStyle.letter => fallback.withValues(alpha: 0.9),
      },
    );
  }

  @override
  TraceStoneColors copyWith({
    Color? textMuted,
    Color? border,
    Color? accent,
    Color? paper,
    ShinenCardStyle? cardStyle,
    ShinenChipStyle? chipStyle,
    ShinenInputStyle? inputStyle,
    ShinenNavStyle? navStyle,
    ShinenShapeScale? shapeScale,
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
      cardStyle: cardStyle ?? this.cardStyle,
      chipStyle: chipStyle ?? this.chipStyle,
      inputStyle: inputStyle ?? this.inputStyle,
      navStyle: navStyle ?? this.navStyle,
      shapeScale: shapeScale ?? this.shapeScale,
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
      cardStyle: t < 0.5 ? cardStyle : other.cardStyle,
      chipStyle: t < 0.5 ? chipStyle : other.chipStyle,
      inputStyle: t < 0.5 ? inputStyle : other.inputStyle,
      navStyle: t < 0.5 ? navStyle : other.navStyle,
      shapeScale: t < 0.5 ? shapeScale : other.shapeScale,
      calm: Color.lerp(calm, other.calm, t)!,
      joy: Color.lerp(joy, other.joy, t)!,
      sad: Color.lerp(sad, other.sad, t)!,
      anxious: Color.lerp(anxious, other.anxious, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
    );
  }
}
