import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../sessions/session_sidebar.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';
import 'message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _promptController = TextEditingController();
  final _scrollController = ScrollController();
  AppController? _controller;
  bool _wasRunning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = context.read<AppController>();
    if (_controller == nextController) return;
    _controller?.removeListener(_handleControllerChanged);
    _controller = nextController;
    _wasRunning = nextController.isRunning;
    nextController.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (_wasRunning && !controller.isRunning && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.statusText),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
    _wasRunning = controller.isRunning;
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChanged);
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return AnimatedChatGptBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: wide
            ? null
            : Drawer(
                width: MediaQuery.sizeOf(context).width * 0.86,
                child: SessionSidebar(
                  onPicked: () => Navigator.maybePop(context),
                ),
              ),
        body: SafeArea(
          child: Row(
            children: [
              if (wide) const SessionSidebar(),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _MessageList(scrollController: _scrollController),
                    ),
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _EdgeFade(top: true),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _EdgeFade(top: false),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _FloatingTopBar(
                        controller: controller,
                        showMenu: !wide,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CommandRail(controller: controller),
                          _PromptComposer(
                            controller: controller,
                            textController: _promptController,
                          ),
                        ],
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

class _FloatingTopBar extends StatelessWidget {
  const _FloatingTopBar({required this.controller, required this.showMenu});

  final AppController controller;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final session = controller.activeSession;
    final connection = _connectionLabel(controller);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        radius: AppRadius.xl,
        color: CodexColors.panel.withValues(alpha: 0.56),
        blur: 24,
        child: Row(
          children: [
            if (showMenu)
              Builder(
                builder: (context) => ChatGptCircleButton(
                  icon: Icons.menu_rounded,
                  size: 38,
                  background: CodexColors.composer,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            if (showMenu) const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    session?.title ?? 'Codex Link',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (session?.workdirName.isNotEmpty == true)
                        session!.workdirName,
                      controller.statusText,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CodexColors.dim,
                      fontSize: 12,
                      height: 1.1,
                    ),
                  ),
                  if (session?.goal != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _ActiveGoalChip(goal: session!.goal!),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: controller.isOffline ? controller.reconnect : null,
              child: SoftPill(
                label: connection.label,
                color: connection.color,
                icon: connection.icon,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (controller.isRunning) ...[
              const _RunningIndicator(),
              const SizedBox(width: AppSpacing.sm),
            ],
            ChatGptActionPill(
              children: [
                IconButton(
                  tooltip: controller.isRunning ? 'Stop' : 'New chat',
                  onPressed: controller.isRunning
                      ? controller.cancelRun
                      : controller.createSession,
                  icon: Icon(
                    controller.isRunning
                        ? Icons.stop_rounded
                        : Icons.edit_square,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: 'Session info',
                  onPressed: () => _showSessionInfo(context, controller),
                  icon: const Icon(Icons.settings_rounded, size: 21),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSessionInfo(BuildContext context, AppController controller) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }
}

class _ActiveGoalChip extends StatelessWidget {
  const _ActiveGoalChip({required this.goal});

  final CodexGoalInfo goal;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final objective = goal.objective.trim().isEmpty
        ? 'No objective set'
        : goal.objective.trim();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('active-goal-chip'),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_rounded, color: accent, size: 14),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                'Goal · $objective',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CodexColors.text,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionBadge {
  const _ConnectionBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

_ConnectionBadge _connectionLabel(AppController controller) {
  if (controller.isOffline) {
    return const _ConnectionBadge(
      label: 'Offline',
      icon: Icons.cloud_off_rounded,
      color: CodexColors.amber,
    );
  }
  final info = controller.hostInfo;
  if (info?.connectionMode == 'tunnel') {
    return const _ConnectionBadge(
      label: 'Tunnel',
      icon: Icons.cloud_done_rounded,
      color: CodexColors.greenSoft,
    );
  }
  return const _ConnectionBadge(
    label: 'Local',
    icon: Icons.lan_rounded,
    color: CodexColors.muted,
  );
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: top ? 118 : 176,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                CodexColors.ink.withValues(alpha: 0.82),
                CodexColors.ink.withValues(alpha: 0.28),
                CodexColors.ink.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageList extends StatefulWidget {
  const _MessageList({required this.scrollController});

  final ScrollController scrollController;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  bool _showJumpToBottom = false;
  bool _autoScrollQueued = false;
  bool _queuedAutoScrollAnimated = false;
  int _lastItemCount = 0;
  String _lastTimelineSignature = '';

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController == widget.scrollController) return;
    oldWidget.scrollController.removeListener(_handleScroll);
    widget.scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final shouldShow = position.maxScrollExtent - position.pixels > 240;
    if (shouldShow != _showJumpToBottom && mounted) {
      setState(() => _showJumpToBottom = shouldShow);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!widget.scrollController.hasClients) return;
    final target = widget.scrollController.position.maxScrollExtent;
    if (!animated) {
      widget.scrollController.jumpTo(target);
      return;
    }
    widget.scrollController.animateTo(
      target,
      duration: AppMotion.scroll,
      curve: Curves.easeInOutCubic,
    );
  }

  void _queueAutoScroll({required bool animated}) {
    _queuedAutoScrollAnimated = _queuedAutoScrollAnimated || animated;
    if (_autoScrollQueued) return;
    _autoScrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shouldAnimate = _queuedAutoScrollAnimated;
      _autoScrollQueued = false;
      _queuedAutoScrollAnimated = false;
      if (!mounted ||
          _showJumpToBottom ||
          !widget.scrollController.hasClients) {
        return;
      }
      _scrollToBottom(animated: shouldAnimate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final messages = controller.activeMessages;
    if (messages.isEmpty && !controller.isRunning) {
      return const _EmptyChatHero();
    }
    final items = _timelineItems(
      messages,
      isRunning: controller.isRunning,
      runId: controller.activeRunId,
    );
    final timelineSignature = _timelineSignature(items);
    final timelineChanged = timelineSignature != _lastTimelineSignature;
    final itemCountChanged = items.length != _lastItemCount;
    final shouldAutoScroll = timelineChanged && !_showJumpToBottom;
    _lastItemCount = items.length;
    _lastTimelineSignature = timelineSignature;
    if (shouldAutoScroll) {
      _queueAutoScroll(animated: itemCountChanged);
    }
    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView.separated(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(16, 112, 16, 176),
              cacheExtent: 900,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final item = items[index];
                final shouldAnimateItem = index >= items.length - 6;
                return switch (item) {
                  _SingleTimelineItem(:final message) => MessageBubble(
                    key: ValueKey('message-${message.id}-${message.kind.name}'),
                    message: message,
                    animate: shouldAnimateItem,
                  ),
                  _ActivityTimelineItem(:final messages) => ActivityStackBubble(
                    key: ValueKey(
                      'activity-${messages.map((item) => item.id).join('-')}',
                    ),
                    messages: messages,
                  ),
                };
              },
            ),
          ),
        ),
        Positioned(
          right: AppSpacing.lg,
          bottom: 152,
          child: AnimatedScale(
            scale: _showJumpToBottom ? 1 : 0.82,
            duration: AppMotion.quick,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _showJumpToBottom ? 1 : 0,
              duration: AppMotion.quick,
              child: IgnorePointer(
                ignoring: !_showJumpToBottom,
                child: ChatGptCircleButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  size: 42,
                  background: CodexColors.panelHigh,
                  onPressed: _scrollToBottom,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

sealed class _TimelineItem {}

class _SingleTimelineItem extends _TimelineItem {
  _SingleTimelineItem(this.message);

  final ChatMessage message;
}

class _ActivityTimelineItem extends _TimelineItem {
  _ActivityTimelineItem(this.messages);

  final List<ChatMessage> messages;
}

List<_TimelineItem> _timelineItems(
  List<ChatMessage> messages, {
  bool isRunning = false,
  String? runId,
}) {
  final items = <_TimelineItem>[];
  final pendingActivity = <ChatMessage>[];
  var hasActiveLiveItem = false;

  void flushActivity() {
    if (pendingActivity.isNotEmpty) {
      items.add(_ActivityTimelineItem(List<ChatMessage>.from(pendingActivity)));
      pendingActivity.clear();
    }
  }

  for (final message in messages) {
    if (!message.complete &&
        (message.kind == AgentMessageKind.thinking ||
            message.kind == AgentMessageKind.executing ||
            message.kind == AgentMessageKind.reasoning ||
            message.kind == AgentMessageKind.response)) {
      hasActiveLiveItem = true;
    }
    if (message.kind == AgentMessageKind.thinking && message.complete) {
      continue;
    }
    if (message.kind == AgentMessageKind.executing) {
      pendingActivity.add(message);
      continue;
    }
    flushActivity();
    items.add(_SingleTimelineItem(message));
  }
  flushActivity();
  if (isRunning && !hasActiveLiveItem) {
    items.add(
      _SingleTimelineItem(
        ChatMessage(
          id: 'live-thinking-${runId ?? 'active'}',
          role: ChatRole.system,
          kind: AgentMessageKind.thinking,
          text: 'Thinking…',
          title: 'Thinking',
          runId: runId,
          createdAt: DateTime.now(),
          complete: false,
        ),
      ),
    );
  }
  return items;
}

String _timelineSignature(List<_TimelineItem> items) {
  return items
      .map(
        (item) => switch (item) {
          _SingleTimelineItem(:final message) =>
            '${message.id}:${message.kind.name}:${message.text.length}:${message.complete}',
          _ActivityTimelineItem(:final messages) =>
            messages
                .map(
                  (message) =>
                      '${message.id}:${message.text.length}:${message.complete}',
                )
                .join(','),
        },
      )
      .join('|');
}

class _EmptyChatHero extends StatelessWidget {
  const _EmptyChatHero();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'What can I help with?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Message Codex or pick a recent session.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CodexColors.muted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandRail extends StatelessWidget {
  const _CommandRail({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final commands = controller.commands
        .where((command) => command.category != 'mode')
        .toList();
    if (commands.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        scrollDirection: Axis.horizontal,
        itemCount: commands.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final command = commands[index];
          return ActionChip(
            avatar: Icon(
              Icons.auto_fix_high_rounded,
              size: 16,
              color: CodexColors.muted,
            ),
            label: Text(command.title),
            tooltip: command.description,
            labelStyle: const TextStyle(
              color: CodexColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            backgroundColor: CodexColors.panelHigh,
            side: const BorderSide(color: CodexColors.borderSoft),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            visualDensity: VisualDensity.compact,
            onPressed: controller.isRunning && command.commandId != 'codex.stop'
                ? null
                : () => _runRailCommand(context, controller, command),
          );
        },
      ),
    );
  }

  void _runRailCommand(
    BuildContext context,
    AppController controller,
    CodexCommandInfo command,
  ) {
    switch (command.commandId) {
      case 'codex.sessions':
      case 'codex.model':
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
        return;
      default:
        controller.runCommand(command);
    }
  }
}

class _PromptComposer extends StatefulWidget {
  const _PromptComposer({
    required this.controller,
    required this.textController,
  });

  final AppController controller;
  final TextEditingController textController;

  @override
  State<_PromptComposer> createState() => _PromptComposerState();
}

class _PromptComposerState extends State<_PromptComposer> {
  final List<PromptAttachmentInfo> _attachments = [];
  Timer? _fileMentionDebounce;

  @override
  void dispose() {
    _fileMentionDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final textController = widget.textController;
    final activeMention = _activeFileMention(textController.value);
    final fileSuggestions =
        activeMention == null ||
            controller.fileSuggestionQuery != activeMention.query
        ? const <WorkspaceFileInfo>[]
        : controller.fileSuggestions;
    final slashQuery = _slashCommandQuery(textController.text);
    final slashCommands = slashQuery == null
        ? const <CodexCommandInfo>[]
        : controller.commands
              .where(
                (command) =>
                    command.category != 'mode' &&
                    (command.commandId.toLowerCase().contains(slashQuery) ||
                        command.title.toLowerCase().contains(slashQuery) ||
                        command.description.toLowerCase().contains(slashQuery)),
              )
              .take(6)
              .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            radius: AppRadius.xl,
            color: CodexColors.composer.withValues(alpha: 0.72),
            blur: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (slashQuery != null && controller.isConnected) ...[
                  _SlashCommandSuggestions(
                    commands: slashCommands,
                    onSendFile: _insertSendCommand,
                    onCommand: _runSlashCommand,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                if (activeMention != null && fileSuggestions.isNotEmpty) ...[
                  _FileMentionSuggestions(
                    files: fileSuggestions,
                    onSelected: _insertFileMention,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                if (_attachments.isNotEmpty) ...[
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _attachments.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AppSpacing.xs),
                      itemBuilder: (context, index) {
                        final attachment = _attachments[index];
                        return InputChip(
                          avatar: Icon(
                            _isImageName(attachment.name)
                                ? Icons.image_rounded
                                : Icons.attach_file_rounded,
                            size: 16,
                          ),
                          label: Text(attachment.name),
                          onDeleted: () =>
                              setState(() => _attachments.removeAt(index)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: CodexColors.panelHigh,
                          side: const BorderSide(color: CodexColors.borderSoft),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Attach',
                      onPressed: controller.isConnected && !controller.isRunning
                          ? () => _showAttachmentPicker(context)
                          : null,
                      icon: const Icon(
                        Icons.add_rounded,
                        size: 22,
                        color: CodexColors.text,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: textController,
                        minLines: 1,
                        maxLines: 5,
                        enabled:
                            controller.isConnected && !controller.isRunning,
                        cursorColor: CodexColors.text,
                        style: const TextStyle(
                          color: CodexColors.text,
                          height: 1.35,
                        ),
                        decoration: InputDecoration(
                          hintText: controller.isOffline
                              ? 'Offline - cached chat'
                              : 'Message Codex',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                        ),
                        textInputAction: TextInputAction.newline,
                        onChanged: _handleTextChanged,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    SizedBox.square(
                      dimension: 38,
                      child: Material(
                        color: CodexColors.text,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          tooltip: controller.isRunning ? 'Stop' : 'Send',
                          color: CodexColors.ink,
                          iconSize: 18,
                          icon: Icon(
                            controller.isRunning
                                ? Icons.stop_rounded
                                : Icons.arrow_upward_rounded,
                          ),
                          onPressed: controller.isRunning
                              ? controller.cancelRun
                              : () {
                                  final text = textController.text.trim();
                                  final attachments =
                                      List<PromptAttachmentInfo>.from(
                                        _attachments,
                                      );
                                  textController.clear();
                                  widget.controller.clearFileSuggestions();
                                  setState(() => _attachments.clear());
                                  controller.sendPrompt(
                                    text.isEmpty && attachments.isNotEmpty
                                        ? 'Please inspect the uploaded attachments.'
                                        : text,
                                    attachments: attachments,
                                  );
                                },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleTextChanged(String value) {
    setState(() {});
    final mention = _activeFileMention(widget.textController.value);
    if (mention == null ||
        !widget.controller.isConnected ||
        widget.controller.isRunning) {
      _fileMentionDebounce?.cancel();
      widget.controller.clearFileSuggestions();
      return;
    }
    _fileMentionDebounce?.cancel();
    _fileMentionDebounce = Timer(const Duration(milliseconds: 130), () {
      if (!mounted) return;
      widget.controller.searchWorkspaceFiles(mention.query);
    });
  }

  void _insertSendCommand() {
    widget.textController.value = const TextEditingValue(
      text: '/send ',
      selection: TextSelection.collapsed(offset: 6),
    );
    widget.controller.clearFileSuggestions();
    setState(() {});
  }

  void _runSlashCommand(CodexCommandInfo command) {
    widget.textController.clear();
    widget.controller.clearFileSuggestions();
    switch (command.commandId) {
      case 'codex.goal':
        widget.textController.value = const TextEditingValue(
          text: '/goal ',
          selection: TextSelection.collapsed(offset: 6),
        );
        break;
      case 'codex.sessions':
      case 'codex.model':
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
        break;
      default:
        widget.controller.runCommand(command);
    }
    setState(() {});
  }

  void _insertFileMention(WorkspaceFileInfo file) {
    final value = widget.textController.value;
    final mention = _activeFileMention(value);
    if (mention == null || file.path.trim().isEmpty) return;
    final insertion = '@${file.path} ';
    final text = value.text.replaceRange(mention.start, mention.end, insertion);
    final offset = mention.start + insertion.length;
    widget.textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
    widget.controller.clearFileSuggestions();
    setState(() {});
  }

  Future<void> _showAttachmentPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<_AttachmentPickMode>(
      context: context,
      backgroundColor: CodexColors.panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_rounded),
                title: const Text('Upload image'),
                subtitle: const Text('Attach a screenshot or visual reference'),
                onTap: () =>
                    Navigator.of(context).pop(_AttachmentPickMode.image),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_rounded),
                title: const Text('Upload file'),
                subtitle: const Text('Save a file into the active workspace'),
                onTap: () =>
                    Navigator.of(context).pop(_AttachmentPickMode.file),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    await _pickFiles(picked);
  }

  Future<void> _pickFiles(_AttachmentPickMode mode) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: mode == _AttachmentPickMode.image ? FileType.image : FileType.any,
    );
    if (!mounted || result == null) return;
    final selected = <PromptAttachmentInfo>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      if (bytes.length > 6 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${file.name} is too large to upload.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        continue;
      }
      selected.add(
        PromptAttachmentInfo(
          name: file.name,
          mimeType: _mimeTypeForName(file.name),
          dataBase64: base64Encode(bytes),
        ),
      );
    }
    if (selected.isEmpty) return;
    setState(() {
      _attachments.addAll(selected);
      if (_attachments.length > 4) {
        _attachments.removeRange(4, _attachments.length);
      }
    });
  }
}

enum _AttachmentPickMode { image, file }

class _SlashCommandSuggestions extends StatelessWidget {
  const _SlashCommandSuggestions({
    required this.commands,
    required this.onSendFile,
    required this.onCommand,
  });

  final List<CodexCommandInfo> commands;
  final VoidCallback onSendFile;
  final ValueChanged<CodexCommandInfo> onCommand;

  @override
  Widget build(BuildContext context) {
    final visibleCommands = commands.take(5).toList(growable: false);
    return Container(
      key: const ValueKey('slash-command-suggestions'),
      constraints: const BoxConstraints(maxHeight: 232),
      decoration: BoxDecoration(
        color: CodexColors.ink2.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: CodexColors.text.withValues(alpha: AppOpacity.hairline),
        ),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        children: [
          _SlashCommandRow(
            key: const ValueKey('slash-command-/send'),
            icon: Icons.file_download_outlined,
            title: '/send',
            description: 'Offer a workspace file to this phone',
            onTap: onSendFile,
          ),
          for (final command in visibleCommands)
            _SlashCommandRow(
              key: ValueKey('slash-command-${command.commandId}'),
              icon: Icons.keyboard_command_key_rounded,
              title: _slashCommandName(command),
              description: command.description,
              onTap: () => onCommand(command),
            ),
        ],
      ),
    );
  }
}

String _slashCommandName(CodexCommandInfo command) {
  final tail = command.commandId.split('.').last.trim();
  return '/${tail.isEmpty ? command.title.toLowerCase() : tail.toLowerCase()}';
}

class _SlashCommandRow extends StatelessWidget {
  const _SlashCommandRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: CodexColors.muted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CodexColors.dim,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileMentionSuggestions extends StatelessWidget {
  const _FileMentionSuggestions({
    required this.files,
    required this.onSelected,
  });

  final List<WorkspaceFileInfo> files;
  final ValueChanged<WorkspaceFileInfo> onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      key: const ValueKey('file-mention-suggestions'),
      constraints: const BoxConstraints(maxHeight: 216),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CodexColors.ink2.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: CodexColors.text.withValues(alpha: AppOpacity.hairline),
          ),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          itemCount: files.length > 8 ? 8 : files.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            color: CodexColors.text.withValues(alpha: AppOpacity.hairline),
          ),
          itemBuilder: (context, index) {
            final file = files[index];
            return InkWell(
              key: ValueKey('file-mention-${file.path}'),
              onTap: () => onSelected(file),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      _isImageName(file.name)
                          ? Icons.image_rounded
                          : Icons.insert_drive_file_outlined,
                      size: 17,
                      color: CodexColors.muted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            file.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CodexColors.dim,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (file.sizeBytes case final size?)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: Text(
                          _formatBytes(size),
                          style: const TextStyle(
                            color: CodexColors.dim,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FileMention {
  const _FileMention({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

_FileMention? _activeFileMention(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  final cursor = selection.isValid ? selection.baseOffset : text.length;
  if (cursor < 0 || cursor > text.length) return null;
  final beforeCursor = text.substring(0, cursor);
  final atIndex = beforeCursor.lastIndexOf('@');
  if (atIndex < 0) return null;
  if (atIndex > 0) {
    final previous = beforeCursor[atIndex - 1];
    if (!RegExp(r'[\s([{]').hasMatch(previous)) return null;
  }
  final query = beforeCursor.substring(atIndex + 1);
  if (query.contains(RegExp(r'\s'))) return null;
  return _FileMention(start: atIndex, end: cursor, query: query);
}

String? _slashCommandQuery(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('/')) return null;
  if (trimmed.contains(RegExp(r'\s'))) return null;
  return trimmed.substring(1).toLowerCase();
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)}KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)}MB';
}

bool _isImageName(String name) =>
    _mimeTypeForName(name)?.startsWith('image/') == true;

String? _mimeTypeForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.txt')) return 'text/plain';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.md')) return 'text/markdown';
  return null;
}

class _RunningIndicator extends StatefulWidget {
  const _RunningIndicator();

  @override
  State<_RunningIndicator> createState() => _RunningIndicatorState();
}

class _RunningIndicatorState extends State<_RunningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: CodexColors.text.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: CodexColors.text.withValues(alpha: 0.12)),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final opacity =
              0.58 +
              (0.42 *
                  Curves.easeInOut.transform(
                    _controller.value < 0.5
                        ? _controller.value * 2
                        : (1 - _controller.value) * 2,
                  ));
          return Opacity(opacity: opacity, child: child);
        },
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: CodexColors.greenSoft,
            shape: BoxShape.circle,
          ),
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}
