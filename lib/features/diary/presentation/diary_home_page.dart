import 'package:flutter/material.dart';

import '../../../core/routing/app_routes.dart';
import '../../companion/presentation/companion_page.dart';
import '../../review/presentation/review_page.dart';
import '../../settings/presentation/profile_page.dart';
import 'today_page.dart';
import '../../../data/models/diary_entry.dart';

class DiaryHomePage extends StatefulWidget {
  const DiaryHomePage({super.key});

  @override
  State<DiaryHomePage> createState() => _DiaryHomePageState();
}

class _DiaryHomePageState extends State<DiaryHomePage> {
  int _currentIndex = 0;

  void _handleDiarySaved(DiaryEntry entry) {
    final now = DateTime.now();
    final isToday = entry.date.year == now.year &&
        entry.date.month == now.month &&
        entry.date.day == now.day;
    setState(() {
      if (!isToday) _currentIndex = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          TodayPage(
            onDiarySaved: _handleDiarySaved,
          ),
          const ReviewPage(),
          const CompanionPage(),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '时光',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '树洞',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我',
          ),
        ],
      ),
    );
  }
}

void openSearch(BuildContext context) {
  Navigator.of(context).pushNamed(AppRoutes.search);
}
