import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../theme/app_theme.dart';

class AppServerActionsScreen extends StatefulWidget {
  const AppServerActionsScreen({super.key});

  @override
  State<AppServerActionsScreen> createState() => _AppServerActionsScreenState();
}

class _AppServerActionsScreenState extends State<AppServerActionsScreen> {
  static const _initialPluginLimit = 5;
  static const _pluginPageSize = 10;

  final _searchController = TextEditingController();
  int _visiblePluginCount = _initialPluginLimit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppController>().refreshAppServerActions();
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
    final plugins = _filteredPlugins(controller, query);
    return AnimatedChatGptBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('App Server Actions'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: controller.refreshAppServerActions,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              if (controller.appServerActionsErrorText case final error?)
                _InlineNotice(text: error, icon: Icons.error_outline_rounded),
              _PluginsSection(
                controller: controller,
                searchController: _searchController,
                plugins: plugins,
                visibleCount: _visiblePluginCount,
                onLoadMore: () =>
                    setState(() => _visiblePluginCount += _pluginPageSize),
                onSearchChanged: () =>
                    setState(() => _visiblePluginCount = _initialPluginLimit),
              ),
              const SizedBox(height: AppSpacing.md),
              _McpSection(controller: controller),
              const SizedBox(height: AppSpacing.md),
              _RemoteSection(controller: controller),
              const SizedBox(height: AppSpacing.md),
              _HostUpdateSection(controller: controller),
              const SizedBox(height: AppSpacing.md),
              _UsageSection(controller: controller),
              const SizedBox(height: AppSpacing.md),
              _RequestsSection(controller: controller),
            ],
          ),
        ),
      ),
    );
  }

  List<AppPluginSummaryInfo> _filteredPlugins(
    AppController controller,
    String query,
  ) {
    final plugins = controller.appPluginMarketplaces
        .expand((marketplace) => marketplace.plugins)
        .toList(growable: false);
    if (query.isEmpty) return plugins;
    return plugins
        .where(
          (plugin) =>
              plugin.name.toLowerCase().contains(query) ||
              plugin.displayName.toLowerCase().contains(query) ||
              (plugin.description ?? '').toLowerCase().contains(query),
        )
        .toList(growable: false);
  }
}

class _PluginsSection extends StatelessWidget {
  const _PluginsSection({
    required this.controller,
    required this.searchController,
    required this.plugins,
    required this.visibleCount,
    required this.onLoadMore,
    required this.onSearchChanged,
  });

  final AppController controller;
  final TextEditingController searchController;
  final List<AppPluginSummaryInfo> plugins;
  final int visibleCount;
  final VoidCallback onLoadMore;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final selected = controller.appSelectedPlugin;
    final visiblePlugins = plugins.take(visibleCount).toList(growable: false);
    final remaining = plugins.length - visiblePlugins.length;
    return _ActionSection(
      title: 'Plugins',
      icon: Icons.extension_rounded,
      trailing: _TinyButton(
        label: 'Refresh',
        icon: Icons.sync_rounded,
        onPressed: controller.refreshAppPlugins,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: (_) => onSearchChanged(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search plugins',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (plugins.isEmpty)
            const _EmptyLine(text: 'No plugins found.')
          else
            for (final plugin in visiblePlugins)
              _PluginTile(controller: controller, plugin: plugin),
          if (remaining > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: _TinyButton(
                label: 'Load more',
                icon: Icons.expand_more_rounded,
                onPressed: onLoadMore,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Showing ${visiblePlugins.length} of ${plugins.length}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: codexMutedColor(context)),
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: AppSpacing.md),
            _PluginDetail(controller: controller, plugin: selected),
          ],
        ],
      ),
    );
  }
}

class _PluginTile extends StatelessWidget {
  const _PluginTile({required this.controller, required this.plugin});

  final AppController controller;
  final AppPluginSummaryInfo plugin;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.extension_rounded, color: accent, size: 20),
      title: Text(plugin.displayName),
      subtitle: Text(
        plugin.description ?? plugin.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SoftPill(
        label: plugin.installed ? 'Installed' : 'Available',
        color: plugin.installed ? accent : codexMutedColor(context),
      ),
      onTap: () => controller.readAppPlugin(
        plugin.name,
        marketplacePath: plugin.marketplacePath,
        remoteMarketplaceName: plugin.remoteMarketplaceName,
      ),
    );
  }
}

class _PluginDetail extends StatelessWidget {
  const _PluginDetail({required this.controller, required this.plugin});

  final AppController controller;
  final AppPluginDetailInfo plugin;

