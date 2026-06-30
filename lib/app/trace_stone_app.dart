import 'package:flutter/material.dart';

import '../core/routing/app_routes.dart';
import 'theme_controller.dart';

class TraceStoneApp extends StatelessWidget {
  const TraceStoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: '溯石',
          debugShowCheckedModeBanner: false,
          theme: themeController.lightTheme,
          darkTheme: themeController.darkTheme,
          themeMode: themeController.themeMode,
          routes: AppRoutes.routes,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          initialRoute: AppRoutes.home,
        );
      },
    );
  }
}
