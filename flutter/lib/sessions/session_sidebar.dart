import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../theme/app_theme.dart';

class SessionSidebar extends StatelessWidget {
  const SessionSidebar({super.key, this.onPicked});

  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return SafeArea(
      child: Container(
        width: 340,
        color: CodexColors.ink,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
              child: Row(
                children: [
                  Text('Codex', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  ChatGptActionPill(
                    children: [
                      IconButton(onPressed: null, icon: const Icon(Icons.search_rounded, size: 28)),
                      IconButton(onPressed: controller.createSession, icon: const Icon(Icons.edit_square, size: 24)),
                    ],
                  ),
                ],
              ),
            ),
            _NavRow(icon: Icons.folder_outlined, label: 'Workspaces', onTap: () {}),
            _NavRow(icon: Icons.terminal_rounded, label: 'Commands', onTap: () => _showCommands(context, controller)),
            _NavRow(icon: Icons.code_rounded, label: 'Codex', onTap: () {}),
            _NavRow(icon: Icons.more_horiz_rounded, label: 'More', onTap: () {}),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 28, 22, 10),
              child: Text('Recents', style: TextStyle(color: CodexColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: controller.sessions.length,
                itemBuilder: (context, index) {
                  final session = controller.sessions[index];
                  final active = session.sessionId == controller.activeSession?.sessionId;
                  return _SessionRow(
                    session: session,
                    active: active,
                    onTap: () {
                      controller.selectSession(session.sessionId);
                      onPicked?.call();
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WorkspacePicker(controller: controller),
                  const SizedBox(height: 12),
                  _YoloSwitch(controller: controller),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: controller.createSession,
                    icon: const Icon(Icons.edit_square),
                    label: const Text('Chat'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommands(BuildContext context, AppController controller) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CodexColors.panel,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          Text('Commands', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final command in controller.commands)
            ListTile(
              leading: Icon(command.commandId == 'mode.yolo' ? Icons.bolt_rounded : Icons.auto_fix_high_rounded, color: command.commandId == 'mode.yolo' ? CodexColors.danger : CodexColors.text),
              title: Text(command.title),
              subtitle: Text(command.description, style: const TextStyle(color: CodexColors.muted)),
              onTap: () {
                Navigator.pop(context);
                controller.runCommand(command);
              },
            ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 28, color: CodexColors.text),
            const SizedBox(width: 22),
            Text(label, style: const TextStyle(color: CodexColors.text, fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.active, required this.onTap});

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
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          child: Row(
            children: [
              Expanded(child: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, color: CodexColors.text))),
              if (session.isRunning) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox.square(dimension: 8, child: DecoratedBox(decoration: BoxDecoration(color: CodexColors.blue, shape: BoxShape.circle)))),
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

  @override
  Widget build(BuildContext context) {
    final activeWorkspace = controller.workspaces.where((workspace) => workspace.workspaceId == controller.activeSession?.workspaceId).firstOrNull ?? (controller.workspaces.isEmpty ? null : controller.workspaces.first);
    if (controller.workspaces.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: CodexColors.panelHigh, borderRadius: BorderRadius.circular(18), border: Border.all(color: CodexColors.borderSoft)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: activeWorkspace?.workspaceId,
          dropdownColor: CodexColors.panelHigh,
          iconEnabledColor: CodexColors.muted,
          items: [
            for (final workspace in controller.workspaces)
              DropdownMenuItem(value: workspace.workspaceId, child: Text(workspace.label, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: controller.isRunning ? null : (value) => value == null ? null : controller.switchWorkspace(value),
        ),
      ),
    );
  }
}

class _YoloSwitch extends StatelessWidget {
  const _YoloSwitch({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.activeSession?.mode == RunMode.yolo;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(color: CodexColors.panelHigh, borderRadius: BorderRadius.circular(18), border: Border.all(color: enabled ? CodexColors.danger : CodexColors.borderSoft)),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, color: enabled ? CodexColors.danger : CodexColors.muted),
          const SizedBox(width: 10),
          const Expanded(child: Text('Yolo mode', style: TextStyle(fontWeight: FontWeight.w700))),
          Switch(value: enabled, activeThumbColor: CodexColors.danger, onChanged: controller.isRunning ? null : controller.setYolo),
        ],
      ),
    );
  }
}
