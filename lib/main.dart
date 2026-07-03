import 'package:flutter/material.dart';

import 'app/trace_stone_app.dart';
import 'data/services/app_startup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const startupService = AppStartupService();
  await startupService.runBeforeApp();
  runApp(const TraceStoneApp());
  startupService.runAfterAppStart();
}
