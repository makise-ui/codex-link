import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return AnimatedChatGptBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [
            IconButton(
              tooltip: 'Reconnect',
              onPressed: controller.credentials == null
                  ? null
                  : controller.reconnect,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _Section(
                title: 'Connection',
                children: [
                  _SettingRow(
                    icon: controller.isOffline
                        ? Icons.cloud_off_rounded
                        : Icons.cloud_done_rounded,
                    title: controller.isOffline ? 'Offline' : 'Bridge',
                    subtitle: controller.statusText,
                    trailing: controller.credentials == null
                        ? null
                        : TextButton(
                            onPressed: controller.reconnect,
                            child: const Text('Reconnect'),
                          ),
                  ),
                  if (controller.credentials != null)
                    _SettingRow(
                      icon: Icons.link_rounded,
                      title: 'Saved host',
                      subtitle: controller.credentials!.url,
                      trailing: TextButton(
                        onPressed: controller.forgetSaved,
                        child: const Text('Forget'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'Workspace',
                children: [
                  _AddWorkspaceRow(controller: controller),
                  for (final workspace in controller.workspaces)
                    _WorkspaceRow(controller: controller, workspace: workspace),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'All sessions',
                children: [
                  for (final workspace in controller.workspaces)
                    _WorkspaceSessionGroup(
                      workspace: workspace,
                      sessions: controller.sessions
                          .where(
                            (session) =>
                                session.workspaceId == workspace.workspaceId,
                          )
                          .toList(),
                      onPick: (session) {
                        controller.selectSession(session.sessionId);
                        Navigator.maybePop(context);
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'External Codex sessions',
                children: [
                  if (controller.externalSessions.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.history_toggle_off_rounded),
                      title: Text('No external sessions found'),
                      subtitle: Text(
                        'Run Codex CLI once to create ~/.codex sessions',
                      ),
                    )
                  else
                    for (final session in controller.externalSessions.take(40))
                      _ExternalSessionRow(
                        session: session,
                        onImport: () {
                          controller.importExternalSession(session);
                          Navigator.maybePop(context);
                        },
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddWorkspaceRow extends StatefulWidget {
  const _AddWorkspaceRow({required this.controller});

  final AppController controller;

  @override
  State<_AddWorkspaceRow> createState() => _AddWorkspaceRowState();
}

class _AddWorkspaceRowState extends State<_AddWorkspaceRow> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !widget.controller.isRunning,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.create_new_folder_rounded),
                hintText: '/home/kurisu/project',
                labelText: 'Add host folder',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filledTonal(
            tooltip: 'Add workspace',
            onPressed: widget.controller.isRunning ? null : _submit,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  void _submit() {
    widget.controller.addWorkspacePath(_controller.text);
    _controller.clear();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CodexColors.panelHigh.withValues(alpha: AppOpacity.panel),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: CodexColors.text.withValues(alpha: AppOpacity.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: CodexColors.muted),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({required this.controller, required this.workspace});

  final AppController controller;
  final WorkspaceInfo workspace;

  @override
  Widget build(BuildContext context) {
    final active =
        workspace.workspaceId == controller.activeSession?.workspaceId;
    return ListTile(
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: active ? CodexColors.greenSoft : CodexColors.muted,
      ),
      title: Text(workspace.label),
      subtitle: Text(
        workspace.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      onTap: controller.isRunning
          ? null
          : () => controller.switchWorkspace(workspace.workspaceId),
    );
  }
}

class _WorkspaceSessionGroup extends StatelessWidget {
  const _WorkspaceSessionGroup({
    required this.workspace,
    required this.sessions,
    required this.onPick,
  });

  final WorkspaceInfo workspace;
  final List<CodexSessionInfo> sessions;
  final ValueChanged<CodexSessionInfo> onPick;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: workspace.active,
      leading: const Icon(Icons.folder_rounded),
      title: Text(workspace.label),
      subtitle: Text(
        workspace.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      children: [
        if (sessions.isEmpty)
          const ListTile(
            dense: true,
            title: Text('No sessions in this workspace'),
          )
        else
          for (final session in sessions)
            ListTile(
              dense: true,
              title: Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(session.workdir, maxLines: 1),
              onTap: () => onPick(session),
            ),
      ],
    );
  }
}

class _ExternalSessionRow extends StatelessWidget {
  const _ExternalSessionRow({required this.session, required this.onImport});

  final ExternalSessionInfo session;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.history_rounded),
      title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        session.workdir,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      trailing: const Icon(Icons.call_made_rounded, size: 17),
      onTap: onImport,
    );
  }
}
