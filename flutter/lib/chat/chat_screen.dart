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
        drawer: wide ? null : Drawer(width: MediaQuery.sizeOf(context).width * 0.92, child: SessionSidebar(onPicked: () => Navigator.maybePop(context))),
        body: SafeArea(
          child: Row(
            children: [
              if (wide) const SessionSidebar(),
              Expanded(
                child: Column(
                  children: [
                    _FloatingTopBar(controller: controller, showMenu: !wide),
                    Expanded(child: _MessageList(scrollController: _scrollController)),
                    _CommandRail(controller: controller),
                    _PromptComposer(controller: controller, textController: _promptController),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (context) => ChatGptCircleButton(icon: Icons.menu_rounded, onPressed: () => Scaffold.of(context).openDrawer()),
            ),
          if (!showMenu) const SizedBox(width: 4),
          const Spacer(),
          ChatGptActionPill(
            children: [
              IconButton(onPressed: controller.isRunning ? controller.cancelRun : controller.createSession, icon: Icon(controller.isRunning ? Icons.stop_rounded : Icons.edit_square, size: 25)),
              IconButton(onPressed: () => _showSessionInfo(context, controller), icon: const Icon(Icons.more_vert_rounded, size: 27)),
            ],
          ),
          if (session?.mode == RunMode.yolo) ...[
            const SizedBox(width: 8),
            const SoftPill(label: 'YOLO', color: CodexColors.danger, icon: Icons.bolt_rounded),
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
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session?.title ?? 'Codex session', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(controller.statusText, style: const TextStyle(color: CodexColors.muted, height: 1.35)),
            const SizedBox(height: 14),
            if (session != null) Text(session.workdir, style: const TextStyle(color: CodexColors.dim, fontFamily: 'monospace')),
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
        scrollController.animateTo(scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
      }
    });
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      itemCount: messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 24),
      itemBuilder: (context, index) => MessageBubble(message: messages[index]),
    );
  }
}

class _EmptyChatHero extends StatelessWidget {
  const _EmptyChatHero();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('What can I help with?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('Message Codex, switch sessions from the menu, or run a command chip below.', textAlign: TextAlign.center, style: TextStyle(color: CodexColors.muted, fontSize: 16, height: 1.35)),
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
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: controller.commands.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final command = controller.commands[index];
          final isYolo = command.commandId == 'mode.yolo';
          return ActionChip(
            avatar: Icon(isYolo ? Icons.bolt_rounded : Icons.auto_fix_high_rounded, size: 16, color: isYolo ? CodexColors.danger : CodexColors.muted),
            label: Text(command.title),
            tooltip: command.description,
            onPressed: controller.isRunning ? null : () => controller.runCommand(command),
            labelStyle: const TextStyle(color: CodexColors.text, fontWeight: FontWeight.w600),
            backgroundColor: CodexColors.panelHigh,
            side: const BorderSide(color: CodexColors.borderSoft),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          );
        },
      ),
    );
  }
}

class _PromptComposer extends StatelessWidget {
  const _PromptComposer({required this.controller, required this.textController});

  final AppController controller;
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        radius: 999,
        color: CodexColors.composer,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(onPressed: controller.isConnected && !controller.isRunning ? controller.createSession : null, icon: const Icon(Icons.add_rounded, size: 30, color: CodexColors.text)),
            Expanded(
              child: TextField(
                controller: textController,
                minLines: 1,
                maxLines: 5,
                enabled: controller.isConnected && !controller.isRunning,
                cursorColor: CodexColors.text,
                style: const TextStyle(fontSize: 17, color: CodexColors.text),
                decoration: const InputDecoration(
                  hintText: 'Message Codex',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                textInputAction: TextInputAction.newline,
              ),
            ),
            IconButton(onPressed: null, icon: Icon(Icons.mic_none_rounded, size: 28, color: controller.isConnected ? CodexColors.text : CodexColors.dim)),
            const SizedBox(width: 4),
            SizedBox.square(
              dimension: 48,
              child: Material(
                color: CodexColors.text,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  color: CodexColors.ink,
                  icon: Icon(controller.isRunning ? Icons.stop_rounded : Icons.arrow_upward_rounded),
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
    );
  }
}
