import 'dart:convert';

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
          color: CodexColors.bubble,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: CodexColors.text.withValues(alpha: AppOpacity.hairline),
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
                  color: CodexColors.text,
                  height: 1.34,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _CopyMessageButton(text: message.text),
          ],
        ),
      ),
    );
  }
}

class _CopyMessageButton extends StatelessWidget {
  const _CopyMessageButton({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Copy message',
      visualDensity: VisualDensity.compact,
      iconSize: 17,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      onPressed: text.trim().isEmpty ? null : () => _copyMessage(context, text),
      icon: const Icon(Icons.copy_rounded, color: CodexColors.muted),
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
                color: CodexColors.greenSoft,
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
                    color: CodexColors.text,
                    height: 1.5,
                  ),
                  child: MarkdownCodeRenderer(text: message.text),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _CopyMessageButton(text: message.text),
          ],
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
    final summary = active
        ? 'Running ${messages.length} ${messages.length == 1 ? 'action' : 'actions'}'
        : messages.length == 1
        ? _singleSummary(messages.first)
        : _stackSummary(messages);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          key: const ValueKey('activity-card'),
          decoration: BoxDecoration(
            color: CodexColors.panelHigh.withValues(alpha: AppOpacity.panel),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: active
                  ? CodexColors.greenSoft.withValues(alpha: AppOpacity.glow)
                  : CodexColors.text.withValues(alpha: AppOpacity.hairline),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                key: const ValueKey('activity-stack-toggle'),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(
                        active
                            ? Icons.more_horiz_rounded
                            : Icons.check_circle_rounded,
                        color: active
                            ? CodexColors.greenSoft
                            : CodexColors.muted,
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
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Column(
                    children: [
                      for (final message in messages)
                        _ActivityStackRow(message: message),
                    ],
                  ),
                ),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: AppMotion.quick,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _singleSummary(ChatMessage message) {
    final title = message.title ?? 'Action';
    final lower = title.toLowerCase();
    if (lower.contains('reading')) {
      final target = _activityTarget(message);
      return target == null ? 'Read file' : 'Read $target';
    }
    if (lower.contains('editing')) return 'Edited files';
    if (lower.contains('command')) return 'Ran command';
    return '$title completed';
  }

  String _stackSummary(List<ChatMessage> messages) {
    final labels = <String>[];
    for (final message in messages) {
      final label = _singleSummary(message);
      if (!labels.contains(label)) labels.add(label);
    }
    final joined = labels.take(3).join(', ');
    final extra = labels.length > 3 ? ' +${labels.length - 3}' : '';
    return '$joined$extra';
  }
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

class _ActivityStackRow extends StatelessWidget {
  const _ActivityStackRow({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: CodexColors.ink2.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: CodexColors.text.withValues(alpha: AppOpacity.hairline),
        ),
      ),
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
                      color: CodexColors.muted,
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
    _controller = AnimationController(vsync: this, duration: AppMotion.pulse)
      ..repeat();
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
            const Text(
              'Thinking',
              style: TextStyle(
                color: CodexColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ThinkingDots(animation: _controller),
          ],
        ),
      ),
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
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: CodexColors.panelHigh.withValues(alpha: AppOpacity.panel),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: widget.active
                  ? CodexColors.greenSoft.withValues(alpha: AppOpacity.glow)
                  : CodexColors.text.withValues(alpha: AppOpacity.hairline),
            ),
            boxShadow: [
              BoxShadow(
                color: CodexColors.greenSoft.withValues(
                  alpha: widget.active ? 0.06 : 0,
                ),
                blurRadius: AppSpacing.xl,
                offset: const Offset(0, AppSpacing.sm),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ActivityGlyph(
                icon: widget.icon,
                animation: _controller,
                active: widget.active,
                complete: widget.complete,
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
                          color: CodexColors.muted,
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
  });

  final IconData icon;
  final Animation<double> animation;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final effectiveIcon = complete ? Icons.check_rounded : icon;
    final effectiveColor = active || complete
        ? CodexColors.greenSoft
        : CodexColors.muted;
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
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: CodexColors.composer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: effectiveColor.withValues(alpha: AppOpacity.border),
          ),
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
                margin: const EdgeInsets.only(right: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: index == activeDot
                      ? CodexColors.text
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
    final files = _parseFileChanges(message.text);
    final controller = Provider.of<AppController?>(context);
    if (files.isEmpty) {
      return _ActivityCard(
        text: message.text.trim(),
        title: message.title ?? 'File activity',
        icon: Icons.description_outlined,
        active: false,
        complete: false,
      );
    }
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
                  if (files.length > 1) ...[
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
                ],
              ),
              const SizedBox(height: 8),
              for (final file in files)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FileRow(file: file, controller: controller),
                      if (_imageDownloadFor(controller, file) case final image?)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: _ImageFilePreview(download: image),
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
        ),
      ),
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
