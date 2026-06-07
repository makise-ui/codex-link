export const PROTOCOL_VERSION = 5;

export type SessionStatus = "idle" | "starting" | "running" | "waiting_for_approval" | "cancelling" | "cancelled" | "completed" | "failed" | "connected";
export type MessageKind = "thinking" | "executing" | "response" | "system";
export type StoredMessageKind = MessageKind | "files" | "error";
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
export type RunMode = "safe" | "yolo";
export type ReasoningEffort = "low" | "medium" | "high" | "xhigh";
export type ConnectionMode = "lan" | "tunnel";
export type TunnelProvider = "ngrok" | "cloudflared" | "tailscale" | "other";

export type ClientMessage =
  | PairingClaimMessage
  | AuthResumeMessage
  | AuthPasswordMessage
  | SessionStartMessage
  | SessionListRequestMessage
  | SessionCreateMessage
  | SessionRenameMessage
  | SessionDeleteMessage
  | SessionModeSetMessage
  | SessionConfigSetMessage
  | WorkspaceListRequestMessage
  | WorkspaceAddMessage
  | WorkspaceSwitchMessage
  | WorkspaceFileSearchMessage
  | ExternalSessionListRequestMessage
  | ExternalSessionImportMessage
  | CommandListRequestMessage
  | CommandRunMessage
  | PromptSendMessage
  | FileOfferRequestMessage
  | FileRequestMessage
  | RunCancelMessage
  | ApprovalDecisionMessage
  | PingMessage;

export type PairingClaimMessage = {
  type: "pairing.claim";
  pairingToken: string;
  deviceName: string;
};

export type AuthResumeMessage = {
  type: "auth.resume";
  deviceToken: string;
};

export type AuthPasswordMessage = {
  type: "auth.password";
  password: string;
  deviceName: string;
};

export type SessionStartMessage = {
  type: "session.start";
  sessionId?: string;
};

export type SessionListRequestMessage = {
  type: "session.list";
};

export type SessionCreateMessage = {
  type: "session.create";
  title?: string;
  workspaceId?: string;
  mode?: RunMode;
};

export type SessionRenameMessage = {
  type: "session.rename";
  sessionId: string;
  title: string;
};

export type SessionDeleteMessage = {
  type: "session.delete";
  sessionId: string;
};

export type SessionModeSetMessage = {
  type: "session.mode.set";
  sessionId: string;
  mode: RunMode;
};

export type SessionConfigSetMessage = {
  type: "session.config.set";
  sessionId: string;
  model?: string;
  reasoningEffort?: ReasoningEffort;
};

export type WorkspaceListRequestMessage = {
  type: "workspace.list";
};

export type WorkspaceAddMessage = {
  type: "workspace.add";
  path: string;
  sessionId?: string;
  create?: boolean;
};

export type WorkspaceSwitchMessage = {
  type: "workspace.switch";
  sessionId: string;
  workspaceId: string;
};

export type WorkspaceFileSearchMessage = {
  type: "workspace.file.search";
  sessionId: string;
  query?: string;
  limit?: number;
};

export type ExternalSessionListRequestMessage = {
  type: "external.session.list";
};

export type ExternalSessionImportMessage = {
  type: "external.session.import";
  externalSessionId: string;
};

export type CommandListRequestMessage = {
  type: "command.list";
};

export type CommandRunMessage = {
  type: "command.run";
  commandId: string;
  sessionId?: string;
};

export type PromptSendMessage = {
  type: "prompt.send";
  sessionId: string;
  prompt: string;
  attachments?: PromptAttachment[];
};

export type PromptAttachment = {
  name: string;
  mimeType?: string;
  dataBase64: string;
};

export type FileRequestMessage = {
  type: "file.request";
  fileId: string;
};

export type FileOfferRequestMessage = {
  type: "file.offer.request";
  sessionId: string;
  path: string;
};

export type RunCancelMessage = {
  type: "run.cancel";
  sessionId: string;
  runId: string;
};

export type ApprovalDecisionMessage = {
  type: "approval.decision";
  sessionId: string;
  approvalId: string;
  decision: "approve" | "reject";
};

export type PingMessage = {
  type: "ping";
  nonce?: string;
};

export type ServerMessage =
  | PairingAcceptedMessage
  | AuthAcceptedMessage
  | HostInfoMessage
  | SessionStartedMessage
  | SessionListMessage
  | SessionUpdatedMessage
  | SessionDeletedMessage
  | MessageHistoryMessage
  | WorkspaceListMessage
  | WorkspaceUpdatedMessage
  | WorkspaceFileSearchResultsMessage
  | ExternalSessionListMessage
  | CommandListMessage
  | RunStartedMessage
  | OutputDeltaMessage
  | MessageStartedMessage
  | MessageDeltaMessage
  | MessageCompletedMessage
  | StatusMessage
  | ApprovalRequestedMessage
  | DiffAvailableMessage
  | FileOfferMessage
  | FileDownloadMessage
  | RunCompletedMessage
  | ErrorMessage
  | PongMessage;

