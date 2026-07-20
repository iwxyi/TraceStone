import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/simple_markdown_text.dart';
import '../../../data/models/companion_answer.dart';
import '../../../data/repositories/developer_settings_repository.dart';
import '../../../data/services/companion_answer_service.dart';
import '../../../data/utils/ai_source_formatter.dart';

class CompanionPage extends StatefulWidget {
  const CompanionPage({
    super.key,
    this.initialQuestion,
    this.answerService,
    this.developerModeFuture,
  });

  final String? initialQuestion;
  final CompanionAnswerService? answerService;
  final Future<bool>? developerModeFuture;

  @override
  State<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends State<CompanionPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _listKey = GlobalKey();
  late final CompanionAnswerService _service =
      widget.answerService ?? const CompanionAnswerService();
  late final Future<bool> _developerModeFuture = widget.developerModeFuture ??
      const DeveloperSettingsRepository().isDeveloperModeEnabled();
  final _messages = <_ChatMessage>[];
  final _messageKeys = <GlobalKey>[];
  bool _isSending = false;
  bool _isUserScrolling = false;
  bool _autoScrollCancelledByUser = false;

  @override
  void initState() {
    super.initState();
    _addMessage(const _ChatMessage.assistant(
      text: '你可以问我：最近我反复在意什么？我和自己的关系有什么变化？',
    ));
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
    late final int userIndex;
    setState(() {
      _autoScrollCancelledByUser = false;
      _addMessage(_ChatMessage.user(text: text));
      userIndex = _messages.length - 1;
      _addMessage(const _ChatMessage.assistant(
        text: '正在整理线索',
        isPending: true,
        researchSteps: [],
      ));
      _isSending = true;
      _controller.clear();
    });
    _scrollWithUserAnchor(userIndex: userIndex, force: true);
    final progressIndex = _messages.length - 1;
    final researchSteps = <CompanionResearchStep>[];
    try {
      final answer = await _service.answer(
        text,
        onProgress: (step) {
          if (!mounted) return;
          researchSteps.add(step);
          setState(() {
            _messages[progressIndex] = _ChatMessage.assistant(
              text: _publicStatusFor(step),
              isPending: true,
              thinkingHints: _publicHintsFor(step),
              researchSteps: List.unmodifiable(researchSteps),
            );
          });
          _scrollWithUserAnchor(userIndex: userIndex);
        },
      );
      if (!mounted) return;
      await _revealAnswer(
        messageIndex: progressIndex,
        userIndex: userIndex,
        answer: answer,
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messages[progressIndex] = _ChatMessage.assistant(
          text: '洞察生成失败：$error',
          isError: true,
          researchSteps: List.unmodifiable(researchSteps),
        );
        _isSending = false;
      });
    }
    _scrollWithUserAnchor(userIndex: userIndex);
  }

  Future<void> _revealAnswer({
    required int messageIndex,
    required int userIndex,
    required CompanionAnswer answer,
  }) async {
    final text = answer.answer;
    final chunks = _streamChunks(text);
    setState(() {
      _messages[messageIndex] = _ChatMessage.assistant(
        text: '',
        isStreaming: true,
        researchSteps: answer.researchSteps,
      );
    });
    await Future<void>.delayed(const Duration(milliseconds: 90));
    final buffer = StringBuffer();
    for (final chunk in chunks) {
      if (!mounted) return;
      buffer.write(chunk);
      setState(() {
        _messages[messageIndex] = _ChatMessage.assistant(
          text: buffer.toString(),
          isStreaming: true,
          researchSteps: answer.researchSteps,
        );
      });
      _scrollWithUserAnchor(userIndex: userIndex);
      await Future<void>.delayed(
        Duration(milliseconds: chunk.length > 8 ? 22 : 16),
      );
    }
    if (!mounted) return;
    setState(() {
      _messages[messageIndex] = _ChatMessage.assistant(
        text: answer.answer,
        followUp: answer.followUp,
        sources: answer.sources,
        usedFallback: answer.usedFallback,
        researchSteps: answer.researchSteps,
      );
      _isSending = false;
    });
  }

  List<String> _streamChunks(String text) {
    final runes = text.runes.toList(growable: false);
    final chunks = <String>[];
    for (var index = 0; index < runes.length;) {
      final remaining = runes.length - index;
      final size = remaining < 6 ? remaining : 6;
      chunks.add(String.fromCharCodes(runes.sublist(index, index + size)));
      index += size;
    }
    return chunks;
  }

  void _addMessage(_ChatMessage message) {
    _messages.add(message);
    _messageKeys.add(GlobalKey());
  }

  String _publicStatusFor(CompanionResearchStep step) {
    final title = step.title;
    if (title.contains('理解问题')) return '正在理解问题';
    if (title.contains('检索基础资料')) return '正在查找相关日记';
    if (title.contains('规划研究路径')) return '正在规划分析路径';
    if (title.startsWith('研究第')) return '正在查找更多线索';
    if (title.startsWith('整理')) return '正在整理线索';
    if (title.contains('AI 判断下一步')) return '正在判断资料是否足够';
    if (title.contains('评估证据覆盖')) return '正在核对线索';
    if (title.contains('生成回答')) return '正在组织回答';
    return '正在整理线索';
  }

  List<String> _publicHintsFor(CompanionResearchStep step) {
    final hints = <String>[];
    void add(String value) {
      final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length < 2) return;
      if (normalized.contains('=') || normalized.contains('：')) return;
      if (normalized.contains('候选资料') || normalized.contains('证据')) return;
      final clipped = normalized.length <= 12
          ? normalized
          : '${normalized.substring(0, 11)}…';
      if (!hints.contains(clipped)) hints.add(clipped);
    }

    if (step.evidence.isNotEmpty) {
      for (final item in step.evidence) {
        add(item.title);
        if (hints.length >= 4) return hints;
      }
    }
    for (final part in step.detail.split(RegExp(r'[；;，,、\n]'))) {
      add(part);
      if (hints.length >= 4) break;
    }
    return hints;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      _isUserScrolling = notification.direction != ScrollDirection.idle;
      if (_isUserScrolling && !_isNearBottom()) {
        final lastUserTop = _lastUserTopInViewport();
        if (lastUserTop == null || lastUserTop >= -8) {
          _autoScrollCancelledByUser = true;
        }
      }
      if (_isNearBottom()) _autoScrollCancelledByUser = false;
    } else if (notification is ScrollEndNotification) {
      _isUserScrolling = false;
      if (_isNearBottom()) _autoScrollCancelledByUser = false;
    }
    return false;
  }

  void _scrollWithUserAnchor({
    required int userIndex,
    bool force = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (!force && _isUserScrolling) return;
      final userTop = _messageTopInViewport(userIndex);
      final pinnedAtTop = userTop != null && userTop.abs() <= 10;
      final passedTop = userTop != null && userTop < -10;
      if (!force) {
        if (_autoScrollCancelledByUser && !passedTop) return;
        if (pinnedAtTop) return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutQuart,
      );
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) <= 28;
  }

  double? _lastUserTopInViewport() {
    for (var index = _messages.length - 1; index >= 0; index--) {
      if (_messages[index].isUser) return _messageTopInViewport(index);
    }
    return null;
  }

  double? _messageTopInViewport(int index) {
    if (index < 0 || index >= _messageKeys.length) return null;
    final listContext = _listKey.currentContext;
    final itemContext = _messageKeys[index].currentContext;
    if (listContext == null || itemContext == null) return null;
    final listBox = listContext.findRenderObject();
    final itemBox = itemContext.findRenderObject();
    if (listBox is! RenderBox || itemBox is! RenderBox) return null;
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final itemTop = itemBox.localToGlobal(Offset.zero).dy;
    return itemTop - listTop;
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
                return NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: ListView.builder(
                    key: _listKey,
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return KeyedSubtree(
                        key: _messageKeys[index],
                        child: _AnimatedMessageEntry(
                          index: index,
                          child: _MessageBubble(
                            message: _messages[index],
                            developerMode: developerMode,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: _ComposerBar(
              controller: _controller,
              isSending: _isSending,
              onSend: _send,
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
    this.thinkingHints = const [],
    this.isPending = false,
    this.isStreaming = false,
    this.isError = false,
  });

  const _ChatMessage.user({required String text})
      : this(text: text, isUser: true);

  const _ChatMessage.assistant({
    required String text,
    String followUp = '',
    List<CompanionAnswerSource> sources = const [],
    bool usedFallback = false,
    List<CompanionResearchStep> researchSteps = const [],
    List<String> thinkingHints = const [],
    bool isPending = false,
    bool isStreaming = false,
    bool isError = false,
  }) : this(
          text: text,
          isUser: false,
          followUp: followUp,
          sources: sources,
          usedFallback: usedFallback,
          researchSteps: researchSteps,
          thinkingHints: thinkingHints,
          isPending: isPending,
          isStreaming: isStreaming,
          isError: isError,
        );

  final String text;
  final bool isUser;
  final String followUp;
  final List<CompanionAnswerSource> sources;
  final bool usedFallback;
  final List<CompanionResearchStep> researchSteps;
  final List<String> thinkingHints;
  final bool isPending;
  final bool isStreaming;
  final bool isError;
}

class _AnimatedMessageEntry extends StatelessWidget {
  const _AnimatedMessageEntry({
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(index),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
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
    final colors = theme.colorScheme;
    final shinen = theme.extension<TraceStoneColors>() ??
        AppTheme.themeFrom(AppTheme.decadePaper).extension<TraceStoneColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    final radius = switch (shinen.cardStyle) {
      ShinenCardStyle.glass => 18.0,
      ShinenCardStyle.letter => 12.0,
      ShinenCardStyle.archive => 10.0,
      _ => shinen.cardRadius + 4,
    };
    final bubbleColor = message.isUser
        ? colors.primaryContainer.withValues(alpha: isDark ? 0.62 : 0.82)
        : message.isError
            ? colors.errorContainer.withValues(alpha: isDark ? 0.58 : 0.72)
            : shinen.cardColor(colors.surface, isDark);
    final borderColor = message.isUser
        ? colors.primary.withValues(alpha: isDark ? 0.26 : 0.14)
        : shinen.cardBorderSide(colors.outlineVariant).color;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
                bottomLeft: Radius.circular(message.isUser ? radius : 6),
                bottomRight: Radius.circular(message.isUser ? 6 : radius),
              ),
              border: Border.all(
                color: borderColor,
              ),
              boxShadow: [
                if (shinen.cardStyle == ShinenCardStyle.clean ||
                    shinen.cardStyle == ShinenCardStyle.glass)
                  BoxShadow(
                    color:
                        colors.shadow.withValues(alpha: isDark ? 0.12 : 0.04),
                    blurRadius:
                        shinen.cardStyle == ShinenCardStyle.glass ? 22 : 14,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  reverseDuration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    );
                    return FadeTransition(
                      opacity: curved,
                      child: SizeTransition(
                        sizeFactor: curved,
                        alignment: Alignment.topCenter,
                        child: child,
                      ),
                    );
                  },
                  child: message.isPending
                      ? _ThinkingPanel(
                          key: const ValueKey('thinking'),
                          status: message.text,
                          hints: message.thinkingHints,
                          developerMode: developerMode,
                          steps: message.researchSteps,
                        )
                      : _MessageContent(
                          key: ValueKey(
                            '${message.text}${message.followUp}${message.sources.length}${message.researchSteps.length}',
                          ),
                          message: message,
                          developerMode: developerMode,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({
    super.key,
    required this.message,
    required this.developerMode,
  });

  final _ChatMessage message;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SimpleMarkdownText(text: message.text),
        if (message.isStreaming) const _StreamingCursor(),
        if (message.followUp.isNotEmpty) ...[
          const SizedBox(height: 10),
          SimpleMarkdownText(text: '**${message.followUp}**'),
        ],
        if (message.usedFallback) ...[
          const SizedBox(height: 10),
          Text(
            '本地检索回答',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
        if (developerMode &&
            !message.isUser &&
            message.researchSteps.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResearchStepsView(
            steps: message.researchSteps,
            developerMode: developerMode,
          ),
        ],
        if (message.sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SourceChips(
            sources: message.sources,
            developerMode: developerMode,
          ),
        ],
      ],
    );
  }
}

class _ThinkingPanel extends StatefulWidget {
  const _ThinkingPanel({
    super.key,
    required this.status,
    required this.hints,
    required this.developerMode,
    required this.steps,
  });

  final String status;
  final List<String> hints;
  final bool developerMode;
  final List<CompanionResearchStep> steps;

  @override
  State<_ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<_ThinkingPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ThinkingMark(controller: _controller),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.18),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                widget.status,
                key: ValueKey(widget.status),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.08, end: _progressForSteps(widget.steps)),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 3,
              value: value,
              backgroundColor:
                  colors.surfaceContainerHighest.withValues(alpha: 0.42),
              color: colors.primary.withValues(alpha: 0.68),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: widget.hints.isEmpty
              ? const SizedBox.shrink(key: ValueKey('empty-hints'))
              : _ThinkingHintChips(
                  key: ValueKey(widget.hints.join('|')),
                  hints: widget.hints,
                ),
        ),
        if (widget.developerMode && widget.steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResearchStepsView(
            steps: widget.steps,
            developerMode: widget.developerMode,
          ),
        ],
      ],
    );
  }

  double _progressForSteps(List<CompanionResearchStep> steps) {
    if (steps.isEmpty) return 0.08;
    final title = steps.last.title;
    if (title.contains('理解问题')) return 0.14;
    if (title.contains('检索基础资料')) return 0.28;
    if (title.contains('规划研究路径')) return 0.4;
    if (title.startsWith('研究第')) {
      final round = int.tryParse(
            RegExp(r'研究第\s*(\d+)').firstMatch(title)?.group(1) ?? '',
          ) ??
          1;
      return (0.48 + round * 0.08).clamp(0.48, 0.74).toDouble();
    }
    if (title.startsWith('整理')) return 0.78;
    if (title.contains('AI 判断下一步')) return 0.84;
    if (title.contains('评估证据覆盖')) return 0.88;
    if (title.contains('生成回答')) return 0.94;
    return (0.12 + steps.length * 0.08).clamp(0.12, 0.9).toDouble();
  }
}

