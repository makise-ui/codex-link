import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../app_server/app_server_actions_screen.dart';
import '../protocol/bridge_messages.dart';
import '../sessions/session_sidebar.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';
import 'file_browser_screen.dart';
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
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
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
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _UsageLimitLine(controller: controller),
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
                        showSidebarButton: !wide,
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
  const _FloatingTopBar({
    required this.controller,
    required this.showSidebarButton,
  });

  final AppController controller;
  final bool showSidebarButton;

  @override
  Widget build(BuildContext context) {
    final session = controller.activeSession;
    final subtitle = _topBarSubtitle(controller, session);
    final card = GlassCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      radius: AppRadius.xl,
      color: CodexColors.panel.withValues(alpha: 0.42),
      blur: 24,
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
          Row(
            children: [
              _ConnectionDot(offline: controller.isOffline),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CodexColors.dim,
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          if (session?.goal != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _ActiveGoalChip(goal: session!.goal!),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSidebarButton) ...[
            Builder(
              builder: (context) => ChatGptCircleButton(
                icon: Icons.menu_rounded,
                size: 40,
                background: CodexColors.composer.withValues(alpha: 0.82),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('top-session-card'),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                onTap: controller.isOffline ? controller.reconnect : null,
                child: card,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (controller.isRunning) ...[
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: _RunningIndicator(),
            ),
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
              Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: 'Actions',
                  onPressed: () => _showActionMenu(buttonContext, controller),
                  icon: const Icon(Icons.apps_rounded, size: 21),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    final color = offline
        ? CodexColors.amber
        : Theme.of(context).colorScheme.secondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const SizedBox.square(dimension: 7),
    );
  }
}

String _topBarSubtitle(AppController controller, CodexSessionInfo? session) {
  if (controller.isOffline) return 'Disconnected - tap to reconnect';
  final parts = <String>[];
  final workdir = session?.workdirName.trim() ?? '';
  if (workdir.isNotEmpty) parts.add(workdir);
  parts.add(_sessionModelLabel(controller, session));
  final effort = session?.reasoningEffort?.trim() ?? '';
  if (effort.isNotEmpty) parts.add('effort $effort');
  final serviceTier = _sessionServiceTierLabel(controller, session);
  if (serviceTier.isNotEmpty) parts.add(serviceTier);
  return parts.join(' / ');
}

String _sessionModelLabel(AppController controller, CodexSessionInfo? session) {
  final configured = session?.model?.trim() ?? '';
  if (configured.isEmpty) return 'default model';
  for (final model in controller.appModels) {
    if (model.id == configured || model.model == configured) {
      return model.displayName;
    }
  }
  return configured;
}

String _sessionServiceTierLabel(
  AppController controller,
  CodexSessionInfo? session,
) {
  final selected = session?.serviceTier?.trim() ?? '';
  if (selected.isEmpty) return '';
  final model = _selectedModel(controller.appModels, session?.model);
  for (final tier in model?.serviceTiers ?? const <AppModelServiceTierInfo>[]) {
    if (tier.id == selected) return tier.name;
  }
  return selected;
}

AppModelInfo? _selectedModel(List<AppModelInfo> models, String? modelId) {
  final configured = modelId?.trim() ?? '';
  if (configured.isEmpty) {
    for (final model in models) {
      if (model.isDefault) return model;
    }
    return models.isEmpty ? null : models.first;
  }
  for (final model in models) {
    if (model.id == configured || model.model == configured) return model;
  }
  return null;
}

AppModelServiceTierInfo? _preferredFastServiceTier(AppModelInfo? model) {
  final tiers = model?.serviceTiers ?? const <AppModelServiceTierInfo>[];
  if (tiers.isEmpty) return null;
  final defaultTier = model?.defaultServiceTier?.trim() ?? '';
  for (final tier in tiers) {
    final haystack = '${tier.id} ${tier.name} ${tier.description ?? ''}'
        .toLowerCase();
    if (haystack.contains('priority') ||
        haystack.contains('fast') ||
        haystack.contains('scale')) {
      return tier;
    }
  }
  for (final tier in tiers) {
    if (tier.id != defaultTier) return tier;
  }
  return tiers.first;
}

List<String> _effortOptionsFor(AppModelInfo? model, CodexSessionInfo? session) {
  final supported = model?.supportedReasoningEfforts ?? const <String>[];
  final options = supported.isEmpty
      ? <String>['low', 'medium', 'high', 'xhigh']
      : List<String>.from(supported);
  final current = session?.reasoningEffort?.trim() ?? '';
  if (current.isNotEmpty && !options.contains(current)) {
    options.add(current);
  }
  return options;
}

String? _nextEffortForModel(AppModelInfo model, String? currentEffort) {
  final current = currentEffort?.trim() ?? '';
  final supported = model.supportedReasoningEfforts;
  if (current.isNotEmpty &&
      (supported.isEmpty || supported.contains(current))) {
    return current;
  }
  final fallback = model.defaultReasoningEffort?.trim();
  if (fallback != null && fallback.isNotEmpty) return fallback;
  if (supported.contains('medium')) return 'medium';
  return supported.isEmpty ? null : supported.first;
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

void _showSessionControlsDialog(
  BuildContext context,
  AppController controller,
) {
  controller.refreshAppModels(includeHidden: true);
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: codexPanelHighColor(context),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: codexDimColor(context).withValues(alpha: 0.18)),
      ),
      child: const _SessionControlsSheet(),
    ),
  );
}

