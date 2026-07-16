import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/routing/app_route_observer.dart';
import '../core/routing/app_routes.dart';
import '../data/services/app_startup_service.dart';
import 'theme_controller.dart';

class TraceStoneApp extends StatefulWidget {
  const TraceStoneApp({
    super.key,
    this.startupService = const AppStartupService(),
  });

  final AppStartupService startupService;

  @override
  State<TraceStoneApp> createState() => _TraceStoneAppState();
}

class _TraceStoneAppState extends State<TraceStoneApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(widget.startupService.resumeAiQueue());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final locale = Localizations.maybeLocaleOf(context) ??
            WidgetsBinding.instance.platformDispatcher.locale;
        return MaterialApp(
          title: AppConstants.displayNameFor(locale.languageCode),
          debugShowCheckedModeBanner: false,
          theme: themeController.lightTheme,
          darkTheme: themeController.darkTheme,
          themeMode: themeController.themeMode,
          routes: AppRoutes.routes,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          navigatorObservers: [appRouteObserver],
          initialRoute: AppRoutes.home,
        );
      },
    );
  }
}
