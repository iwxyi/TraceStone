import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors/app_error_reporter.dart';

class AppErrorOverlay extends StatelessWidget {
  const AppErrorOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppErrorReport?>(
      valueListenable: AppErrorReporter.latest,
      builder: (context, report, _) {
        return Stack(
          children: [
            child,
            if (report != null) _ErrorNotice(report: report),
          ],
        );
      },
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.report});

  final AppErrorReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '发生未处理错误：${report.error}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制错误',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: report.diagnosticText),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('错误诊断已复制')),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                  IconButton(
                    tooltip: '关闭错误提示',
                    onPressed: AppErrorReporter.clear,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