Future<void> _showChatSettingsMenu(
  BuildContext context,
  AppController controller,
) async {
  controller.refreshAppModels(includeHidden: true);
  final session = controller.activeSession;
  final selectedModel = _selectedModel(controller.appModels, session?.model);
  final effortOptions = _effortOptionsFor(selectedModel, session).take(5);
  final selectedEffort = session?.reasoningEffort?.trim().isNotEmpty == true
      ? session!.reasoningEffort!.trim()
      : selectedModel?.defaultReasoningEffort ?? 'medium';
  final picked = await _showAnchoredMenu<String>(
    context: context,
    minWidth: 360,
    maxWidth: 430,
    items: [
      _menuHeaderItem(
        context,
        'Chat settings',
        _sessionModelLabel(controller, session),
      ),
      _chatSettingsGridItem(
        context: context,
        leftTitle: 'Permission mode',
        rightTitle: 'Text size',
        leftChildren: [
          _compactSettingButton(
            context,
            value: 'mode:safe',
            label: 'default permissions',
            key: const ValueKey('chat-mode-safe'),
            selected: session?.mode != RunMode.yolo,
          ),
          _compactSettingButton(
            context,
            value: 'mode:yolo',
            label: 'yolo',
            key: const ValueKey('chat-mode-yolo'),
            selected: session?.mode == RunMode.yolo,
            enabled: controller.hostInfo?.yoloAllowed == true,
          ),
        ],
        rightChildren: [
          for (final size in const [
            ('compact', 'Compact'),
            ('default', 'Default'),
            ('large', 'Large'),
            ('xl', 'XL'),
          ])
            _compactSettingButton(
              context,
              value: 'text:${size.$1}',
              label: size.$2,
              key: ValueKey('chat-text-size-${size.$1}'),
              selected: controller.chatTextSize == size.$1,
            ),
        ],
      ),
      _chatSettingsGridItem(
        context: context,
        leftTitle: 'Models',
        rightTitle: 'Effort',
        leftChildren: [
          _compactSettingButton(
            context,
            value: 'model:',
            label: 'Default model',
            selected: (session?.model?.trim() ?? '').isEmpty,
          ),
          for (final model in controller.appModels.take(4))
            _compactSettingButton(
              context,
              value: 'model:${model.id}',
              label: model.displayName,
              key: ValueKey('chat-model-${model.id}'),
              selected:
                  session?.model == model.id || session?.model == model.model,
            ),
        ],
        rightChildren: [
          for (final effort in effortOptions)
            _compactSettingButton(
              context,
              value: 'effort:$effort',
              label: effort,
              key: ValueKey('chat-effort-$effort'),
              selected: selectedEffort == effort,
            ),
        ],
      ),
      const PopupMenuDivider(height: 8),
      _chatSettingItem(
        context,
        'refresh-models',
        Icons.refresh_rounded,
        'Refresh models',
        'Reload host model options',
        key: const ValueKey('chat-settings-refresh-models'),
      ),
      _chatSettingItem(
        context,
        'settings:advanced',
        Icons.tune_rounded,
        'Advanced controls',
        'Open the full chat controls panel',
      ),
      _chatSettingItem(
        context,
        'settings:full',
        Icons.settings_rounded,
        'Full settings',
        'Open account, notifications, env, and updates',
      ),
    ],
  );
  if (!context.mounted || picked == null) return;
  if (picked == 'refresh-models') {
    controller.refreshAppModels(includeHidden: true);
    return;
  }
  if (picked == 'mode:safe') {
    controller.setYolo(false);
    return;
  }
  if (picked == 'mode:yolo') {
    controller.setYolo(true);
    return;
  }
  if (picked.startsWith('model:')) {
    final modelId = picked.substring('model:'.length);
    final model = controller.appModels
        .where((item) => item.id == modelId || item.model == modelId)
        .firstOrNull;
    controller.setSessionConfig(
      model: modelId,
      reasoningEffort: model == null
          ? selectedEffort
          : _nextEffortForModel(model, session?.reasoningEffort),
      serviceTier: '',
    );
    return;
  }
  if (picked.startsWith('effort:')) {
    controller.setSessionConfig(
      reasoningEffort: picked.substring('effort:'.length),
    );
    return;
  }
  if (picked.startsWith('text:')) {
    controller.setChatTextSize(picked.substring('text:'.length));
    return;
  }
  if (picked == 'settings:full') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    return;
  }
  if (picked == 'settings:advanced') {
    _showSessionControlsDialog(context, controller);
  }
}

enum _TopAction {
  commandCenter,
  sessions,
  shell,
  workspace,
  skills,
  review,
  hostUpdate,
  usage,
}

Future<void> _showActionMenu(
  BuildContext context,
  AppController controller,
) async {
  final picked = await _showAnchoredMenu<_TopAction>(
    context: context,
    minWidth: 278,
    maxWidth: 340,
    items: [
      _topActionMenuItem(
        context,
        _TopAction.commandCenter,
        Icons.terminal_rounded,
        'Command center',
        'Plugins, MCP, remote, host tools',
        key: const ValueKey('action-command-center'),
      ),
      _topActionMenuItem(
        context,
        _TopAction.sessions,
        Icons.history_rounded,
        'Codex sessions',
        'Import app-server and CLI sessions',
        key: const ValueKey('action-codex-sessions'),
      ),
      _topActionMenuItem(
        context,
        _TopAction.shell,
        Icons.code_rounded,
        'Workspace shell',
        controller.activeSession?.workdir ?? 'Active workspace',
        key: const ValueKey('action-shell'),
      ),
      _topActionMenuItem(
        context,
        _TopAction.workspace,
        Icons.folder_open_rounded,
        'Workspace explorer',
        'Browse, preview, and edit files',
        key: const ValueKey('action-workspace'),
      ),
      _topActionMenuItem(
        context,
        _TopAction.skills,
        Icons.auto_awesome_rounded,
        'Skills',
        'Browse app-server skills',
        key: const ValueKey('action-skills'),
      ),
      _topActionMenuItem(
        context,
        _TopAction.review,
        Icons.fact_check_rounded,
        'Review changes',
        'Start an inline code review',
        key: const ValueKey('action-review'),
      ),
      _topActionMenuItem(
        context,
        _TopAction.hostUpdate,
        Icons.system_update_alt_rounded,
        'Host update',
        _hostUpdateSubtitle(controller),
        key: const ValueKey('action-host-update'),
      ),
      _topActionMenuItem(
        context,
        _TopAction.usage,
        Icons.query_stats_rounded,
        'Usage limits',
        _usageSubtitle(controller.appRateLimits),
        key: const ValueKey('action-usage'),
      ),
    ],
  );
  if (!context.mounted || picked == null) return;
  switch (picked) {
    case _TopAction.commandCenter:
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AppServerActionsScreen()),
      );
      break;
    case _TopAction.sessions:
      _showCodexSessionsSheet(context, controller);
      break;
    case _TopAction.shell:
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const WorkspaceShellScreen()),
      );
      break;
    case _TopAction.workspace:
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FileBrowserScreen()),
      );
      break;
    case _TopAction.skills:
      _showSkillsSheet(context, controller);
      break;
    case _TopAction.review:
      _showReviewSheet(context, controller);
      break;
    case _TopAction.hostUpdate:
      _showHostUpdateSheet(context, controller);
      break;
    case _TopAction.usage:
      _showUsageLimits(context, controller);
      break;
  }
}

