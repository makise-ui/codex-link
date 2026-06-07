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
  });

  final int version;
  final String url;
  final String pairingToken;
  final String hostId;
  final bool insecureDevMode;
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

  bool get isRunning =>
      activeRunId != null ||
      lastStatus == 'running' ||
      lastStatus == 'cancelling';

  CodexSessionInfo copyWith({
    String? title,
    String? lastStatus,
    String? activeRunId,
  }) {
    return CodexSessionInfo(
      sessionId: sessionId,
      title: title ?? this.title,
      updatedAt: updatedAt,
      workspaceId: workspaceId,
      workdir: workdir,
      lastStatus: lastStatus ?? this.lastStatus,
      mode: mode,
      sandbox: sandbox,
      activeRunId: activeRunId ?? this.activeRunId,
      codexThreadId: codexThreadId,
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

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceInfo(
      workspaceId: json['workspaceId'] as String? ?? '',
      label: json['label'] as String? ?? 'Workspace',
      path: json['path'] as String? ?? '',
      active: json['active'] as bool? ?? false,
    );
  }
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
