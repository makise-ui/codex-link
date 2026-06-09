import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../theme/app_theme.dart';
import 'markdown_code_renderer.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.animate = true});

  final ChatMessage message;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final child = isUser
        ? _UserMessage(message: message)
        : _AssistantMessage(message: message);
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.messageEnter,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * AppSpacing.sm),
          child: Transform.scale(
            scale: 0.99 + (value * 0.01),
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final light = isCodexLight(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.68,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: light ? LightCodexColors.bubble : CodexColors.bubble,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: codexTextColor(
              context,
            ).withValues(alpha: AppOpacity.hairline),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onLongPress: () => _copyMessage(context, message.text),
              child: Text(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: codexTextColor(context),
                  height: 1.34,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _copyMessage(BuildContext context, String text) {
  if (text.trim().isEmpty) return;
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Copied'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 1),
    ),
  );
}

class _ResponseReveal extends StatelessWidget {
  const _ResponseReveal({
    required this.child,
    required this.complete,
    required this.long,
  });

  final Widget child;
  final bool complete;
  final bool long;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: complete ? 0.22 : 0.76, end: complete ? 1 : 0.86),
      duration: long
          ? const Duration(milliseconds: 380)
          : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: (1 - value).clamp(0.0, 0.7),
            child: Container(
              width: 2,
              height: 24,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Opacity(opacity: value, child: child),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.kind == AgentMessageKind.thinking) {
      if (message.complete) return const SizedBox.shrink();
      return const _ThinkingLine();
    }
    if (message.kind == AgentMessageKind.executing) {
      return _ActivityCard(
        text: message.text.trim(),
        title: message.title ?? 'Running tool',
        icon: _activityIconFor(message),
        active: !message.complete,
        complete: message.complete,
      );
    }
    if (message.kind == AgentMessageKind.reasoning) {
      return _ReasoningSummaryCard(message: message);
    }
    if (message.kind == AgentMessageKind.approval) {
      return _ApprovalCard(message: message);
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
        complete: false,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () => _copyMessage(context, message.text),
              child: _ResponseReveal(
                complete: message.complete,
                long: message.text.length > 600,
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: codexTextColor(context),
                    height: 1.5,
                  ),
                  child: MarkdownCodeRenderer(text: message.text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasoningSummaryCard extends StatelessWidget {
  const _ReasoningSummaryCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: CodexColors.panel.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: accent.withValues(alpha: AppOpacity.border),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.psychology_alt_rounded, color: accent, size: 17),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message.text.trim().isEmpty
                      ? (message.title ?? 'Thinking summary')
                      : message.text.trim(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CodexColors.muted,
                    height: 1.38,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppController>();
    final approval = ApprovalRequestInfo.fromText(
      message.text,
      fallbackTitle: message.title,
    );
    final accent = Theme.of(context).colorScheme.secondary;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: CodexColors.panelHigh.withValues(alpha: AppOpacity.panel),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined, color: accent, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      approval.title,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    approval.riskLevel,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: CodexColors.muted),
                  ),
                ],
              ),
              if (approval.body.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  approval.body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CodexColors.muted,
                    height: 1.35,
                  ),
                ),
              ],
              if (!message.complete && approval.approvalId.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => controller.decideApproval(
                        approval.approvalId,
                        'reject',
                      ),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Reject'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: () => controller.decideApproval(
                        approval.approvalId,
                        'approve',
                      ),
                      icon: const Icon(Icons.check_rounded, size: 17),
                      label: const Text('Approve'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ActivityStackBubble extends StatefulWidget {
  const ActivityStackBubble({super.key, required this.messages});

  final List<ChatMessage> messages;

  @override
  State<ActivityStackBubble> createState() => _ActivityStackBubbleState();
}

class _ActivityStackBubbleState extends State<ActivityStackBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    final active = messages.any((message) => !message.complete);
    final summary = _activitySummary(messages, active: active);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          key: const ValueKey('activity-card'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const ValueKey('activity-stack-toggle'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      active
                          ? Icons.more_horiz_rounded
                          : Icons.check_circle_rounded,
                      color: active ? CodexColors.greenSoft : CodexColors.muted,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        summary,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: CodexColors.muted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: AppMotion.quick,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.lg,
                        top: AppSpacing.xs,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: CodexColors.text.withValues(
                                alpha: AppOpacity.hairline,
                              ),
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.md),
                          child: Column(
                            children: [
                              for (final message in messages)
                                _ActivityStackRow(message: message),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

String _activitySummary(List<ChatMessage> messages, {required bool active}) {
  if (messages.isEmpty) return active ? 'Running action...' : 'Action complete';
  final commandMessages = messages.where(_isCommandActivity).toList();
  if (commandMessages.length == messages.length) {
    if (messages.length == 1) {
      final command = _commandTarget(messages.first);
      if (active) return 'Running: ${command ?? 'command'}...';
      return command == null ? 'Ran command' : 'Ran: $command';
    }
    return active
        ? 'Running ${messages.length} commands...'
        : 'Ran ${messages.length} commands';
  }
  if (active) {
    return 'Running ${messages.length} ${messages.length == 1 ? 'action' : 'actions'}';
  }
  if (messages.length == 1) return _singleActivitySummary(messages.first);
  final labels = <String>[];
  for (final message in messages) {
    final label = _singleActivitySummary(message);
    if (!labels.contains(label)) labels.add(label);
  }
  final joined = labels.take(3).join(', ');
  final extra = labels.length > 3 ? ' +${labels.length - 3}' : '';
  return '$joined$extra';
}

String _singleActivitySummary(ChatMessage message) {
  final title = message.title ?? 'Action';
  final lower = title.toLowerCase();
  if (lower.contains('reading')) {
    final target = _activityTarget(message);
    return target == null ? 'Read file' : 'Read $target';
  }
  if (lower.contains('skill')) {
    final target = _skillTarget(message);
    return target == null ? 'Using skill' : 'Using skill: $target';
  }
  if (lower.contains('editing')) return 'Edited files';
  if (_isCommandActivity(message)) {
    final command = _commandTarget(message);
    return command == null ? 'Ran command' : 'Ran: $command';
  }
  return '$title completed';
}

bool _isCommandActivity(ChatMessage message) {
  final title = message.title?.toLowerCase() ?? '';
  return title.contains('command') ||
      title.contains('terminal') ||
      title.contains('shell');
}

String? _commandTarget(ChatMessage message) {
  for (final rawLine in message.text.split(RegExp(r'\r?\n'))) {
    var line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.toLowerCase().startsWith('command:')) {
      line = line.substring('command:'.length).trim();
    }
    if (line.isEmpty) continue;
    return _compactCommandLine(line);
  }
  return null;
}

String _compactCommandLine(String line) {
  const maxLength = 44;
  if (line.length <= maxLength) return line;
  return '${line.substring(0, maxLength - 1).trimRight()}…';
}

String? _activityTarget(ChatMessage message) {
  final text = message.text.trim();
  final explicit = RegExp(r"Reading file:\s*([^\n]+)").firstMatch(text);
  final raw = explicit?.group(1) ?? (text.contains('\n') ? null : text);
  if (raw == null || raw.trim().isEmpty) return null;
  final normalized = raw.trim().replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? null : parts.last;
}

String? _skillTarget(ChatMessage message) {
  final explicit = RegExp(r"Using skill:\s*([^\n]+)").firstMatch(message.text);
  final name = explicit?.group(1)?.trim();
  return name == null || name.isEmpty ? null : name;
}

class _ActivityStackRow extends StatelessWidget {
  const _ActivityStackRow({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_activityIconFor(message), color: CodexColors.muted, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.title ?? 'Action',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (message.text.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message.text.trim(),
                    style: const TextStyle(
                      color: CodexColors.dim,
                      fontFamily: 'monospace',
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingLine extends StatefulWidget {
  const _ThinkingLine();

  @override
  State<_ThinkingLine> createState() => _ThinkingLineState();
}

class _ThinkingLineState extends State<_ThinkingLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.pulse);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
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
      child: Opacity(
        opacity: 0.72,
        child: Row(
          key: const ValueKey('thinking-inline-row'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _ThinkingWaveText(
              key: const ValueKey('thinking-wave-text'),
              text: 'Thinking',
              animation: _controller,
            ),
            const SizedBox(width: AppSpacing.sm),
            _ThinkingDots(animation: _controller),
          ],
        ),
      ),
    );
  }
}

class _ThinkingWaveText extends StatelessWidget {
  const _ThinkingWaveText({
    super.key,
    required this.text,
    required this.animation,
  });

  final String text;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      return Text(
        text,
        style: const TextStyle(
          color: CodexColors.muted,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final letters = text.split('');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < letters.length; index++)
              Transform.translate(
                offset: Offset(
                  0,
                  math.sin(
                        ((animation.value + index * 0.055) % 1.0) * math.pi * 2,
                      ) *
                      0.8,
                ),
                child: Opacity(
                  opacity:
                      (0.52 +
                              (0.28 *
                                  math
                                      .sin(
                                        ((animation.value + index * 0.055) %
                                                1.0) *
                                            math.pi,
                                      )
                                      .clamp(0.0, 1.0)))
                          .toDouble(),
                  child: Text(
                    letters[index],
                    style: const TextStyle(
                      color: CodexColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

IconData _activityIconFor(ChatMessage message) {
  final haystack = '${message.title ?? ''} ${message.text}'.toLowerCase();
  if (haystack.contains('read') || haystack.contains('open')) {
    return Icons.folder_open_rounded;
  }
  if (haystack.contains('edit') ||
      haystack.contains('write') ||
      haystack.contains('patch') ||
      haystack.contains('create')) {
    return Icons.description_outlined;
  }
  if (haystack.contains('command') ||
      haystack.contains('exec') ||
      haystack.contains('shell')) {
    return Icons.terminal_rounded;
  }
  return Icons.settings_suggest_rounded;
}

class _ActivityCard extends StatefulWidget {
  const _ActivityCard({
    required this.text,
    required this.title,
    required this.icon,
    required this.active,
    required this.complete,
  });

  final String text;
  final String title;
  final IconData icon;
  final bool active;
  final bool complete;

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.pulse);
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
    final accent = Theme.of(context).colorScheme.secondary;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ActivityGlyph(
                icon: widget.icon,
                animation: _controller,
                active: widget.active,
                complete: widget.complete,
                accent: accent,
              ),
              const SizedBox(width: AppSpacing.md),
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
                          const SizedBox(width: AppSpacing.sm),
                          _ThinkingDots(animation: _controller),
                        ],
                      ],
                    ),
                    if (widget.text.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        widget.text.trim(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CodexColors.dim,
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
    required this.complete,
    required this.accent,
  });

  final IconData icon;
  final Animation<double> animation;
  final bool active;
  final bool complete;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final effectiveIcon = complete ? Icons.check_rounded : icon;
    final effectiveColor = active || complete ? accent : CodexColors.muted;
    final iconWidget = Icon(effectiveIcon, color: effectiveColor, size: 16);
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
      child: SizedBox.square(dimension: 24, child: Center(child: iconWidget)),
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
        final disableAnimations =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 3; index++) ...[
              _WaveDot(
                key: ValueKey('thinking-wave-dot-$index'),
                animationValue: animation.value,
                index: index,
                disableAnimations: disableAnimations,
              ),
              if (index < 2) const SizedBox(width: AppSpacing.xs),
            ],
          ],
        );
      },
    );
  }
}

