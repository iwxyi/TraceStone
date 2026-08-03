import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/routing/app_route_observer.dart';
import '../core/routing/app_routes.dart';
import '../data/repositories/app_lock_repository.dart';
import '../data/services/app_lock_authenticator.dart';
import '../data/services/app_startup_service.dart';
import 'app_lock_gate.dart';
import 'theme_controller.dart';

class TraceStoneApp extends StatefulWidget {
  const TraceStoneApp({
    super.key,
    this.startupService = const AppStartupService(),
    this.appLockRepository = const AppLockRepository(),
    this.appLockAuthenticator = const LocalAppLockAuthenticator(),
  });

  final AppStartupService startupService;
  final AppLockRepository appLockRepository;
  final AppLockAuthenticator appLockAuthenticator;

  @override
  State<TraceStoneApp> createState() => _TraceStoneAppState();
}

class _TraceStoneAppState extends State<TraceStoneApp>
    with WidgetsBindingObserver {
  final _lockGateKey = GlobalKey<AppLockGateState>();

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
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lockGateKey.currentState?.markBackgrounded(DateTime.now());
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    unawaited(widget.startupService.resumeAiQueue());
    unawaited(_lockGateKey.currentState?.handleResumed(DateTime.now()));
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
          builder: (context, child) {
            return AppLockGate(
              key: _lockGateKey,
              repository: widget.appLockRepository,
              authenticator: widget.appLockAuthenticator,
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
