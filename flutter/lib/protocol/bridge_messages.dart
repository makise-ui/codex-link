enum ConnectionPhase { idle, connecting, paired, connected, offline, failed }

enum ChatRole { user, assistant, system }

enum AgentMessageKind {
  thinking,
  reasoning,
  executing,
  response,
  system,
  files,
  approval,
  error,
}

enum RunMode { safe, yolo }

class BridgeCredentials {
  const BridgeCredentials({
    required this.url,
    required this.deviceToken,
    required this.deviceId,
  });

  final String url;
  final String deviceToken;
  final String deviceId;

  Map<String, String> toJson() => {
    'url': url,
    'deviceToken': deviceToken,
    'deviceId': deviceId,
  };

  static BridgeCredentials? fromJson(Map<String, String> json) {
    final url = json['url'];
    final token = json['deviceToken'];
    final deviceId = json['deviceId'];
    if (url == null || token == null || deviceId == null) return null;
    return BridgeCredentials(url: url, deviceToken: token, deviceId: deviceId);
  }
}

class PairingPayload {
  const PairingPayload({
    required this.version,
    required this.url,
    required this.pairingToken,
    required this.hostId,
    required this.insecureDevMode,
    this.localUrl,
    this.connectionMode,
    this.tunnelProvider,
  });

  final int version;
  final String url;
  final String? localUrl;
  final String pairingToken;
  final String hostId;
  final bool insecureDevMode;
  final String? connectionMode;
  final String? tunnelProvider;
}

class HostInfo {
  const HostInfo({
    required this.version,
    required this.connectionMode,
    required this.localUrl,
    required this.hostLabel,
    required this.yoloAllowed,
    this.tunnelProvider,
    this.publicUrl,
  });

  final int version;
  final String connectionMode;
  final String? tunnelProvider;
  final String? publicUrl;
  final String localUrl;
  final String hostLabel;
  final bool yoloAllowed;

  factory HostInfo.fromJson(Map<String, dynamic> json) {
    return HostInfo(
      version: json['version'] as int? ?? 1,
      connectionMode: json['connectionMode'] as String? ?? 'lan',
      tunnelProvider: json['tunnelProvider'] as String?,
      publicUrl: json['publicUrl'] as String?,
      localUrl: json['localUrl'] as String? ?? '',
      hostLabel: json['hostLabel'] as String? ?? 'Codex Link',
      yoloAllowed: json['yoloAllowed'] as bool? ?? false,
    );
  }
}

class CodexAccountInfo {
  const CodexAccountInfo({
    required this.accountType,
    required this.requiresOpenaiAuth,
    this.email,
    this.planType,
    this.authMode,
  });

  final String? accountType;
  final String? email;
  final String? planType;
  final String? authMode;
  final bool requiresOpenaiAuth;

  bool get isSignedIn => accountType != null || authMode != null;

  String get displayLabel {
    if (!isSignedIn) return 'Not signed in';
    if (email?.trim().isNotEmpty == true) {
      final plan = planType?.trim();
      return plan == null || plan.isEmpty
          ? email!.trim()
          : '${email!.trim()} · $plan';
    }
    return switch (authMode ?? accountType) {
      'apikey' || 'apiKey' => 'API key',
      'chatgpt' || 'chatgptAuthTokens' => 'ChatGPT',
      'amazonBedrock' => 'Amazon Bedrock',
      _ => 'Codex account',
    };
  }

  factory CodexAccountInfo.fromJson(Map<String, dynamic> json) {
    return CodexAccountInfo(
      accountType: json['accountType'] as String?,
      email: json['email'] as String?,
      planType: json['planType'] as String?,
      authMode: json['authMode'] as String?,
      requiresOpenaiAuth: json['requiresOpenaiAuth'] as bool? ?? false,
    );
  }
}

class CodexAccountLoginFlow {
  const CodexAccountLoginFlow({
    required this.type,
    this.loginId,
    this.authUrl,
    this.verificationUrl,
    this.userCode,
  });

