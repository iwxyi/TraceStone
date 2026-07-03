import 'package:flutter/foundation.dart';

class AiAnalysisQueueBus {
  const AiAnalysisQueueBus._();

  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void bump() {
    version.value++;
  }
}
