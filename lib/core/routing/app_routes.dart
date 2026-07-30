import 'package:flutter/material.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/account_page.dart';
import '../../features/ai_insight/presentation/insight_page.dart';
import '../../features/companion/presentation/companion_page.dart';
import '../../features/diary/presentation/diary_edit_page.dart';
import '../../features/diary/presentation/diary_home_page.dart';
import '../../features/relationships/presentation/relationships_page.dart';
import '../../features/review/presentation/review_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/settings/presentation/ai_debug_page.dart';
import '../../features/settings/presentation/ai_task_queue_page.dart';
import '../../features/settings/presentation/calendar_memory_page.dart';
import '../../features/settings/presentation/custom_ai_page.dart';
import '../../features/settings/presentation/memory_management_page.dart';
import '../../features/settings/presentation/recycle_bin_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shaping_stone/presentation/shaping_stone_page.dart';

class AppRoutes {
  const AppRoutes._();

  static const home = '/';
  static const diaryEdit = '/diary/edit';

  static String diaryEditPath([String? id]) =>
      id == null ? diaryEdit : '$diaryEdit?id=$id';
  static const insight = '/insight';
  static const shapingStone = '/shaping-stone';
  static const companion = '/companion';
  static const review = '/review';
  static const search = '/search';
  static const relationships = '/relationships';
  static const settings = '/settings';
  static const login = '/login';
  static const account = '/account';
  static const customAi = '/settings/custom-ai';
  static const calendarMemory = '/settings/calendar-memory';
  static const memoryManagement = '/settings/memories';
  static const aiTaskQueue = '/settings/ai-task-queue';
  static const aiDebug = '/settings/ai-debug';
  static const recycleBin = '/settings/recycle-bin';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '';
    if (name == diaryEdit || name.startsWith('$diaryEdit?')) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const DiaryEditPage(),
      );
    }
    final builder = routes[settings.name];
    if (builder == null) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => _UnknownRoutePage(routeName: settings.name),
      );
    }
    return MaterialPageRoute(settings: settings, builder: builder);
  }

  static Map<String, WidgetBuilder> get routes => {
        home: (_) => const DiaryHomePage(),
        insight: (_) => const InsightPage(),
        shapingStone: (_) => const ShapingStonePage(),
        companion: (_) => const CompanionPage(),
        review: (_) => const ReviewPage(),
        search: (_) => const SearchPage(),
        relationships: (_) => const RelationshipsPage(),
        login: (_) => const LoginPage(),
        account: (_) => const AccountPage(),
        settings: (_) => const SettingsPage(),
        customAi: (_) => const CustomAiPage(),
        calendarMemory: (_) => const CalendarMemoryPage(),
        memoryManagement: (_) => const MemoryManagementPage(),
        aiTaskQueue: (_) => const AiTaskQueuePage(),
        aiDebug: (_) => const AiDebugPage(),
        recycleBin: (_) => const RecycleBinPage(),
      };
}

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage({required this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('没有找到页面：${routeName ?? 'unknown'}'),
        ),
      ),
    );
  }
}
