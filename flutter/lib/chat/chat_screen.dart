import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../commands/command_center_screen.dart';
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
                          _NoticeBanner(controller: controller),
                          _SessionPlanBar(plan: controller.activePlan),
                          _ApprovalQueueBar(controller: controller),
                          _ErrorStatusBar(controller: controller),
                          _BottomConnectionChip(controller: controller),
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
                  tooltip: 'Commands',
                  onPressed: () => _showCommands(context),
                  icon: const Icon(Icons.terminal_rounded, size: 21),
                ),
                IconButton(
                  tooltip: 'Settings',
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

  void _showCommands(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CommandCenterScreen()),
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

class _BottomConnectionChip extends StatelessWidget {
  const _BottomConnectionChip({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.hostInfo == null && !controller.isOffline) {
      return const SizedBox.shrink();
    }
    final connection = _connectionLabel(controller);
    final info = controller.hostInfo;
    final detail = controller.isOffline
        ? 'tap to reconnect'
        : info?.connectionMode == 'tunnel'
        ? (info?.tunnelProvider ?? 'tunnel')
        : 'local bridge';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        0,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              key: const ValueKey('bottom-connection-chip'),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: controller.isOffline ? controller.reconnect : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: CodexColors.panel.withValues(alpha: 0.44),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: connection.color.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(connection.icon, size: 13, color: connection.color),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      connection.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: CodexColors.text,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: CodexColors.dim,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final notice = controller.latestNotice;
    if (notice == null) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: GlassCard(
            key: const ValueKey('chat-notice-banner'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            radius: AppRadius.lg,
            color: CodexColors.panelHigh.withValues(alpha: 0.88),
            blur: 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notifications_none_rounded, color: accent, size: 17),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        notice.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        notice.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CodexColors.muted,
                          height: 1.28,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss notification',
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  onPressed: controller.clearLatestNotice,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: CodexColors.muted,
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

class _SessionPlanBar extends StatefulWidget {
  const _SessionPlanBar({required this.plan});

  final CodexPlanInfo? plan;

  @override
  State<_SessionPlanBar> createState() => _SessionPlanBarState();
}

class _SessionPlanBarState extends State<_SessionPlanBar>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _SessionPlanBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan?.text != widget.plan?.text) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    if (plan == null) return const SizedBox.shrink();
    final lines = plan.text
        .trim()
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return const SizedBox.shrink();
    final summary = lines.first;
    final details = lines.skip(1).join('\n');
    final accent = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('session-plan-bar'),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => setState(() => _expanded = !_expanded),
              child: AnimatedContainer(
                duration: AppMotion.quick,
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: CodexColors.panel.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: CodexColors.ink.withValues(alpha: 0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.checklist_rounded, size: 16, color: accent),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          plan.title,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: CodexColors.muted),
                          ),
                        ),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: AppMotion.quick,
                          curve: Curves.easeOutCubic,
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: CodexColors.muted,
                          ),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: AppMotion.quick,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _expanded && details.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.sm,
                              ),
                              child: Text(
                                details,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: CodexColors.muted,
                                      height: 1.35,
                                    ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovalQueueBar extends StatelessWidget {
  const _ApprovalQueueBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final approvals = controller.pendingApprovals;
    if (approvals.isEmpty) return const SizedBox.shrink();
    final approval = ApprovalRequestInfo.fromText(
      approvals.last.text,
      fallbackTitle: approvals.last.title,
    );
    final accent = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Container(
            key: const ValueKey('approval-queue-bar'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: CodexColors.panelHigh.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: accent.withValues(alpha: 0.24)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, color: accent, size: 17),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        approvals.length == 1
                            ? approval.title
                            : '${approvals.length} approvals pending',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      if (approval.body.trim().isNotEmpty)
                        Text(
                          approval.body.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: CodexColors.muted),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('approval-queue-reject'),
                  onPressed: approval.approvalId.isEmpty
                      ? null
                      : () => controller.decideApproval(
                          approval.approvalId,
                          'reject',
                        ),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(
                  key: const ValueKey('approval-queue-approve'),
                  onPressed: approval.approvalId.isEmpty
                      ? null
                      : () => controller.decideApproval(
                          approval.approvalId,
                          'approve',
                        ),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorStatusBar extends StatefulWidget {
  const _ErrorStatusBar({required this.controller});

  final AppController controller;

  @override
  State<_ErrorStatusBar> createState() => _ErrorStatusBarState();
}

class _ErrorStatusBarState extends State<_ErrorStatusBar> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ErrorStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.latestErrorText !=
        widget.controller.latestErrorText) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.latestErrorText?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final lines = text.split(RegExp(r'\r?\n'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('chat-error-status-bar'),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: CodexColors.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: CodexColors.danger.withValues(alpha: 0.26),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: CodexColors.danger,
                      size: 17,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _expanded ? text : lines.first,
                        maxLines: _expanded ? 6 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CodexColors.text,
                          height: 1.35,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss error',
                      visualDensity: VisualDensity.compact,
                      iconSize: 17,
                      onPressed: widget.controller.clearLatestError,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: CodexColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
              .toList(growable: false);
    final goalSubcommands = _goalSubcommandsFor(textController.text);
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
                if (goalSubcommands.isNotEmpty && controller.isConnected) ...[
                  _SlashSubcommandSuggestions(
                    subcommands: goalSubcommands,
                    onSelected: _insertGoalSubcommand,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ] else if (slashQuery != null && controller.isConnected) ...[
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
                        enabled: controller.isConnected,
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
                          tooltip: 'Send',
                          color: CodexColors.ink,
                          iconSize: 18,
                          icon: const Icon(Icons.arrow_upward_rounded),
                          onPressed: controller.isConnected
                              ? () => _submitPrompt(controller)
                              : null,
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
    if (mention == null || !widget.controller.isConnected) {
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

  void _insertGoalSubcommand(_GoalSubcommand subcommand) {
    final text = '${subcommand.command} ';
    widget.textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
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
        _openCommandCenter(CommandCenterSection.sessions);
        break;
      case 'codex.model':
        _openSettings(SettingsSection.model);
        break;
      case 'codex.workspace':
        widget.controller.runCommand(command);
        _openCommandCenter(CommandCenterSection.workspace);
        break;
      case 'codex.skills':
        widget.controller.runCommand(command);
        _openCommandCenter(CommandCenterSection.skills);
        break;
      case 'codex.files':
        widget.controller.runCommand(command);
        _openCommandCenter(CommandCenterSection.files);
        break;
      case 'codex.history':
        widget.controller.runCommand(command);
        _openCommandCenter(CommandCenterSection.sessions);
        break;
      case 'codex.tunnel':
        widget.controller.runCommand(command);
        _openSettings(SettingsSection.connection);
        break;
      case 'codex.approvals':
        widget.controller.runCommand(command);
        _openCommandCenter(CommandCenterSection.approvals);
        break;
      case 'codex.review':
        widget.controller.runCommand(command);
        _openCommandCenter(CommandCenterSection.review);
        break;
      case 'codex.doctor':
        widget.controller.runCommand(command);
        _openCommandCenter(CommandCenterSection.diagnostics);
        break;
      default:
        widget.controller.runCommand(command);
    }
    setState(() {});
  }

  void _openSettings(SettingsSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(initialSection: section),
      ),
    );
  }

  void _openCommandCenter(CommandCenterSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommandCenterScreen(initialSection: section),
      ),
    );
  }

  void _submitPrompt(AppController controller) {
    final text = widget.textController.text.trim();
    final attachments = List<PromptAttachmentInfo>.from(_attachments);
    widget.textController.clear();
    widget.controller.clearFileSuggestions();
    setState(() => _attachments.clear());
    controller.sendPrompt(
      text.isEmpty && attachments.isNotEmpty
          ? 'Please inspect the uploaded attachments.'
          : text,
      attachments: attachments,
    );
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

class _GoalSubcommand {
  const _GoalSubcommand({required this.command, required this.description});

  final String command;
  final String description;
}

const _goalSubcommandCatalog = <_GoalSubcommand>[
  _GoalSubcommand(
    command: '/goal',
    description: 'Inspect the current session goal',
  ),
  _GoalSubcommand(
    command: '/goal clear',
    description: 'Remove the active goal',
  ),
  _GoalSubcommand(
    command: '/goal active',
    description: 'Resume the active goal',
  ),
  _GoalSubcommand(
    command: '/goal complete',
    description: 'Mark the goal as complete',
  ),
  _GoalSubcommand(
    command: '/goal blocked',
    description: 'Mark the goal as blocked',
  ),
  _GoalSubcommand(
    command: '/goal paused',
    description: 'Pause goal progress tracking',
  ),
];

List<_GoalSubcommand> _goalSubcommandsFor(String text) {
  final trimmedLeft = text.trimLeft();
  final match = RegExp(
    r'^/goal(?:\s+([^\s]*))?$',
    caseSensitive: false,
  ).firstMatch(trimmedLeft);
  if (match == null) return const [];
  if (!trimmedLeft.contains(RegExp(r'\s'))) return const [];
  final query = (match.group(1) ?? '').toLowerCase();
  return _goalSubcommandCatalog
      .where((subcommand) {
        final tail = subcommand.command.split(' ').skip(1).join(' ');
        return query.isEmpty ||
            tail.toLowerCase().startsWith(query) ||
            subcommand.description.toLowerCase().contains(query);
      })
      .take(6)
      .toList(growable: false);
}

class _SlashSubcommandSuggestions extends StatelessWidget {
  const _SlashSubcommandSuggestions({
    required this.subcommands,
    required this.onSelected,
  });

  final List<_GoalSubcommand> subcommands;
  final ValueChanged<_GoalSubcommand> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('slash-subcommand-suggestions'),
      constraints: const BoxConstraints(maxHeight: 232),
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
        itemCount: subcommands.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: CodexColors.text.withValues(alpha: AppOpacity.hairline),
        ),
        itemBuilder: (context, index) {
          final subcommand = subcommands[index];
          return _SlashCommandRow(
            key: ValueKey('slash-subcommand-${subcommand.command}'),
            icon: Icons.subdirectory_arrow_right_rounded,
            title: subcommand.command,
            description: subcommand.description,
            onTap: () => onSelected(subcommand),
          );
        },
      ),
    );
  }
}

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
          for (final command in commands)
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