  final String type;
  final String? loginId;
  final String? authUrl;
  final String? verificationUrl;
  final String? userCode;

  bool get isDeviceCode => type == 'chatgptDeviceCode';
  bool get isBrowserLogin => type == 'chatgpt';

  factory CodexAccountLoginFlow.fromJson(Map<String, dynamic> json) {
    return CodexAccountLoginFlow(
      type: json['type'] as String? ?? '',
      loginId: json['loginId'] as String?,
      authUrl: json['authUrl'] as String?,
      verificationUrl: json['verificationUrl'] as String?,
      userCode: json['userCode'] as String?,
    );
  }
}

class CodexSessionInfo {
  const CodexSessionInfo({
    required this.sessionId,
    required this.title,
    required this.updatedAt,
    required this.workspaceId,
    required this.workdir,
    required this.lastStatus,
    required this.mode,
    required this.sandbox,
    this.activeRunId,
    this.codexThreadId,
    this.model,
    this.reasoningEffort,
    this.serviceTier,
    this.goal,
  });

  final String sessionId;
  final String title;
  final String updatedAt;
  final String workspaceId;
  final String workdir;
  final String lastStatus;
  final RunMode mode;
  final String sandbox;
  final String? activeRunId;
  final String? codexThreadId;
  final String? model;
  final String? reasoningEffort;
  final String? serviceTier;
  final CodexGoalInfo? goal;

  bool get isRunning =>
      activeRunId != null ||
      lastStatus == 'running' ||
      lastStatus == 'cancelling';

  String get workdirName => _baseName(workdir);

  CodexSessionInfo copyWith({
    String? title,
    String? workspaceId,
    String? workdir,
    String? lastStatus,
    String? activeRunId,
    bool clearActiveRunId = false,
    String? model,
    String? reasoningEffort,
    String? serviceTier,
    CodexGoalInfo? goal,
    bool clearGoal = false,
  }) {
    return CodexSessionInfo(
      sessionId: sessionId,
      title: title ?? this.title,
      updatedAt: updatedAt,
      workspaceId: workspaceId ?? this.workspaceId,
      workdir: workdir ?? this.workdir,
      lastStatus: lastStatus ?? this.lastStatus,
      mode: mode,
      sandbox: sandbox,
      activeRunId: clearActiveRunId ? null : activeRunId ?? this.activeRunId,
      codexThreadId: codexThreadId,
      model: model ?? this.model,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      serviceTier: serviceTier ?? this.serviceTier,
      goal: clearGoal ? null : goal ?? this.goal,
    );
  }

  factory CodexSessionInfo.fromJson(Map<String, dynamic> json) {
    return CodexSessionInfo(
      sessionId: json['sessionId'] as String? ?? '',
      title: json['title'] as String? ?? 'New session',
      updatedAt: json['updatedAt'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? 'default',
      workdir: json['workdir'] as String? ?? '',
      lastStatus: json['lastStatus'] as String? ?? 'idle',
      mode: (json['mode'] as String?) == 'yolo' ? RunMode.yolo : RunMode.safe,
      sandbox: json['sandbox'] as String? ?? 'workspace-write',
      activeRunId: json['activeRunId'] as String?,
      codexThreadId: json['codexThreadId'] as String?,
      model: json['model'] as String?,
      reasoningEffort: json['reasoningEffort'] as String?,
      serviceTier: json['serviceTier'] as String?,
      goal: json['goal'] is Map
          ? CodexGoalInfo.fromJson(
              Map<String, dynamic>.from(json['goal'] as Map),
            )
          : null,
    );
  }
}

class CodexGoalInfo {
  const CodexGoalInfo({
    required this.threadId,
    required this.objective,
    required this.status,
    required this.tokensUsed,
    required this.timeUsedSeconds,
    required this.createdAt,
    required this.updatedAt,
    this.tokenBudget,
  });

