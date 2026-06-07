import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/app_theme.dart';

class MarkdownCodeRenderer extends StatelessWidget {
  const MarkdownCodeRenderer({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final segments = _splitFencedCode(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in segments)
          if (segment.isCode)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: HighlightView(
                  segment.content,
                  language: segment.language?.isEmpty == true
                      ? null
                      : segment.language,
                  theme: atomOneDarkTheme,
                  padding: const EdgeInsets.all(12),
                  textStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.42,
                  ),
                ),
              ),
            )
          else if (segment.content.trim().isNotEmpty)
            MarkdownBody(
              data: segment.content,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: CodexColors.text,
                      height: 1.45,
                    ),
                    code: const TextStyle(
                      fontFamily: 'monospace',
                      color: CodexColors.greenSoft,
                      fontSize: 12,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    blockquoteDecoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: CodexColors.green.withValues(alpha: 0.6),
                          width: 3,
                        ),
                      ),
                    ),
                    a: const TextStyle(color: CodexColors.greenSoft),
                  ),
            ),
      ],
    );
  }
}

List<_Segment> _splitFencedCode(String input) {
  final regex = RegExp(r'```([^\n`]*)\n([\s\S]*?)```', multiLine: true);
  final segments = <_Segment>[];
  var cursor = 0;
  for (final match in regex.allMatches(input)) {
    if (match.start > cursor) {
      segments.add(_Segment.text(input.substring(cursor, match.start)));
    }
    segments.add(
      _Segment.code(match.group(2) ?? '', (match.group(1) ?? '').trim()),
    );
    cursor = match.end;
  }
  if (cursor < input.length) {
    segments.add(_Segment.text(input.substring(cursor)));
  }
  if (segments.isEmpty) {
    segments.add(_Segment.text(input));
  }
  return segments;
}

class _Segment {
  const _Segment({required this.content, required this.isCode, this.language});

  factory _Segment.text(String content) =>
      _Segment(content: content, isCode: false);
  factory _Segment.code(String content, String language) =>
      _Segment(content: content, isCode: true, language: language);

  final String content;
  final bool isCode;
  final String? language;
}
