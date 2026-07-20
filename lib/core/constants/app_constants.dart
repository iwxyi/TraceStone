class AppConstants {
  const AppConstants._();

  static const appName = '拾年';
  static const appNameEn = 'Shinen';
  static const defaultThemeName = '十年纸页';

  static const freeDailyAiLimit = 3;
  static const memberDailyAiLimit = 20;
  static const memberMonthlyAiLimit = 500;

  static const embeddingDimension = 384;
  static const embeddingModelName = 'all-MiniLM-L6-v2';
  static const diaryPreviewMaxLines = 3;

  static String displayNameFor(String localeLanguageCode) {
    return localeLanguageCode == 'en' ? appNameEn : appName;
  }
}
