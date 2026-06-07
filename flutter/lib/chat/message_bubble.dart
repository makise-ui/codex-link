import 'package:flutter/material.dart';

import '../protocol/bridge_messages.dart';
import '../theme/app_theme.dart';
import 'markdown_code_renderer.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 8),
          child: Transform.scale(
            scale: 0.99 + (value * 0.01),
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        ),
      ),
      child: isUser
          ? _UserMessage(message: message)
          : _AssistantMessage(message: message),
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.68,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: CodexColors.bubble,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Text(
          message.text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: CodexColors.text,
            height: 1.34,
          ),
        ),
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.kind == AgentMessageKind.thinking && !message.complete) {
      return _ActivityCard(
        text: message.text.trim().isEmpty ? 'Thinking' : message.text.trim(),
        title: message.title ?? 'Thinking',
        icon: Icons.auto_awesome_rounded,
        active: true,
      );
    }
    if (message.kind == AgentMessageKind.executing) {
      return _ActivityCard(
        text: message.text.trim(),
        title: message.title ?? 'Running tool',
        icon: Icons.terminal_rounded,
        active: !message.complete,
      );
    }
    if (message.kind == AgentMessageKind.error) {
      return _ErrorBlock(text: message.text);
    }
    if (message.kind == AgentMessageKind.files) {
      return _FileChangeCard(message: message);
    }
    if (message.kind == AgentMessageKind.system) {
      return _ActivityCard(
        text: message.text.trim(),
        title: message.title ?? 'System',
        icon: Icons.info_outline_rounded,
        active: false,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: CodexColors.text,
            height: 1.5,
          ),
          child: MarkdownCodeRenderer(text: message.text),
        ),
      ),
    );
  }
}

class _ActivityCard extends StatefulWidget {
  const _ActivityCard({
    required this.text,
    required this.title,
    required this.icon,
    required this.active,
  });

  final String text;
  final String title;
  final IconData icon;
  final bool active;

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.active && !_controller.isAnimating && !disableAnimations) {
      _controller.repeat();
    } else if ((!widget.active || disableAnimations) &&
        _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: CodexColors.panelHigh.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ActivityGlyph(
                icon: widget.icon,
                animation: _controller,
                active: widget.active,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CodexColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (widget.active) ...[
                          const SizedBox(width: 5),
                          _ThinkingDots(animation: _controller),
                        ],
                      ],
                    ),
                    if (widget.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.text.trim(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CodexColors.muted,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityGlyph extends StatelessWidget {
  const _ActivityGlyph({
    required this.icon,
    required this.animation,
    required this.active,
  });

  final IconData icon;
  final Animation<double> animation;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      icon,
      color: active ? CodexColors.greenSoft : CodexColors.muted,
      size: 16,
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final scale = active
            ? 0.88 +
                  (0.12 *
                      Curves.easeInOut.transform(
                        animation.value < 0.5
                            ? animation.value * 2
                            : (1 - animation.value) * 2,
                      ))
            : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: CodexColors.composer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Center(child: iconWidget),
      ),
    );
  }
}

class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final activeDot = (animation.value * 3).floor().clamp(0, 2);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 3; index++)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color: index == activeDot
                      ? CodexColors.greenSoft
                      : CodexColors.dim,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FileChangeCard extends StatelessWidget {
  const _FileChangeCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final files = message.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_FileChange.fromLine)
        .toList();
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CodexColors.panelHigh.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: CodexColors.green.withValues(alpha: 0.24),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    color: CodexColors.greenSoft,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    message.title ?? 'Files changed',
                    style: const TextStyle(
                      color: CodexColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${files.length}',
                    style: const TextStyle(
                      color: CodexColors.dim,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final file in files)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      _StatusBadge(status: file.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CodexColors.text,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'added' => CodexColors.greenSoft,
      'deleted' => CodexColors.danger,
      'renamed' => CodexColors.blue,
      _ => CodexColors.amber,
    };
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FileChange {
  const _FileChange({required this.status, required this.path});

  factory _FileChange.fromLine(String line) {
    final splitAt = line.indexOf(' ');
    if (splitAt <= 0 || splitAt >= line.length - 1) {
      return _FileChange(status: 'modified', path: line);
    }
    return _FileChange(
      status: line.substring(0, splitAt),
      path: line.substring(splitAt + 1),
    );
  }

  final String status;
  final String path;
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CodexColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CodexColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: CodexColors.danger,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: CodexColors.text,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
