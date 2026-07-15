import 'package:flutter/material.dart';

import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/companion_answer.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/services/companion_answer_service.dart';
import '../../../data/utils/ai_source_formatter.dart';

class CompanionPage extends StatefulWidget {
  const CompanionPage({
    super.key,
    this.initialQuestion,
  });

  final String? initialQuestion;

  @override
  State<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends State<CompanionPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _service = const CompanionAnswerService();
  final _developerSettings = const DeveloperSettingsRepository();
  late final Future<bool> _developerModeFuture =
      _developerSettings.isDeveloperModeEnabled();
  final _messages = <_ChatMessage>[
    const _ChatMessage.assistant(
      text: '你可以问我：最近我反复在意什么？我和自己的关系有什么变化？',
    ),
  ];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    final question = widget.initialQuestion?.trim();
    if (question == null || question.isEmpty) return;
    _controller.text = question;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _send();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() {
      _messages.add(_ChatMessage.user(text: text));
      _messages.add(const _ChatMessage.assistant(
        text: '正在理解问题…',
        researchSteps: [],
      ));
      _isSending = true;
      _controller.clear();
    });
    _scrollToBottom();
    final progressIndex = _messages.length - 1;
    final researchSteps = <CompanionResearchStep>[];
    final answer = await _service.answer(
      text,
      onProgress: (step) {
        if (!mounted) return;
        researchSteps.add(step);
        setState(() {
          _messages[progressIndex] = _ChatMessage.assistant(
            text: step.status,
            researchSteps: List.unmodifiable(researchSteps),
          );
        });
        _scrollToBottom();
      },
    );
    if (!mounted) return;
    setState(() {
      _messages[progressIndex] = _ChatMessage.assistant(
        text: answer.answer,
        followUp: answer.followUp,
        sources: answer.sources,
        usedFallback: answer.usedFallback,
        researchSteps: answer.researchSteps,
      );
      _isSending = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('洞察')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<bool>(
              future: _developerModeFuture,
              builder: (context, snapshot) {
                final developerMode = snapshot.data ?? false;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    return _MessageBubble(
                      message: _messages[index],
                      developerMode: developerMode,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_isSending,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '问问最近的自己……',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: _isSending ? null : _send,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.followUp = '',
    this.sources = const [],
    this.usedFallback = false,
    this.researchSteps = const [],
  });

  const _ChatMessage.user({required String text})
      : this(text: text, isUser: true);

  const _ChatMessage.assistant({
    required String text,
    String followUp = '',
    List<CompanionAnswerSource> sources = const [],
    bool usedFallback = false,
    List<CompanionResearchStep> researchSteps = const [],
  }) : this(
          text: text,
          isUser: false,
          followUp: followUp,
          sources: sources,
          usedFallback: usedFallback,
          researchSteps: researchSteps,
        );

  final String text;
  final bool isUser;
  final String followUp;
  final List<CompanionAnswerSource> sources;
  final bool usedFallback;
  final List<CompanionResearchStep> researchSteps;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.developerMode,
  });

  final _ChatMessage message;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          elevation: 0,
          color: message.isUser ? theme.colorScheme.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SimpleMarkdownText(text: message.text),
                if (message.followUp.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SimpleMarkdownText(text: '**${message.followUp}**'),
                ],
                if (message.usedFallback) ...[
                  const SizedBox(height: 10),
                  Text('本地检索回答',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                ],
                if (!message.isUser && message.researchSteps.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ResearchStepsView(
                    steps: message.researchSteps,
                    developerMode: developerMode,
                  ),
                ],
                if (message.sources.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final source in message.sources.take(3))
                        Tooltip(
                          message: source.reason,
                          child: Chip(
                            label: Text(_sourceLabel(source, developerMode)),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _sourceLabel(CompanionAnswerSource source, bool developerMode) {
    if (!developerMode) return source.title;
    final id = (source.sourceType?.isNotEmpty ?? false) &&
            (source.sourceId?.isNotEmpty ?? false)
        ? ' ${formatAiSourceId(source.sourceType!, source.sourceId!)}'
        : '';
    final score = source.score > 0 ? ' ${source.score}' : '';
    return '${source.title}$id$score';
  }
}

class _ResearchStepsView extends StatelessWidget {
  const _ResearchStepsView({
    required this.steps,
    required this.developerMode,
  });

  final List<CompanionResearchStep> steps;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('研究过程', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(left: 4, bottom: 8),
              title: Text(step.title, style: theme.textTheme.bodyMedium),
              subtitle: Text(step.status, style: theme.textTheme.bodySmall),
              initiallyExpanded: (step.evidence.isNotEmpty ||
                      step.batchSummaries.isNotEmpty) &&
                  identical(steps.last, step),
              children: [
                if (step.detail.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(step.detail, style: theme.textTheme.bodySmall),
                  ),
                if (developerMode && step.developerDetail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      step.developerDetail,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                ],
                if (step.evidence.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final item in step.evidence.take(8))
                    _ResearchEvidenceTile(
                      evidence: item,
                      developerMode: developerMode,
                    ),
                ],
                if (step.batchSummaries.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final batch in step.batchSummaries.take(6))
                    _ResearchBatchTile(
                      batch: batch,
                      developerMode: developerMode,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ResearchBatchTile extends StatelessWidget {
  const _ResearchBatchTile({
    required this.batch,
    required this.developerMode,
  });

  final CompanionResearchBatchSummary batch;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${batch.title} · ${batch.candidateCount} 条',
                style: theme.textTheme.bodyMedium,
              ),
              if (batch.summary.isNotEmpty)
                Text(batch.summary, style: theme.textTheme.bodySmall),
              if (developerMode && batch.developerDetail.isNotEmpty)
                Text(
                  batch.developerDetail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              if (batch.evidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final item in batch.evidence.take(3))
                  _ResearchEvidenceTile(
                    evidence: item,
                    developerMode: developerMode,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResearchEvidenceTile extends StatelessWidget {
  const _ResearchEvidenceTile({
    required this.evidence,
    required this.developerMode,
  });

  final CompanionResearchEvidence evidence;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = evidence.sourceType == null || evidence.sourceId == null
        ? ''
        : formatAiSourceId(evidence.sourceType!, evidence.sourceId!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(evidence.title, style: theme.textTheme.bodyMedium),
              if (evidence.summary.isNotEmpty)
                Text(evidence.summary, style: theme.textTheme.bodySmall),
              if (evidence.reason.isNotEmpty)
                Text(evidence.reason, style: theme.textTheme.bodySmall),
              if (developerMode)
                Text(
                  [
                    if (source.isNotEmpty) source,
                    if (evidence.entryId?.isNotEmpty ?? false)
                      'entry=${evidence.entryId}',
                    'score=${evidence.score}',
                  ].join(' | '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
