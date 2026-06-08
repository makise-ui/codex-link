enum ConnectionPhase { idle, connecting, paired, connected, offline, failed }

enum ChatRole { user, assistant, system }

enum AgentMessageKind { thinking, executing, response, system, files, error }

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
    case 'executing':
      return AgentMessageKind.executing;
    case 'response':
      return AgentMessageKind.response;
    case 'system':
      return AgentMessageKind.system;
    case 'files':
      return AgentMessageKind.files;
    case 'error':
      return AgentMessageKind.error;
    default:
      return AgentMessageKind.system;
  }
}
