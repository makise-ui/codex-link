import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<AppController>();
      controller.refreshWorkspaces();
      controller.refreshExternalSessions();
      controller.refreshAppModels();
      controller.refreshAppThreads();
      controller.refreshAppSkills();
      controller.listAppDirectory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final hostInfo = controller.hostInfo;
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
                    title: controller.isOffline ? 'Offline' : 'Codex Link',
                    subtitle: controller.statusText,
                    trailing: controller.credentials == null
                        ? null
                        : TextButton(
                            onPressed: controller.reconnect,
                            child: const Text('Reconnect'),
                          ),
                  ),
                  if (hostInfo != null) ...[
                    _SettingRow(
                      icon: hostInfo.connectionMode == 'tunnel'
                          ? Icons.cloud_done_rounded
                          : Icons.lan_rounded,
                      title: 'Connection mode',
                      subtitle: _hostModeLabel(hostInfo),
                    ),
                    if (hostInfo.publicUrl?.isNotEmpty == true)
                      _SettingRow(
                        icon: Icons.public_rounded,
                        title: 'Public URL',
                        subtitle: hostInfo.publicUrl!,
                      ),
                    if (hostInfo.localUrl.isNotEmpty)
                      _SettingRow(
                        icon: Icons.router_rounded,
                        title: 'Local bridge',
                        subtitle: hostInfo.localUrl,
                      ),
                    _SettingRow(
                      icon: Icons.info_outline_rounded,
                      title: 'Host protocol',
                      subtitle:
                          'v${hostInfo.version} - yolo ${hostInfo.yoloAllowed ? 'allowed' : 'disabled'}',
                    ),
                  ],
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
                title: 'Model',
                children: [_ModelConfigSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'App-server sessions',
                children: [_AppThreadSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'Skills',
                children: [_SkillSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'Files',
                children: [_AppFileSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'Review',
                children: [_ReviewSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'Appearance',
                children: [_AccentPicker(controller: controller)],
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

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.controller});

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
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final entry in accentColorOptions.entries)
            ChoiceChip(
              label: Text(accentLabelForName(entry.key)),
              selected: controller.accentName == entry.key,
              avatar: DecoratedBox(
                decoration: BoxDecoration(
                  color: entry.value,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: const SizedBox.square(dimension: 13),
              ),
              onSelected: (_) => controller.setAccentName(entry.key),
              visualDensity: VisualDensity.compact,
              backgroundColor: CodexColors.panelHigh,
              selectedColor: entry.value.withValues(alpha: 0.16),
              side: BorderSide(
                color: controller.accentName == entry.key
                    ? entry.value.withValues(alpha: 0.46)
                    : CodexColors.borderSoft,
              ),
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

String _parentPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
  if (parts.isEmpty) return '';
  parts.removeLast();
  return parts.join('/');
}

class _ModelConfigSection extends StatefulWidget {
  const _ModelConfigSection({required this.controller});

  final AppController controller;

  @override
  State<_ModelConfigSection> createState() => _ModelConfigSectionState();
}

class _ModelConfigSectionState extends State<_ModelConfigSection> {
  late final TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(
      text: widget.controller.activeSession?.model ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _ModelConfigSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.controller.activeSession?.model ?? '';
    if (_modelController.text != next &&
        oldWidget.controller.activeSession?.sessionId !=
            widget.controller.activeSession?.sessionId) {
      _modelController.text = next;
    }
  }

  @override
  void dispose() {
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.activeSession;
    final selectedModel = widget.controller.appModels
        .where(
          (model) =>
              model.id == session?.model || model.model == session?.model,
        )
        .firstOrNull;
    final effort =
        session?.reasoningEffort ??
        selectedModel?.defaultReasoningEffort ??
        'medium';
    final effortOptions =
        selectedModel?.supportedReasoningEfforts.isNotEmpty == true
        ? selectedModel!.supportedReasoningEfforts
        : const ['low', 'medium', 'high', 'xhigh'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.controller.appModels.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue:
                  widget.controller.appModels.any(
                    (model) => model.id == _modelController.text,
                  )
                  ? _modelController.text
                  : null,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.auto_awesome_rounded),
                labelText: 'Available models',
              ),
              items: [
                for (final model in widget.controller.appModels)
                  DropdownMenuItem(
                    value: model.id,
                    child: Text(model.displayName),
                  ),
              ],
              onChanged: widget.controller.isRunning
                  ? null
                  : (value) {
                      if (value == null) return;
                      final model = widget.controller.appModels
                          .where((item) => item.id == value)
                          .firstOrNull;
                      _modelController.text = value;
                      _save(model?.defaultReasoningEffort ?? effort);
                    },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            controller: _modelController,
            enabled: !widget.controller.isRunning,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.memory_rounded),
              hintText: 'Default from Codex CLI',
              labelText: 'Model',
            ),
            onSubmitted: (_) => _save(effort),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final value in effortOptions)
                ChoiceChip(
                  label: Text(value),
                  selected: effort == value,
                  onSelected: widget.controller.isRunning
                      ? null
                      : (_) => _save(value),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: CodexColors.panelHigh,
                  selectedColor: CodexColors.green.withValues(alpha: 0.18),
                  side: BorderSide(
                    color: effort == value
                        ? CodexColors.greenSoft.withValues(alpha: 0.36)
                        : CodexColors.borderSoft,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: widget.controller.isRunning
                  ? null
                  : () => _save(effort),
              icon: const Icon(Icons.check_rounded, size: 17),
              label: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }

  void _save(String effort) {
    widget.controller.setSessionConfig(
      model: _modelController.text,
      reasoningEffort: effort,
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

String _hostModeLabel(HostInfo hostInfo) {
  if (hostInfo.connectionMode == 'tunnel') {
    final provider = hostInfo.tunnelProvider;
    return provider == null || provider.isEmpty
        ? 'Tunnel'
        : 'Tunnel via $provider';
  }
  return 'Local';
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