export type SessionRecord = {
  sessionId: string;
  codexThreadId?: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  workspaceId: string;
  workdir: string;
  activeRunId?: string;
  lastStatus: SessionStatus;
  mode: RunMode;
  sandbox: SandboxMode;
  model?: string;
  reasoningEffort?: ReasoningEffort;
};

export type StoredChatMessage = {
  messageId: string;
  role: "user" | "assistant" | "system";
  kind: StoredMessageKind;
  text: string;
  createdAt: string;
  title?: string;
  runId?: string;
  complete: boolean;
};

export type WorkspaceRecord = {
  workspaceId: string;
  label: string;
  path: string;
  active: boolean;
};

export type WorkspaceFileRecord = {
  path: string;
  name: string;
  sizeBytes?: number;
  mimeType?: string;
};

export type ExternalSessionRecord = {
  externalSessionId: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  workdir: string;
  codexThreadId: string;
  path: string;
};

export type CommandRecord = {
  commandId: string;
  title: string;
  description: string;
  category: "agent" | "session" | "mode";
};

export type PairingAcceptedMessage = {
  type: "pairing.accepted";
  version: number;
  deviceId: string;
  deviceToken: string;
  sessionId: string;
};

export type AuthAcceptedMessage = {
  type: "auth.accepted";
  version: number;
  deviceId: string;
  sessionId: string;
  deviceToken?: string;
};

export type HostInfoMessage = {
  type: "host.info";
  version: number;
  connectionMode: ConnectionMode;
  tunnelProvider?: TunnelProvider;
  publicUrl?: string;
  localUrl: string;
  hostLabel: string;
  yoloAllowed: boolean;
};

export type SessionStartedMessage = {
  type: "session.started";
  sessionId: string;
};

export type SessionListMessage = {
  type: "session.list";
  sessions: SessionRecord[];
  activeSessionId?: string;
};

export type SessionUpdatedMessage = {
  type: "session.updated";
  session: SessionRecord;
};

export type SessionDeletedMessage = {
  type: "session.deleted";
  sessionId: string;
};

export type MessageHistoryMessage = {
  type: "message.history";
  sessionId: string;
  messages: StoredChatMessage[];
};

export type WorkspaceListMessage = {
  type: "workspace.list";
  workspaces: WorkspaceRecord[];
};

export type WorkspaceUpdatedMessage = {
  type: "workspace.updated";
  sessionId: string;
  workspace: WorkspaceRecord;
};

export type WorkspaceFileSearchResultsMessage = {
  type: "workspace.file.search.results";
  sessionId: string;
  query: string;
  files: WorkspaceFileRecord[];
};

export type ExternalSessionListMessage = {
  type: "external.session.list";
  sessions: ExternalSessionRecord[];
};

export type CommandListMessage = {
  type: "command.list";
  commands: CommandRecord[];
};

export type RunStartedMessage = {
  type: "run.started";
  sessionId: string;
  runId: string;
};

export type OutputDeltaMessage = {
  type: "output.delta";
  sessionId: string;
  runId: string;
  stream: "assistant" | "stdout" | "stderr" | "system";
  text: string;
};

export type MessageStartedMessage = {
  type: "message.started";
  sessionId: string;
  runId: string;
  messageId: string;
  kind: MessageKind;
  role: "assistant" | "system";
  title?: string;
};

export type MessageDeltaMessage = {
  type: "message.delta";
  sessionId: string;
  runId: string;
  messageId: string;
  text: string;
};

export type MessageCompletedMessage = {
  type: "message.completed";
  sessionId: string;
  runId: string;
  messageId: string;
};

export type StatusMessage = {
  type: "status";
  status: SessionStatus;
  sessionId?: string;
  runId?: string;
  detail?: string;
};

export type ApprovalRequestedMessage = {
  type: "approval.requested";
  sessionId: string;
  approvalId: string;
  title: string;
  body: string;
  riskLevel: "low" | "medium" | "high";
};

export type DiffAvailableMessage = {
  type: "diff.available";
  sessionId: string;
  files: Array<{
    path: string;
    status: "added" | "modified" | "deleted" | "renamed";
    patch?: string;
  }>;
};

export type FileOfferMessage = {
  type: "file.offer";
  fileId: string;
  sessionId?: string;
  path: string;
  name: string;
  mimeType?: string;
  sizeBytes: number;
  reason: "requested" | "generated" | "attachment";
};

export type FileDownloadMessage = {
  type: "file.download";
  fileId: string;
  name: string;
  mimeType?: string;
  sizeBytes: number;
  dataBase64: string;
};

export type RunCompletedMessage = {
  type: "run.completed";
  sessionId: string;
  runId: string;
  exitCode?: number;
};

export type ErrorMessage = {
  type: "error";
  code: string;
  message: string;
};

export type PongMessage = {
  type: "pong";
  nonce?: string;
};

export type PairingPayload = {
  version: number;
  url: string;
  localUrl?: string;
  pairingToken: string;
  hostId: string;
  connectionMode?: ConnectionMode;
  tunnelProvider?: TunnelProvider;
  insecureDevMode: boolean;
};