  final String threadId;
  final String objective;
  final String status;
  final int? tokenBudget;
  final int tokensUsed;
  final int timeUsedSeconds;
  final int createdAt;
  final int updatedAt;

  factory CodexGoalInfo.fromJson(Map<String, dynamic> json) {
    return CodexGoalInfo(
      threadId: json['threadId'] as String? ?? '',
      objective: json['objective'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      tokenBudget: json['tokenBudget'] as int?,
      tokensUsed: json['tokensUsed'] as int? ?? 0,
      timeUsedSeconds: json['timeUsedSeconds'] as int? ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }
}

class CodexPlanInfo {
  const CodexPlanInfo({
    required this.sessionId,
    required this.title,
    required this.text,
    this.runId,
  });

  final String sessionId;
  final String? runId;
  final String title;
  final String text;

  factory CodexPlanInfo.fromJson(Map<String, dynamic> json) {
    return CodexPlanInfo(
      sessionId: json['sessionId'] as String? ?? '',
      runId: json['runId'] as String?,
      title: json['title'] as String? ?? 'Plan',
      text: json['text'] as String? ?? '',
    );
  }
}

class WorkspaceInfo {
  const WorkspaceInfo({
    required this.workspaceId,
    required this.label,
    required this.path,
    required this.active,
  });

  final String workspaceId;
  final String label;
  final String path;
  final bool active;

  String get displayName {
    final trimmed = label.trim();
    return trimmed.isNotEmpty ? trimmed : _baseName(path);
  }

  WorkspaceInfo copyWith({bool? active}) {
    return WorkspaceInfo(
      workspaceId: workspaceId,
      label: label,
      path: path,
      active: active ?? this.active,
    );
  }

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceInfo(
      workspaceId: json['workspaceId'] as String? ?? '',
      label: json['label'] as String? ?? 'Workspace',
      path: json['path'] as String? ?? '',
      active: json['active'] as bool? ?? false,
    );
  }
}

class WorkspaceFileInfo {
  const WorkspaceFileInfo({
    required this.path,
    required this.name,
    this.sizeBytes,
    this.mimeType,
  });

  final String path;
  final String name;
  final int? sizeBytes;
  final String? mimeType;

  factory WorkspaceFileInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceFileInfo(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? _baseName(json['path'] as String? ?? ''),
      sizeBytes: json['sizeBytes'] as int?,
      mimeType: json['mimeType'] as String?,
    );
  }
}

class AppProviderCapabilitiesInfo {
  const AppProviderCapabilitiesInfo({
    required this.namespaceTools,
    required this.imageGeneration,
    required this.webSearch,
  });

  final bool namespaceTools;
  final bool imageGeneration;
  final bool webSearch;

  factory AppProviderCapabilitiesInfo.fromJson(Map<String, dynamic> json) {
    return AppProviderCapabilitiesInfo(
      namespaceTools: json['namespaceTools'] as bool? ?? false,
      imageGeneration: json['imageGeneration'] as bool? ?? false,
      webSearch: json['webSearch'] as bool? ?? false,
    );
  }
}

class AppModelInfo {
  const AppModelInfo({
    required this.id,
    required this.model,
    required this.displayName,
    required this.hidden,
    required this.supportedReasoningEfforts,
    required this.inputModalities,
    required this.supportsPersonality,
    required this.serviceTiers,
    required this.isDefault,
    this.description,
    this.defaultReasoningEffort,
    this.defaultServiceTier,
  });

  final String id;
  final String model;
  final String displayName;
  final String? description;
  final bool hidden;
  final List<String> supportedReasoningEfforts;
  final String? defaultReasoningEffort;
  final List<String> inputModalities;
  final bool supportsPersonality;
  final List<AppModelServiceTierInfo> serviceTiers;
  final String? defaultServiceTier;
  final bool isDefault;

