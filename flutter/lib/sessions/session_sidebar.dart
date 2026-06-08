import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';

class SessionSidebar extends StatefulWidget {
  const SessionSidebar({super.key, this.onPicked});

  final VoidCallback? onPicked;

  @override
  State<SessionSidebar> createState() => _SessionSidebarState();
}

class _SessionSidebarState extends State<SessionSidebar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final query = _searchController.text.trim().toLowerCase();
    final sessions = query.isEmpty
        ? controller.sessions
        : controller.sessions
              .where(
                (session) =>
                    session.title.toLowerCase().contains(query) ||
                    session.workdir.toLowerCase().contains(query) ||
                    session.workdirName.toLowerCase().contains(query),
              )
              .toList(growable: false);
    return SafeArea(
      child: Container(
        width: 288,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B1B1D), Color(0xFF0A0A0B), Color(0xFF161618)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Codex Link',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  ChatGptCircleButton(
                    icon: Icons.edit_square,
                    size: 38,
                    onPressed: controller.createSession,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _ConnectionSummary(controller: controller),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                height: 38,
                child: TextField(
                  key: const ValueKey('sidebar-search'),
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search sessions',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    filled: true,
                    fillColor: CodexColors.panelHigh.withValues(alpha: 0.54),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Recents',
                style: TextStyle(
                  color: CodexColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final active =
                      session.sessionId == controller.activeSession?.sessionId;
                  return _SessionRow(
                    session: session,
                    active: active,
                    onTap: () {
                      controller.selectSession(session.sessionId);
                      widget.onPicked?.call();
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WorkspacePicker(controller: controller),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Settings'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: controller.createSession,
                    icon: const Icon(Icons.edit_square),
                    label: const Text('New chat'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
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

class _ConnectionSummary extends StatelessWidget {
  const _ConnectionSummary({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final hostInfo = controller.hostInfo;
    final label = controller.isOffline
        ? 'Offline'
        : hostInfo?.connectionMode == 'tunnel'
        ? _tunnelLabel(hostInfo)
        : 'Local bridge';
    final icon = controller.isOffline
        ? Icons.cloud_off_rounded
        : hostInfo?.connectionMode == 'tunnel'
        ? Icons.cloud_done_rounded
        : Icons.lan_rounded;
    final color = controller.isOffline
        ? CodexColors.amber
        : hostInfo?.connectionMode == 'tunnel'
        ? CodexColors.greenSoft
        : CodexColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: CodexColors.panelHigh.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: CodexColors.text.withValues(alpha: AppOpacity.border),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: CodexColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

String _tunnelLabel(HostInfo? hostInfo) {
  final provider = hostInfo?.tunnelProvider;
  if (provider == null || provider.trim().isEmpty) return 'Tunnel';
  return 'Tunnel via $provider';
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.active,
    required this.onTap,
  });

  final CodexSessionInfo session;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? CodexColors.panelHigh : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: CodexColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 82),
                child: Text(
                  session.workdirName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CodexColors.dim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (session.isRunning)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox.square(
                    dimension: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: CodexColors.blue,
                        shape: BoxShape.circle,
                      ),
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

class _WorkspacePicker extends StatelessWidget {
  const _WorkspacePicker({required this.controller});

  final AppController controller;
  static const _addWorkspaceAction = '__add_workspace__';
  static const _createWorkspaceAction = '__create_workspace__';

  @override
  Widget build(BuildContext context) {
    final activeWorkspace =
        controller.workspaces
            .where(
              (workspace) =>
                  workspace.workspaceId ==
                  controller.activeSession?.workspaceId,
            )
            .firstOrNull ??
        (controller.workspaces.isEmpty ? null : controller.workspaces.first);
    if (controller.workspaces.isEmpty) return const SizedBox.shrink();
    final disabled = controller.isRunning;
    return PopupMenuButton<String>(
      key: const ValueKey('workspace-picker'),
      tooltip: 'Switch workspace',
      enabled: !disabled,
      color: CodexColors.panelHigh.withValues(alpha: 0.98),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.38),
      offset: const Offset(0, -8),
      constraints: const BoxConstraints(minWidth: 252, maxWidth: 280),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: CodexColors.text.withValues(alpha: AppOpacity.border),
        ),
      ),
      onSelected: (value) => _handleSelection(context, value),
      itemBuilder: (context) => [
        for (final workspace in controller.workspaces)
          PopupMenuItem<String>(
            value: workspace.workspaceId,
            height: 50,
            child: _WorkspaceMenuItem(
              workspace: workspace,
              active: workspace.workspaceId == activeWorkspace?.workspaceId,
            ),
          ),
        const PopupMenuDivider(height: AppSpacing.sm),
        const PopupMenuItem<String>(
          value: _addWorkspaceAction,
          height: 44,
          child: _WorkspaceActionMenuItem(
            icon: Icons.folder_open_rounded,
            title: 'Add folder...',
          ),
        ),
        const PopupMenuItem<String>(
          value: _createWorkspaceAction,
          height: 44,
          child: _WorkspaceActionMenuItem(
            icon: Icons.create_new_folder_rounded,
            title: 'Create folder...',
          ),
        ),
      ],
      child: AnimatedOpacity(
        opacity: disabled ? 0.58 : 1,
        duration: AppMotion.quick,
        child: Container(
          height: 42,
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: CodexColors.panelHigh.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: CodexColors.text.withValues(alpha: AppOpacity.border),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.028),
                blurRadius: 0,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.folder_open_rounded,
                size: 17,
                color: CodexColors.muted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  activeWorkspace?.displayName ?? 'Workspace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: CodexColors.text),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: CodexColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSelection(BuildContext context, String value) async {
    if (value == _addWorkspaceAction) {
      await _showWorkspaceDialog(context, create: false);
      return;
    }
    if (value == _createWorkspaceAction) {
      await _showWorkspaceDialog(context, create: true);
      return;
    }
    controller.switchWorkspace(value);
  }

  Future<void> _showWorkspaceDialog(
    BuildContext context, {
    required bool create,
  }) async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => _WorkspacePathDialog(create: create),
    );
    if (!context.mounted || path == null || path.trim().isEmpty) return;
    controller.addWorkspacePath(path, create: create);
  }
}

class _WorkspaceActionMenuItem extends StatelessWidget {
  const _WorkspaceActionMenuItem({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: CodexColors.muted),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
      ],
    );
  }
}

class _WorkspacePathDialog extends StatefulWidget {
  const _WorkspacePathDialog({required this.create});

  final bool create;

  @override
  State<_WorkspacePathDialog> createState() => _WorkspacePathDialogState();
}

class _WorkspacePathDialogState extends State<_WorkspacePathDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.create ? 'Create folder' : 'Add folder';
    return AlertDialog(
      title: Text(title),
      content: TextField(
        key: const ValueKey('workspace-path-input'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Path',
          hintText: widget.create
              ? '/home/kurisu/projects/new-task'
              : '/home/kurisu/projects/existing',
        ),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _submit(_controller.text),
          child: Text(widget.create ? 'Create' : 'Add'),
        ),
      ],
    );
  }

  void _submit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(trimmed);
  }
}

class _WorkspaceMenuItem extends StatelessWidget {
  const _WorkspaceMenuItem({required this.workspace, required this.active});

  final WorkspaceInfo workspace;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: CodexColors.text);
    final subtitleStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: CodexColors.dim,
      fontWeight: FontWeight.w600,
    );
    return Row(
      children: [
        Icon(
          active ? Icons.check_circle_rounded : Icons.folder_rounded,
          color: active ? CodexColors.greenSoft : CodexColors.muted,
          size: 17,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workspace.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                workspace.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
