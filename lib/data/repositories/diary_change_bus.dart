import 'package:flutter/foundation.dart';

class DiaryChangeBus {
  DiaryChangeBus._();

  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void bump() {
    version.value = version.value + 1;
  }
}
