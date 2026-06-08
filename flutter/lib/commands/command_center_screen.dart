import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../theme/app_theme.dart';

enum CommandCenterSection {
  commands,
  approvals,
  workspace,
  sessions,
  files,
  skills,
  review,
  diagnostics,
}

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({super.key, this.initialSection});

  final CommandCenterSection? initialSection;

  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  late final Map<CommandCenterSection, GlobalKey> _sectionKeys = {
    for (final section in CommandCenterSection.values) section: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<AppController>();
      controller.refreshWorkspaces();
      controller.refreshExternalSessions();
      controller.refreshAppThreads();
      controller.refreshAppSkills();
      controller.listAppDirectory();
      final target = widget.initialSection;
      final sectionContext = target == null
          ? null
          : _sectionKeys[target]?.currentContext;
      if (sectionContext != null) {
        Scrollable.ensureVisible(
          sectionContext,
          duration: AppMotion.scroll,
          curve: Curves.easeInOutCubic,
          alignment: 0.08,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return AnimatedChatGptBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Commands'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () {
                controller.refreshWorkspaces();
                controller.refreshExternalSessions();
                controller.refreshAppThreads();
                controller.refreshAppSkills(forceReload: true);
                controller.listAppDirectory(controller.appFilePath);
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _Section(
                key: _sectionKeys[CommandCenterSection.commands],
                title: 'Commands',
                children: [_CommandCatalogSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[CommandCenterSection.approvals],
                title: 'Approvals',
                children: [_ApprovalSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[CommandCenterSection.workspace],
                title: 'Workspace',
                children: [
                  _AddWorkspaceRow(controller: controller),
                  for (final workspace in controller.workspaces)
                    _WorkspaceRow(controller: controller, workspace: workspace),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[CommandCenterSection.sessions],
                title: 'App-server sessions',
                children: [_AppThreadSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'External Codex sessions',
                children: [_ExternalSessionsSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[CommandCenterSection.files],
                title: 'Files',
                children: [_AppFileSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[CommandCenterSection.skills],
                title: 'Skills',
                children: [_SkillSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[CommandCenterSection.review],
                title: 'Review',
                children: [_ReviewSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[CommandCenterSection.diagnostics],
                title: 'Diagnostics',
                children: [_DiagnosticsSection(controller: controller)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandCatalogSection extends StatelessWidget {
  const _CommandCatalogSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final commands = controller.commands
        .where((command) => command.category != 'mode')
        .toList(growable: false);
    if (commands.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.keyboard_command_key_rounded),
        title: Text('No commands reported'),
      );
    }
    return Column(
      children: [
        for (final command in commands)
          ListTile(
            dense: true,
            leading: const Icon(Icons.keyboard_command_key_rounded),
            title: Text(_slashCommandName(command)),
            subtitle: Text(
              command.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.play_arrow_rounded, size: 17),
            onTap: controller.isConnected
                ? () => controller.runCommand(command)
                : null,
          ),
      ],
    );
  }
}

class _ApprovalSection extends StatelessWidget {
  const _ApprovalSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final approvals = controller.pendingApprovals;
    if (approvals.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.verified_user_outlined),
        title: Text('No approvals pending'),
      );
    }
    return Column(
      children: [
        for (final message in approvals)
          _ApprovalTile(controller: controller, message: message),
      ],
    );
  }
}

class _ApprovalTile extends StatelessWidget {
  const _ApprovalTile({required this.controller, required this.message});

  final AppController controller;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final approval = ApprovalRequestInfo.fromText(
      message.text,
      fallbackTitle: message.title,
    );
    return ListTile(
      dense: true,
      leading: const Icon(Icons.verified_user_outlined),
      title: Text(approval.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        approval.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: AppSpacing.xs,
        children: [
          TextButton(
            onPressed: approval.approvalId.isEmpty
                ? null
                : () => controller.decideApproval(
                    approval.approvalId,
                    'reject',
                  ),
            child: const Text('Reject'),
          ),
          FilledButton(
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
    );
  }
}

class _AppThreadSection extends StatelessWidget {
  const _AppThreadSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${controller.appThreads.length} native sessions',
                  style: const TextStyle(
                    color: CodexColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => controller.refreshAppThreads(),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        if (controller.appThreads.isEmpty)
          const ListTile(
            leading: Icon(Icons.history_toggle_off_rounded),
            title: Text('No app-server sessions loaded'),
          )
        else
          for (final thread in controller.appThreads.take(30))
            ListTile(
              dense: true,
              leading: const Icon(Icons.forum_outlined),
              title: Text(
                thread.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                thread.workdir,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              trailing: const Icon(Icons.call_made_rounded, size: 17),
              onTap: () {
                controller.importAppThread(thread);
                Navigator.maybePop(context);
              },
            ),
      ],
    );
  }
}

class _ExternalSessionsSection extends StatelessWidget {
  const _ExternalSessionsSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${controller.externalSessions.length} found in ~/.codex/sessions',
                  style: const TextStyle(
                    color: CodexColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: controller.refreshExternalSessions,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        if (controller.externalSessions.isEmpty)
          const ListTile(
            leading: Icon(Icons.history_toggle_off_rounded),
            title: Text('No external sessions found'),
            subtitle: Text('Run Codex CLI once to create ~/.codex sessions'),
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
    );
  }
}

class _SkillSection extends StatelessWidget {
  const _SkillSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final skills = controller.appSkillGroups
        .expand((group) => group.skills)
        .where((skill) => skill.enabled)
        .toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${skills.length} enabled',
                  style: const TextStyle(
                    color: CodexColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => controller.refreshAppSkills(forceReload: true),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Reload'),
              ),
            ],
          ),
        ),
        if (skills.isEmpty)
          const ListTile(
            leading: Icon(Icons.extension_off_rounded),
            title: Text('No skills reported'),
          )
        else
          for (final skill in skills.take(24))
            ListTile(
              dense: true,
              leading: const Icon(Icons.extension_rounded),
              title: Text(
                skill.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                skill.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
      ],
    );
  }
}

class _AppFileSection extends StatelessWidget {
  const _AppFileSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.appPreviewFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  controller.appFilePath.isEmpty ? '/' : controller.appFilePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CodexColors.muted,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Parent folder',
                onPressed: controller.appFilePath.isEmpty
                    ? null
                    : () => controller.listAppDirectory(
                        _parentPath(controller.appFilePath),
                      ),
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              IconButton(
                tooltip: 'Refresh files',
                onPressed: () =>
                    controller.listAppDirectory(controller.appFilePath),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        for (final entry in controller.appFileEntries.take(32))
          ListTile(
            dense: true,
            leading: Icon(
              entry.isDirectory
                  ? Icons.folder_rounded
                  : Icons.insert_drive_file_outlined,
            ),
            title: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              entry.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => entry.isDirectory
                ? controller.listAppDirectory(entry.path)
                : controller.readAppFile(entry.path),
          ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: CodexColors.ink2.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: CodexColors.borderSoft),
              ),
              child: Text(
                preview.text?.trim().isNotEmpty == true
                    ? preview.text!.trim()
                    : '${preview.name}\n${preview.sizeBytes} bytes',
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CodexColors.muted,
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Run native app-server review for current workspace changes.',
              style: TextStyle(color: CodexColors.muted, fontSize: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: controller.isRunning
                ? null
                : () => controller.startReview(),
            icon: const Icon(Icons.rate_review_outlined, size: 17),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final doctorCommand = controller.commands
        .where((command) => command.commandId == 'codex.doctor')
        .firstOrNull;
    return Column(
      children: [
        const ListTile(
          dense: true,
          leading: Icon(Icons.health_and_safety_outlined),
          title: Text('Codex CLI health'),
          subtitle: Text(
            'Usage-limit numbers are not exposed by this Codex CLI. /doctor runs the supported local health check.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: doctorCommand == null
                  ? null
                  : () => controller.runCommand(doctorCommand),
              icon: const Icon(Icons.play_arrow_rounded, size: 17),
              label: const Text('Run /doctor'),
            ),
          ),
        ),
      ],
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
          const SizedBox(width: AppSpacing.xs),
          IconButton.filledTonal(
            tooltip: 'Create workspace folder',
            onPressed: widget.controller.isRunning ? null : _create,
            icon: const Icon(Icons.create_new_folder_rounded),
          ),
        ],
      ),
    );
  }

  void _submit() {
    widget.controller.addWorkspacePath(_controller.text);
    _controller.clear();
  }

  void _create() {
    widget.controller.addWorkspacePath(_controller.text, create: true);
    _controller.clear();
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

String _parentPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
  if (parts.isEmpty) return '';
  parts.removeLast();
  return parts.join('/');
}

String _slashCommandName(CodexCommandInfo command) {
  final tail = command.commandId.split('.').last.trim();
  return '/${tail.isEmpty ? command.title.toLowerCase() : tail.toLowerCase()}';
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.children});

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
