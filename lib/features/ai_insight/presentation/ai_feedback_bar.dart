import 'package:flutter/material.dart';

import '../../../data/models/ai_feedback.dart';
import '../../../data/repositories/ai_feedback_repository.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/services/ai_feedback_service.dart';

class AiFeedbackBar extends StatefulWidget {
  const AiFeedbackBar({
    super.key,
    required this.entryId,
    this.compact = false,
  });

  final String entryId;
  final bool compact;

  @override
  State<AiFeedbackBar> createState() => _AiFeedbackBarState();
}

class _AiFeedbackBarState extends State<AiFeedbackBar> {
  final _repository = const AiFeedbackRepository();
  final _developerSettings = const DeveloperSettingsRepository();
  final _feedbackService = const AiFeedbackService();
  late Future<AiFeedback?> _feedbackFuture =
      _repository.getFeedback(widget.entryId);

  Future<void> _save(AiFeedbackValue value, {String? note}) async {
    final feedback = await _feedbackService.submitInsightFeedback(
      entryId: widget.entryId,
      value: value,
      note: note,
    );
    if (!mounted) return;
    setState(() {
      _feedbackFuture = Future.value(feedback);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            value == AiFeedbackValue.helpful ? '已记录反馈' : '已标记为不准确，将重新整理这篇洞察'),
      ),
    );
  }

  Future<void> _markInaccurate() async {
    final developerMode = await _developerSettings.isDeveloperModeEnabled();
    if (!mounted) return;
    final note = await showDialog<String?>(
      context: context,
      builder: (context) => _InaccurateFeedbackDialog(
        developerMode: developerMode,
      ),
    );
    if (note == null) return;
    await _save(AiFeedbackValue.inaccurate, note: note);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AiFeedback?>(
      future: _feedbackFuture,
      builder: (context, snapshot) {
        final value = snapshot.data?.value;
        if (widget.compact) {
          return _CompactFeedbackActions(
            value: value,
            onHelpful: () => _save(AiFeedbackValue.helpful),
            onInaccurate: _markInaccurate,
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              avatar: const Icon(Icons.thumb_up_outlined, size: 16),
              label: const Text('有帮助'),
              selected: value == AiFeedbackValue.helpful,
              onSelected: (_) => _save(AiFeedbackValue.helpful),
            ),
            FilterChip(
              avatar: const Icon(Icons.report_problem_outlined, size: 16),
              label: const Text('不准确'),
              selected: value == AiFeedbackValue.inaccurate,
              onSelected: (_) => _markInaccurate(),
            ),
          ],
        );
      },
    );
  }
}

class _InaccurateFeedbackDialog extends StatefulWidget {
  const _InaccurateFeedbackDialog({required this.developerMode});

  final bool developerMode;

  @override
  State<_InaccurateFeedbackDialog> createState() =>
      _InaccurateFeedbackDialogState();
}

class _InaccurateFeedbackDialogState extends State<_InaccurateFeedbackDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('哪里不准确？'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '可选：写下哪里不对，帮我重新核对这篇日记',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.developerMode) ...[
              const SizedBox(height: 10),
              Text(
                '开发者模式：这条反馈会写入 AI 调试记录，并作为重新生成洞察的上下文。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('跳过'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('提交'),
        ),
      ],
    );
  }
}

class _CompactFeedbackActions extends StatelessWidget {
  const _CompactFeedbackActions({
    required this.value,
    required this.onHelpful,
    required this.onInaccurate,
  });

  final AiFeedbackValue? value;
  final VoidCallback onHelpful;
  final VoidCallback onInaccurate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
    final selectedColor = theme.colorScheme.primary.withValues(alpha: 0.84);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FeedbackTextButton(
          label: value == AiFeedbackValue.helpful ? '已标记有帮助' : '有帮助',
          color: value == AiFeedbackValue.helpful ? selectedColor : color,
          onTap: onHelpful,
        ),
        Text('/', style: theme.textTheme.bodySmall?.copyWith(color: color)),
        _FeedbackTextButton(
          label: value == AiFeedbackValue.inaccurate ? '已标记不准确' : '不准确',
          color: value == AiFeedbackValue.inaccurate ? selectedColor : color,
          onTap: onInaccurate,
        ),
      ],
    );
  }
}

class _FeedbackTextButton extends StatelessWidget {
  const _FeedbackTextButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                decoration: TextDecoration.underline,
                decorationColor: color.withValues(alpha: 0.34),
                decorationThickness: 0.8,
              ),
        ),
      ),
    );
  }
}