class _WaveDot extends StatelessWidget {
  const _WaveDot({
    super.key,
    required this.animationValue,
    required this.index,
    required this.disableAnimations,
  });

  final double animationValue;
  final int index;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final phase = (animationValue + index * 0.18) % 1.0;
    final wave = disableAnimations ? 0.0 : math.sin(phase * math.pi);
    final waveAmount = wave.clamp(0.0, 1.0).toDouble();
    final opacity = disableAnimations ? 0.72 : 0.36 + (waveAmount * 0.64);
    return Transform.translate(
      offset: Offset(0, 3 * wave),
      child: Opacity(
        opacity: opacity.clamp(0.32, 1.0).toDouble(),
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: Color.lerp(CodexColors.dim, CodexColors.text, waveAmount),
            shape: BoxShape.circle,
            boxShadow: disableAnimations
                ? null
                : [
                    BoxShadow(
                      color: CodexColors.text.withValues(alpha: 0.08 * wave),
                      blurRadius: 6,
                      spreadRadius: 0.4,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

class _FileChangeCard extends StatefulWidget {
  const _FileChangeCard({required this.message});

  final ChatMessage message;

  @override
  State<_FileChangeCard> createState() => _FileChangeCardState();
}

class _FileChangeCardState extends State<_FileChangeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final files = _parseFileChanges(widget.message.text);
    final controller = Provider.of<AppController?>(context);
    if (files.isEmpty) {
      return _ActivityCard(
        text: widget.message.text.trim(),
        title: widget.message.title ?? 'File activity',
        icon: Icons.description_outlined,
        active: false,
        complete: false,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                key: const ValueKey('file-activity-toggle'),
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: codexMutedColor(context),
                            size: 19,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: files.length == 1
                                ? _CompactFileChangeLine(file: files.first)
                                : Text(
                                    _fileActivitySummary(files),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: codexMutedColor(context),
                                        ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: AppMotion.quick,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(
                          left: AppSpacing.lg,
                          top: AppSpacing.xs,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final file in files)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.xs,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _CompactFileChangeLine(file: file),
                                    const SizedBox(height: AppSpacing.xs),
                                    _FileRow(
                                      file: file,
                                      controller: controller,
                                    ),
                                    if (_imageDownloadFor(controller, file)
                                        case final image?)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: AppSpacing.sm,
                                        ),
                                        child: _ImageFilePreview(
                                          download: image,
                                        ),
                                      ),
                                    if (file.patchLines.isNotEmpty) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      _PatchPreview(lines: file.patchLines),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactFileChangeLine extends StatelessWidget {
  const _CompactFileChangeLine({required this.file});

  final _FileChange file;

  @override
  Widget build(BuildContext context) {
    final color = _fileChangeColor(context, file.status);
    return Row(
      children: [
        Icon(_fileChangeIcon(file.status), color: color, size: 14),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            '${_fileChangeVerb(file.status)}:${file.path}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: codexTextColor(context),
              fontFamily: 'monospace',
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.controller});

  final _FileChange file;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatusBadge(status: file.status),
        const SizedBox(width: AppSpacing.sm),
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
        IconButton(
          tooltip: 'Copy file path',
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          onPressed: () => _copyMessage(context, file.path),
          icon: const Icon(Icons.copy_rounded, color: CodexColors.muted),
        ),
        if (file.fileId != null)
          TextButton.icon(
            onPressed: controller == null
                ? null
                : () {
                    final offer = controller!.fileOffers
                        .where((offer) => offer.fileId == file.fileId)
                        .firstOrNull;
                    if (offer != null) {
                      controller!.requestFileDownload(offer);
                    }
                  },
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download'),
          ),
      ],
    );
  }
}

String _fileActivitySummary(List<_FileChange> files) {
  final editCount = files.where((file) => _isEditStatus(file.status)).length;
  final fileCount = files.length;
  if (editCount == fileCount) {
    return 'Edited $editCount ${editCount == 1 ? 'file' : 'files'}';
  }
  if (editCount == 0) {
    return 'Agent attached $fileCount ${fileCount == 1 ? 'file' : 'files'}';
  }
  return '$editCount edits · ${fileCount - editCount} files';
}

bool _isEditStatus(String status) {
  return status == 'added' ||
      status == 'modified' ||
      status == 'deleted' ||
      status == 'renamed';
}

String _fileChangeVerb(String status) {
  if (_isEditStatus(status)) return 'Edit';
  return switch (status) {
    'downloaded' => 'Saved',
    'requested' => 'File',
    'generated' => 'File',
    'attachment' => 'Attach',
    _ => 'File',
  };
}

IconData _fileChangeIcon(String status) {
  return switch (status) {
    'deleted' => Icons.remove_circle_outline_rounded,
    'renamed' => Icons.drive_file_rename_outline_rounded,
    'downloaded' => Icons.download_done_rounded,
    'requested' || 'generated' => Icons.insert_drive_file_outlined,
    _ => Icons.edit_document,
  };
}

Color _fileChangeColor(BuildContext context, String status) {
  return switch (status) {
    'deleted' => CodexColors.danger,
    'renamed' => CodexColors.blue,
    'requested' || 'generated' || 'downloaded' => codexMutedColor(context),
    _ => Theme.of(context).colorScheme.secondary,
  };
}

class _ImageFilePreview extends StatelessWidget {
  const _ImageFilePreview({required this.download});

  final DownloadedFileInfo download;

  @override
  Widget build(BuildContext context) {
    late final Uint8List bytes;
    try {
      bytes = base64Decode(download.dataBase64);
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (bytes.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 280),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CodexColors.ink2,
            border: Border.all(
              color: CodexColors.text.withValues(alpha: AppOpacity.hairline),
            ),
          ),
          child: Image.memory(
            bytes,
            key: ValueKey('image-preview-${download.fileId}'),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

DownloadedFileInfo? _imageDownloadFor(
  AppController? controller,
  _FileChange file,
) {
  final fileId = file.fileId;
  if (controller == null || fileId == null) return null;
  final download = controller.downloadedFiles
      .where((candidate) => candidate.fileId == fileId)
      .firstOrNull;
  if (download == null) return null;
  final offer = controller.fileOffers
      .where((candidate) => candidate.fileId == fileId)
      .firstOrNull;
  final mimeType = download.mimeType ?? offer?.mimeType;
  if (_isImageFile(file.path, mimeType) ||
      _isImageFile(download.name, download.mimeType)) {
    return download;
  }
  return null;
}

bool _isImageFile(String path, String? mimeType) {
  final lowerMime = mimeType?.toLowerCase();
  if (lowerMime?.startsWith('image/') == true) return true;
  final lowerPath = path.toLowerCase();
  return lowerPath.endsWith('.png') ||
      lowerPath.endsWith('.jpg') ||
      lowerPath.endsWith('.jpeg') ||
      lowerPath.endsWith('.webp') ||
      lowerPath.endsWith('.gif');
}

class _PatchPreview extends StatelessWidget {
  const _PatchPreview({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: CodexColors.ink2.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: CodexColors.text.withValues(alpha: AppOpacity.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines.take(16))
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _patchLineColor(line),
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.25,
              ),
            ),
          if (lines.length > 16)
            Text(
              '... ${lines.length - 16} more diff lines',
              style: const TextStyle(
                color: CodexColors.dim,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.25,
              ),
            ),
        ],
      ),
    );
  }
}

Color _patchLineColor(String line) {
  if (line.startsWith('+')) return CodexColors.greenSoft;
  if (line.startsWith('-')) return CodexColors.danger;
  if (line.startsWith('@@')) return CodexColors.blue;
  return CodexColors.muted;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'added' => CodexColors.greenSoft,
      'requested' => CodexColors.greenSoft,
      'deleted' => CodexColors.danger,
      'renamed' => CodexColors.blue,
      _ => CodexColors.amber,
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 64, maxWidth: 92),
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
  const _FileChange({
    required this.status,
    required this.path,
    this.patchLines = const [],
    this.fileId,
    this.sizeBytes,
  });

  final String status;
  final String path;
  final List<String> patchLines;
  final String? fileId;
  final int? sizeBytes;
}

List<_FileChange> _parseFileChanges(String text) {
  final files = <_FileChange>[];
  String? status;
  String? path;
  String? fileId;
  int? sizeBytes;
  final patch = <String>[];

  void flush() {
    final currentStatus = status;
    final currentPath = path;
    if (currentStatus == null || currentPath == null) return;
    files.add(
      _FileChange(
        status: currentStatus,
        path: currentPath,
        patchLines: List<String>.from(patch),
        fileId: fileId,
        sizeBytes: sizeBytes,
      ),
    );
    fileId = null;
    sizeBytes = null;
    patch.clear();
  }

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;
    final match = RegExp(
      r"^(added|modified|deleted|renamed|generated|attachment|requested|downloaded)\s+(.+)$",
    ).firstMatch(line.trim());
    if (match != null) {
      flush();
      status = match.group(1);
      path = match.group(2);
      continue;
    }
    if (status != null) {
      final trimmed = line.trim();
      if (trimmed.startsWith('fileId ')) {
        fileId = trimmed.substring('fileId '.length).trim();
        continue;
      }
      if (trimmed.startsWith('size ')) {
        sizeBytes = int.tryParse(trimmed.substring('size '.length).trim());
        continue;
      }
      patch.add(line);
    }
  }
  flush();
  return files;
}

class _ErrorBlock extends StatefulWidget {
  const _ErrorBlock({required this.text});

  final String text;

  @override
  State<_ErrorBlock> createState() => _ErrorBlockState();
}

class _ErrorBlockState extends State<_ErrorBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.text.trim().split(RegExp(r'\r?\n'));
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('error-compact-row'),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: CodexColors.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: CodexColors.danger.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: CodexColors.danger,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _expanded ? widget.text.trim() : lines.first,
                      maxLines: _expanded ? 8 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CodexColors.text,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: CodexColors.muted,
                    size: 20,
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