  factory AppModelInfo.fromJson(Map<String, dynamic> json) {
    return AppModelInfo(
      id: json['id'] as String? ?? '',
      model: json['model'] as String? ?? json['id'] as String? ?? '',
      displayName:
          json['displayName'] as String? ?? json['id'] as String? ?? 'Model',
      description: json['description'] as String?,
      hidden: json['hidden'] as bool? ?? false,
      supportedReasoningEfforts:
          (json['supportedReasoningEfforts'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      defaultReasoningEffort: json['defaultReasoningEffort'] as String?,
      inputModalities: (json['inputModalities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      supportsPersonality: json['supportsPersonality'] as bool? ?? false,
      serviceTiers: (json['serviceTiers'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => AppModelServiceTierInfo.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      defaultServiceTier: json['defaultServiceTier'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}

class AppModelServiceTierInfo {
  const AppModelServiceTierInfo({
    required this.id,
    required this.name,
    this.description,
  });

  final String id;
  final String name;
  final String? description;

  factory AppModelServiceTierInfo.fromJson(Map<String, dynamic> json) {
    return AppModelServiceTierInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? 'Tier',
      description: json['description'] as String?,
    );
  }
}

class AppThreadInfo {
  const AppThreadInfo({
    required this.threadId,
    required this.title,
    required this.preview,
    required this.createdAt,
    required this.updatedAt,
    required this.workdir,
    this.codexSessionId,
    this.path,
    this.source,
    this.status,
    this.modelProvider,
    this.cliVersion,
    this.messageCount,
  });

  final String threadId;
  final String? codexSessionId;
  final String title;
  final String preview;
  final String createdAt;
  final String updatedAt;
  final String workdir;
  final String? path;
  final String? source;
  final String? status;
  final String? modelProvider;
  final String? cliVersion;
  final int? messageCount;

  factory AppThreadInfo.fromJson(Map<String, dynamic> json) {
    return AppThreadInfo(
      threadId: json['threadId'] as String? ?? '',
      codexSessionId: json['codexSessionId'] as String?,
      title: json['title'] as String? ?? 'Codex session',
      preview: json['preview'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      workdir: json['workdir'] as String? ?? '',
      path: json['path'] as String?,
      source: json['source'] as String?,
      status: json['status'] as String?,
      modelProvider: json['modelProvider'] as String?,
      cliVersion: json['cliVersion'] as String?,
      messageCount: json['messageCount'] as int?,
    );
  }
}

class AppSkillInfo {
  const AppSkillInfo({
    required this.name,
    required this.description,
    required this.path,
    required this.enabled,
    this.scope,
  });

  final String name;
  final String description;
  final String path;
  final String? scope;
  final bool enabled;

  factory AppSkillInfo.fromJson(Map<String, dynamic> json) {
    return AppSkillInfo(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      path: json['path'] as String? ?? '',
      scope: json['scope'] as String?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class AppSkillGroupInfo {
  const AppSkillGroupInfo({
    required this.cwd,
    required this.skills,
    required this.errors,
  });

  final String cwd;
  final List<AppSkillInfo> skills;
  final List<String> errors;

  factory AppSkillGroupInfo.fromJson(Map<String, dynamic> json) {
    return AppSkillGroupInfo(
      cwd: json['cwd'] as String? ?? '',
      skills: (json['skills'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                AppSkillInfo.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      errors: (json['errors'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}

class AppFsEntryInfo {
  const AppFsEntryInfo({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.isFile,
    this.sizeBytes,
    this.mimeType,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final bool isFile;
  final int? sizeBytes;
  final String? mimeType;

  factory AppFsEntryInfo.fromJson(Map<String, dynamic> json) {
    return AppFsEntryInfo(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? _baseName(json['path'] as String? ?? ''),
      isDirectory: json['isDirectory'] as bool? ?? false,
      isFile: json['isFile'] as bool? ?? false,
      sizeBytes: json['sizeBytes'] as int?,
      mimeType: json['mimeType'] as String?,
    );
  }
}

class AppFsFileInfo {
  const AppFsFileInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.mimeType,
    this.text,
    this.dataBase64,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final String? mimeType;
  final String? text;
  final String? dataBase64;

  factory AppFsFileInfo.fromJson(Map<String, dynamic> json) {
    return AppFsFileInfo(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? _baseName(json['path'] as String? ?? ''),
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      mimeType: json['mimeType'] as String?,
      text: json['text'] as String?,
      dataBase64: json['dataBase64'] as String?,
    );
  }
}

class AppPluginMarketplaceInfo {
  const AppPluginMarketplaceInfo({
    required this.name,
    required this.plugins,
    this.displayName,
    this.path,
  });

  final String name;
  final String? displayName;
  final String? path;
  final List<AppPluginSummaryInfo> plugins;

  factory AppPluginMarketplaceInfo.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    final remote = json['remoteMarketplaceName'] as String?;
    return AppPluginMarketplaceInfo(
      name: json['name'] as String? ?? '',
      displayName: json['displayName'] as String?,
      path: path,
      plugins: (json['plugins'] as List<dynamic>? ?? const [])
          .map(
            (item) => AppPluginSummaryInfo.fromJson(
              Map<String, dynamic>.from(item as Map),
              fallbackMarketplacePath: path,
              fallbackRemoteMarketplaceName: remote,
            ),
          )
          .toList(growable: false),
    );
  }
}

class AppPluginSummaryInfo {
  const AppPluginSummaryInfo({
    required this.name,
    required this.displayName,
    required this.installed,
    required this.enabled,
    this.id,
    this.description,
    this.version,
    this.category,
    this.marketplacePath,
    this.remoteMarketplaceName,
    this.authType,
  });

  final String? id;
  final String name;
  final String displayName;
  final String? description;
  final String? version;
  final bool installed;
  final bool enabled;
  final String? category;
  final String? marketplacePath;
  final String? remoteMarketplaceName;
  final String? authType;

  factory AppPluginSummaryInfo.fromJson(
    Map<String, dynamic> json, {
    String? fallbackMarketplacePath,
    String? fallbackRemoteMarketplaceName,
  }) {
    final name = json['name'] as String? ?? json['id'] as String? ?? '';
    return AppPluginSummaryInfo(
      id: json['id'] as String?,
      name: name,
      displayName: json['displayName'] as String? ?? name,
      description: json['description'] as String?,
      version: json['version'] as String?,
      installed: json['installed'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
      category: json['category'] as String?,
      marketplacePath:
          json['marketplacePath'] as String? ?? fallbackMarketplacePath,
      remoteMarketplaceName:
          json['remoteMarketplaceName'] as String? ??
          fallbackRemoteMarketplaceName,
      authType: json['authType'] as String?,
    );
  }
}

class AppPluginDetailInfo {
  const AppPluginDetailInfo({
    required this.name,
    required this.displayName,
    required this.installed,
    required this.enabled,
    required this.skills,
    required this.apps,
    required this.mcpServers,
    this.id,
    this.description,
    this.version,
    this.category,
    this.marketplacePath,
    this.remoteMarketplaceName,
    this.authType,
  });

  final String? id;
  final String name;
  final String displayName;
  final String? description;
  final String? version;
  final bool installed;
  final bool enabled;
  final String? category;
  final String? marketplacePath;
  final String? remoteMarketplaceName;
  final String? authType;
  final List<AppPluginSkillInfo> skills;
  final List<AppPluginAuthAppInfo> apps;
  final List<AppPluginMcpServerInfo> mcpServers;

  factory AppPluginDetailInfo.fromJson(Map<String, dynamic> json) {
    final summary = AppPluginSummaryInfo.fromJson(json);
    return AppPluginDetailInfo(
      id: summary.id,
      name: summary.name,
      displayName: summary.displayName,
      description: summary.description,
      version: summary.version,
      installed: summary.installed,
      enabled: summary.enabled,
      category: summary.category,
      marketplacePath: summary.marketplacePath,
      remoteMarketplaceName: summary.remoteMarketplaceName,
      authType: summary.authType,
      skills: (json['skills'] as List<dynamic>? ?? const [])
          .map(
            (item) => AppPluginSkillInfo.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      apps: (json['apps'] as List<dynamic>? ?? const [])
          .map(
            (item) => AppPluginAuthAppInfo.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      mcpServers: (json['mcpServers'] as List<dynamic>? ?? const [])
          .map(
            (item) => AppPluginMcpServerInfo.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class AppPluginSkillInfo {
  const AppPluginSkillInfo({required this.name, this.description});

  final String name;
  final String? description;

  factory AppPluginSkillInfo.fromJson(Map<String, dynamic> json) {
    return AppPluginSkillInfo(
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
    );
  }
}

class AppPluginAuthAppInfo {
  const AppPluginAuthAppInfo({
    required this.name,
    this.authStatus,
    this.installUrl,
  });

  final String name;
  final String? authStatus;
  final String? installUrl;

  factory AppPluginAuthAppInfo.fromJson(Map<String, dynamic> json) {
    return AppPluginAuthAppInfo(
      name: json['name'] as String? ?? '',
      authStatus: json['authStatus'] as String?,
      installUrl: json['installUrl'] as String?,
    );
  }
}

class AppPluginMcpServerInfo {
  const AppPluginMcpServerInfo({
    required this.name,
    this.authStatus,
    this.toolCount,
  });

  final String name;
  final String? authStatus;
  final int? toolCount;

  factory AppPluginMcpServerInfo.fromJson(Map<String, dynamic> json) {
    return AppPluginMcpServerInfo(
      name: json['name'] as String? ?? '',
      authStatus: json['authStatus'] as String?,
      toolCount: json['toolCount'] as int?,
    );
  }
}

class AppPluginInstallResultInfo {
  const AppPluginInstallResultInfo({
    required this.pluginName,
    required this.installed,
    required this.appsNeedingAuth,
    this.message,
  });

  final String pluginName;
  final bool installed;
  final String? message;
  final List<AppPluginAuthAppInfo> appsNeedingAuth;

  factory AppPluginInstallResultInfo.fromJson(Map<String, dynamic> json) {
    return AppPluginInstallResultInfo(
      pluginName: json['pluginName'] as String? ?? '',
      installed: json['installed'] as bool? ?? false,
      message: json['message'] as String?,
      appsNeedingAuth: (json['appsNeedingAuth'] as List<dynamic>? ?? const [])
          .map(
            (item) => AppPluginAuthAppInfo.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class AppMcpServerInfo {
  const AppMcpServerInfo({
    required this.name,
    required this.toolCount,
    required this.tools,
    required this.resourceCount,
    this.status,
    this.authStatus,
  });

  final String name;
  final String? status;
  final String? authStatus;
  final int toolCount;
  final List<String> tools;
  final int resourceCount;

  factory AppMcpServerInfo.fromJson(Map<String, dynamic> json) {
    return AppMcpServerInfo(
      name: json['name'] as String? ?? '',
      status: json['status'] as String?,
      authStatus: json['authStatus'] as String?,
      toolCount: json['toolCount'] as int? ?? 0,
      tools: (json['tools'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      resourceCount: json['resourceCount'] as int? ?? 0,
    );
  }
}

class AppMcpOauthLoginInfo {
  const AppMcpOauthLoginInfo({
    required this.serverName,
    this.loginUrl,
    this.status,
    this.message,
  });

  final String serverName;
  final String? loginUrl;
  final String? status;
  final String? message;

  factory AppMcpOauthLoginInfo.fromJson(Map<String, dynamic> json) {
    return AppMcpOauthLoginInfo(
      serverName: json['serverName'] as String? ?? '',
      loginUrl: json['loginUrl'] as String?,
      status: json['status'] as String?,
      message: json['message'] as String?,
    );
  }
}

class AppRemoteStatusInfo {
  const AppRemoteStatusInfo({
    required this.enabled,
    this.connectionStatus,
    this.serverName,
    this.environmentId,
    this.installationId,
  });

  final bool enabled;
  final String? connectionStatus;
  final String? serverName;
  final String? environmentId;
  final String? installationId;

  factory AppRemoteStatusInfo.fromJson(Map<String, dynamic> json) {
    return AppRemoteStatusInfo(
      enabled: json['enabled'] as bool? ?? false,
      connectionStatus: json['connectionStatus'] as String?,
      serverName: json['serverName'] as String?,
      environmentId: json['environmentId'] as String?,
      installationId: json['installationId'] as String?,
    );
  }
}

class AppRemotePairingInfo {
  const AppRemotePairingInfo({
    this.pairingCode,
    this.manualPairingCode,
    this.environmentId,
    this.expiresAt,
  });

  final String? pairingCode;
  final String? manualPairingCode;
  final String? environmentId;
  final int? expiresAt;

  factory AppRemotePairingInfo.fromJson(Map<String, dynamic> json) {
    return AppRemotePairingInfo(
      pairingCode: json['pairingCode'] as String?,
      manualPairingCode: json['manualPairingCode'] as String?,
      environmentId: json['environmentId'] as String?,
      expiresAt: json['expiresAt'] as int?,
    );
  }
}

class AppRateLimitInfo {
  const AppRateLimitInfo({
    required this.limitId,
    required this.usedPercent,
    required this.remainingPercent,
    this.planType,
    this.windowDurationMins,
    this.resetsAt,
  });

  final String limitId;
  final String? planType;
  final int usedPercent;
  final int remainingPercent;
  final int? windowDurationMins;
  final int? resetsAt;

  factory AppRateLimitInfo.fromJson(Map<String, dynamic> json) {
    return AppRateLimitInfo(
      limitId: json['limitId'] as String? ?? 'codex',
      planType: json['planType'] as String?,
      usedPercent: json['usedPercent'] as int? ?? 0,
      remainingPercent: json['remainingPercent'] as int? ?? 100,
      windowDurationMins: json['windowDurationMins'] as int?,
      resetsAt: json['resetsAt'] as int?,
    );
  }
}

class ApprovalRequestInfo {
  const ApprovalRequestInfo({
    required this.approvalId,
    required this.title,
    required this.body,
    required this.riskLevel,
  });

  final String approvalId;
  final String title;
  final String body;
  final String riskLevel;

  factory ApprovalRequestInfo.fromText(String text, {String? fallbackTitle}) {
    final lines = text.split('\n');
    String? id;
    String? risk;
    final body = <String>[];
    for (final line in lines) {
      if (line.startsWith('approvalId ')) {
        id = line.substring('approvalId '.length).trim();
      } else if (line.startsWith('risk ')) {
        risk = line.substring('risk '.length).trim();
      } else {
        body.add(line);
      }
    }
    return ApprovalRequestInfo(
      approvalId: id ?? '',
      title: fallbackTitle ?? 'Approval needed',
      body: body.join('\n').trim(),
      riskLevel: risk ?? 'medium',
    );
  }
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return path;
  return parts.last;
}

class CodexCommandInfo {
  const CodexCommandInfo({
    required this.commandId,
    required this.title,
    required this.description,
    required this.category,
  });

  final String commandId;
  final String title;
  final String description;
  final String category;

  factory CodexCommandInfo.fromJson(Map<String, dynamic> json) {
    return CodexCommandInfo(
      commandId: json['commandId'] as String? ?? '',
      title: json['title'] as String? ?? 'Command',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'agent',
    );
  }
}

class PromptAttachmentInfo {
  const PromptAttachmentInfo({
    required this.name,
    required this.dataBase64,
    this.mimeType,
  });

  final String name;
  final String dataBase64;
  final String? mimeType;

  Map<String, dynamic> toJson() => {
    'name': name,
    'dataBase64': dataBase64,
    if (mimeType != null) 'mimeType': mimeType,
  };
}

class FileOfferInfo {
  const FileOfferInfo({
    required this.fileId,
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.reason,
    this.sessionId,
    this.mimeType,
  });

  final String fileId;
  final String? sessionId;
  final String path;
  final String name;
  final String? mimeType;
  final int sizeBytes;
  final String reason;

  factory FileOfferInfo.fromJson(Map<String, dynamic> json) {
    return FileOfferInfo(
      fileId: json['fileId'] as String? ?? '',
      sessionId: json['sessionId'] as String?,
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? 'download',
      mimeType: json['mimeType'] as String?,
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      reason: json['reason'] as String? ?? 'generated',
    );
  }
}

class DownloadedFileInfo {
  const DownloadedFileInfo({
    required this.fileId,
    required this.name,
    required this.sizeBytes,
    required this.dataBase64,
    this.mimeType,
  });

  final String fileId;
  final String name;
  final String? mimeType;
  final int sizeBytes;
  final String dataBase64;

  factory DownloadedFileInfo.fromJson(Map<String, dynamic> json) {
    return DownloadedFileInfo(
      fileId: json['fileId'] as String? ?? '',
      name: json['name'] as String? ?? 'download',
      mimeType: json['mimeType'] as String?,
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      dataBase64: json['dataBase64'] as String? ?? '',
    );
  }
}

class ExternalSessionInfo {
  const ExternalSessionInfo({
    required this.externalSessionId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.workdir,
    required this.codexThreadId,
    required this.path,
  });

  final String externalSessionId;
  final String title;
  final String createdAt;
  final String updatedAt;
  final String workdir;
  final String codexThreadId;
  final String path;

  factory ExternalSessionInfo.fromJson(Map<String, dynamic> json) {
    return ExternalSessionInfo(
      externalSessionId: json['externalSessionId'] as String? ?? '',
      title: json['title'] as String? ?? 'Codex session',
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      workdir: json['workdir'] as String? ?? '',
      codexThreadId: json['codexThreadId'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.kind,
    required this.text,
    required this.createdAt,
    this.title,
    this.runId,
    this.complete = true,
  });

  final String id;
  final ChatRole role;
  final AgentMessageKind kind;
  final String text;
  final DateTime createdAt;
  final String? title;
  final String? runId;
  final bool complete;

  ChatMessage copyWith({String? text, bool? complete, String? title}) {
    return ChatMessage(
      id: id,
      role: role,
      kind: kind,
      text: text ?? this.text,
      createdAt: createdAt,
      title: title ?? this.title,
      runId: runId,
      complete: complete ?? this.complete,
    );
  }

  factory ChatMessage.fromHistory(Map<String, dynamic> json) {
    final role = switch (json['role'] as String?) {
      'user' => ChatRole.user,
      'assistant' => ChatRole.assistant,
      _ => ChatRole.system,
    };
    return ChatMessage(
      id: json['messageId'] as String? ?? '',
      role: role,
      kind: kindFromWire(json['kind'] as String?),
      text: json['text'] as String? ?? '',
      title: json['title'] as String?,
      runId: json['runId'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      complete: json['complete'] as bool? ?? true,
    );
  }
}

AgentMessageKind kindFromWire(String? value) {
  switch (value) {
    case 'thinking':
      return AgentMessageKind.thinking;
    case 'reasoning':
      return AgentMessageKind.reasoning;
    case 'executing':
      return AgentMessageKind.executing;
    case 'response':
      return AgentMessageKind.response;
    case 'system':
      return AgentMessageKind.system;
    case 'files':
      return AgentMessageKind.files;
    case 'approval':
      return AgentMessageKind.approval;
    case 'error':
      return AgentMessageKind.error;
    default:
      return AgentMessageKind.system;
  }
}
