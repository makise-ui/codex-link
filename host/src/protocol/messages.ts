export const PROTOCOL_VERSION = 15;

export type SessionStatus = "idle" | "starting" | "running" | "waiting_for_approval" | "cancelling" | "cancelled" | "completed" | "failed" | "connected";
export type MessageKind = "thinking" | "reasoning" | "executing" | "response" | "system";
export type StoredMessageKind = MessageKind | "files" | "error";
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
export type RunMode = "safe" | "yolo";
export type ReasoningEffort = "low" | "medium" | "high" | "xhigh";
export type GoalStatus = "active" | "paused" | "blocked" | "usageLimited" | "budgetLimited" | "complete";
export type ConnectionMode = "lan" | "tunnel";
export type TunnelProvider = "ngrok" | "cloudflared" | "tailscale" | "other";
export type CodexAccountType = "apiKey" | "chatgpt" | "amazonBedrock" | null;
export type CodexAuthMode = "apikey" | "chatgpt" | "chatgptAuthTokens" | "agentIdentity" | null;
export type CodexAccountLoginType = "apiKey" | "chatgpt" | "chatgptDeviceCode";
export type CodexAccountLoginCancelStatus = "canceled" | "notFound";

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
  | SessionGoalSetMessage
  | SessionGoalGetMessage
  | SessionGoalClearMessage
  | WorkspaceListRequestMessage
  | WorkspaceAddMessage
  | WorkspaceSwitchMessage
  | WorkspaceFileSearchMessage
  | WorkspaceEnvSetMessage
  | ExternalSessionListRequestMessage
  | ExternalSessionImportMessage
  | AppModelListRequestMessage
  | AppThreadListRequestMessage
  | AppThreadImportMessage
  | AppSkillListRequestMessage
  | AppFsListRequestMessage
  | AppFsReadRequestMessage
  | AppFsWriteRequestMessage
  | AppFsCreateDirectoryRequestMessage
  | AppFileSearchRequestMessage
  | AppReviewStartRequestMessage
  | AppAccountReadRequestMessage
  | AppAccountLoginStartRequestMessage
  | AppAccountLoginCancelRequestMessage
  | AppAccountLogoutRequestMessage
  | AppAccountRateLimitsReadRequestMessage
  | AppPluginListRequestMessage
  | AppPluginReadRequestMessage
  | AppPluginInstallRequestMessage
  | AppPluginUninstallRequestMessage
  | AppMcpStatusListRequestMessage
  | AppMcpOauthLoginRequestMessage
  | AppRemoteStatusReadRequestMessage
  | AppRemotePairingStartRequestMessage
  | HostUpdateCheckRequestMessage
  | HostUpdateRunRequestMessage
  | ShellCommandRunMessage
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
  serviceTier?: string | null;
};

export type SessionGoalSetMessage = {
  type: "session.goal.set";
  sessionId: string;
  objective?: string;
  status?: GoalStatus;
  tokenBudget?: number | null;
};

export type SessionGoalGetMessage = {
  type: "session.goal.get";
  sessionId: string;
};

