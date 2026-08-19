import 'dart:async';

import 'package:flutter/material.dart';

import 'app/trace_stone_app.dart';
import 'core/errors/app_error_reporter.dart';
import 'data/services/app_startup_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    AppErrorReporter.install();
    const startupService = AppStartupService();
    await startupService.runBeforeApp();
    runApp(const TraceStoneApp());
    startupService.runAfterAppStart();
  }, (error, stackTrace) {
    AppErrorReporter.report(error, stackTrace, source: 'Dart zone');
  });
}
