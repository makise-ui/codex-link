import { z } from "zod";

const sessionIdSchema = z.string().trim().min(1);
const runModeSchema = z.enum(["safe", "yolo"]);
const reasoningEffortSchema = z.enum(["low", "medium", "high", "xhigh"]);
const goalStatusSchema = z.enum(["active", "paused", "blocked", "usageLimited", "budgetLimited", "complete"]);
const accountLoginTypeSchema = z.enum(["apiKey", "chatgpt", "chatgptDeviceCode"]);
const attachmentSchema = z.object({
  name: z.string().trim().min(1).max(160),
  mimeType: z.string().trim().min(1).max(120).optional(),
  dataBase64: z.string().min(1).max(8 * 1024 * 1024),
});

export const pairingClaimSchema = z.object({
  type: z.literal("pairing.claim"),
  pairingToken: z.string().min(16),
  deviceName: z.string().trim().min(1).max(80),
});

export const authResumeSchema = z.object({
  type: z.literal("auth.resume"),
  deviceToken: z.string().min(16),
});

export const authPasswordSchema = z.object({
  type: z.literal("auth.password"),
  password: z.string().min(1).max(256),
  deviceName: z.string().trim().min(1).max(80),
});

export const sessionStartSchema = z.object({
  type: z.literal("session.start"),
  sessionId: sessionIdSchema.optional(),
});

export const sessionListSchema = z.object({
  type: z.literal("session.list"),
});

export const sessionCreateSchema = z.object({
  type: z.literal("session.create"),
  title: z.string().trim().min(1).max(80).optional(),
  workspaceId: z.string().trim().min(1).optional(),
  mode: runModeSchema.optional(),
});

export const sessionRenameSchema = z.object({
  type: z.literal("session.rename"),
  sessionId: sessionIdSchema,
  title: z.string().trim().min(1).max(80),
});

export const sessionDeleteSchema = z.object({
  type: z.literal("session.delete"),
  sessionId: sessionIdSchema,
});

export const sessionModeSetSchema = z.object({
  type: z.literal("session.mode.set"),
  sessionId: sessionIdSchema,
  mode: runModeSchema,
});

export const sessionConfigSetSchema = z.object({
  type: z.literal("session.config.set"),
  sessionId: sessionIdSchema,
  model: z.string().trim().max(120).optional(),
  reasoningEffort: reasoningEffortSchema.optional(),
  serviceTier: z.string().trim().max(80).nullable().optional(),
});

export const sessionGoalSetSchema = z.object({
  type: z.literal("session.goal.set"),
  sessionId: sessionIdSchema,
  objective: z.string().trim().min(1).max(4000).optional(),
  status: goalStatusSchema.optional(),
  tokenBudget: z.number().int().positive().nullable().optional(),
});

export const sessionGoalGetSchema = z.object({
  type: z.literal("session.goal.get"),
  sessionId: sessionIdSchema,
});

export const sessionGoalClearSchema = z.object({
  type: z.literal("session.goal.clear"),
  sessionId: sessionIdSchema,
});

export const workspaceListSchema = z.object({
  type: z.literal("workspace.list"),
});

export const workspaceAddSchema = z.object({
  type: z.literal("workspace.add"),
  path: z.string().trim().min(1).max(4096),
  sessionId: sessionIdSchema.optional(),
  create: z.boolean().optional(),
});

export const workspaceSwitchSchema = z.object({
  type: z.literal("workspace.switch"),
  sessionId: sessionIdSchema,
  workspaceId: z.string().trim().min(1),
});

export const workspaceFileSearchSchema = z.object({
  type: z.literal("workspace.file.search"),
  sessionId: sessionIdSchema,
  query: z.string().trim().max(240).optional(),
  limit: z.number().int().min(1).max(80).optional(),
});

export const workspaceEnvSetSchema = z.object({
  type: z.literal("workspace.env.set"),
  sessionId: sessionIdSchema,
  content: z.string().min(1).max(64 * 1024),
  path: z.enum([".env", ".env.local"]).optional(),
});

