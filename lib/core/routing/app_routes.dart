import 'package:flutter/material.dart';

import '../../features/ai_insight/presentation/insight_page.dart';
import '../../features/companion/presentation/companion_page.dart';
import '../../features/diary/presentation/diary_edit_page.dart';
import '../../features/diary/presentation/diary_home_page.dart';
import '../../features/relationships/presentation/relationships_page.dart';
import '../../features/review/presentation/review_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/settings/presentation/custom_ai_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shaping_stone/presentation/shaping_stone_page.dart';

class AppRoutes {
  const AppRoutes._();

  static const home = '/';
  static const diaryEdit = '/diary/edit';
  static const insight = '/insight';
  static const shapingStone = '/shaping-stone';
  static const companion = '/companion';
  static const review = '/review';
  static const search = '/search';
  static const relationships = '/relationships';
  static const settings = '/settings';
  static const customAi = '/settings/custom-ai';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (settings.name == diaryEdit) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const DiaryEditPage(),
      );
    }
    final builder = routes[settings.name];
    if (builder == null) return null;
    return MaterialPageRoute(settings: settings, builder: builder);
  }

  static final routes = <String, WidgetBuilder>{
    home: (_) => const DiaryHomePage(),
    insight: (_) => const InsightPage(),
    shapingStone: (_) => const ShapingStonePage(),
    companion: (_) => const CompanionPage(),
    review: (_) => const ReviewPage(),
    search: (_) => const SearchPage(),
    relationships: (_) => const RelationshipsPage(),
    settings: (_) => const SettingsPage(),
    customAi: (_) => const CustomAiPage(),
  };
}
