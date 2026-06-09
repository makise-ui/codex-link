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
          if (showMenu) ...[
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
              IconButton(
                tooltip: 'App server actions',
                onPressed: () => _showCommands(context),
                icon: const Icon(Icons.terminal_rounded, size: 21),
              ),
              IconButton(
                tooltip: 'Session controls',
                onPressed: () => _showSessionControls(context, controller),
                icon: const Icon(Icons.tune_rounded, size: 21),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCommands(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AppServerActionsScreen()),
    );
  }

  void _showSessionControls(BuildContext context, AppController controller) {
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
          side: BorderSide(
            color: codexDimColor(context).withValues(alpha: 0.18),
          ),
        ),
        child: const _SessionControlsSheet(),
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
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 660),
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
              Expanded(
                child: GlassCard(
                  key: const ValueKey('composer-input-shell'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xxs,
                    AppSpacing.xs,
                    AppSpacing.xxs,
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
                                tooltip: 'Send',
                                color: Theme.of(context).colorScheme.surface,
                                iconSize: 18,
                                icon: const Icon(Icons.arrow_upward_rounded),
                                onPressed: canSendPrompt
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
