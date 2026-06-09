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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<AppController>();
      controller.refreshAppThreads(limit: 40);
      controller.refreshExternalSessions();
    });
  }

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
    final appThreads = query.isEmpty
        ? controller.appThreads
        : controller.appThreads
              .where(
                (thread) =>
                    thread.title.toLowerCase().contains(query) ||
                    thread.workdir.toLowerCase().contains(query) ||
                    thread.preview.toLowerCase().contains(query),
              )
              .toList(growable: false);
    final externalSessions = query.isEmpty
        ? controller.externalSessions
        : controller.externalSessions
              .where(
                (session) =>
                    session.title.toLowerCase().contains(query) ||
                    session.workdir.toLowerCase().contains(query),
              )
              .toList(growable: false);
    final sidebarColor = isCodexLight(context)
        ? LightCodexColors.panelHigh
        : CodexColors.ink2;
    return SafeArea(
      child: Container(
        width: 288,
        decoration: BoxDecoration(
          color: sidebarColor,
          border: Border(
            right: BorderSide(
              color: codexDimColor(context).withValues(alpha: 0.12),
            ),
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
                  cursorColor: codexTextColor(context),
                  decoration: InputDecoration(
                    hintText: 'Search sessions',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    filled: true,
                    fillColor: codexPanelHighColor(
                      context,
                    ).withValues(alpha: isCodexLight(context) ? 0.86 : 0.54),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Recents',
                style: TextStyle(
                  color: codexMutedColor(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final session in sessions)
                    _SessionRow(
                      session: session,
                      active:
                          session.sessionId ==
                          controller.activeSession?.sessionId,
                      onTap: () {
                        controller.selectSession(session.sessionId);
                        widget.onPicked?.call();
                      },
                    ),
                  if (appThreads.isNotEmpty || externalSessions.isNotEmpty)
                    _CodexSessionSection(
                      appThreads: appThreads,
                      externalSessions: externalSessions,
                      onImportThread: (thread) {
                        controller.importAppThread(thread);
                        widget.onPicked?.call();
                      },
                      onImportExternal: (session) {
                        controller.importExternalSession(session);
                        widget.onPicked?.call();
                      },
                      onRefresh: () {
                        controller.refreshAppThreads(
                          query: _searchController.text,
                          limit: 40,
                        );
                        controller.refreshExternalSessions();
                      },
                    ),
                  if (sessions.isEmpty &&
                      appThreads.isEmpty &&
                      externalSessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        query.isEmpty
                            ? 'No sessions yet.'
                            : 'No matching sessions.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: codexMutedColor(context),
                        ),
                      ),
                    ),
                ],
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
        : codexMutedColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: codexPanelHighColor(context).withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: codexDimColor(context).withValues(alpha: AppOpacity.border),
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
              ).textTheme.labelLarge?.copyWith(color: codexTextColor(context)),
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
    final textColor = codexTextColor(context);
    final dimColor = codexDimColor(context);
    return Material(
      color: active
          ? codexPanelHighColor(context).withValues(alpha: 0.72)
          : Colors.transparent,
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
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor,
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
                  style: TextStyle(
                    color: dimColor,
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

class _CodexSessionSection extends StatelessWidget {
  const _CodexSessionSection({
    required this.appThreads,
    required this.externalSessions,
    required this.onImportThread,
    required this.onImportExternal,
    required this.onRefresh,
  });

  final List<AppThreadInfo> appThreads;
  final List<ExternalSessionInfo> externalSessions;
  final ValueChanged<AppThreadInfo> onImportThread;
  final ValueChanged<ExternalSessionInfo> onImportExternal;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final total = appThreads.length + externalSessions.length;
    if (total == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('system-codex-sessions'),
          initiallyExpanded: appThreads.isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
          leading: Icon(
            Icons.history_rounded,
            size: 18,
            color: codexMutedColor(context),
          ),
          title: Text(
            'System Codex',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: codexTextColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            '$total importable ${total == 1 ? 'session' : 'sessions'}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: codexDimColor(context)),
          ),
          trailing: IconButton(
            tooltip: 'Refresh Codex sessions',
            icon: const Icon(Icons.refresh_rounded, size: 18),
            onPressed: onRefresh,
          ),
          children: [
            for (final thread in appThreads.take(8))
              _ImportableCodexThreadRow(
                thread: thread,
                onTap: () => onImportThread(thread),
              ),
            for (final session in externalSessions.take(8))
              _ImportableExternalSessionRow(
                session: session,
                onTap: () => onImportExternal(session),
              ),
            if (total > 16)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  0,
                ),
                child: Text(
                  'Search to narrow ${total - 16} more sessions.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: codexDimColor(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImportableCodexThreadRow extends StatelessWidget {
  const _ImportableCodexThreadRow({required this.thread, required this.onTap});

  final AppThreadInfo thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ImportableSessionRow(
      icon: Icons.account_tree_outlined,
      title: thread.title,
      subtitle: _sessionSubtitle(thread.workdir, thread.preview),
      source: thread.source?.trim().isNotEmpty == true
          ? thread.source!.trim()
          : 'app-server',
      onTap: onTap,
    );
  }
}

class _ImportableExternalSessionRow extends StatelessWidget {
  const _ImportableExternalSessionRow({
    required this.session,
    required this.onTap,
  });

  final ExternalSessionInfo session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ImportableSessionRow(
      icon: Icons.terminal_rounded,
      title: session.title,
      subtitle: _sessionSubtitle(session.workdir, session.codexThreadId),
      source: '~/.codex',
      onTap: onTap,
    );
  }
}

class _ImportableSessionRow extends StatelessWidget {
  const _ImportableSessionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.source,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: codexMutedColor(context)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.trim().isEmpty ? 'Codex session' : title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: codexTextColor(context),
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty)
                      Text(
                        subtitle.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: codexDimColor(context),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              SoftPill(label: source, color: codexMutedColor(context)),
            ],
          ),
        ),
      ),
    );
  }
}

