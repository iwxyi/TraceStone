import 'package:flutter/material.dart';

import '../../../data/models/ai_feedback.dart';
import '../../../data/repositories/ai_feedback_repository.dart';

class AiFeedbackBar extends StatefulWidget {
  const AiFeedbackBar({super.key, required this.entryId});

  final String entryId;

  @override
  State<AiFeedbackBar> createState() => _AiFeedbackBarState();
}

class _AiFeedbackBarState extends State<AiFeedbackBar> {
  final _repository = const AiFeedbackRepository();
  late Future<AiFeedback?> _feedbackFuture =
      _repository.getFeedback(widget.entryId);

  Future<void> _save(AiFeedbackValue value, {String? note}) async {
    final createdAt = DateTime.now();
    final feedback = AiFeedback(
      entryId: widget.entryId,
      value: value,
      createdAt: createdAt,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
    );
    await _repository.saveFeedback(feedback);
    if (!mounted) return;
    setState(() {
      _feedbackFuture = Future.value(feedback);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(value == AiFeedbackValue.helpful ? '已记录反馈' : '已标记为不准确')),
    );
  }

  Future<void> _markInaccurate() async {
    final controller = TextEditingController();
    try {
      final note = await showDialog<String?>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('哪里不准确？'),
            content: TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '可选：写下错误点，便于后续调试',
                border: OutlineInputBorder(),
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
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('提交'),
              ),
            ],
          );
        },
      );
      if (note == null) return;
      await _save(AiFeedbackValue.inaccurate, note: note);
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AiFeedback?>(
      future: _feedbackFuture,
      builder: (context, snapshot) {
        final value = snapshot.data?.value;
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
