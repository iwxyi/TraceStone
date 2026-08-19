import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppErrorReport {
  const AppErrorReport({
    required this.error,
    required this.stackTrace,
    required this.source,
    required this.occurredAt,
  });

  final Object error;
  final StackTrace stackTrace;
  final String source;
  final DateTime occurredAt;

  String get diagnosticText => [
        'TraceStone error report',
        'time=${occurredAt.toIso8601String()}',
        'source=$source',
        'error=$error',
        'stackTrace=$stackTrace',
      ].join('\n');
}

class AppErrorReporter {
  AppErrorReporter._();

  static final ValueNotifier<AppErrorReport?> latest =
      ValueNotifier<AppErrorReport?>(null);

  static void install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(
        details.exception,
        details.stack ?? StackTrace.current,
        source: 'Flutter framework',
      );
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      report(error, stackTrace, source: 'Platform dispatcher');
      return true;
    };
    ErrorWidget.builder = (details) {
      report(
        details.exception,
        details.stack ?? StackTrace.current,
        source: 'Widget build',
      );
      return _ErrorFallback(message: details.exceptionAsString());
    };
  }

  static void report(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {
    latest.value = AppErrorReport(
      error: error,
      stackTrace: stackTrace,
      source: source,
      occurredAt: DateTime.now(),
    );
  }

  static void clear() {
    latest.value = null;
  }
}

class _ErrorFallback extends StatelessWidget {
  const _ErrorFallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '页面发生错误：$message',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        ),
      ),
    );
  }
}