export type SessionGoalClearMessage = {
  type: "session.goal.clear";
  sessionId: string;
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

export type WorkspaceEnvSetMessage = {
  type: "workspace.env.set";
  sessionId: string;
  content: string;
  path?: string;
};

export type ExternalSessionListRequestMessage = {
  type: "external.session.list";
};

export type ExternalSessionImportMessage = {
  type: "external.session.import";
  externalSessionId: string;
};

export type AppModelListRequestMessage = {
  type: "app.model.list";
  sessionId?: string;
  includeHidden?: boolean;
};

export type AppThreadListRequestMessage = {
  type: "app.thread.list";
  sessionId?: string;
  query?: string;
  cwd?: string;
  limit?: number;
};

export type AppThreadImportMessage = {
  type: "app.thread.import";
  threadId: string;
};

export type AppSkillListRequestMessage = {
  type: "app.skill.list";
  sessionId?: string;
  forceReload?: boolean;
};

export type AppFsListRequestMessage = {
  type: "app.fs.list";
  sessionId: string;
  path?: string;
};

export type AppFsReadRequestMessage = {
  type: "app.fs.read";
  sessionId: string;
  path: string;
};

export type AppFsWriteRequestMessage = {
  type: "app.fs.write";
  sessionId: string;
  path: string;
  dataBase64: string;
};

export type AppFsCreateDirectoryRequestMessage = {
  type: "app.fs.createDirectory";
  sessionId: string;
  path: string;
};

export type AppFileSearchRequestMessage = {
  type: "app.file.search";
  sessionId: string;
  query: string;
  limit?: number;
};

export type AppReviewStartRequestMessage = {
  type: "app.review.start";
  sessionId: string;
  target?: "uncommittedChanges" | "custom";
  instructions?: string;
  delivery?: "inline" | "detached";
};

export type AppAccountReadRequestMessage = {
  type: "app.account.read";
  refreshToken?: boolean;
};

export type AppAccountLoginStartRequestMessage = {
  type: "app.account.login.start";
  loginType: CodexAccountLoginType;
  apiKey?: string;
  codexStreamlinedLogin?: boolean;
};

export type AppAccountLoginCancelRequestMessage = {
  type: "app.account.login.cancel";
  loginId: string;
};

export type AppAccountLogoutRequestMessage = {
  type: "app.account.logout";
};

export type AppAccountRateLimitsReadRequestMessage = {
  type: "app.account.rateLimits.read";
};

export type AppPluginListRequestMessage = {
  type: "app.plugin.list";
  sessionId?: string;
};

export type AppPluginReadRequestMessage = {
  type: "app.plugin.read";
  pluginName: string;
  marketplacePath?: string;
  remoteMarketplaceName?: string;
};

export type AppPluginInstallRequestMessage = {
  type: "app.plugin.install";
  pluginName: string;
  marketplacePath?: string;
  remoteMarketplaceName?: string;
};

export type AppPluginUninstallRequestMessage = {
  type: "app.plugin.uninstall";
  pluginName: string;
};

export type AppMcpStatusListRequestMessage = {
  type: "app.mcp.status.list";
  sessionId?: string;
  detail?: "full" | "toolsAndAuthOnly";
};

export type AppMcpOauthLoginRequestMessage = {
  type: "app.mcp.oauth.login";
  serverName: string;
};

export type AppRemoteStatusReadRequestMessage = {
  type: "app.remote.status.read";
};

export type AppRemotePairingStartRequestMessage = {
  type: "app.remote.pairing.start";
  manualPairingCode?: string;
};

export type HostUpdateCheckRequestMessage = {
  type: "host.update.check";
};

export type HostUpdateRunRequestMessage = {
  type: "host.update.run";
};

export type ShellCommandRunMessage = {
  type: "shell.command.run";
  sessionId: string;
  command: string;
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
  | WorkspaceEnvUpdatedMessage
  | ExternalSessionListMessage
  | AppModelListMessage
  | AppThreadListMessage
  | AppSkillListMessage
  | AppFsListMessage
  | AppFsFileMessage
  | AppFsWriteResultMessage
  | AppFsDirectoryCreatedMessage
  | AppFileSearchResultsMessage
  | AppReviewStartedMessage
  | AppAccountStatusMessage
  | AppAccountLoginStartedMessage
  | AppAccountLoginCancelledMessage
  | AppAccountUpdatedMessage
  | AppAccountLoginCompletedMessage
  | AppAccountRateLimitsMessage
  | AppPluginListMessage
  | AppPluginDetailMessage
  | AppPluginInstallResultMessage
  | AppPluginUninstallResultMessage
  | AppMcpStatusListMessage
  | AppMcpOauthLoginStartedMessage
  | AppRemoteStatusMessage
  | AppRemotePairingStartedMessage
  | HostUpdateStatusMessage
  | HostUpdateProgressMessage
  | HostUpdateResultMessage
  | ShellCommandResultMessage
  | CommandListMessage
  | SessionGoalUpdatedMessage
  | SessionGoalClearedMessage
  | SessionPlanUpdatedMessage
  | SessionSubagentsUpdatedMessage
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
  serviceTier?: string | null;
  goal?: SessionGoalRecord;
};

export type SessionGoalRecord = {
  threadId: string;
  objective: string;
  status: GoalStatus;
  tokenBudget?: number | null;
  tokensUsed: number;
  timeUsedSeconds: number;
  createdAt: number;
  updatedAt: number;
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

export type ShellCommandResultMessage = {
  type: "shell.command.result";
  sessionId: string;
  command: string;
  exitCode: number;
  stdout: string;
  stderr: string;
  durationMs: number;
  cwd: string;
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

export type AppProviderCapabilitiesRecord = {
  namespaceTools: boolean;
  imageGeneration: boolean;
  webSearch: boolean;
};

export type AppModelRecord = {
  id: string;
  model: string;
  displayName: string;
  description?: string;
  hidden: boolean;
  supportedReasoningEfforts: ReasoningEffort[];
  defaultReasoningEffort?: ReasoningEffort;
  inputModalities: string[];
  supportsPersonality: boolean;
  serviceTiers: AppModelServiceTierRecord[];
  defaultServiceTier?: string | null;
  isDefault: boolean;
};

export type AppModelServiceTierRecord = {
  id: string;
  name: string;
  description?: string;
};

export type AppThreadRecord = {
  threadId: string;
  codexSessionId?: string;
  parentThreadId?: string;
  title: string;
  preview: string;
  createdAt: string;
  updatedAt: string;
  workdir: string;
  path?: string;
  source?: string;
  status?: string;
  modelProvider?: string;
  cliVersion?: string;
  messageCount?: number;
  agentNickname?: string;
  agentRole?: string;
};

export type AppThreadHistoryRecord = AppThreadRecord & {
  messages: StoredChatMessage[];
};

export type SessionSubagentRecord = {
  threadId: string;
  parentThreadId?: string;
  title: string;
  preview: string;
  status?: string;
  updatedAt: string;
  agentNickname?: string;
  agentRole?: string;
};

export type AppSkillRecord = {
  name: string;
  description: string;
  path: string;
  scope?: string;
  enabled: boolean;
};

export type AppSkillGroupRecord = {
  cwd: string;
  skills: AppSkillRecord[];
  errors: string[];
};

export type AppFsEntryRecord = {
  path: string;
  name: string;
  isDirectory: boolean;
  isFile: boolean;
  sizeBytes?: number;
  mimeType?: string;
};

export type AppFsFileRecord = {
  path: string;
  name: string;
  sizeBytes: number;
  mimeType?: string;
  text?: string;
  dataBase64?: string;
};

export type AppPluginAuthAppRecord = {
  name: string;
  authStatus?: string;
  installUrl?: string;
};

export type AppPluginMcpServerRecord = {
  name: string;
  authStatus?: string;
  toolCount?: number;
};

export type AppPluginSkillRecord = {
  name: string;
  description?: string;
};

export type AppPluginSummaryRecord = {
  id?: string;
  name: string;
  displayName: string;
  description?: string;
  version?: string;
  installed: boolean;
  enabled: boolean;
  category?: string;
  marketplacePath?: string;
  remoteMarketplaceName?: string;
  authType?: string;
};

export type AppPluginMarketplaceRecord = {
  name: string;
  displayName?: string;
  path?: string;
  plugins: AppPluginSummaryRecord[];
};

export type AppPluginDetailRecord = AppPluginSummaryRecord & {
  skills: AppPluginSkillRecord[];
  apps: AppPluginAuthAppRecord[];
  mcpServers: AppPluginMcpServerRecord[];
};

export type AppPluginInstallResultRecord = {
  pluginName: string;
  installed: boolean;
  message?: string;
  appsNeedingAuth: AppPluginAuthAppRecord[];
};

export type AppPluginUninstallResultRecord = {
  pluginName: string;
  uninstalled: boolean;
  message?: string;
};

export type AppMcpServerRecord = {
  name: string;
  status?: string;
  authStatus?: string;
  toolCount: number;
  tools: string[];
  resourceCount: number;
};

export type AppMcpOauthLoginRecord = {
  serverName: string;
  loginUrl?: string;
  status?: string;
  message?: string;
};

export type AppRemoteControlStatusRecord = {
  enabled: boolean;
  connectionStatus?: "disabled" | "connecting" | "connected" | "errored" | string;
  serverName?: string;
  environmentId?: string;
  installationId?: string;
};

export type AppRemotePairingRecord = {
  pairingCode?: string;
  manualPairingCode?: string;
  environmentId?: string;
  expiresAt?: number;
};

export type AppRateLimitRecord = {
  limitId: string;
  planType?: string;
  usedPercent: number;
  remainingPercent: number;
  windowDurationMins?: number;
  resetsAt?: number;
};

export type HostUpdateStatusMessage = {
  type: "host.update.status";
  packageName: string;
  currentVersion: string;
  latestVersion?: string;
  updateAvailable: boolean;
  updateRunning: boolean;
  error?: string;
};

export type HostUpdateProgressPhase = "checking" | "installing" | "completed" | "failed";

export type HostUpdateProgressMessage = {
  type: "host.update.progress";
  packageName: string;
  phase: HostUpdateProgressPhase;
  line: string;
};

export type HostUpdateResultMessage = {
  type: "host.update.result";
  packageName: string;
  previousVersion: string;
  latestVersion?: string;
  updated: boolean;
  exitCode: number;
  stdout: string;
  stderr: string;
  restartRequired: boolean;
  message: string;
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

export type WorkspaceEnvUpdatedMessage = {
  type: "workspace.env.updated";
  sessionId: string;
  path: string;
  variableNames: string[];
  skippedLineCount: number;
};

export type ExternalSessionListMessage = {
  type: "external.session.list";
  sessions: ExternalSessionRecord[];
};

export type AppModelListMessage = {
  type: "app.model.list";
  models: AppModelRecord[];
  capabilities: AppProviderCapabilitiesRecord;
};

export type AppThreadListMessage = {
  type: "app.thread.list";
  threads: AppThreadRecord[];
};

export type AppSkillListMessage = {
  type: "app.skill.list";
  groups: AppSkillGroupRecord[];
};

export type AppFsListMessage = {
  type: "app.fs.list";
  sessionId: string;
  path: string;
  entries: AppFsEntryRecord[];
};

export type AppFsFileMessage = {
  type: "app.fs.file";
  sessionId: string;
  file: AppFsFileRecord;
};

export type AppFsWriteResultMessage = {
  type: "app.fs.write.result";
  sessionId: string;
  file: AppFsFileRecord;
};

export type AppFsDirectoryCreatedMessage = {
  type: "app.fs.directory.created";
  sessionId: string;
  path: string;
};

export type AppFileSearchResultsMessage = {
  type: "app.file.search.results";
  sessionId: string;
  query: string;
  files: WorkspaceFileRecord[];
};

export type AppReviewStartedMessage = {
  type: "app.review.started";
  sessionId: string;
  runId: string;
  reviewThreadId: string;
};

export type CodexAccountInfo = {
  accountType: CodexAccountType;
  email?: string;
  planType?: string | null;
  authMode?: CodexAuthMode;
  requiresOpenaiAuth: boolean;
};

export type CodexAccountLoginFlow =
  | { type: "apiKey" }
  | { type: "chatgpt"; loginId: string; authUrl: string }
  | { type: "chatgptDeviceCode"; loginId: string; verificationUrl: string; userCode: string }
  | { type: "chatgptAuthTokens" };

export type AppAccountStatusMessage = {
  type: "app.account.status";
  account: CodexAccountInfo;
};

export type AppAccountLoginStartedMessage = {
  type: "app.account.login.started";
  flow: CodexAccountLoginFlow;
};

export type AppAccountLoginCancelledMessage = {
  type: "app.account.login.cancelled";
  loginId: string;
  status: CodexAccountLoginCancelStatus;
};

export type AppAccountUpdatedMessage = {
  type: "app.account.updated";
  account: CodexAccountInfo;
};

export type AppAccountLoginCompletedMessage = {
  type: "app.account.login.completed";
  loginId?: string | null;
  success: boolean;
  error?: string | null;
};

export type AppAccountRateLimitsMessage = {
  type: "app.account.rateLimits";
  limits: AppRateLimitRecord[];
};

export type AppPluginListMessage = {
  type: "app.plugin.list";
  marketplaces: AppPluginMarketplaceRecord[];
};

export type AppPluginDetailMessage = {
  type: "app.plugin.detail";
  plugin: AppPluginDetailRecord;
};

export type AppPluginInstallResultMessage = {
  type: "app.plugin.install.result";
} & AppPluginInstallResultRecord;

export type AppPluginUninstallResultMessage = {
  type: "app.plugin.uninstall.result";
} & AppPluginUninstallResultRecord;

export type AppMcpStatusListMessage = {
  type: "app.mcp.status.list";
  servers: AppMcpServerRecord[];
};

export type AppMcpOauthLoginStartedMessage = {
  type: "app.mcp.oauth.login.started";
} & AppMcpOauthLoginRecord;

export type AppRemoteStatusMessage = {
  type: "app.remote.status";
  status: AppRemoteControlStatusRecord;
};

export type AppRemotePairingStartedMessage = {
  type: "app.remote.pairing.started";
  pairing: AppRemotePairingRecord;
};

export type CommandListMessage = {
  type: "command.list";
  commands: CommandRecord[];
};

export type SessionGoalUpdatedMessage = {
  type: "session.goal.updated";
  sessionId: string;
  goal: SessionGoalRecord;
};

export type SessionGoalClearedMessage = {
  type: "session.goal.cleared";
  sessionId: string;
};

export type SessionPlanUpdatedMessage = {
  type: "session.plan.updated";
  sessionId: string;
  runId?: string;
  title: string;
  text: string;
};

export type SessionSubagentsUpdatedMessage = {
  type: "session.subagents.updated";
  sessionId: string;
  runId?: string;
  parentThreadId?: string;
  subagents: SessionSubagentRecord[];
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
