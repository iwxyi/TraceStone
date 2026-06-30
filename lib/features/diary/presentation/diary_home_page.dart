import 'package:flutter/material.dart';

import '../../../core/routing/app_routes.dart';
import '../../companion/presentation/companion_page.dart';
import '../../review/presentation/review_page.dart';
import '../../settings/presentation/profile_page.dart';
import 'today_page.dart';

class DiaryHomePage extends StatefulWidget {
  const DiaryHomePage({super.key});

  @override
  State<DiaryHomePage> createState() => _DiaryHomePageState();
}

class _DiaryHomePageState extends State<DiaryHomePage> {
  int _currentIndex = 0;
  int _refreshToken = 0;

  void _refreshPages() {
    setState(() => _refreshToken++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          TodayPage(
            key: ValueKey('today-$_refreshToken'),
            onDiaryChanged: _refreshPages,
          ),
          ReviewPage(key: ValueKey('review-$_refreshToken')),
          const CompanionPage(),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() {
          _currentIndex = index;
          if (index == 0 || index == 1) _refreshToken++;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '回顾',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '洞察',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

void openSearch(BuildContext context) {
  Navigator.of(context).pushNamed(AppRoutes.search);
}