Future<T?> _showAnchoredMenu<T>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
  required double minWidth,
  required double maxWidth,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final box = context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  return showMenu<T>(
    context: context,
    color: codexPanelHighColor(context),
    surfaceTintColor: Colors.transparent,
    elevation: 10,
    constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: codexDimColor(context).withValues(alpha: 0.18)),
    ),
    position: RelativeRect.fromRect(
      Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

class _PopupContentEntry<T> extends PopupMenuEntry<T> {
  const _PopupContentEntry({required this.entryHeight, required this.child});

  final double entryHeight;
  final Widget child;

  @override
  double get height => entryHeight;

  @override
  bool represents(T? value) => false;

  @override
  State<_PopupContentEntry<T>> createState() => _PopupContentEntryState<T>();
}

class _PopupContentEntryState<T> extends State<_PopupContentEntry<T>> {
  @override
  Widget build(BuildContext context) => widget.child;
}

PopupMenuItem<String> _menuHeaderItem(
  BuildContext context,
  String title,
  String subtitle,
) {
  return PopupMenuItem<String>(
    enabled: false,
    height: 48,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: codexDimColor(context)),
        ),
      ],
    ),
  );
}

PopupMenuEntry<String> _chatSettingsGridItem({
  required BuildContext context,
  required String leftTitle,
  required String rightTitle,
  required List<Widget> leftChildren,
  required List<Widget> rightChildren,
}) {
  final rowCount = leftChildren.length > rightChildren.length
      ? leftChildren.length
      : rightChildren.length;
  return _PopupContentEntry<String>(
    entryHeight: 42 + rowCount * 36.0,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _chatSettingsColumn(context, leftTitle, leftChildren),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _chatSettingsColumn(context, rightTitle, rightChildren),
          ),
        ],
      ),
    ),
  );
}

Widget _chatSettingsColumn(
  BuildContext context,
  String title,
  List<Widget> children,
) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: codexDimColor(context),
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      ...children,
    ],
  );
}

