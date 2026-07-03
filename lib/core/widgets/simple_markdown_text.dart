import 'package:flutter/material.dart';

class SimpleMarkdownText extends StatelessWidget {
  const SimpleMarkdownText({
    super.key,
    required this.text,
    this.emptyText = '',
  });

  final String text;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final value = text.trim().isEmpty ? emptyText : text;
    final lines = value.trim().isEmpty ? const <String>[] : value.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) _MarkdownLine(line: line),
      ],
    );
  }
}

class _MarkdownLine extends StatelessWidget {
  const _MarkdownLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final trimmed = line.trimRight();
    if (trimmed.trim().isEmpty) return const SizedBox(height: 8);

    final headingMatch = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(trimmed);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!.length;
      final value = headingMatch.group(2)!.trim();
      final style = switch (level) {
        1 => Theme.of(context).textTheme.headlineSmall,
        2 => Theme.of(context).textTheme.titleLarge,
        _ => Theme.of(context).textTheme.titleMedium,
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _MarkdownInlineText(text: value, style: style),
      );
    }

    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed.trim())) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
      );
    }

    if (trimmed.startsWith('> ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _MarkdownInlineText(text: trimmed.substring(2)),
          ),
        ),
      );
    }

    final bullet = RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
    if (bullet != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• '),
            Expanded(child: _MarkdownInlineText(text: bullet.group(1)!)),
          ],
        ),
      );
    }

    final ordered = RegExp(r'^\d+\.\s+(.+)$').firstMatch(trimmed);
    if (ordered != null) {
      final marker = trimmed.substring(0, trimmed.indexOf(' ') + 1);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(marker),
            Expanded(child: _MarkdownInlineText(text: ordered.group(1)!)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _MarkdownInlineText(text: trimmed),
    );
  }
}

class _MarkdownInlineText extends StatelessWidget {
  const _MarkdownInlineText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium;
    return RichText(
      text: TextSpan(
        style: baseStyle?.copyWith(
          color: baseStyle.color ?? Theme.of(context).colorScheme.onSurface,
        ),
        children: _spans(context, text),
      ),
    );
  }

  List<TextSpan> _spans(BuildContext context, String value) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)');
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (token.startsWith('*')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ));
      }
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return spans;
  }
}
