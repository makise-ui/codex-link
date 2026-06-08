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
    required this.isDefault,
    this.description,
    this.defaultReasoningEffort,
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
      isDefault: json['isDefault'] as bool? ?? false,
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
