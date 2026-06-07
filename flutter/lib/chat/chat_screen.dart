import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../sessions/session_sidebar.dart';
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

  @override
  void dispose() {
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
                child: Column(
                  children: [
                    _FloatingTopBar(controller: controller, showMenu: !wide),
                    Expanded(
                      child: _MessageList(scrollController: _scrollController),
                    ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (context) => ChatGptCircleButton(
                icon: Icons.menu_rounded,
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
                  session?.title ?? 'Codex',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  controller.statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CodexColors.dim,
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (controller.isOffline) ...[
            const SoftPill(
              label: 'Offline',
              color: CodexColors.amber,
              icon: Icons.cloud_off_rounded,
            ),
            const SizedBox(width: AppSpacing.sm),
          ] else if (controller.isRunning) ...[
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
                  controller.isRunning ? Icons.stop_rounded : Icons.edit_square,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: 'Session info',
                onPressed: () => _showSessionInfo(context, controller),
                icon: const Icon(Icons.more_vert_rounded, size: 21),
              ),
            ],
          ),
          if (session?.mode == RunMode.yolo) ...[
            const SizedBox(width: 8),
            const SoftPill(
              label: 'YOLO',
              color: CodexColors.danger,
              icon: Icons.bolt_rounded,
            ),
          ],
        ],
      ),
    );
  }

  void _showSessionInfo(BuildContext context, AppController controller) {
    final session = controller.activeSession;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CodexColors.panel,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session?.title ?? 'Codex session',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              controller.statusText,
              style: const TextStyle(color: CodexColors.muted, height: 1.35),
            ),
            const SizedBox(height: 12),
            if (session != null)
              Text(
                session.workdir,
                style: const TextStyle(
                  color: CodexColors.dim,
                  fontFamily: 'monospace',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final messages = controller.activeMessages;
    if (messages.isEmpty) {
      return const _EmptyChatHero();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          itemCount: messages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) =>
              MessageBubble(message: messages[index]),
        ),
      ),
    );
  }
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
    if (controller.commands.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        scrollDirection: Axis.horizontal,
        itemCount: controller.commands.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final command = controller.commands[index];
          final isYolo = command.commandId == 'mode.yolo';
          return ActionChip(
            avatar: Icon(
              isYolo ? Icons.bolt_rounded : Icons.auto_fix_high_rounded,
              size: 16,
              color: isYolo ? CodexColors.danger : CodexColors.muted,
            ),
            label: Text(command.title),
            tooltip: command.description,
            onPressed: controller.isRunning
                ? null
                : () => controller.runCommand(command),
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
          );
        },
      ),
    );
  }
}

class _PromptComposer extends StatelessWidget {
  const _PromptComposer({
    required this.controller,
    required this.textController,
  });

  final AppController controller;
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
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
            color: CodexColors.composer,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'New chat',
                  onPressed: controller.isConnected && !controller.isRunning
                      ? controller.createSession
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
                    enabled: controller.isConnected && !controller.isRunning,
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
                              final text = textController.text;
                              textController.clear();
                              controller.sendPrompt(text);
                            },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: CodexColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: CodexColors.green.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final scale =
                  0.72 +
                  (0.28 *
                      Curves.easeInOut.transform(
                        _controller.value < 0.5
                            ? _controller.value * 2
                            : (1 - _controller.value) * 2,
                      ));
              return Transform.scale(scale: scale, child: child);
            },
            child: const SizedBox.square(
              dimension: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: CodexColors.greenSoft,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            'Running',
            style: TextStyle(
              color: CodexColors.greenSoft,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