export const externalSessionListSchema = z.object({
  type: z.literal("external.session.list"),
});

export const externalSessionImportSchema = z.object({
  type: z.literal("external.session.import"),
  externalSessionId: z.string().trim().min(1).max(128),
});

export const appModelListSchema = z.object({
  type: z.literal("app.model.list"),
  sessionId: sessionIdSchema.optional(),
  includeHidden: z.boolean().optional(),
});

export const appThreadListSchema = z.object({
  type: z.literal("app.thread.list"),
  sessionId: sessionIdSchema.optional(),
  query: z.string().trim().max(240).optional(),
  cwd: z.string().trim().min(1).max(4096).optional(),
  limit: z.number().int().min(1).max(80).optional(),
});

export const appThreadImportSchema = z.object({
  type: z.literal("app.thread.import"),
  threadId: z.string().trim().min(1).max(160),
});

export const appSkillListSchema = z.object({
  type: z.literal("app.skill.list"),
  sessionId: sessionIdSchema.optional(),
  forceReload: z.boolean().optional(),
});

export const appFsListSchema = z.object({
  type: z.literal("app.fs.list"),
  sessionId: sessionIdSchema,
  path: z.string().trim().max(4096).optional(),
});

export const appFsReadSchema = z.object({
  type: z.literal("app.fs.read"),
  sessionId: sessionIdSchema,
  path: z.string().trim().min(1).max(4096),
});

export const appFsWriteSchema = z.object({
  type: z.literal("app.fs.write"),
  sessionId: sessionIdSchema,
  path: z.string().trim().min(1).max(4096),
  dataBase64: z.string().min(1).max(8 * 1024 * 1024),
});

export const appFsCreateDirectorySchema = z.object({
  type: z.literal("app.fs.createDirectory"),
  sessionId: sessionIdSchema,
  path: z.string().trim().min(1).max(4096),
});

export const appFileSearchSchema = z.object({
  type: z.literal("app.file.search"),
  sessionId: sessionIdSchema,
  query: z.string().trim().min(1).max(240),
  limit: z.number().int().min(1).max(80).optional(),
});

export const appReviewStartSchema = z.object({
  type: z.literal("app.review.start"),
  sessionId: sessionIdSchema,
  target: z.enum(["uncommittedChanges", "custom"]).optional(),
  instructions: z.string().trim().max(4000).optional(),
  delivery: z.enum(["inline", "detached"]).optional(),
});

export const appAccountReadSchema = z.object({
  type: z.literal("app.account.read"),
  refreshToken: z.boolean().optional(),
});

export const appAccountLoginStartSchema = z.object({
  type: z.literal("app.account.login.start"),
  loginType: accountLoginTypeSchema,
  apiKey: z.string().trim().min(1).max(4096).optional(),
  codexStreamlinedLogin: z.boolean().optional(),
});

export const appAccountLoginCancelSchema = z.object({
  type: z.literal("app.account.login.cancel"),
  loginId: z.string().trim().min(1).max(240),
});

export const appAccountLogoutSchema = z.object({
  type: z.literal("app.account.logout"),
});

export const appAccountRateLimitsReadSchema = z.object({
  type: z.literal("app.account.rateLimits.read"),
});

export const appPluginListSchema = z.object({
  type: z.literal("app.plugin.list"),
  sessionId: sessionIdSchema.optional(),
});

const appPluginLocatorSchema = {
  pluginName: z.string().trim().min(1).max(160),
  marketplacePath: z.string().trim().min(1).max(4096).optional(),
  remoteMarketplaceName: z.string().trim().min(1).max(160).optional(),
};

export const appPluginReadSchema = z.object({
  type: z.literal("app.plugin.read"),
  ...appPluginLocatorSchema,
});

export const appPluginInstallSchema = z.object({
  type: z.literal("app.plugin.install"),
  ...appPluginLocatorSchema,
});

