import 'package:flutter/material.dart';

import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/companion_answer.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/services/companion_answer_service.dart';

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
      _isSending = true;
      _controller.clear();
    });
    _scrollToBottom();
    final answer = await _service.answer(text);
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage.assistant(
        text: answer.answer,
        followUp: answer.followUp,
        sources: answer.sources,
        usedFallback: answer.usedFallback,
      ));
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
                  itemCount: _messages.length + (_isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return _MessageBubble(
                        message: const _ChatMessage.assistant(
                          text: '正在整理相关记忆…',
                        ),
                        developerMode: developerMode,
                      );
                    }
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
  });

  const _ChatMessage.user({required String text})
      : this(text: text, isUser: true);

  const _ChatMessage.assistant({
    required String text,
    String followUp = '',
    List<CompanionAnswerSource> sources = const [],
    bool usedFallback = false,
  }) : this(
          text: text,
          isUser: false,
          followUp: followUp,
          sources: sources,
          usedFallback: usedFallback,
        );

  final String text;
  final bool isUser;
  final String followUp;
  final List<CompanionAnswerSource> sources;
  final bool usedFallback;
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
        ? ' ${source.sourceType}:${source.sourceId}'
        : '';
    final score = source.score > 0 ? ' ${source.score}' : '';
    return '${source.title}$id$score';
  }
}
