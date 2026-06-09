import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

enum SettingsSection {
  connection,
  account,
  env,
  updates,
  mode,
  model,
  appearance,
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initialSection});

  final SettingsSection? initialSection;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Map<SettingsSection, GlobalKey> _sectionKeys = {
    for (final section in SettingsSection.values) section: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<AppController>();
      controller.refreshAppModels();
      controller.refreshCodexAccount();
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
                key: _sectionKeys[SettingsSection.connection],
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
                key: _sectionKeys[SettingsSection.account],
                title: 'Codex Account',
                children: [_CodexAccountSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[SettingsSection.mode],
                title: 'Mode',
                children: [_RunModeSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[SettingsSection.model],
                title: 'Model',
                children: [_ModelConfigSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[SettingsSection.appearance],
                title: 'Appearance',
                children: [
                  _ThemeModePicker(controller: controller),
                  _AccentPicker(controller: controller),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[SettingsSection.env],
                title: 'Env Secrets',
                children: [_EnvSecretsSection(controller: controller)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                key: _sectionKeys[SettingsSection.updates],
                title: 'Updates',
                children: [_UpdateSection(controller: controller)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateSection extends StatelessWidget {
  const _UpdateSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final update = controller.availableUpdate;
    final checking = controller.updateStatus == UpdateCheckStatus.checking;
    final hasUpdate =
        controller.updateStatus == UpdateCheckStatus.available &&
        update?.hasUpdate == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          _SettingRow(
            icon: hasUpdate
                ? Icons.system_update_alt_rounded
                : Icons.system_update_rounded,
            title: _updateTitle(controller.updateStatus, update),
            subtitle: _updateSubtitle(
              controller.updateStatus,
              update,
              controller.updateErrorText,
            ),
            trailing: checking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : hasUpdate
                ? FilledButton.tonal(
                    onPressed: controller.openAvailableUpdate,
                    child: const Text('Download APK'),
                  )
                : TextButton(
                    onPressed: () => controller.checkForUpdates(),
                    child: const Text('Check'),
                  ),
          ),
          if (hasUpdate)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => controller.checkForUpdates(),
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Check again'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CodexAccountSection extends StatelessWidget {
  const _CodexAccountSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final account = controller.codexAccount;
    final login = controller.activeCodexLogin;
    final signedIn = account?.isSignedIn == true;
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
          _SettingRow(
            icon: signedIn
                ? Icons.verified_user_rounded
                : Icons.person_off_rounded,
            title: account?.email?.trim().isNotEmpty == true
                ? account!.email!.trim()
                : account?.displayLabel ?? 'Not signed in',
            subtitle: _accountSubtitle(account),
            trailing: controller.codexAccountBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: () =>
                        controller.refreshCodexAccount(refreshToken: true),
                    child: const Text('Refresh'),
                  ),
          ),
          if (controller.codexAccountErrorText?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                controller.codexAccountErrorText!.trim(),
                style: const TextStyle(color: CodexColors.danger),
              ),
            ),
          if (login != null) ...[
            _ActiveLoginCard(controller: controller, login: login),
            const SizedBox(height: AppSpacing.sm),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: controller.codexAccountBusy
                    ? null
                    : controller.startCodexDeviceLogin,
                icon: const Icon(Icons.password_rounded, size: 17),
                label: const Text('Device code'),
              ),
              OutlinedButton.icon(
                onPressed: controller.codexAccountBusy
                    ? null
                    : controller.startCodexBrowserLogin,
                icon: const Icon(Icons.open_in_browser_rounded, size: 17),
                label: const Text('Browser'),
              ),
              OutlinedButton.icon(
                onPressed: controller.codexAccountBusy
                    ? null
                    : () => _showApiKeyDialog(context, controller),
                icon: const Icon(Icons.key_rounded, size: 17),
                label: const Text('API key'),
              ),
              if (signedIn)
                TextButton.icon(
                  onPressed: controller.codexAccountBusy
                      ? null
                      : controller.logoutCodexAccount,
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: const Text('Logout'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveLoginCard extends StatelessWidget {
  const _ActiveLoginCard({required this.controller, required this.login});

  final AppController controller;
  final CodexAccountLoginFlow login;

  @override
  Widget build(BuildContext context) {
    final url = login.verificationUrl ?? login.authUrl;
    final code = login.userCode;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: codexComposerColor(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: CodexColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                login.isDeviceCode
                    ? Icons.password_rounded
                    : Icons.open_in_browser_rounded,
                size: 18,
                color: codexMutedColor(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  login.isDeviceCode ? 'Device login' : 'Browser login',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (login.loginId?.isNotEmpty == true)
                IconButton(
                  tooltip: 'Cancel login',
                  onPressed: () => controller.cancelCodexLogin(login.loginId!),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
          if (code?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              code!,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 0,
              ),
            ),
          ],
          if (url?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              url!,
              style: TextStyle(
                color: codexMutedColor(context),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openUrl(url),
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: const Text('Open'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showApiKeyDialog(
  BuildContext context,
  AppController controller,
) async {
  final apiKey = await showDialog<String>(
    context: context,
    builder: (context) => const _ApiKeyDialog(),
  );
  if (apiKey == null) return;
  controller.loginCodexWithApiKey(apiKey);
}

class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog();

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_keyController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('API key'),
      content: TextField(
        controller: _keyController,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.key_rounded),
          labelText: 'OpenAI API key',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _EnvSecretsSection extends StatelessWidget {
  const _EnvSecretsSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final workspace = controller.activeSession?.workdir ?? 'No workspace';
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
          _SettingRow(
            icon: Icons.enhanced_encryption_rounded,
            title: '.env.local',
            subtitle: controller.envSecretsStatusText ?? workspace,
            trailing: controller.envSecretsBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonalIcon(
                    onPressed: controller.isConnected
                        ? () => _showEnvSecretsDialog(context, controller)
                        : null,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Add'),
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showEnvSecretsDialog(
  BuildContext context,
  AppController controller,
) async {
  final content = await showDialog<String>(
    context: context,
    builder: (context) => const _EnvSecretsDialog(),
  );
  if (content == null || content.trim().isEmpty) return;
  controller.setWorkspaceEnvSecrets(content);
}

class _EnvSecretsDialog extends StatefulWidget {
  const _EnvSecretsDialog();

  @override
  State<_EnvSecretsDialog> createState() => _EnvSecretsDialogState();
}

class _EnvSecretsDialogState extends State<_EnvSecretsDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Env secrets'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 6,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.key_rounded),
            labelText: 'NAME=value',
            hintText: 'OPENAI_API_KEY=...\nALLOWED_HOSTS=one,two',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

Future<void> _openUrl(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _accountSubtitle(CodexAccountInfo? account) {
  if (account == null) return 'Host Codex account status is unknown.';
  final parts = [
    if (account.authMode?.trim().isNotEmpty == true) 'auth ${account.authMode}',
    if (account.planType?.trim().isNotEmpty == true) 'plan ${account.planType}',
    'limits unavailable',
    account.requiresOpenaiAuth ? 'auth required' : 'ready',
  ];
  return parts.join(' · ');
}

String _updateTitle(UpdateCheckStatus status, AppUpdateInfo? update) {
  if (status == UpdateCheckStatus.available && update != null) {
    return update.title;
  }
  return switch (status) {
    UpdateCheckStatus.checking => 'Checking for updates',
    UpdateCheckStatus.current => 'Codex Link is up to date',
    UpdateCheckStatus.failed => 'Update check failed',
    _ => 'App updates',
  };
}

String _updateSubtitle(
  UpdateCheckStatus status,
  AppUpdateInfo? update,
  String? errorText,
) {
  if (update != null) {
    final target = update.hasUpdate ? 'Latest' : 'Current';
    return 'Installed ${update.currentVersion} - $target ${update.latestVersion}';
  }
  return switch (status) {
    UpdateCheckStatus.failed =>
      errorText?.trim().isNotEmpty == true
          ? errorText!.trim()
          : 'Could not reach the latest GitHub release.',
    _ => 'Checks GitHub Releases and opens the latest APK when available.',
  };
}

class _RunModeSection extends StatelessWidget {
  const _RunModeSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.activeSession;
    final yoloAllowed = controller.hostInfo?.yoloAllowed == true;
    final yoloEnabled = session?.mode == RunMode.yolo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey('run-mode-yolo-switch'),
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              yoloEnabled ? Icons.warning_amber_rounded : Icons.shield_outlined,
              color: yoloEnabled ? CodexColors.amber : CodexColors.muted,
            ),
            title: const Text('Yolo mode'),
            subtitle: Text(
              yoloAllowed
                  ? 'Use danger-full-access for future prompts in this session.'
                  : 'Restart the host with yolo allowed to enable this.',
              style: const TextStyle(color: CodexColors.muted),
            ),
            value: yoloEnabled,
            onChanged: !yoloAllowed || controller.isRunning
                ? null
                : controller.setYolo,
          ),
          const Divider(height: 1, color: CodexColors.borderSoft),
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_open_rounded),
            title: Text(yoloEnabled ? 'Danger full access' : 'Safe mode'),
            subtitle: Text(
              session?.sandbox ?? 'workspace-write',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
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

class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          ChoiceChip(
            key: const ValueKey('theme-mode-dark'),
            label: const Text('Dark'),
            avatar: const Icon(Icons.dark_mode_rounded, size: 16),
            selected: controller.themeName == 'dark',
            onSelected: (_) => controller.setThemeName('dark'),
            visualDensity: VisualDensity.compact,
            backgroundColor: CodexColors.panelHigh,
            selectedColor: CodexColors.text.withValues(alpha: 0.14),
            side: BorderSide(
              color: controller.themeName == 'dark'
                  ? CodexColors.text.withValues(alpha: 0.38)
                  : CodexColors.borderSoft,
            ),
          ),
          ChoiceChip(
            key: const ValueKey('theme-mode-light'),
            label: const Text('Light'),
            avatar: const Icon(Icons.light_mode_rounded, size: 16),
            selected: controller.themeName == 'light',
            onSelected: (_) => controller.setThemeName('light'),
            visualDensity: VisualDensity.compact,
            backgroundColor: CodexColors.panelHigh,
            selectedColor: CodexColors.amber.withValues(alpha: 0.16),
            side: BorderSide(
              color: controller.themeName == 'light'
                  ? CodexColors.amber.withValues(alpha: 0.48)
                  : CodexColors.borderSoft,
            ),
          ),
        ],
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
                    color: CodexColors.text.withValues(alpha: 0.18),
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