  @override
  Widget build(BuildContext context) {
    final authApps = plugin.apps.where((app) => app.installUrl != null);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: codexDimColor(context).withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plugin.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (plugin.description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                plugin.description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: codexMutedColor(context),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _TinyButton(
                  label: plugin.installed ? 'Reinstall' : 'Install',
                  icon: Icons.download_rounded,
                  onPressed: () => controller.installAppPlugin(
                    plugin.name,
                    marketplacePath: plugin.marketplacePath,
                    remoteMarketplaceName: plugin.remoteMarketplaceName,
                  ),
                ),
                if (plugin.installed)
                  _TinyButton(
                    label: 'Uninstall',
                    icon: Icons.delete_outline_rounded,
                    onPressed: () => controller.uninstallAppPlugin(plugin.name),
                  ),
                for (final app in authApps)
                  _TinyButton(
                    label: '${app.name} auth',
                    icon: Icons.open_in_new_rounded,
                    onPressed: () => _openUrl(app.installUrl),
                  ),
              ],
            ),
            if (plugin.skills.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _Subheading('Skills'),
              for (final skill in plugin.skills)
                _CompactLine(
                  icon: Icons.bolt_rounded,
                  title: skill.name,
                  subtitle: skill.description,
                ),
            ],
            if (plugin.mcpServers.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _Subheading('MCP'),
              for (final server in plugin.mcpServers)
                _CompactLine(
                  icon: Icons.hub_rounded,
                  title: server.name,
                  subtitle: [
                    if (server.authStatus != null) server.authStatus,
                    if (server.toolCount != null) '${server.toolCount} tools',
                  ].join(' · '),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _McpSection extends StatelessWidget {
  const _McpSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _ActionSection(
      title: 'MCP Servers',
      icon: Icons.hub_rounded,
      trailing: _TinyButton(
        label: 'Refresh',
        icon: Icons.sync_rounded,
        onPressed: controller.refreshAppMcpServers,
      ),
      child: Column(
        children: [
          if (controller.appMcpServers.isEmpty)
            const _EmptyLine(text: 'No MCP servers reported.')
          else
            for (final server in controller.appMcpServers)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hub_rounded, size: 20),
                title: Text(server.name),
                subtitle: Text(
                  [
                    if (server.status != null) server.status,
                    if (server.authStatus != null) server.authStatus,
                    '${server.toolCount} tools',
                    if (server.tools.isNotEmpty)
                      server.tools.take(4).join(', '),
                  ].join(' · '),
                ),
                trailing: _TinyButton(
                  label: 'OAuth',
                  icon: Icons.login_rounded,
                  onPressed: () =>
                      controller.startAppMcpOauthLogin(server.name),
                ),
              ),
          if (controller.appMcpOauthLogin?.loginUrl case final url?) ...[
            const SizedBox(height: AppSpacing.sm),
            _InlineNotice(
              text: url,
              icon: Icons.open_in_new_rounded,
              onTap: () => _openUrl(url),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoteSection extends StatelessWidget {
  const _RemoteSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.appRemoteStatus;
    final pairing = controller.appRemotePairing;
    final state =
        status?.connectionStatus ??
        (status == null
            ? 'not loaded'
            : status.enabled
            ? 'enabled'
            : 'disabled');
    return _ActionSection(
      title: 'Remote Control',
      icon: Icons.devices_rounded,
      trailing: _TinyButton(
        label: status?.enabled == false ? 'Enable & pair' : 'Pair',
        icon: Icons.add_link_rounded,
        onPressed: controller.startRemotePairing,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompactLine(
            icon: status?.enabled == true
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            title: 'Remote control',
            subtitle: [
              if (status?.serverName != null) status!.serverName,
              state,
              if (status?.environmentId != null) status!.environmentId,
            ].join(' · '),
          ),
          if (pairing != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _InlineNotice(
              text:
                  pairing.manualPairingCode ??
                  pairing.pairingCode ??
                  'Pairing started.',
              icon: Icons.password_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageSection extends StatelessWidget {
  const _UsageSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _ActionSection(
      title: 'Usage Limits',
      icon: Icons.speed_rounded,
      trailing: _TinyButton(
        label: 'Refresh',
        icon: Icons.sync_rounded,
        onPressed: controller.refreshAppRateLimits,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.appRateLimits.isEmpty)
            const _EmptyLine(text: 'Usage limits unavailable.')
          else
            for (final limit in controller.appRateLimits)
              _RateLimitRow(limit: limit),
        ],
      ),
    );
  }
}

class _HostUpdateSection extends StatelessWidget {
  const _HostUpdateSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.hostUpdateStatus;
    final result = controller.hostUpdateResult;
    final progress = controller.hostUpdateProgress.reversed.take(3).toList();
    final latest = status?.latestVersion ?? result?.latestVersion;
    final current = status?.currentVersion ?? result?.previousVersion;
    final updateAvailable = status?.updateAvailable == true;
    return _ActionSection(
      title: 'Host Update',
      icon: Icons.system_update_alt_rounded,
      trailing: _TinyButton(
        label: 'Check',
        icon: Icons.sync_rounded,
        onPressed: controller.hostUpdateBusy
            ? null
            : controller.refreshHostUpdateStatus,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompactLine(
            icon: updateAvailable
                ? Icons.new_releases_rounded
                : Icons.check_circle_rounded,
            title: status == null
                ? 'Host package status'
                : updateAvailable
                ? 'Update available'
                : 'Host package current',
            subtitle: [
              status?.packageName ?? result?.packageName ?? 'codex-link-host',
              if (current != null && current.isNotEmpty) 'current $current',
              if (latest != null && latest.isNotEmpty) 'latest $latest',
              if (controller.hostUpdateBusy) 'running',
            ].join(' · '),
          ),
          if (controller.hostUpdateErrorText case final error?) ...[
            const SizedBox(height: AppSpacing.xs),
            _InlineNotice(text: error, icon: Icons.error_outline_rounded),
          ],
          if (result != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _InlineNotice(
              text: result.restartRequired
                  ? '${result.message} Restart the host bridge after this finishes.'
                  : result.message,
              icon: result.updated
                  ? Icons.check_circle_outline_rounded
                  : Icons.info_outline_rounded,
            ),
          ],
          if (progress.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final item in progress)
              _CompactLine(
                icon: _hostUpdatePhaseIcon(item.phase),
                title: item.phase,
                subtitle: item.line,
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _TinyButton(
            key: const ValueKey('host-update-run'),
            label: controller.hostUpdateBusy ? 'Updating' : 'Update host',
            icon: Icons.download_rounded,
            onPressed: controller.hostUpdateBusy
                ? null
                : controller.runHostUpdate,
          ),
        ],
      ),
    );
  }
}

class _RequestsSection extends StatelessWidget {
  const _RequestsSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final approvals = controller.pendingApprovals;
    return _ActionSection(
      title: 'Interactive Requests',
      icon: Icons.fact_check_rounded,
      child: approvals.isEmpty
          ? const _EmptyLine(text: 'No interactive requests.')
          : Column(
              children: [
                for (final message in approvals)
                  _ApprovalAction(controller: controller, message: message),
              ],
            ),
    );
  }
}

class _ApprovalAction extends StatelessWidget {
  const _ApprovalAction({required this.controller, required this.message});

  final AppController controller;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final request = ApprovalRequestInfo.fromText(
      message.text,
      fallbackTitle: message.title,
    );
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.verified_user_rounded, size: 20),
      title: Text(request.title),
      subtitle: Text(
        request.body,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: AppSpacing.xs,
        children: [
          IconButton(
            tooltip: 'Approve',
            onPressed: () =>
                controller.decideApproval(request.approvalId, 'approve'),
            icon: const Icon(Icons.check_rounded),
          ),
          IconButton(
            tooltip: 'Reject',
            onPressed: () =>
                controller.decideApproval(request.approvalId, 'reject'),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _RateLimitRow extends StatelessWidget {
  const _RateLimitRow({required this.limit});

  final AppRateLimitInfo limit;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    limit.limitId,
                    if (limit.planType != null) limit.planType,
                    '${limit.remainingPercent}% left',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                '${limit.usedPercent}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: codexMutedColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: limit.usedPercent / 100,
              minHeight: 7,
              color: accent,
              backgroundColor: codexDimColor(context).withValues(alpha: 0.18),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadius.lg,
      color: codexPanelHighColor(context).withValues(alpha: 0.72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _CompactLine extends StatelessWidget {
  const _CompactLine({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                if (subtitle?.trim().isNotEmpty == true)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: codexMutedColor(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.text, required this.icon, this.onTap});

  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: codexComposerColor(context).withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: codexDimColor(context).withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: codexMutedColor(context),
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

class _TinyButton extends StatelessWidget {
  const _TinyButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
    );
  }
}

class _Subheading extends StatelessWidget {
  const _Subheading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: codexMutedColor(context)),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: codexMutedColor(context)),
    );
  }
}

Future<void> _openUrl(String? rawUrl) async {
  final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

IconData _hostUpdatePhaseIcon(String phase) {
  return switch (phase) {
    'checking' => Icons.manage_search_rounded,
    'installing' => Icons.downloading_rounded,
    'completed' => Icons.check_circle_outline_rounded,
    'failed' => Icons.error_outline_rounded,
    _ => Icons.info_outline_rounded,
  };
}
