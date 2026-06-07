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
      tween: Tween(begin: 0.985, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: child),
      child: isUser ? _UserMessage(message: message) : _AssistantMessage(message: message),
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
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: CodexColors.bubble,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Text(message.text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: CodexColors.text, height: 1.32)),
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
      return _MutedStatusLine(text: message.text.trim().isEmpty ? 'Thinking…' : message.text.trim(), icon: Icons.auto_awesome_rounded, pulsing: true);
    }
    if (message.kind == AgentMessageKind.executing) {
      return _MutedStatusLine(text: message.text.trim(), icon: Icons.terminal_rounded, pulsing: !message.complete);
    }
    if (message.kind == AgentMessageKind.error) {
      return _ErrorBlock(text: message.text);
    }
    if (message.kind == AgentMessageKind.system) {
      return _MutedStatusLine(text: message.text.trim(), icon: Icons.info_outline_rounded, pulsing: false);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: CodexColors.text, height: 1.5),
          child: MarkdownCodeRenderer(text: message.text),
        ),
      ),
    );
  }
}

class _MutedStatusLine extends StatefulWidget {
  const _MutedStatusLine({required this.text, required this.icon, required this.pulsing});

  final String text;
  final IconData icon;
  final bool pulsing;

  @override
  State<_MutedStatusLine> createState() => _MutedStatusLineState();
}

class _MutedStatusLineState extends State<_MutedStatusLine> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _MutedStatusLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
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
    final child = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(widget.icon, color: CodexColors.muted, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(widget.text, style: const TextStyle(color: CodexColors.muted, fontSize: 18, height: 1.45, fontWeight: FontWeight.w600))),
      ],
    );
    if (!widget.pulsing) return child;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.48, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: child,
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CodexColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CodexColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: CodexColors.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: CodexColors.text, height: 1.35))),
        ],
      ),
    );
  }
}