class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor();

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      child: Container(
        width: 8,
        height: 18,
        margin: const EdgeInsets.only(left: 2, top: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _ThinkingMark extends StatelessWidget {
  const _ThinkingMark({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 3; index++)
              Padding(
                padding: EdgeInsets.only(right: index == 2 ? 0 : 4),
                child: Transform.scale(
                  scale: _scaleFor(index),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: _alphaFor(index)),
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 7, height: 7),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  double _phase(int index) => (controller.value + index * 0.18) % 1;

  double _scaleFor(int index) {
    final wave = Curves.easeInOutCubic.transform(_phase(index));
    return 0.72 + wave * 0.42;
  }

  double _alphaFor(int index) {
    final wave = Curves.easeInOutCubic.transform(_phase(index));
    return 0.38 + wave * 0.48;
  }
}

class _ThinkingHintChips extends StatelessWidget {
  const _ThinkingHintChips({
    super.key,
    required this.hints,
  });

  final List<String> hints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final hint in hints.take(4))
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceChips extends StatelessWidget {
  const _SourceChips({
    required this.sources,
    required this.developerMode,
  });

  final List<CompanionAnswerSource> sources;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final source in sources.take(3))
          Tooltip(
            message: source.reason,
            child: Chip(
              avatar: Icon(
                Icons.article_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: Text(_sourceLabel(source)),
            ),
          ),
      ],
    );
  }

  String _sourceLabel(CompanionAnswerSource source) {
    if (!developerMode) return source.title;
    final id = (source.sourceType?.isNotEmpty ?? false) &&
            (source.sourceId?.isNotEmpty ?? false)
        ? ' ${formatAiSourceId(source.sourceType!, source.sourceId!)}'
        : '';
    final score = source.score > 0 ? ' ${source.score}' : '';
    return '${source.title}$id$score';
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isSending,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: '问问最近的自己……',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: Icon(
                  Icons.auto_awesome_outlined,
                  size: 19,
                  color: colors.primary.withValues(alpha: 0.78),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedScale(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            scale: isSending ? 0.94 : 1,
            child: IconButton.filled(
              tooltip: '发送',
              onPressed: isSending ? null : onSend,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: isSending
                    ? const SizedBox(
                        key: ValueKey('sending'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.arrow_upward,
                        key: ValueKey('send'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
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