Widget _compactSettingButton(
  BuildContext context, {
  required String value,
  required String label,
  bool selected = false,
  bool enabled = true,
  Key? key,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final background = selected
      ? colorScheme.secondary.withValues(alpha: 0.16)
      : codexPanelHighColor(context).withValues(alpha: 0.72);
  final borderColor = selected
      ? colorScheme.secondary.withValues(alpha: 0.55)
      : codexDimColor(context).withValues(alpha: 0.14);
  final foreground = enabled
      ? (selected ? colorScheme.secondary : codexTextColor(context))
      : codexDimColor(context).withValues(alpha: 0.58);
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Builder(
      builder: (menuContext) => Material(
        key: key,
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: enabled ? () => Navigator.of(menuContext).pop(value) : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: borderColor),
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                if (selected) ...[
                  Icon(Icons.check_rounded, size: 14, color: foreground),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

PopupMenuItem<String> _chatSettingItem(
  BuildContext context,
  String value,
  IconData icon,
  String title,
  String subtitle, {
  bool selected = false,
  Key? key,
}) {
  return PopupMenuItem<String>(
    key: key,
    value: value,
    height: 52,
    child: Row(
      children: [
        Icon(
          selected ? Icons.check_circle_rounded : icon,
          size: 18,
          color: selected
              ? Theme.of(context).colorScheme.secondary
              : codexMutedColor(context),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: codexDimColor(context)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

PopupMenuItem<_TopAction> _topActionMenuItem(
  BuildContext context,
  _TopAction value,
  IconData icon,
  String title,
  String subtitle, {
  Key? key,
}) {
  return PopupMenuItem<_TopAction>(
    key: key,
    value: value,
    height: 54,
    child: Row(
      children: [
        Icon(icon, size: 18, color: codexMutedColor(context)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: codexDimColor(context)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _hostUpdateSubtitle(AppController controller) {
  final status = controller.hostUpdateStatus;
  final result = controller.hostUpdateResult;
  final current = status?.currentVersion ?? result?.previousVersion;
  final latest = status?.latestVersion ?? result?.latestVersion;
  if (controller.hostUpdateBusy) return 'checking or updating';
  if (status?.updateAvailable == true && latest != null) {
    return 'latest $latest available';
  }
  if (current != null && current.isNotEmpty) return 'current $current';
  return 'check npm package updates';
}

String _pathTail(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '';
  final normalized = trimmed.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? normalized : parts.last;
}

void _showCodexSessionsSheet(BuildContext context, AppController controller) {
  controller.refreshAppThreads(limit: 40);
  controller.refreshExternalSessions();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: codexPanelHighColor(context),
    showDragHandle: true,
    builder: (_) => const _CodexSessionsQuickSheet(),
  );
}

class _CodexSessionsQuickSheet extends StatelessWidget {
  const _CodexSessionsQuickSheet();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final appThreads = controller.appThreads;
    final externalSessions = controller.externalSessions;
    final empty = appThreads.isEmpty && externalSessions.isEmpty;
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Codex sessions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh sessions',
                  onPressed: () {
                    controller.refreshAppThreads(limit: 40);
                    controller.refreshExternalSessions();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (empty)
              Text(
                'No importable Codex sessions found yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: codexMutedColor(context),
                ),
              ),
            for (final thread in appThreads.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.forum_rounded),
                title: Text(thread.title, maxLines: 1),
                subtitle: Text(
                  [
                    if (thread.preview.trim().isNotEmpty) thread.preview,
                    if (thread.workdir.trim().isNotEmpty)
                      _pathTail(thread.workdir),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  controller.importAppThread(thread);
                  Navigator.of(context).pop();
                },
              ),
            for (final session in externalSessions.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_edu_rounded),
                title: Text(session.title, maxLines: 1),
                subtitle: Text(
                  [
                    if (session.codexThreadId.trim().isNotEmpty)
                      session.codexThreadId,
                    if (session.workdir.trim().isNotEmpty)
                      _pathTail(session.workdir),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  controller.importExternalSession(session);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

void _showSkillsSheet(BuildContext context, AppController controller) {
  controller.refreshAppSkills(forceReload: true);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: codexPanelHighColor(context),
    showDragHandle: true,
    builder: (_) => const _SkillsQuickSheet(),
  );
}

class _SkillsQuickSheet extends StatelessWidget {
  const _SkillsQuickSheet();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final groups = controller.appSkillGroups;
    final skills = [
      for (final group in groups)
        for (final skill in group.skills) (group: group, skill: skill),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Skills',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh skills',
                  onPressed: () =>
                      controller.refreshAppSkills(forceReload: true),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (skills.isEmpty)
              Text(
                'No app-server skills reported for this workspace.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: codexMutedColor(context),
                ),
              ),
            for (final item in skills.take(18))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  item.skill.enabled
                      ? Icons.auto_awesome_rounded
                      : Icons.block_rounded,
                ),
                title: Text(item.skill.name, maxLines: 1),
                subtitle: Text(
                  [
                    if (item.skill.description.trim().isNotEmpty)
                      item.skill.description,
                    if (item.skill.path.trim().isNotEmpty) item.skill.path,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            for (final group in groups)
              for (final error in group.errors)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    error,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

void _showReviewSheet(BuildContext context, AppController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: codexPanelHighColor(context),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _ReviewQuickSheet(),
  );
}

class _ReviewQuickSheet extends StatefulWidget {
  const _ReviewQuickSheet();

  @override
  State<_ReviewQuickSheet> createState() => _ReviewQuickSheetState();
}

class _ReviewQuickSheetState extends State<_ReviewQuickSheet> {
  final _instructionsController = TextEditingController();

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl + inset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review changes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _instructionsController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Optional focus',
                hintText: 'Security, tests, UI regressions...',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: controller.isConnected
                  ? () {
                      controller.startReview(
                        instructions: _instructionsController.text,
                      );
                      Navigator.of(context).pop();
                    }
                  : null,
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('Start review'),
            ),
          ],
        ),
      ),
    );
  }
}

void _showHostUpdateSheet(BuildContext context, AppController controller) {
  controller.refreshHostUpdateStatus();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: codexPanelHighColor(context),
    showDragHandle: true,
    builder: (_) => const _HostUpdateQuickSheet(),
  );
}

class _HostUpdateQuickSheet extends StatelessWidget {
  const _HostUpdateQuickSheet();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final status = controller.hostUpdateStatus;
    final result = controller.hostUpdateResult;
    final latest = status?.latestVersion ?? result?.latestVersion;
    final current = status?.currentVersion ?? result?.previousVersion;
    final updateAvailable = status?.updateAvailable == true;
    final progress = controller.hostUpdateProgress.reversed.take(4).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Host update',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Check host update',
                  onPressed: controller.hostUpdateBusy
                      ? null
                      : controller.refreshHostUpdateStatus,
                  icon: const Icon(Icons.sync_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _HostUpdateLine(
              icon: updateAvailable
                  ? Icons.new_releases_rounded
                  : Icons.check_circle_rounded,
              title: updateAvailable ? 'Update available' : 'Package status',
              subtitle: [
                status?.packageName ?? result?.packageName ?? 'codex-link-host',
                if (current != null && current.isNotEmpty) 'current $current',
                if (latest != null && latest.isNotEmpty) 'latest $latest',
                if (controller.hostUpdateBusy) 'running',
              ].join(' · '),
            ),
            if (controller.hostUpdateErrorText case final error?) ...[
              const SizedBox(height: AppSpacing.xs),
              _HostUpdateLine(
                icon: Icons.error_outline_rounded,
                title: 'Update error',
                subtitle: error,
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _HostUpdateLine(
                icon: result.updated
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                title: result.updated ? 'Update installed' : 'No update needed',
                subtitle: result.restartRequired
                    ? '${result.message} Restart the host bridge.'
                    : result.message,
              ),
            ],
            for (final item in progress) ...[
              const SizedBox(height: AppSpacing.xs),
              _HostUpdateLine(
                icon: Icons.chevron_right_rounded,
                title: item.phase,
                subtitle: item.line,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: const ValueKey('host-update-run-quick'),
              onPressed: controller.hostUpdateBusy
                  ? null
                  : controller.runHostUpdate,
              icon: const Icon(Icons.download_rounded),
              label: Text(
                controller.hostUpdateBusy ? 'Updating' : 'Update host',
              ),
            ),
            if (result?.restartRequired == true) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: controller.reconnect,
                icon: const Icon(Icons.cable_rounded),
                label: const Text('Reconnect after restart'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HostUpdateLine extends StatelessWidget {
  const _HostUpdateLine({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: codexMutedColor(context)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              if (subtitle.trim().isNotEmpty)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: codexMutedColor(context),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionControlsSheet extends StatelessWidget {
  const _SessionControlsSheet();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final session = controller.activeSession;
    final selectedModel = _selectedModel(controller.appModels, session?.model);
    final selectedModelId = session?.model?.trim() ?? '';
    final effortOptions = _effortOptionsFor(selectedModel, session);
    final speedTier = session?.serviceTier?.trim() ?? '';
    final fastTier = _preferredFastServiceTier(selectedModel);
    final serviceTiers =
        selectedModel?.serviceTiers ?? const <AppModelServiceTierInfo>[];
    final selectedEffort = session?.reasoningEffort?.trim().isNotEmpty == true
        ? session!.reasoningEffort!.trim()
        : selectedModel?.defaultReasoningEffort ?? 'medium';
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 760),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chat controls',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh models',
                  onPressed: controller.isConnected
                      ? () => controller.refreshAppModels(includeHidden: true)
                      : null,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Full settings',
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _ControlSection(
              title: 'Text size',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: const [
                  _ChatTextSizeChip(
                    key: ValueKey('chat-text-size-compact'),
                    value: 'compact',
                    label: 'Compact',
                  ),
                  _ChatTextSizeChip(
                    key: ValueKey('chat-text-size-default'),
                    value: 'default',
                    label: 'Default',
                  ),
                  _ChatTextSizeChip(
                    key: ValueKey('chat-text-size-large'),
                    value: 'large',
                    label: 'Large',
                  ),
                  _ChatTextSizeChip(
                    key: ValueKey('chat-text-size-xl'),
                    value: 'xl',
                    label: 'XL',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ControlSection(
              title: 'Codex permission mode',
              child: Column(
                children: [
                  _ControlRadioTile(
                    title: 'default permissions',
                    selected: session?.mode != RunMode.yolo,
                    enabled: controller.isConnected,
                    onTap: () => controller.setYolo(false),
                  ),
                  _ControlRadioTile(
                    title: 'yolo',
                    subtitle: controller.hostInfo?.yoloAllowed == true
                        ? 'full access for this chat'
                        : 'host must be started with --allow-yolo',
                    selected: session?.mode == RunMode.yolo,
                    enabled:
                        controller.isConnected &&
                        controller.hostInfo?.yoloAllowed == true,
                    onTap: () => controller.setYolo(true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ControlSection(
              title: 'Speed',
              child: serviceTiers.isEmpty
                  ? ListTile(
                      dense: true,
                      leading: const Icon(Icons.speed_rounded),
                      title: const Text('fast mode unavailable'),
                      subtitle: const Text(
                        'the selected model did not report paid speed tiers',
                      ),
                      enabled: false,
                    )
                  : Column(
                      children: [
                        _ControlRadioTile(
                          title: 'default speed',
                          subtitle: 'normal credit usage',
                          selected: speedTier.isEmpty,
                          enabled: controller.isConnected,
                          onTap: () =>
                              controller.setSessionConfig(serviceTier: ''),
                        ),
                        for (final tier in serviceTiers)
                          _ControlRadioTile(
                            title: tier.id == fastTier?.id
                                ? '${tier.name} fast mode'
                                : tier.name,
                            subtitle:
                                tier.description ??
                                'faster responses may use more credits',
                            selected: speedTier == tier.id,
                            enabled: controller.isConnected,
                            onTap: () => controller.setSessionConfig(
                              serviceTier: tier.id,
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ControlSection(
              title: 'Model',
              child: Column(
                children: [
                  if (controller.appModels.isEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.cloud_sync_outlined),
                      title: const Text('model list unavailable'),
                      subtitle: const Text('refresh after the host connects'),
                      onTap: controller.isConnected
                          ? () =>
                                controller.refreshAppModels(includeHidden: true)
                          : null,
                    )
                  else ...[
                    _ControlRadioTile(
                      title: 'default model',
                      selected: selectedModelId.isEmpty,
                      enabled: controller.isConnected,
                      onTap: () => controller.setSessionConfig(
                        model: '',
                        serviceTier: '',
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: controller.appModels.length,
                        itemBuilder: (context, index) {
                          final model = controller.appModels[index];
                          return _ControlRadioTile(
                            title: model.displayName,
                            subtitle: model.description ?? model.model,
                            selected:
                                selectedModelId == model.id ||
                                selectedModelId == model.model,
                            enabled: controller.isConnected,
                            onTap: () => controller.setSessionConfig(
                              model: model.id,
                              reasoningEffort: _nextEffortForModel(
                                model,
                                session?.reasoningEffort,
                              ),
                              serviceTier: '',
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  _LegacyModelField(
                    value: selectedModelId,
                    enabled: controller.isConnected,
                    onApply: (value) => controller.setSessionConfig(
                      model: value,
                      reasoningEffort: selectedEffort,
                      serviceTier: '',
                    ),
                    onClear: () =>
                        controller.setSessionConfig(model: '', serviceTier: ''),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ControlSection(
              title: 'Effort',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final effort in effortOptions)
                    ChoiceChip(
                      label: Text(effort),
                      selected: selectedEffort == effort,
                      onSelected: controller.isConnected
                          ? (_) => controller.setSessionConfig(
                              reasoningEffort: effort,
                            )
                          : null,
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

class _UsageLimitLine extends StatelessWidget {
  const _UsageLimitLine({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final limit = _primaryRateLimit(controller.appRateLimits);
    if (limit == null) return const SizedBox.shrink();
    final used = limit.usedPercent.clamp(0, 100);
    final accent = _usageColor(context, used);
    return Semantics(
      label: 'Usage limits',
      button: true,
      child: Tooltip(
        message: 'Usage limits',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('usage-limit-line'),
            onTap: () => _showUsageLimits(context, controller),
            child: SizedBox(
              height: 8,
              child: Align(
                alignment: Alignment.topLeft,
                child: FractionallySizedBox(
                  widthFactor: used / 100,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _usageSubtitle(List<AppRateLimitInfo> limits) {
  final limit = _primaryRateLimit(limits);
  if (limit == null) return 'limits unavailable';
  return '${limit.usedPercent.clamp(0, 100)}% used';
}

void _showUsageLimits(BuildContext context, AppController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: codexPanelHighColor(context),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Usage limits',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh usage',
                  onPressed: controller.isConnected
                      ? controller.refreshAppRateLimits
                      : null,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (controller.appRateLimits.isEmpty)
              Text(
                'limits unavailable',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: codexMutedColor(context),
                ),
              )
            else
              for (final limit in controller.appRateLimits)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _UsageLimitRow(limit: limit),
                ),
          ],
        ),
      ),
    ),
  );
}

class _UsageLimitRow extends StatelessWidget {
  const _UsageLimitRow({required this.limit});

  final AppRateLimitInfo limit;

  @override
  Widget build(BuildContext context) {
    final used = limit.usedPercent.clamp(0, 100);
    final remaining = limit.remainingPercent.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: codexPanelHighColor(context).withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: CodexColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  limit.limitId,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                '$used% used',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _usageColor(context, used),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: used / 100,
            minHeight: 6,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            backgroundColor: codexDimColor(context).withValues(alpha: 0.16),
            valueColor: AlwaysStoppedAnimation<Color>(
              _usageColor(context, used),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              '$remaining% remaining',
              if (limit.planType?.trim().isNotEmpty == true) limit.planType!,
              if (limit.windowDurationMins != null)
                '${limit.windowDurationMins} min window',
              if (limit.resetsAt != null)
                'resets ${_formatEpoch(limit.resetsAt!)}',
            ].join(' · '),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: codexMutedColor(context)),
          ),
        ],
      ),
    );
  }
}

AppRateLimitInfo? _primaryRateLimit(List<AppRateLimitInfo> limits) {
  if (limits.isEmpty) return null;
  return limits.reduce(
    (left, right) => left.usedPercent >= right.usedPercent ? left : right,
  );
}

Color _usageColor(BuildContext context, int usedPercent) {
  if (usedPercent >= 90) return Theme.of(context).colorScheme.error;
  if (usedPercent >= 70) return CodexColors.amber;
  return Theme.of(context).colorScheme.secondary;
}

String _formatEpoch(int seconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _ChatTextSizeChip extends StatelessWidget {
  const _ChatTextSizeChip({
    super.key,
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return ChoiceChip(
      label: Text(label),
      selected: controller.chatTextSize == value,
      onSelected: (_) => controller.setChatTextSize(value),
      visualDensity: VisualDensity.compact,
    );
  }
}

class WorkspaceShellScreen extends StatefulWidget {
  const WorkspaceShellScreen({super.key});

  @override
  State<WorkspaceShellScreen> createState() => _WorkspaceShellScreenState();
}

class _WorkspaceShellScreenState extends State<WorkspaceShellScreen> {
  final _commandController = TextEditingController();

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final session = controller.activeSession;
    return AnimatedChatGptBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Workspace shell'),
          actions: [
            if (controller.shellBusy)
              const Padding(
                padding: EdgeInsets.only(right: AppSpacing.md),
                child: Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Column(
              children: [
                _ShellCwdBar(path: session?.workdir ?? 'No workspace'),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: _ShellOutputList(results: controller.shellHistory),
                ),
                const SizedBox(height: AppSpacing.sm),
                _ShellCommandInput(
                  controller: _commandController,
                  enabled: controller.isConnected && !controller.shellBusy,
                  onRun: () => _run(controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _run(AppController controller) {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;
    controller.runShellCommand(command);
    _commandController.clear();
  }
}

class _ShellCwdBar extends StatelessWidget {
  const _ShellCwdBar({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      radius: AppRadius.lg,
      color: codexPanelHighColor(context).withValues(alpha: 0.74),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: codexMutedColor(context),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellOutputList extends StatelessWidget {
  const _ShellOutputList({required this.results});

  final List<ShellCommandResultInfo> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No commands run yet',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: codexMutedColor(context)),
        ),
      );
    }
    return ListView.separated(
      reverse: true,
      itemBuilder: (context, index) {
        final result = results[results.length - index - 1];
        return _ShellResultBlock(result: result);
      },
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemCount: results.length,
    );
  }
}

class _ShellResultBlock extends StatelessWidget {
  const _ShellResultBlock({required this.result});

  final ShellCommandResultInfo result;

  @override
  Widget build(BuildContext context) {
    final ok = result.exitCode == 0;
    final output = [
      if (result.stdout.trim().isNotEmpty) result.stdout.trimRight(),
      if (result.stderr.trim().isNotEmpty) result.stderr.trimRight(),
    ].join('\n');
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadius.lg,
      color: codexPanelHighColor(context).withValues(alpha: 0.74),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: ok
                    ? CodexColors.greenSoft
                    : Theme.of(context).colorScheme.error,
                size: 17,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  r'$ ' + result.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              Text(
                '${result.durationMs} ms',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: codexMutedColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            output.isEmpty ? '(no output)' : output,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: codexTextColor(context),
              fontFamily: 'monospace',
              height: 1.32,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellCommandInput extends StatelessWidget {
  const _ShellCommandInput({
    required this.controller,
    required this.enabled,
    required this.onRun,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      radius: AppRadius.xl,
      color: codexPanelHighColor(context).withValues(alpha: 0.82),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.sm),
            child: Icon(Icons.terminal_rounded, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              key: const ValueKey('shell-command-input'),
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 3,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Run command in workspace',
              ),
              onSubmitted: (_) => onRun(),
            ),
          ),
          IconButton(
            tooltip: 'Run command',
            onPressed: enabled ? onRun : null,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
    );
  }
}

class _LegacyModelField extends StatefulWidget {
  const _LegacyModelField({
    required this.value,
    required this.enabled,
    required this.onApply,
    required this.onClear,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onApply;
  final VoidCallback onClear;

  @override
  State<_LegacyModelField> createState() => _LegacyModelFieldState();
}

class _LegacyModelFieldState extends State<_LegacyModelField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _LegacyModelField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('legacy-model-input'),
            controller: _controller,
            enabled: widget.enabled,
            style: TextStyle(
              color: codexTextColor(context),
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.memory_rounded),
              labelText: 'Legacy model id',
              hintText: 'gpt-5.1-codex-max',
            ),
            onSubmitted: (_) => _apply(),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          tooltip: 'Clear model',
          onPressed: widget.enabled ? widget.onClear : null,
          icon: const Icon(Icons.close_rounded),
        ),
        IconButton(
          tooltip: 'Apply legacy model',
          onPressed: widget.enabled ? _apply : null,
          icon: const Icon(Icons.check_rounded),
        ),
      ],
    );
  }

  void _apply() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      widget.onClear();
      return;
    }
    widget.onApply(value);
  }
}

class _ControlSection extends StatelessWidget {
  const _ControlSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: codexComposerColor(context).withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: codexDimColor(context).withValues(alpha: 0.14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: codexMutedColor(context),
                  letterSpacing: 0.3,
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _ControlRadioTile extends StatelessWidget {
  const _ControlRadioTile({
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).colorScheme.secondary;
    final foreground = enabled
        ? codexTextColor(context)
        : codexDimColor(context);
    return ListTile(
      dense: true,
      enabled: enabled,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? active : codexDimColor(context),
      ),
      title: Text(title, style: TextStyle(color: foreground)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: codexDimColor(context), fontSize: 12),
            ),
      onTap: enabled ? onTap : null,
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
    if (!controller.isOffline) return const SizedBox.shrink();
    final connection = _connectionLabel(controller);
    const detail = 'tap to reconnect';
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

class _NoticeBanner extends StatefulWidget {
  const _NoticeBanner({required this.controller});

  final AppController controller;

  @override
  State<_NoticeBanner> createState() => _NoticeBannerState();
}

class _NoticeBannerState extends State<_NoticeBanner> {
  Timer? _timer;
  String? _noticeId;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _NoticeBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    final notice = widget.controller.latestNotice;
    final duration = widget.controller.inAppNoticeDurationSeconds;
    if (notice == null) {
      _timer?.cancel();
      _timer = null;
      _noticeId = null;
      _remainingSeconds = 0;
      return;
    }
    if (_noticeId == notice.id && _remainingSeconds > 0) return;
    _timer?.cancel();
    _noticeId = notice.id;
    _remainingSeconds = duration;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        _timer?.cancel();
        _timer = null;
        widget.controller.clearLatestNotice();
        return;
      }
      setState(() => _remainingSeconds -= 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
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
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.sm,
                    right: AppSpacing.xs,
                    top: 2,
                  ),
                  child: SoftPill(
                    label: '${_remainingSeconds}s',
                    color: accent,
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
    final base = isCodexLight(context) ? LightCodexColors.ink : CodexColors.ink;
    return IgnorePointer(
      child: SizedBox(
        height: top ? 118 : 176,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                base.withValues(alpha: 0.82),
                base.withValues(alpha: 0.28),
                base.withValues(alpha: 0),
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
  bool _showJumpToPrevious = false;
  bool _autoScrollQueued = false;
  bool _queuedAutoScrollAnimated = false;
  int _lastItemCount = 0;
  String _lastTimelineSignature = '';
  final Map<String, GlobalKey> _messageKeys = {};

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
    final shouldShowPrevious = position.pixels > 360;
    if ((shouldShow != _showJumpToBottom ||
            shouldShowPrevious != _showJumpToPrevious) &&
        mounted) {
      setState(() {
        _showJumpToBottom = shouldShow;
        _showJumpToPrevious = shouldShowPrevious;
      });
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

  GlobalKey _keyForMessage(String id) {
    return _messageKeys.putIfAbsent(id, GlobalKey.new);
  }

  void _jumpToPreviousResponse(List<ChatMessage> messages) {
    if (!widget.scrollController.hasClients) return;
    final current = widget.scrollController.position.pixels;
    final max = widget.scrollController.position.maxScrollExtent;
    for (final message in messages.reversed) {
      if (message.role != ChatRole.assistant) continue;
      final context = _messageKeys[message.id]?.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject == null) continue;
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) continue;
      final target = viewport.getOffsetToReveal(renderObject, 0).offset;
      if (target < current - 24) {
        widget.scrollController.animateTo(
          target.clamp(0.0, max).toDouble(),
          duration: AppMotion.scroll,
          curve: Curves.easeInOutCubic,
        );
        return;
      }
    }
    widget.scrollController.animateTo(
      0,
      duration: AppMotion.scroll,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final messages = controller.activeMessages;
    _messageKeys.removeWhere(
      (id, _) => !messages.any((message) => message.id == id),
    );
    if (messages.isEmpty && !controller.isRunning) {
      return const _EmptyChatHero();
    }
    final items = _timelineItems(
      messages,
      isRunning: controller.isRunning,
      runId: controller.activeRunId,
    );
    final subagents = controller.activeSubagents;
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
                  _SingleTimelineItem(:final message) => KeyedSubtree(
                    key: _keyForMessage(message.id),
                    child: MessageBubble(
                      key: ValueKey(
                        'bubble-${message.id}-${message.kind.name}',
                      ),
                      message: message,
                      animate: shouldAnimateItem,
                      textScale: controller.chatTextScale,
                      onOpenWorkspaceFile: (path) =>
                          _openWorkspaceFile(context, path),
                    ),
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
          bottom: 252,
          child: _SubagentActivityChip(subagents: subagents),
        ),
        Positioned(
          right: AppSpacing.lg,
          bottom: 202,
          child: AnimatedScale(
            scale: _showJumpToPrevious ? 1 : 0.82,
            duration: AppMotion.quick,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _showJumpToPrevious ? 1 : 0,
              duration: AppMotion.quick,
              child: IgnorePointer(
                ignoring: !_showJumpToPrevious,
                child: ChatGptCircleButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  size: 42,
                  background: CodexColors.panelHigh,
                  onPressed: () => _jumpToPreviousResponse(messages),
                ),
              ),
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

  void _openWorkspaceFile(BuildContext context, String path) {
    final normalized = _workspaceOpenPath(path);
    if (normalized.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FileBrowserScreen(initialPath: normalized),
      ),
    );
  }
}

class _SubagentActivityChip extends StatelessWidget {
  const _SubagentActivityChip({required this.subagents});

  final List<AppSubagentInfo> subagents;

  @override
  Widget build(BuildContext context) {
    final visible = subagents.isNotEmpty;
    if (!visible) return const SizedBox.shrink();
    final running = subagents.where((item) => item.isRunning).length;
    final active = running > 0;
    final count = active ? running : subagents.length;
    final label = count == 1 ? 'subagent' : 'subagents';
    final summary = active ? '$count $label running' : '$count $label';
    return AnimatedScale(
      scale: visible ? 1 : 0.84,
      duration: AppMotion.quick,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.quick,
        child: IgnorePointer(
          ignoring: !visible,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('agent-activity-chip'),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: () => _showSubagentActivitySheet(context, subagents),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: codexPanelHighColor(context).withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      active
                          ? Icons.account_tree_rounded
                          : Icons.check_circle_rounded,
                      color: active
                          ? Theme.of(context).colorScheme.secondary
                          : CodexColors.greenSoft,
                      size: 17,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.expand_less_rounded,
                      color: codexMutedColor(context),
                      size: 18,
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

void _showSubagentActivitySheet(
  BuildContext context,
  List<AppSubagentInfo> subagents,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: codexPanelHighColor(context),
    barrierColor: Colors.black.withValues(alpha: 0.38),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (context) => _SubagentActivitySheet(subagents: subagents),
  );
}

class _SubagentActivitySheet extends StatelessWidget {
  const _SubagentActivitySheet({required this.subagents});

  final List<AppSubagentInfo> subagents;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree_rounded,
                    color: Theme.of(context).colorScheme.secondary,
                    size: 19,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Subagents',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${subagents.length} ${subagents.length == 1 ? 'item' : 'items'}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: codexDimColor(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView.separated(
                  itemCount: subagents.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    return _SubagentActivityTile(subagent: subagents[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubagentActivityTile extends StatelessWidget {
  const _SubagentActivityTile({required this.subagent});

  final AppSubagentInfo subagent;

  @override
  Widget build(BuildContext context) {
    final active = subagent.isRunning;
    final preview = subagent.preview.trim();
    final role = subagent.agentRole?.trim();
    return Material(
      color: codexComposerColor(context).withValues(alpha: 0.44),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              active ? Icons.sync_rounded : Icons.check_circle_rounded,
              color: active
                  ? Theme.of(context).colorScheme.secondary
                  : CodexColors.greenSoft,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subagent.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'running',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                        ),
                      ],
                    ],
                  ),
                  if (role != null && role.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: codexMutedColor(context),
                      ),
                    ),
                  ],
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: codexDimColor(context),
                        height: 1.34,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed: () {
                final controller = context.read<AppController>();
                final workdir = controller.activeSession?.workdir ?? '';
                controller.importAppThread(
                  subagent.toThreadInfo(workdir: workdir),
                );
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Theme.of(context).colorScheme.secondary,
                textStyle: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _workspaceOpenPath(String path) {
  var normalized = path.trim().replaceAll('\\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  if (normalized.startsWith('a/') || normalized.startsWith('b/')) {
    normalized = normalized.substring(2);
  }
  return normalized;
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
    final canEditPrompt = controller.canShowChat;
    final canSendPrompt = controller.isConnected;
    final hasPromptText = textController.text.trim().isNotEmpty;
    final hasAttachments = _attachments.isNotEmpty;
    final canSubmitPrompt = hasPromptText || hasAttachments;
    final light = isCodexLight(context);
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Builder(
                builder: (buttonContext) => ChatGptCircleButton(
                  key: const ValueKey('floating-attach-button'),
                  icon: Icons.add_rounded,
                  size: 44,
                  background: codexComposerColor(
                    context,
                  ).withValues(alpha: 0.82),
                  onPressed: controller.isConnected
                      ? () => _showAttachmentPicker(buttonContext)
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Builder(
                builder: (buttonContext) => ChatGptCircleButton(
                  key: const ValueKey('composer-settings-button'),
                  icon: Icons.tune_rounded,
                  size: 44,
                  background: codexComposerColor(
                    context,
                  ).withValues(alpha: 0.82),
                  onPressed: controller.isConnected
                      ? () => _showChatSettingsMenu(buttonContext, controller)
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: GlassCard(
                  key: const ValueKey('composer-input-shell'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xxs / 2,
                    AppSpacing.xs,
                    AppSpacing.xxs / 2,
                  ),
                  radius: AppRadius.xl,
                  color: codexComposerColor(
                    context,
                  ).withValues(alpha: light ? 0.90 : 0.72),
                  blur: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (goalSubcommands.isNotEmpty &&
                          controller.isConnected) ...[
                        _SlashSubcommandSuggestions(
                          subcommands: goalSubcommands,
                          onSelected: _insertGoalSubcommand,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ] else if (slashQuery != null &&
                          controller.isConnected) ...[
                        _SlashCommandSuggestions(
                          commands: slashCommands,
                          onSendFile: _insertSendCommand,
                          onCommand: _runSlashCommand,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      if (activeMention != null &&
                          fileSuggestions.isNotEmpty) ...[
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
                                onDeleted: () => setState(
                                  () => _attachments.removeAt(index),
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: CodexColors.panelHigh,
                                side: const BorderSide(
                                  color: CodexColors.borderSoft,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: textController,
                              minLines: 1,
                              maxLines: 5,
                              enabled: canEditPrompt,
                              textAlignVertical: TextAlignVertical.center,
                              cursorColor: codexTextColor(context),
                              style: TextStyle(
                                color: codexTextColor(context),
                                height: 1.25,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: controller.isOffline
                                    ? 'Offline - cached chat'
                                    : 'Message Codex',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.zero,
                              ),
                              textInputAction: TextInputAction.newline,
                              onChanged: _handleTextChanged,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          SizedBox.square(
                            dimension: 38,
                            child: Material(
                              color: codexTextColor(context),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: IconButton(
                                tooltip: canSubmitPrompt
                                    ? 'Send'
                                    : controller.voiceInputBusy
                                    ? 'Listening'
                                    : 'Voice input',
                                color: Theme.of(context).colorScheme.surface,
                                iconSize: 18,
                                icon: controller.voiceInputBusy
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        canSubmitPrompt
                                            ? Icons.arrow_upward_rounded
                                            : Icons.mic_rounded,
                                      ),
                                onPressed: canSendPrompt
                                    ? () => canSubmitPrompt
                                          ? _submitPrompt(controller)
                                          : _startVoiceInput(controller)
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
            ],
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
      case 'codex.model':
        _openSettings(SettingsSection.model);
        break;
      case 'codex.tunnel':
        widget.controller.runCommand(command);
        _openSettings(SettingsSection.connection);
        break;
      case 'codex.review':
        widget.controller.runCommand(command);
        break;
      case 'codex.doctor':
        widget.controller.runCommand(command);
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

  Future<void> _startVoiceInput(AppController controller) async {
    final result = await controller.transcribeVoiceInput();
    if (!mounted || result == null) return;
    final text = result.text.trim();
    if (text.isEmpty) return;
    widget.textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _handleTextChanged(text);
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
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await showMenu<_AttachmentPickMode>(
      context: context,
      color: codexPanelHighColor(context),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: codexDimColor(context).withValues(alpha: 0.18)),
      ),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height),
        Offset.zero & overlay.size,
      ),
      items: [
        _attachmentMenuItem(
          context,
          _AttachmentPickMode.workspace,
          Icons.folder_open_rounded,
          'Browse workspace',
          'Open files, preview code, or upload',
        ),
        _attachmentMenuItem(
          context,
          _AttachmentPickMode.image,
          Icons.image_rounded,
          'Upload image',
          'Attach a screenshot or visual reference',
        ),
        _attachmentMenuItem(
          context,
          _AttachmentPickMode.file,
          Icons.attach_file_rounded,
          'Upload file',
          'Save a file into the active workspace',
        ),
      ],
    );
    if (!mounted || picked == null) return;
    if (picked == _AttachmentPickMode.workspace) {
      await _openFileBrowser();
      return;
    }
    await _pickFiles(picked);
  }

  Future<void> _openFileBrowser() async {
    final selectedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FileBrowserScreen()),
    );
    if (!mounted || selectedPath == null || selectedPath.trim().isEmpty) return;
    _insertPathMention(selectedPath.trim());
  }

  void _insertPathMention(String path) {
    final controller = widget.textController;
    final value = controller.value;
    final selection = value.selection;
    final cursor = selection.isValid ? selection.baseOffset : value.text.length;
    final safeCursor = cursor.clamp(0, value.text.length).toInt();
    final prefix =
        safeCursor > 0 && !value.text.substring(0, safeCursor).endsWith(' ')
        ? ' '
        : '';
    final insertion = '$prefix@$path ';
    final text = value.text.replaceRange(safeCursor, safeCursor, insertion);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: safeCursor + insertion.length),
    );
    widget.controller.clearFileSuggestions();
    setState(() {});
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

enum _AttachmentPickMode { workspace, image, file }

PopupMenuItem<_AttachmentPickMode> _attachmentMenuItem(
  BuildContext context,
  _AttachmentPickMode value,
  IconData icon,
  String title,
  String subtitle,
) {
  return PopupMenuItem<_AttachmentPickMode>(
    value: value,
    height: 58,
    child: Row(
      children: [
        Icon(icon, size: 18, color: codexMutedColor(context)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: codexDimColor(context)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

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
