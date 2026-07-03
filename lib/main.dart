import 'package:flutter/material.dart';

import 'app/trace_stone_app.dart';
import 'data/repositories/diary_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await const DiaryRepository().purgeExpiredTrash();
  runApp(const TraceStoneApp());
}