String _sessionSubtitle(String workdir, String fallback) {
  final cleanWorkdir = workdir.trim();
  if (cleanWorkdir.isNotEmpty) return _shortPath(cleanWorkdir);
  return fallback.trim();
}

String _shortPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (parts.length <= 2) return normalized;
  return '${parts[parts.length - 2]}/${parts.last}';
}

class _WorkspacePicker extends StatelessWidget {
  const _WorkspacePicker({required this.controller});

  final AppController controller;
  static const _addWorkspaceAction = '__add_workspace__';
  static const _createWorkspaceAction = '__create_workspace__';
  static const _cloneWorkspaceAction = '__clone_workspace__';

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
      color: codexPanelHighColor(context).withValues(alpha: 0.98),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: CodexColors.ink.withValues(alpha: 0.38),
      offset: const Offset(0, -8),
      constraints: const BoxConstraints(minWidth: 252, maxWidth: 280),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: codexDimColor(context).withValues(alpha: AppOpacity.border),
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
            title: 'Add folder or URL...',
          ),
        ),
        const PopupMenuItem<String>(
          value: _cloneWorkspaceAction,
          height: 44,
          child: _WorkspaceActionMenuItem(
            icon: Icons.cloud_download_rounded,
            title: 'Clone GitHub URL...',
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
            color: codexPanelHighColor(context).withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: codexDimColor(
                context,
              ).withValues(alpha: AppOpacity.border),
            ),
            boxShadow: [
              BoxShadow(
                color: CodexColors.ink.withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 17,
                color: codexMutedColor(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  activeWorkspace?.displayName ?? 'Workspace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: codexTextColor(context),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: codexMutedColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSelection(BuildContext context, String value) async {
    if (value == _addWorkspaceAction) {
      await _showWorkspaceDialog(context, create: false, clone: false);
      return;
    }
    if (value == _cloneWorkspaceAction) {
      await _showWorkspaceDialog(context, create: false, clone: true);
      return;
    }
    if (value == _createWorkspaceAction) {
      await _showWorkspaceDialog(context, create: true, clone: false);
      return;
    }
    controller.switchWorkspace(value);
  }

  Future<void> _showWorkspaceDialog(
    BuildContext context, {
    required bool create,
    required bool clone,
  }) async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => _WorkspacePathDialog(create: create, clone: clone),
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
        Icon(icon, size: 17, color: codexMutedColor(context)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
      ],
    );
  }
}

class _WorkspacePathDialog extends StatefulWidget {
  const _WorkspacePathDialog({required this.create, required this.clone});

  final bool create;
  final bool clone;

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
    final title = widget.clone
        ? 'Clone GitHub URL'
        : widget.create
        ? 'Create folder'
        : 'Add workspace';
    return AlertDialog(
      title: Text(title),
      content: TextField(
        key: const ValueKey('workspace-path-input'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.clone ? 'Git URL' : 'Path or Git URL',
          hintText: widget.clone
              ? 'https://github.com/user/repo'
              : widget.create
              ? '/home/kurisu/projects/new-task'
              : '/home/kurisu/projects/existing or GitHub URL',
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
          child: Text(
            widget.clone
                ? 'Clone'
                : widget.create
                ? 'Create'
                : 'Add',
          ),
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
    ).textTheme.labelLarge?.copyWith(color: codexTextColor(context));
    final subtitleStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: codexDimColor(context),
      fontWeight: FontWeight.w600,
    );
    return Row(
      children: [
        Icon(
          active ? Icons.check_circle_rounded : Icons.folder_rounded,
          color: active
              ? Theme.of(context).colorScheme.secondary
              : codexMutedColor(context),
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