export const appPluginUninstallSchema = z.object({
  type: z.literal("app.plugin.uninstall"),
  pluginName: z.string().trim().min(1).max(160),
});

export const appMcpStatusListSchema = z.object({
  type: z.literal("app.mcp.status.list"),
  sessionId: sessionIdSchema.optional(),
  detail: z.enum(["full", "toolsAndAuthOnly"]).optional(),
});

export const appMcpOauthLoginSchema = z.object({
  type: z.literal("app.mcp.oauth.login"),
  serverName: z.string().trim().min(1).max(160),
});

export const appRemoteStatusReadSchema = z.object({
  type: z.literal("app.remote.status.read"),
});

export const appRemotePairingStartSchema = z.object({
  type: z.literal("app.remote.pairing.start"),
  manualPairingCode: z.string().trim().min(1).max(160).optional(),
});

export const commandListSchema = z.object({
  type: z.literal("command.list"),
});

export const commandRunSchema = z.object({
  type: z.literal("command.run"),
  commandId: z.string().trim().min(1).max(80),
  sessionId: sessionIdSchema.optional(),
});

export const promptSendSchema = z.object({
  type: z.literal("prompt.send"),
  sessionId: sessionIdSchema,
  prompt: z.string().min(1).max(64 * 1024),
  attachments: z.array(attachmentSchema).max(4).optional(),
});

export const fileRequestSchema = z.object({
  type: z.literal("file.request"),
  fileId: z.string().trim().min(1).max(160),
});

export const fileOfferRequestSchema = z.object({
  type: z.literal("file.offer.request"),
  sessionId: sessionIdSchema,
  path: z.string().trim().min(1).max(4096),
});

export const runCancelSchema = z.object({
  type: z.literal("run.cancel"),
  sessionId: sessionIdSchema,
  runId: z.string().min(1),
});

export const approvalDecisionSchema = z.object({
  type: z.literal("approval.decision"),
  sessionId: sessionIdSchema,
  approvalId: z.string().min(1),
  decision: z.enum(["approve", "reject"]),
});

export const pingSchema = z.object({
  type: z.literal("ping"),
  nonce: z.string().optional(),
});

export const clientMessageSchema = z.discriminatedUnion("type", [
  pairingClaimSchema,
  authResumeSchema,
  authPasswordSchema,
  sessionStartSchema,
  sessionListSchema,
  sessionCreateSchema,
  sessionRenameSchema,
  sessionDeleteSchema,
  sessionModeSetSchema,
  sessionConfigSetSchema,
  sessionGoalSetSchema,
  sessionGoalGetSchema,
  sessionGoalClearSchema,
  workspaceListSchema,
  workspaceAddSchema,
  workspaceSwitchSchema,
  workspaceFileSearchSchema,
  workspaceEnvSetSchema,
  externalSessionListSchema,
  externalSessionImportSchema,
  appModelListSchema,
  appThreadListSchema,
  appThreadImportSchema,
  appSkillListSchema,
  appFsListSchema,
  appFsReadSchema,
  appFsWriteSchema,
  appFsCreateDirectorySchema,
  appFileSearchSchema,
  appReviewStartSchema,
  appAccountReadSchema,
  appAccountLoginStartSchema,
  appAccountLoginCancelSchema,
  appAccountLogoutSchema,
  appAccountRateLimitsReadSchema,
  appPluginListSchema,
  appPluginReadSchema,
  appPluginInstallSchema,
  appPluginUninstallSchema,
  appMcpStatusListSchema,
  appMcpOauthLoginSchema,
  appRemoteStatusReadSchema,
  appRemotePairingStartSchema,
  commandListSchema,
  commandRunSchema,
  promptSendSchema,
  fileOfferRequestSchema,
  fileRequestSchema,
  runCancelSchema,
  approvalDecisionSchema,
  pingSchema,
]);

export type ParsedClientMessage = z.infer<typeof clientMessageSchema>;

export function parseClientMessage(raw: unknown): ParsedClientMessage {
  return clientMessageSchema.parse(raw);
}
