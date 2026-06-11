import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import path from "node:path";
import readline from "node:readline";
import type { AppFsEntryRecord, AppFsFileRecord, AppMcpOauthLoginRecord, AppMcpServerRecord, AppModelRecord, AppPluginDetailRecord, AppPluginInstallResultRecord, AppPluginMarketplaceRecord, AppPluginSummaryRecord, AppPluginUninstallResultRecord, AppProviderCapabilitiesRecord, AppRateLimitRecord, AppRemoteControlStatusRecord, AppRemotePairingRecord, AppSkillGroupRecord, AppThreadHistoryRecord, AppThreadRecord, ApprovalRequestedMessage, CodexAccountInfo, CodexAccountLoginFlow, CodexAccountType, CodexAuthMode, GoalStatus, MessageKind, ReasoningEffort, SandboxMode, SessionGoalRecord, SessionSubagentRecord, StoredChatMessage, WorkspaceFileRecord } from "../protocol/messages.js";
import type { AccountLoginCancelResult, AccountLoginStartInput, AppFileSearchInput, AppMcpStatusListInput, AppModelListResult, AppPluginListInput, AppPluginLocatorInput, AppRemotePairingInput, AppReviewStartInput, AppReviewStartResult, AppSkillListInput, AppThreadListInput, CodexEvent, CodexSession, GoalSetInput, PreparedAttachment, SendPromptOptions, SendPromptResult } from "./codexSession.js";
import { mimeTypeFor } from "./fileTransferManager.js";

type Listener = (event: CodexEvent) => void;

export type AppServerCodexSessionOptions = {
  sessionId?: string;
  command: string;
  argsPrefix?: string[];
  workdir: string;
  sandbox?: SandboxMode;
  model?: string;
  reasoningEffort?: ReasoningEffort;
  serviceTier?: string | null;
  codexThreadId?: string;
  onThreadStarted?: (threadId: string) => void | Promise<void>;
};

type RpcResponse = {
  id: number | string;
  result?: unknown;
  error?: { code?: number; message?: string };
};

type RpcNotification = {
  method: string;
  params?: Record<string, unknown>;
};

type RpcRequest = RpcNotification & {
  id: number | string;
};

type PendingRequest = {
  method: string;
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
};

type PendingApproval = {
  requestId: number | string;
  method: string;
  params: Record<string, unknown>;
};

type ActiveTurn = {
  turnId: string;
  itemMessageIds: Map<string, string>;
  messageKinds: Map<string, MessageKind>;
  itemTextLengths: Map<string, number>;
  thinkingMessageId?: string;
};

export class AppServerCodexSession implements CodexSession {
  readonly sessionId: string;
  private readonly listeners = new Set<Listener>();
  private readonly pending = new Map<number | string, PendingRequest>();
  private readonly pendingApprovals = new Map<string, PendingApproval>();
  private child?: ChildProcessWithoutNullStreams;
  private initialized?: Promise<void>;
  private requestId = 0;
  private messageCounter = 0;
  private codexThreadId?: string;
  private threadLoaded = false;
  private activeTurn?: ActiveTurn;
  private readonly subagents = new Map<string, SessionSubagentRecord>();
  private readonly subagentThreadIds = new Set<string>();
  private readonly subagentTurnIds = new Set<string>();

  constructor(private readonly options: AppServerCodexSessionOptions) {
    this.sessionId = options.sessionId ?? "default";
    this.codexThreadId = options.codexThreadId;
  }

  async start(): Promise<void> {
    await this.ensureInitialized();
    this.emit({ type: "session.started", sessionId: this.sessionId });
    this.emit({
      type: "status",
      status: "connected",
      sessionId: this.sessionId,
      detail: `app-server workdir=${path.resolve(this.options.workdir)}`,
    });
  }

  async sendPrompt(prompt: string, options: SendPromptOptions = {}): Promise<SendPromptResult> {
    const threadId = await this.ensureThread();
    const input = userInputFromPrompt(prompt, options.attachments);
    if (this.activeTurn?.turnId) {
      const result = await this.request<{ turnId: string }>("turn/steer", {
        threadId,
        expectedTurnId: this.activeTurn.turnId,
        input,
      });
      return { runId: result.turnId };
    }

    const result = await this.request<{ turn: { id: string } }>("turn/start", {
      threadId,
      input,
      cwd: path.resolve(this.options.workdir),
      model: trimmedOrNull(this.options.model),
      serviceTier: trimmedOrNull(this.options.serviceTier ?? undefined),
      effort: this.options.reasoningEffort ?? null,
    });
    return { runId: result.turn.id };
  }

  async listModels(includeHidden = false): Promise<AppModelListResult> {
    await this.ensureInitialized();
    const [modelsResult, capabilitiesResult] = await Promise.all([
      this.request<{ data: unknown[] }>("model/list", {
        includeHidden,
        limit: 100,
      }),
      this.request<unknown>("modelProvider/capabilities/read", {}),
    ]);
    return {
      models: modelsResult.data.map(normalizeModel).filter((model): model is AppModelRecord => model !== undefined),
      capabilities: normalizeProviderCapabilities(capabilitiesResult),
    };
  }

  async listThreads(input: AppThreadListInput = {}): Promise<AppThreadRecord[]> {
    await this.ensureInitialized();
    const params: Record<string, unknown> = {
      limit: Math.min(Math.max(Math.trunc(input.limit ?? 40), 1), 80),
      sortKey: "updated_at",
      sortDirection: "desc",
    };
    if (input.query?.trim()) params.searchTerm = input.query.trim();
    if (input.cwd?.trim()) params.cwd = path.resolve(input.cwd.trim());
    const result = await this.request<{ data: unknown[] }>("thread/list", params);
    return result.data.map(normalizeThread).filter((thread): thread is AppThreadRecord => thread !== undefined);
  }

  async readThread(threadId: string, includeTurns = true): Promise<AppThreadHistoryRecord> {
    await this.ensureInitialized();
    const result = await this.request<{ thread: unknown }>("thread/read", { threadId, includeTurns });
    const thread = normalizeThreadHistory(result.thread);
    if (!thread) {
      throw new Error(`App-server did not return a readable thread: ${threadId}`);
    }
    return thread;
  }

  async listSkills(input: AppSkillListInput = {}): Promise<{ groups: AppSkillGroupRecord[] }> {
    await this.ensureInitialized();
    const result = await this.request<{ data: unknown[] }>("skills/list", {
      cwds: input.cwds?.map((cwd) => path.resolve(cwd)),
      forceReload: input.forceReload ?? false,
    });
    return {
      groups: result.data.map(normalizeSkillGroup).filter((group): group is AppSkillGroupRecord => group !== undefined),
    };
  }

  async listDirectory(absolutePath: string): Promise<AppFsEntryRecord[]> {
    await this.ensureInitialized();
    const resolved = path.resolve(absolutePath);
    const result = await this.request<{ entries: unknown[] }>("fs/readDirectory", { path: resolved });
    return result.entries
      .map((entry) => normalizeDirectoryEntry(entry, resolved, this.options.workdir))
      .filter((entry): entry is AppFsEntryRecord => entry !== undefined);
  }

  async readFile(absolutePath: string): Promise<AppFsFileRecord> {
    await this.ensureInitialized();
    const resolved = path.resolve(absolutePath);
    const result = await this.request<{ dataBase64: string }>("fs/readFile", { path: resolved });
    const bytes = Buffer.from(result.dataBase64 ?? "", "base64");
    const relativePath = relativeToWorkdir(resolved, this.options.workdir);
    return {
      path: relativePath,
      name: path.basename(resolved),
      sizeBytes: bytes.byteLength,
      mimeType: mimeTypeFor(resolved),
      text: isLikelyText(bytes, resolved) ? bytes.toString("utf8") : undefined,
      dataBase64: isLikelyText(bytes, resolved) ? undefined : result.dataBase64,
    };
  }

  async writeFile(absolutePath: string, dataBase64: string): Promise<AppFsFileRecord> {
    await this.ensureInitialized();
    const resolved = path.resolve(absolutePath);
    await this.request("fs/writeFile", { path: resolved, dataBase64 });
    const bytes = Buffer.from(dataBase64, "base64");
    return {
      path: relativeToWorkdir(resolved, this.options.workdir),
      name: path.basename(resolved),
      sizeBytes: bytes.byteLength,
      mimeType: mimeTypeFor(resolved),
      text: isLikelyText(bytes, resolved) ? bytes.toString("utf8") : undefined,
      dataBase64: isLikelyText(bytes, resolved) ? undefined : dataBase64,
    };
  }

  async createDirectory(absolutePath: string): Promise<void> {
    await this.ensureInitialized();
    await this.request("fs/createDirectory", {
      path: path.resolve(absolutePath),
      recursive: true,
    });
  }

  async searchFiles(input: AppFileSearchInput): Promise<WorkspaceFileRecord[]> {
    await this.ensureInitialized();
    const result = await this.request<{ files: unknown[] }>("fuzzyFileSearch", {
      query: input.query.trim().replace(/^@+/, ""),
      roots: input.roots.map((root) => path.resolve(root)),
      cancellationToken: null,
    });
    return result.files
      .map(normalizeFuzzyFile)
      .filter((file): file is WorkspaceFileRecord => file !== undefined)
      .slice(0, Math.min(Math.max(Math.trunc(input.limit ?? 40), 1), 80));
  }

  async startReview(input: AppReviewStartInput): Promise<AppReviewStartResult> {
    const threadId = await this.ensureThread();
    const result = await this.request<{ turn: { id: string }; reviewThreadId: string }>("review/start", {
      threadId,
      target: input.target,
      delivery: input.delivery ?? "inline",
    });
    return {
      runId: result.turn.id,
      reviewThreadId: result.reviewThreadId,
    };
  }

  async getAccount(refreshToken = false): Promise<CodexAccountInfo> {
    await this.ensureInitialized();
    const accountResult = await this.request<unknown>("account/read", { refreshToken });
    let authStatus: unknown;
    try {
      authStatus = await this.request("getAuthStatus", { includeToken: false, refreshToken: false });
    } catch {
      authStatus = undefined;
    }
    return normalizeAccount(accountResult, authStatus);
  }

  async startAccountLogin(input: AccountLoginStartInput): Promise<CodexAccountLoginFlow> {
    await this.ensureInitialized();
    const params = input.type === "apiKey"
      ? { type: "apiKey", apiKey: input.apiKey.trim() }
      : input.type === "chatgpt"
        ? { type: "chatgpt", ...(input.codexStreamlinedLogin === undefined ? {} : { codexStreamlinedLogin: input.codexStreamlinedLogin }) }
        : { type: "chatgptDeviceCode" };
    const result = await this.request<unknown>("account/login/start", params);
    return normalizeLoginFlow(result);
  }

  async cancelAccountLogin(loginId: string): Promise<AccountLoginCancelResult> {
    await this.ensureInitialized();
    const result = await this.request<unknown>("account/login/cancel", { loginId });
    return normalizeCancelLogin(result);
  }

  async logoutAccount(): Promise<void> {
    await this.ensureInitialized();
    await this.request("account/logout", undefined);
  }

  async readRateLimits(): Promise<AppRateLimitRecord[]> {
    await this.ensureInitialized();
    const result = await this.request<unknown>("account/rateLimits/read", {});
    return normalizeRateLimits(result);
  }

  async listPlugins(input: AppPluginListInput = {}): Promise<{ marketplaces: AppPluginMarketplaceRecord[] }> {
    await this.ensureInitialized();
    const result = await this.request<unknown>("plugin/list", {
      cwds: [path.resolve(input.cwd ?? this.options.workdir)],
      marketplaceKinds: null,
    });
    return { marketplaces: normalizePluginMarketplaces(result) };
  }

  async readPlugin(input: AppPluginLocatorInput): Promise<AppPluginDetailRecord> {
    await this.ensureInitialized();
    const result = await this.request<unknown>("plugin/read", pluginLocatorParams(input));
    const plugin = normalizePluginDetail(result, input);
    if (!plugin) {
      throw new Error(`App-server did not return a readable plugin: ${input.pluginName}`);
    }
    return plugin;
  }

  async installPlugin(input: AppPluginLocatorInput): Promise<AppPluginInstallResultRecord> {
    await this.ensureInitialized();
    const result = await this.request<unknown>("plugin/install", pluginLocatorParams(input));
    return normalizePluginInstallResult(result, input.pluginName);
  }

  async uninstallPlugin(pluginName: string): Promise<AppPluginUninstallResultRecord> {
    await this.ensureInitialized();
    const result = await this.request<unknown>("plugin/uninstall", { pluginName });
    return normalizePluginUninstallResult(result, pluginName);
  }

  async listMcpServers(input: AppMcpStatusListInput = {}): Promise<AppMcpServerRecord[]> {
    await this.ensureInitialized();
    const result = await this.request<unknown>("mcpServerStatus/list", {
      limit: 80,
      detail: input.detail ?? "toolsAndAuthOnly",
    });
    return normalizeMcpServers(result);
  }

  async startMcpOauthLogin(serverName: string): Promise<AppMcpOauthLoginRecord> {
    await this.ensureInitialized();
    const result = await this.request<unknown>("mcpServer/oauth/login", { name: serverName });
    return normalizeMcpOauthLogin(result, serverName);
  }

  async readRemoteControlStatus(): Promise<AppRemoteControlStatusRecord> {
    await this.ensureInitialized();
    const result = await this.request<unknown>("remoteControl/status/read", {});
    return normalizeRemoteControlStatus(result);
  }

  async startRemoteControlPairing(input: AppRemotePairingInput = {}): Promise<AppRemotePairingRecord> {
    await this.ensureInitialized();
    const status = await this.readRemoteControlStatus();
    if (!status.enabled) {
      await this.request("remoteControl/enable", undefined);
    }
    const result = await this.request<unknown>("remoteControl/pairing/start", {
      ...(input.manualPairingCode ? { manualCode: true } : {}),
    });
    return normalizeRemotePairing(result);
  }

  async setGoal(input: GoalSetInput): Promise<SessionGoalRecord> {
    const threadId = await this.ensureThread();
    const result = await this.request<{ goal: unknown }>("thread/goal/set", {
      threadId,
      objective: input.objective ?? null,
      status: input.status ?? null,
      tokenBudget: input.tokenBudget ?? null,
    });
    return normalizeGoal(result.goal);
  }

  async getGoal(): Promise<SessionGoalRecord | null> {
    const threadId = await this.ensureThread();
    const result = await this.request<{ goal: unknown | null }>("thread/goal/get", { threadId });
    return result.goal ? normalizeGoal(result.goal) : null;
  }

  async clearGoal(): Promise<boolean> {
    const threadId = await this.ensureThread();
    const result = await this.request<{ cleared: boolean }>("thread/goal/clear", { threadId });
    return result.cleared;
  }

  async cancel(runId: string): Promise<void> {
    const threadId = this.codexThreadId;
    if (!threadId) {
      throw new Error("No active app-server thread is available.");
    }
    this.emit({ type: "status", status: "cancelling", sessionId: this.sessionId, runId });
    await this.request("turn/interrupt", { threadId, turnId: runId });
  }

  async decideApproval(approvalId: string, decision: "approve" | "reject"): Promise<void> {
    const approval = this.pendingApprovals.get(approvalId);
    if (!approval) {
      throw new Error(`Unknown approval request: ${approvalId}`);
    }
    this.pendingApprovals.delete(approvalId);
    this.write({
      id: approval.requestId,
      result: approvalResponse(approval.method, approval.params, decision),
    });
  }

  onEvent(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async close(): Promise<void> {
    for (const request of this.pending.values()) {
      clearTimeout(request.timer);
      request.reject(new Error("App-server session closed."));
    }
    this.pending.clear();
    if (this.child && !this.child.killed) {
      this.child.kill("SIGTERM");
    }
    this.child = undefined;
    this.initialized = undefined;
    this.threadLoaded = false;
    this.activeTurn = undefined;
    this.subagents.clear();
    this.subagentThreadIds.clear();
    this.subagentTurnIds.clear();
    this.listeners.clear();
  }

  private async ensureThread(): Promise<string> {
    await this.ensureInitialized();
    if (this.codexThreadId) {
      if (!this.threadLoaded) {
        const result = await this.request<{ thread: { id: string } }>("thread/resume", {
          threadId: this.codexThreadId,
          cwd: path.resolve(this.options.workdir),
          model: trimmedOrNull(this.options.model),
          serviceTier: trimmedOrNull(this.options.serviceTier ?? undefined),
          sandbox: this.options.sandbox ?? "workspace-write",
          approvalPolicy: approvalPolicyForSandbox(this.options.sandbox),
          approvalsReviewer: "user",
          config: this.options.reasoningEffort
            ? { model_reasoning_effort: this.options.reasoningEffort }
            : null,
        });
        await this.setThreadId(result.thread.id);
        this.threadLoaded = true;
      }
      return this.codexThreadId;
    }
    const result = await this.request<{ thread: { id: string } }>("thread/start", {
      cwd: path.resolve(this.options.workdir),
      model: trimmedOrNull(this.options.model),
      serviceTier: trimmedOrNull(this.options.serviceTier ?? undefined),
      sandbox: this.options.sandbox ?? "workspace-write",
      approvalPolicy: approvalPolicyForSandbox(this.options.sandbox),
      approvalsReviewer: "user",
      config: this.options.reasoningEffort
        ? { model_reasoning_effort: this.options.reasoningEffort }
        : null,
      threadSource: "user",
    });
    await this.setThreadId(result.thread.id);
    this.threadLoaded = true;
    return result.thread.id;
  }

  private ensureInitialized(): Promise<void> {
    if (this.initialized) return this.initialized;
    this.initialized = this.startProcessAndInitialize();
    return this.initialized;
  }

  private async startProcessAndInitialize(): Promise<void> {
    const args = this.options.argsPrefix ?? ["app-server"];
    const child = spawn(this.options.command, args, {
      cwd: path.resolve(this.options.workdir),
      shell: false,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.child = child;

    const rl = readline.createInterface({ input: child.stdout });
    rl.on("line", (line) => this.handleLine(line));
    child.stderr.on("data", (chunk: Buffer) => {
      const text = chunk.toString("utf8");
      if (text.trim().length > 0) {
        this.emit({
          type: "output.delta",
          sessionId: this.sessionId,
          runId: this.activeTurn?.turnId ?? "app-server",
          stream: "stderr",
          text,
        });
      }
    });
    child.on("error", (error) => {
      this.rejectAll(error);
      this.emit({
        type: "status",
        status: "failed",
        sessionId: this.sessionId,
        detail: `app-server error: ${error.message}`,
      });
    });
    child.on("close", (code) => {
      this.rejectAll(new Error(`app-server exited with code ${code ?? "signal"}`));
      const runId = this.activeTurn?.turnId;
      if (runId) {
        this.emit({ type: "status", status: "failed", sessionId: this.sessionId, runId });
        this.emit({ type: "run.completed", sessionId: this.sessionId, runId, exitCode: code ?? undefined });
      }
      this.activeTurn = undefined;
    });

    await this.request("initialize", {
      clientInfo: {
        name: "codex_link_mobile",
        title: "Codex Link Mobile",
        version: "0.1.0",
      },
      capabilities: { experimentalApi: true },
    });
    this.write({ method: "initialized", params: {} });
  }

  private request<T = unknown>(method: string, params: unknown): Promise<T> {
    const id = ++this.requestId;
    const child = this.child;
    if (!child) {
      throw new Error("App-server process is not started.");
    }
    const request = { id, method, params };
    child.stdin.write(`${JSON.stringify(request)}\n`);
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Timed out waiting for app-server response: ${method}`));
      }, 30_000);
      this.pending.set(id, {
        method,
        resolve: (value) => resolve(value as T),
        reject,
        timer,
      });
    });
  }

  private write(message: unknown): void {
    const child = this.child;
    if (!child) return;
    child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  private handleLine(line: string): void {
    if (line.trim().length === 0) return;
    let message: unknown;
    try {
      message = JSON.parse(line);
    } catch (error) {
      this.emitSystemMessage(`Unparsed app-server output: ${error instanceof Error ? error.message : String(error)}\n`, "Raw app-server output");
      return;
    }
    if (!message || typeof message !== "object" || Array.isArray(message)) return;
    const record = message as Partial<RpcResponse & RpcNotification & RpcRequest>;
    if (record.id !== undefined && record.method) {
      this.handleServerRequest(record as RpcRequest);
      return;
    }
    if (record.id !== undefined) {
      this.handleResponse(record as RpcResponse);
      return;
    }
    if (record.method) {
      this.handleNotification(record as RpcNotification);
    }
  }

  private handleResponse(message: RpcResponse): void {
    const pending = this.pending.get(message.id);
    if (!pending) return;
    this.pending.delete(message.id);
    clearTimeout(pending.timer);
    if (message.error) {
      pending.reject(new Error(`${pending.method}: ${message.error.message ?? "Unknown app-server error"}`));
      return;
    }
    pending.resolve(message.result);
  }

  private handleServerRequest(message: RpcRequest): void {
    if (isApprovalMethod(message.method)) {
      const params = safeRecord(message.params);
      const approvalId = String(params.approvalId ?? params.itemId ?? message.id);
      this.pendingApprovals.set(approvalId, {
        requestId: message.id,
        method: message.method,
        params,
      });
      this.emit(approvalMessage(this.sessionId, approvalId, message.method, params));
      return;
    }
    this.write({
      id: message.id,
      error: { code: -32601, message: `Unsupported app-server request: ${message.method}` },
    });
  }

  private handleNotification(message: RpcNotification): void {
    const params = safeRecord(message.params);
    if (this.isSubagentNotification(message.method, params)) return;
    switch (message.method) {
      case "thread/started":
        void this.handleThreadStarted(params);
        return;
      case "thread/goal/updated":
        this.emit({
          type: "session.goal.updated",
          sessionId: this.sessionId,
          goal: normalizeGoal(params.goal),
        });
        return;
      case "thread/goal/cleared":
        this.emit({ type: "session.goal.cleared", sessionId: this.sessionId });
        return;
      case "account/updated":
        this.emit({
          type: "app.account.updated",
          account: normalizeAccountUpdate(params),
        });
        return;
      case "account/login/completed":
        this.emit({
          type: "app.account.login.completed",
          loginId: readString(params, "loginId") ?? null,
          success: params.success === true,
          error: readString(params, "error") ?? null,
        });
        return;
      case "turn/started":
        this.handleTurnStarted(params);
        return;
      case "turn/completed":
        this.handleTurnCompleted(params);
        return;
      case "item/started":
        this.handleItemStarted(params);
        return;
      case "item/agentMessage/delta":
        this.handleItemDelta(params, "response");
        return;
      case "item/reasoning/summaryPartAdded":
        this.handleReasoningSummaryPartAdded(params);
        return;
      case "item/reasoning/summaryTextDelta":
        this.handleReasoningSummaryDelta(params);
        return;
      case "item/reasoning/textDelta":
        this.ensureThinking(readString(params, "turnId") ?? this.activeTurn?.turnId ?? "");
        return;
      case "item/commandExecution/outputDelta":
        this.handleItemDelta(params, "executing");
        return;
      case "item/commandExecution/terminalInteraction":
        this.handleTerminalInteraction(params);
        return;
      case "item/fileChange/outputDelta":
        this.handleItemDelta(params, "executing");
        return;
      case "item/fileChange/patchUpdated":
        this.handleFilePatchUpdated(params);
        return;
      case "item/completed":
        this.handleItemCompleted(params);
        return;
      case "turn/diff/updated":
        this.handleTurnDiffUpdated(params);
        return;
      case "turn/plan/updated":
        this.handlePlanUpdated(params);
        return;
      case "item/mcpToolCall/progress":
        this.handleMcpProgress(params);
        return;
      case "warning":
      case "guardianWarning":
        this.handleWarning(params);
        return;
      default:
        return;
    }
  }

  private async handleThreadStarted(params: Record<string, unknown>): Promise<void> {
    const thread = safeRecord(params.thread);
    const normalized = normalizeThread(thread);
    if (!normalized?.threadId) return;
    if (this.isSubagentThread(normalized)) {
      this.updateSubagent({
        ...normalized,
        parentThreadId: normalized.parentThreadId ?? this.codexThreadId,
      });
      return;
    }
    await this.setThreadId(normalized.threadId);
  }

  private async setThreadId(threadId: string): Promise<void> {
    if (this.codexThreadId === threadId) {
      this.threadLoaded = true;
      return;
    }
    this.codexThreadId = threadId;
    this.threadLoaded = true;
    await this.options.onThreadStarted?.(threadId);
  }

  private handleTurnStarted(params: Record<string, unknown>): void {
    const turn = safeRecord(params.turn);
    const turnId = readString(turn, "id");
    if (!turnId) return;
    this.subagents.clear();
    this.subagentThreadIds.clear();
    this.subagentTurnIds.clear();
    this.activeTurn = {
      turnId,
      itemMessageIds: new Map(),
      messageKinds: new Map(),
      itemTextLengths: new Map(),
    };
    this.emit({ type: "run.started", sessionId: this.sessionId, runId: turnId });
    this.emit({ type: "status", status: "running", sessionId: this.sessionId, runId: turnId });
    this.ensureThinking(turnId);
  }

  private handleTurnCompleted(params: Record<string, unknown>): void {
    const turn = safeRecord(params.turn);
    const turnId = readString(turn, "id") ?? this.activeTurn?.turnId;
    if (!turnId) return;
    this.completeOpenMessages(turnId);
    const status = readString(turn, "status");
    if (status === "interrupted") {
      this.emit({ type: "status", status: "cancelled", sessionId: this.sessionId, runId: turnId });
      this.emit({ type: "run.completed", sessionId: this.sessionId, runId: turnId, exitCode: 0 });
    } else if (status === "failed") {
      this.emit({ type: "status", status: "failed", sessionId: this.sessionId, runId: turnId });
      this.emit({ type: "run.completed", sessionId: this.sessionId, runId: turnId, exitCode: 1 });
    } else {
      this.emit({ type: "status", status: "completed", sessionId: this.sessionId, runId: turnId });
      this.emit({ type: "run.completed", sessionId: this.sessionId, runId: turnId, exitCode: 0 });
    }
    this.clearSubagents(turnId);
    this.activeTurn = undefined;
  }

  private isSubagentThread(thread: AppThreadRecord): boolean {
    return Boolean(
      this.codexThreadId &&
        ((thread.parentThreadId && thread.parentThreadId === this.codexThreadId) ||
          (this.activeTurn && thread.threadId !== this.codexThreadId)),
    );
  }

  private updateSubagent(thread: AppThreadRecord): void {
    this.subagentThreadIds.add(thread.threadId);
    this.subagents.set(thread.threadId, subagentRecordFromThread(thread));
    this.emitSubagentsUpdated();
  }

  private clearSubagents(runId?: string): void {
    if (this.subagents.size === 0) return;
    this.subagents.clear();
    this.subagentThreadIds.clear();
    this.subagentTurnIds.clear();
    this.emitSubagentsUpdated(runId);
  }

  private emitSubagentsUpdated(runId = this.activeTurn?.turnId): void {
    this.emit({
      type: "session.subagents.updated",
      sessionId: this.sessionId,
      runId,
      parentThreadId: this.codexThreadId,
      subagents: [...this.subagents.values()],
    });
  }

  private isSubagentNotification(method: string, params: Record<string, unknown>): boolean {
    if (method === "thread/started") return false;
    const threadId = readString(params, "threadId");
    const turnId = notificationTurnId(params);
    const isChildThread =
      Boolean(threadId && this.codexThreadId && threadId !== this.codexThreadId) ||
      Boolean(threadId && this.subagentThreadIds.has(threadId));
    const isChildTurn = Boolean(turnId && this.subagentTurnIds.has(turnId));
    if (!isChildThread && !isChildTurn) return false;
    if (threadId) this.subagentThreadIds.add(threadId);
    if (turnId && method === "turn/started") {
      this.subagentTurnIds.add(turnId);
    }
    if (threadId) {
      this.ensureSyntheticSubagent(threadId, method === "turn/completed" ? "completed" : "running");
    }
    if (turnId && method === "turn/completed") {
      this.subagentTurnIds.delete(turnId);
    }
    return true;
  }

  private ensureSyntheticSubagent(threadId: string, status: string): void {
    const existing = this.subagents.get(threadId);
    if (existing) {
      if (existing.status !== status) {
        this.subagents.set(threadId, { ...existing, status, updatedAt: new Date().toISOString() });
        this.emitSubagentsUpdated();
      }
      return;
    }
    this.subagents.set(threadId, {
      threadId,
      parentThreadId: this.codexThreadId,
      title: "Subagent",
      preview: "",
      status,
      updatedAt: new Date().toISOString(),
    });
    this.emitSubagentsUpdated();
  }

  private handleItemStarted(params: Record<string, unknown>): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    const item = safeRecord(params.item);
    if (!turnId) return;
    if (readString(item, "type") === "reasoning") {
      this.ensureThinking(turnId);
      return;
    }
    const id = readString(item, "id");
    const presentation = itemPresentation(item);
    if (!presentation) return;
    if (presentation.kind !== "thinking") {
      this.completeThinking(turnId);
    }
    this.emitStartedMessage(turnId, presentation.kind, presentation.title, presentation.text, id);
  }

  private handleItemDelta(params: Record<string, unknown>, fallbackKind: MessageKind): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    const itemId = readString(params, "itemId");
    const delta = readString(params, "delta") ?? "";
    if (!turnId || !itemId || delta.length === 0) return;
    const messageId = this.messageIdForItem(turnId, itemId, fallbackKind);
    this.emitDelta(turnId, messageId, itemId, delta);
  }

  private handleReasoningSummaryPartAdded(params: Record<string, unknown>): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    const itemId = readString(params, "itemId");
    if (!turnId || !itemId) return;
    this.messageIdForItem(turnId, reasoningSummaryKey(itemId, params.summaryIndex), "reasoning", "Thinking summary");
  }

  private handleReasoningSummaryDelta(params: Record<string, unknown>): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    const itemId = readString(params, "itemId");
    const delta = readString(params, "delta") ?? "";
    if (!turnId || !itemId || delta.length === 0) return;
    const key = reasoningSummaryKey(itemId, params.summaryIndex);
    const messageId = this.messageIdForItem(turnId, key, "reasoning", "Thinking summary");
    this.emitDelta(turnId, messageId, key, delta);
  }

  private handleMcpProgress(params: Record<string, unknown>): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    const itemId = readString(params, "itemId");
    const message = readString(params, "message");
    if (!turnId || !itemId || !message) return;
    const messageId = this.messageIdForItem(turnId, itemId, "executing", "Using MCP tool");
    this.emitDelta(turnId, messageId, itemId, `${message}\n`);
  }

  private handleTerminalInteraction(params: Record<string, unknown>): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    const itemId = readString(params, "itemId");
    const stdin = readString(params, "stdin");
    if (!turnId || !itemId || !stdin) return;
    const messageId = this.messageIdForItem(turnId, itemId, "executing", "Running command");
    this.emitDelta(turnId, messageId, itemId, `\nTerminal input:\n${stdin}\n`);
  }

  private handleTurnDiffUpdated(params: Record<string, unknown>): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    const diff = readString(params, "diff");
    if (!turnId || !diff) return;
    const files = parseUnifiedDiffFiles(diff);
    if (files.length > 0) {
      this.emit({
        type: "diff.available",
        sessionId: this.sessionId,
        files,
      });
    }
  }

  private handleWarning(params: Record<string, unknown>): void {
    const warning = readString(params, "message");
    if (!warning) return;
    this.emitSystemMessage(`${warning}\n`, "Warning");
  }

  private handleFilePatchUpdated(params: Record<string, unknown>): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    const itemId = readString(params, "itemId");
    const changes = readChanges(params.changes);
    if (!turnId || !itemId || changes.length === 0) return;
    const messageId = this.messageIdForItem(turnId, itemId, "executing", "Editing files");
    const text = formatChanges(changes);
    this.emitDelta(turnId, messageId, itemId, text.endsWith("\n") ? text : `${text}\n`);
    this.emit({
      type: "diff.available",
      sessionId: this.sessionId,
      files: changes.map((change) => ({
        path: change.path,
        status: change.status,
        patch: change.diff || undefined,
      })),
    });
  }

  private handleItemCompleted(params: Record<string, unknown>): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    const item = safeRecord(params.item);
    const itemId = readString(item, "id");
    if (!turnId || !itemId) return;
    const kind = readString(item, "type");
    if (kind === "agentMessage") {
      this.emitCompletionTextIfNeeded(turnId, itemId, readString(item, "text"));
    }
    if (kind === "commandExecution") {
      this.emitCompletionTextIfNeeded(turnId, itemId, readString(item, "aggregatedOutput"));
    }
    if (kind === "fileChange") {
      const changes = readChanges(item.changes);
      if (changes.length > 0) {
        this.emit({
          type: "diff.available",
          sessionId: this.sessionId,
          files: changes.map((change) => ({
            path: change.path,
            status: change.status,
            patch: change.diff || undefined,
          })),
        });
      }
    }
    const messageId = this.activeTurn?.itemMessageIds.get(itemId);
    if (messageId) {
      this.emit({ type: "message.completed", sessionId: this.sessionId, runId: turnId, messageId });
      this.activeTurn?.messageKinds.delete(messageId);
      this.activeTurn?.itemMessageIds.delete(itemId);
    }
    this.ensureThinking(turnId);
  }

  private handlePlanUpdated(params: Record<string, unknown>): void {
    const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
    if (!turnId) return;
    const explanation = readString(params, "explanation");
    const plan = Array.isArray(params.plan)
      ? params.plan.map((item) => safeRecord(item)).map((item) => `- ${readString(item, "status") ?? "pending"}: ${readString(item, "step") ?? ""}`)
      : [];
    const text = [explanation, ...plan].filter(Boolean).join("\n");
    if (text.trim().length === 0) return;
    this.emit({
      type: "session.plan.updated",
      sessionId: this.sessionId,
      runId: turnId,
      title: "Plan",
      text: text.endsWith("\n") ? text : `${text}\n`,
    });
  }

  private emitCompletionTextIfNeeded(turnId: string, itemId: string, text?: string): void {
    if (!text || text.length === 0) return;
    const emittedLength = this.activeTurn?.itemTextLengths.get(itemId) ?? 0;
    if (emittedLength >= text.length) return;
    const messageId = this.messageIdForItem(turnId, itemId, "response");
    this.emitDelta(turnId, messageId, itemId, text.slice(emittedLength));
  }

  private messageIdForItem(turnId: string, itemId: string, fallbackKind: MessageKind, title?: string): string {
    const existing = this.activeTurn?.itemMessageIds.get(itemId);
    if (existing) return existing;
    return this.emitStartedMessage(turnId, fallbackKind, title ?? readableTitle(fallbackKind), undefined, itemId);
  }

  private emitStartedMessage(runId: string, kind: MessageKind, title?: string, text?: string, itemId?: string): string {
    const messageId = `${runId}:${++this.messageCounter}`;
    if (this.activeTurn && itemId) {
      this.activeTurn.itemMessageIds.set(itemId, messageId);
      this.activeTurn.itemTextLengths.set(itemId, 0);
    }
    this.activeTurn?.messageKinds.set(messageId, kind);
    if (kind === "thinking") {
      if (this.activeTurn) this.activeTurn.thinkingMessageId = messageId;
    }
    this.emit({
      type: "message.started",
      sessionId: this.sessionId,
      runId,
      messageId,
      kind,
      role: kind === "response" ? "assistant" : "system",
      title,
    });
    if (text) {
      this.emitDelta(runId, messageId, itemId, text.endsWith("\n") ? text : `${text}\n`);
    }
    return messageId;
  }

  private emitCompleteMessage(runId: string, kind: MessageKind, title: string | undefined, text: string): void {
    if (kind !== "thinking") this.completeThinking(runId);
    const messageId = this.emitStartedMessage(runId, kind, title);
    this.emit({ type: "message.delta", sessionId: this.sessionId, runId, messageId, text });
    this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId });
    if (kind !== "thinking") this.ensureThinking(runId);
  }

  private emitDelta(runId: string, messageId: string, itemId: string | undefined, text: string): void {
    this.emit({ type: "message.delta", sessionId: this.sessionId, runId, messageId, text });
    if (this.activeTurn && itemId) {
      this.activeTurn.itemTextLengths.set(itemId, (this.activeTurn.itemTextLengths.get(itemId) ?? 0) + text.length);
    }
  }

  private ensureThinking(runId: string): void {
    if (!this.activeTurn || this.activeTurn.thinkingMessageId) return;
    this.emitStartedMessage(runId, "thinking", "Thinking", "Thinking…\n");
  }

  private completeThinking(runId: string): void {
    const thinkingMessageId = this.activeTurn?.thinkingMessageId;
    if (!thinkingMessageId) return;
    this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId: thinkingMessageId });
    this.activeTurn?.messageKinds.delete(thinkingMessageId);
    if (this.activeTurn) this.activeTurn.thinkingMessageId = undefined;
  }

  private completeOpenMessages(runId: string): void {
    this.completeThinking(runId);
    const active = this.activeTurn;
    if (!active) return;
    for (const messageId of active.itemMessageIds.values()) {
      this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId });
    }
    active.itemMessageIds.clear();
    active.messageKinds.clear();
    active.itemTextLengths.clear();
  }

  private emitSystemMessage(text: string, title?: string): void {
    const runId = this.activeTurn?.turnId ?? "app-server";
    this.emitCompleteMessage(runId, "system", title, text);
  }

  private rejectAll(error: Error): void {
    for (const request of this.pending.values()) {
      clearTimeout(request.timer);
      request.reject(error);
    }
    this.pending.clear();
  }

  private emit(event: CodexEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }
}

function userInputFromPrompt(prompt: string, attachments: PreparedAttachment[] = []): Array<Record<string, unknown>> {
  const input: Array<Record<string, unknown>> = [
    { type: "text", text: prompt, text_elements: [] },
  ];
  for (const attachment of attachments) {
    input.push(
      attachment.kind === "image"
        ? { type: "localImage", path: attachment.path, detail: "auto" }
        : { type: "mention", name: attachment.name, path: attachment.path },
    );
  }
  return input;
}

function itemPresentation(item: Record<string, unknown>): { kind: MessageKind; title: string; text?: string } | undefined {
  const type = readString(item, "type");
  switch (type) {
    case "agentMessage":
      return { kind: "response", title: "Response", text: readString(item, "text") };
    case "plan":
      return undefined;
    case "reasoning":
      return { kind: "thinking", title: "Thinking", text: "Thinking…" };
    case "commandExecution":
      return commandPresentation(item);
    case "fileChange": {
      const changes = readChanges(item.changes);
      return { kind: "executing", title: "Editing files", text: formatChanges(changes) || "Applying file changes..." };
    }
    case "mcpToolCall":
      return { kind: "executing", title: "Using MCP tool", text: `${readString(item, "server") ?? "mcp"} ${readString(item, "tool") ?? ""}`.trim() };
    case "dynamicToolCall":
      return { kind: "executing", title: "Running tool", text: `${readString(item, "namespace") ?? ""} ${readString(item, "tool") ?? ""}`.trim() };
    case "webSearch":
      return { kind: "executing", title: "Searching web", text: readString(item, "query") };
    case "imageView":
      return { kind: "executing", title: "Viewing image", text: readString(item, "path") };
    case "imageGeneration":
      return { kind: "executing", title: "Generating image", text: readString(item, "revisedPrompt") ?? "Generating image..." };
    case "contextCompaction":
      return { kind: "executing", title: "Compacting context", text: "Compacting context..." };
    default:
      return undefined;
  }
}

function commandPresentation(item: Record<string, unknown>): { kind: MessageKind; title: string; text?: string } {
  const command = readString(item, "command") ?? "";
  const readAction = (Array.isArray(item.commandActions) ? item.commandActions : [])
    .map((action) => safeRecord(action))
    .find((action) => readString(action, "type") === "read");
  if (readAction || isReadCommand(command)) {
    const filePath = readString(readAction ?? {}, "path") ?? readCommandPath(command);
    const skillName = filePath ? skillNameFromPath(filePath) : undefined;
    if (skillName) {
      return {
        kind: "executing",
        title: "Using skill",
        text: [
          `Using skill: ${skillName}`,
          filePath ? `File: ${filePath}` : undefined,
          command ? `Command: ${command}` : undefined,
        ].filter(Boolean).join("\n"),
      };
    }
    return {
      kind: "executing",
      title: "Reading file",
      text: [
        filePath ? `Reading file: ${filePath}` : "Reading file...",
        command ? `Command: ${command}` : undefined,
      ].filter(Boolean).join("\n"),
    };
  }
  return {
    kind: "executing",
    title: "Running command",
    text: command || "Running command...",
  };
}

function readChanges(value: unknown): Array<{ path: string; status: "added" | "modified" | "deleted" | "renamed"; diff: string }> {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    const record = safeRecord(entry);
    const filePath = readString(record, "path");
    if (!filePath) return [];
    const kind = safeRecord(record.kind);
    const type = readString(kind, "type");
    const status = type === "add" ? "added" : type === "delete" ? "deleted" : type === "update" && readString(kind, "move_path") ? "renamed" : "modified";
    return [{ path: shortPath(filePath), status, diff: readString(record, "diff") ?? "" }];
  });
}

function formatChanges(changes: Array<{ path: string; status: string; diff: string }>): string {
  return changes
    .flatMap((change) => [
      `${change.status} ${change.path}`,
      ...(change.diff ? change.diff.split(/\r?\n/) : []),
    ])
    .filter(Boolean)
    .join("\n");
}

function normalizeAccount(value: unknown, authStatusValue: unknown): CodexAccountInfo {
  const record = safeRecord(value);
  const account = safeRecord(record.account);
  const authStatus = safeRecord(authStatusValue);
  const accountType = normalizeAccountType(readString(account, "type"));
  const authMode = normalizeAuthMode(readString(authStatus, "authMethod")) ?? authModeFromAccountType(accountType);
  return {
    accountType,
    email: readString(account, "email"),
    planType: readString(account, "planType") ?? null,
    authMode,
    requiresOpenaiAuth: record.requiresOpenaiAuth === true || authStatus.requiresOpenaiAuth === true,
  };
}

function normalizeAccountUpdate(value: unknown): CodexAccountInfo {
  const record = safeRecord(value);
  const authMode = normalizeAuthMode(readString(record, "authMode"));
  return {
    accountType: accountTypeFromAuthMode(authMode),
    planType: readString(record, "planType") ?? null,
    authMode,
    requiresOpenaiAuth: authMode === null,
  };
}

function normalizeLoginFlow(value: unknown): CodexAccountLoginFlow {
  const record = safeRecord(value);
  const type = readString(record, "type");
  if (type === "apiKey") return { type: "apiKey" };
  if (type === "chatgpt") {
    return {
      type: "chatgpt",
      loginId: readString(record, "loginId") ?? "",
      authUrl: readString(record, "authUrl") ?? "",
    };
  }
  if (type === "chatgptDeviceCode") {
    return {
      type: "chatgptDeviceCode",
      loginId: readString(record, "loginId") ?? "",
      verificationUrl: readString(record, "verificationUrl") ?? "",
      userCode: readString(record, "userCode") ?? "",
    };
  }
  if (type === "chatgptAuthTokens") return { type: "chatgptAuthTokens" };
  throw new Error(`Unsupported account login response: ${type ?? "unknown"}`);
}

function normalizeCancelLogin(value: unknown): AccountLoginCancelResult {
  const status = readString(safeRecord(value), "status");
  return { status: status === "notFound" ? "notFound" : "canceled" };
}

function pluginLocatorParams(input: AppPluginLocatorInput): Record<string, unknown> {
  return {
    pluginName: input.pluginName.trim(),
    ...(input.marketplacePath?.trim() ? { marketplacePath: input.marketplacePath.trim() } : {}),
    ...(!input.marketplacePath?.trim() && input.remoteMarketplaceName?.trim() ? { remoteMarketplaceName: input.remoteMarketplaceName.trim() } : {}),
  };
}

function normalizeRateLimits(value: unknown): AppRateLimitRecord[] {
  const record = safeRecord(value);
  const limits = Array.isArray(record.rateLimits)
    ? record.rateLimits
    : Object.keys(safeRecord(record.rateLimits)).length > 0
      ? [record.rateLimits]
    : Array.isArray(record.data)
      ? record.data
      : Object.keys(safeRecord(record.rateLimitsByLimitId)).length > 0
        ? Object.values(safeRecord(record.rateLimitsByLimitId))
      : Array.isArray(value)
        ? value
        : [];
  return limits.map(normalizeRateLimit).filter((limit): limit is AppRateLimitRecord => limit !== undefined);
}

function normalizeRateLimit(value: unknown): AppRateLimitRecord | undefined {
  const record = safeRecord(value);
  const primary = safeRecord(record.primary);
  const usedPercent = clampPercent(readNumber(primary, "usedPercent") ?? readNumber(record, "usedPercent") ?? 0);
  const remainingPercent = clampPercent(readNumber(record, "remainingPercent") ?? (100 - usedPercent));
  const limitId = readString(record, "limitId") ?? readString(record, "id") ?? "codex";
  return {
    limitId,
    planType: readString(record, "planType"),
    usedPercent,
    remainingPercent,
    windowDurationMins: readNumber(primary, "windowDurationMins") ?? readNumber(record, "windowDurationMins"),
    resetsAt: readNumber(primary, "resetsAt") ?? readNumber(record, "resetsAt"),
  };
}

function normalizePluginMarketplaces(value: unknown): AppPluginMarketplaceRecord[] {
  const record = safeRecord(value);
  const marketplaces = Array.isArray(record.marketplaces)
    ? record.marketplaces
    : Array.isArray(record.data)
      ? record.data
      : Array.isArray(value)
        ? value
        : [];
  return marketplaces
    .map(normalizePluginMarketplace)
    .filter((marketplace): marketplace is AppPluginMarketplaceRecord => marketplace !== undefined);
}

function normalizePluginMarketplace(value: unknown): AppPluginMarketplaceRecord | undefined {
  const record = safeRecord(value);
  const name = readString(record, "name") ?? readString(record, "id");
  if (!name) return undefined;
  const marketplacePath = readString(record, "path") ?? readString(record, "marketplacePath");
  const remoteMarketplaceName = readString(record, "remoteMarketplaceName");
  const plugins = Array.isArray(record.plugins)
    ? record.plugins
    : Array.isArray(record.items)
      ? record.items
      : [];
  return {
    name,
    displayName: readString(record, "displayName") ?? readString(record, "title"),
    path: marketplacePath,
    plugins: plugins
      .map((plugin) => normalizePluginSummary(plugin, { marketplacePath, remoteMarketplaceName }))
      .filter((plugin): plugin is AppPluginSummaryRecord => plugin !== undefined),
  };
}

function normalizePluginSummary(value: unknown, defaults: { marketplacePath?: string; remoteMarketplaceName?: string } = {}): AppPluginSummaryRecord | undefined {
  const record = safeRecord(value);
  const name = readString(record, "name") ?? readString(record, "id") ?? readString(record, "pluginName");
  if (!name) return undefined;
  const categories = Array.isArray(record.categories) ? record.categories.filter((item): item is string => typeof item === "string") : [];
  return {
    id: readString(record, "id"),
    name,
    displayName: readString(record, "displayName") ?? readString(record, "title") ?? name,
    description: readString(record, "description") ?? readString(record, "shortDescription"),
    version: readString(record, "version"),
    installed: record.installed === true || record.isInstalled === true,
    enabled: record.enabled !== false,
    category: readString(record, "category") ?? categories[0],
    marketplacePath: readString(record, "marketplacePath") ?? defaults.marketplacePath,
    remoteMarketplaceName: readString(record, "remoteMarketplaceName") ?? defaults.remoteMarketplaceName,
    authType: readString(safeRecord(record.auth), "type") ?? readString(record, "authType"),
  };
}

function normalizePluginDetail(value: unknown, input: AppPluginLocatorInput): AppPluginDetailRecord | undefined {
  const envelope = safeRecord(value);
  const record = safeRecord(envelope.plugin && typeof envelope.plugin === "object" ? envelope.plugin : value);
  const summary = normalizePluginSummary(record, {
    marketplacePath: input.marketplacePath,
    remoteMarketplaceName: input.remoteMarketplaceName,
  }) ?? {
    name: input.pluginName,
    displayName: input.pluginName,
    installed: false,
    enabled: true,
    marketplacePath: input.marketplacePath,
    remoteMarketplaceName: input.remoteMarketplaceName,
  };
  return {
    ...summary,
    skills: normalizePluginSkills(record.skills),
    apps: normalizePluginAuthApps(record.apps ?? record.authApps),
    mcpServers: normalizePluginMcpServers(record.mcpServers ?? record.mcp_servers),
  };
}

function normalizePluginSkills(value: unknown): AppPluginDetailRecord["skills"] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const record = safeRecord(item);
    const name = readString(record, "name");
    if (!name) return [];
    return [{ name, description: readString(record, "description") }];
  });
}

function normalizePluginAuthApps(value: unknown): AppPluginDetailRecord["apps"] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const record = safeRecord(item);
    const name = readString(record, "name") ?? readString(record, "id");
    if (!name) return [];
    return [{
      name,
      authStatus: readString(record, "authStatus") ?? readString(record, "status"),
      installUrl: readString(record, "installUrl") ?? readString(record, "url"),
    }];
  });
}

function normalizePluginMcpServers(value: unknown): AppPluginDetailRecord["mcpServers"] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const record = safeRecord(item);
    const name = readString(record, "name") ?? readString(record, "id");
    if (!name) return [];
    return [{
      name,
      authStatus: readString(record, "authStatus") ?? readString(record, "status"),
      toolCount: readNumber(record, "toolCount") ?? (Array.isArray(record.tools) ? record.tools.length : undefined),
    }];
  });
}

function normalizePluginInstallResult(value: unknown, pluginName: string): AppPluginInstallResultRecord {
  const record = safeRecord(value);
  return {
    pluginName: readString(record, "pluginName") ?? readString(record, "name") ?? pluginName,
    installed: record.installed !== false,
    message: readString(record, "message"),
    appsNeedingAuth: normalizePluginAuthApps(record.appsNeedingAuth ?? record.apps),
  };
}

function normalizePluginUninstallResult(value: unknown, pluginName: string): AppPluginUninstallResultRecord {
  const record = safeRecord(value);
  return {
    pluginName: readString(record, "pluginName") ?? readString(record, "name") ?? pluginName,
    uninstalled: record.uninstalled !== false,
    message: readString(record, "message"),
  };
}

function normalizeMcpServers(value: unknown): AppMcpServerRecord[] {
  const record = safeRecord(value);
  const servers = Array.isArray(record.servers)
    ? record.servers
    : Array.isArray(record.data)
      ? record.data
      : Array.isArray(value)
        ? value
        : [];
  return servers.map(normalizeMcpServer).filter((server): server is AppMcpServerRecord => server !== undefined);
}

function normalizeMcpServer(value: unknown): AppMcpServerRecord | undefined {
  const record = safeRecord(value);
  const name = readString(record, "name") ?? readString(record, "id");
  if (!name) return undefined;
  const tools = normalizeToolNames(record.tools);
  const resources = Array.isArray(record.resources) ? record.resources : [];
  return {
    name,
    status: readString(record, "status") ?? readString(safeRecord(record.connection), "status"),
    authStatus: readString(record, "authStatus") ?? readString(safeRecord(record.auth), "status"),
    toolCount: readNumber(record, "toolCount") ?? tools.length,
    tools,
    resourceCount: readNumber(record, "resourceCount") ?? resources.length,
  };
}

function normalizeToolNames(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => typeof item === "string" ? item : readString(safeRecord(item), "name"))
    .filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

function normalizeMcpOauthLogin(value: unknown, serverName: string): AppMcpOauthLoginRecord {
  const record = safeRecord(value);
  return {
    serverName: readString(record, "serverName") ?? readString(record, "name") ?? serverName,
    loginUrl: readString(record, "loginUrl") ?? readString(record, "authUrl") ?? readString(record, "url"),
    status: readString(record, "status"),
    message: readString(record, "message"),
  };
}

function normalizeRemoteControlStatus(value: unknown): AppRemoteControlStatusRecord {
  const record = safeRecord(value);
  const status = safeRecord(record.status);
  const source = Object.keys(status).length > 0 ? status : record;
  const connectionStatus = readString(source, "status");
  return {
    enabled: source.enabled === true || connectionStatus === "connecting" || connectionStatus === "connected" || connectionStatus === "errored",
    connectionStatus,
    serverName: readString(source, "serverName") ?? readString(source, "name"),
    environmentId: readString(source, "environmentId"),
    installationId: readString(source, "installationId"),
  };
}

function normalizeRemotePairing(value: unknown): AppRemotePairingRecord {
  const record = safeRecord(value);
  const pairing = safeRecord(record.pairing);
  const source = Object.keys(pairing).length > 0 ? pairing : record;
  return {
    pairingCode: readString(source, "pairingCode"),
    manualPairingCode: readString(source, "manualPairingCode"),
    environmentId: readString(source, "environmentId"),
    expiresAt: readNumber(source, "expiresAt"),
  };
}

function normalizeAccountType(value: string | undefined): CodexAccountType {
  return value === "apiKey" || value === "chatgpt" || value === "amazonBedrock" ? value : null;
}

function normalizeAuthMode(value: string | undefined): CodexAuthMode {
  return value === "apikey" || value === "chatgpt" || value === "chatgptAuthTokens" || value === "agentIdentity" ? value : null;
}

function authModeFromAccountType(accountType: CodexAccountType): CodexAuthMode {
  if (accountType === "apiKey") return "apikey";
  if (accountType === "chatgpt") return "chatgpt";
  return null;
}

function accountTypeFromAuthMode(authMode: CodexAuthMode): CodexAccountType {
  if (authMode === "apikey") return "apiKey";
  if (authMode === "chatgpt" || authMode === "chatgptAuthTokens") return "chatgpt";
  return null;
}

function normalizeGoal(value: unknown): SessionGoalRecord {
  const record = safeRecord(value);
  const status = readString(record, "status");
  return {
    threadId: readString(record, "threadId") ?? "",
    objective: readString(record, "objective") ?? "",
    status: isGoalStatus(status) ? status : "active",
    tokenBudget: typeof record.tokenBudget === "number" || record.tokenBudget === null ? record.tokenBudget : null,
    tokensUsed: typeof record.tokensUsed === "number" ? record.tokensUsed : 0,
    timeUsedSeconds: typeof record.timeUsedSeconds === "number" ? record.timeUsedSeconds : 0,
    createdAt: typeof record.createdAt === "number" ? record.createdAt : 0,
    updatedAt: typeof record.updatedAt === "number" ? record.updatedAt : 0,
  };
}

function normalizeModel(value: unknown): AppModelRecord | undefined {
  const record = safeRecord(value);
  const id = readString(record, "id") ?? readString(record, "model");
  const model = readString(record, "model") ?? id;
  if (!id || !model) return undefined;
  const efforts = Array.isArray(record.supportedReasoningEfforts)
    ? record.supportedReasoningEfforts
        .map((effort) => readString(safeRecord(effort), "reasoningEffort"))
        .filter(isReasoningEffort)
    : [];
  const defaultEffort = readString(record, "defaultReasoningEffort");
  const serviceTiers = Array.isArray(record.serviceTiers)
    ? record.serviceTiers
        .map(normalizeModelServiceTier)
        .filter((tier): tier is NonNullable<ReturnType<typeof normalizeModelServiceTier>> => tier !== undefined)
    : Array.isArray(record.additionalSpeedTiers)
      ? record.additionalSpeedTiers
          .map((tier) => {
            const id = typeof tier === "string" ? tier : undefined;
            return id ? { id, name: id } : undefined;
          })
          .filter((tier): tier is AppModelRecord["serviceTiers"][number] => tier !== undefined)
      : [];
  return {
    id,
    model,
    displayName: readString(record, "displayName") ?? id,
    description: readString(record, "description"),
    hidden: record.hidden === true,
    supportedReasoningEfforts: efforts,
    defaultReasoningEffort: isReasoningEffort(defaultEffort) ? defaultEffort : undefined,
    inputModalities: Array.isArray(record.inputModalities) ? record.inputModalities.filter((item): item is string => typeof item === "string") : ["text"],
    supportsPersonality: record.supportsPersonality === true,
    serviceTiers,
    defaultServiceTier: readString(record, "defaultServiceTier") ?? null,
    isDefault: record.isDefault === true,
  };
}

function normalizeModelServiceTier(value: unknown): AppModelRecord["serviceTiers"][number] | undefined {
  const record = safeRecord(value);
  const id = readString(record, "id");
  if (!id) return undefined;
  return {
    id,
    name: readString(record, "name") ?? id,
    description: readString(record, "description"),
  };
}

function normalizeProviderCapabilities(value: unknown): AppProviderCapabilitiesRecord {
  const record = safeRecord(value);
  return {
    namespaceTools: record.namespaceTools === true,
    imageGeneration: record.imageGeneration === true,
    webSearch: record.webSearch === true,
  };
}

function normalizeThread(value: unknown): AppThreadRecord | undefined {
  const record = safeRecord(value);
  const threadId = readString(record, "id") ?? readString(record, "sessionId");
  if (!threadId) return undefined;
  const preview = readString(record, "preview") ?? "";
  const name = readString(record, "name");
  const cwd = readString(record, "cwd") ?? "";
  const turns = Array.isArray(record.turns) ? record.turns : [];
  return {
    threadId,
    codexSessionId: readString(record, "sessionId"),
    parentThreadId: readString(record, "parentThreadId") ?? readString(record, "forkedFromId"),
    title: name ?? firstNonEmptyLine(preview) ?? (cwd ? path.basename(cwd) : threadId),
    preview,
    createdAt: timestampToIso(record.createdAt),
    updatedAt: timestampToIso(record.updatedAt),
    workdir: cwd,
    path: readString(record, "path"),
    source: readString(record, "source"),
    status: readString(safeRecord(record.status), "type"),
    modelProvider: readString(record, "modelProvider"),
    cliVersion: readString(record, "cliVersion"),
    messageCount: countThreadMessages(turns),
    agentNickname: readString(record, "agentNickname"),
    agentRole: readString(record, "agentRole"),
  };
}

function subagentRecordFromThread(thread: AppThreadRecord): SessionSubagentRecord {
  return {
    threadId: thread.threadId,
    parentThreadId: thread.parentThreadId,
    title: thread.title,
    preview: thread.preview,
    status: thread.status,
    updatedAt: thread.updatedAt,
    agentNickname: thread.agentNickname,
    agentRole: thread.agentRole,
  };
}

function notificationTurnId(params: Record<string, unknown>): string | undefined {
  return readString(params, "turnId") ?? readString(safeRecord(params.turn), "id");
}

function normalizeThreadHistory(value: unknown): AppThreadHistoryRecord | undefined {
  const thread = normalizeThread(value);
  if (!thread) return undefined;
  const record = safeRecord(value);
  return {
    ...thread,
    messages: Array.isArray(record.turns) ? messagesFromTurns(record.turns) : [],
  };
}

function normalizeSkillGroup(value: unknown): AppSkillGroupRecord | undefined {
  const record = safeRecord(value);
  const cwd = readString(record, "cwd");
  if (!cwd) return undefined;
  const skills: AppSkillGroupRecord["skills"] = [];
  if (Array.isArray(record.skills)) {
    for (const skill of record.skills) {
      const item = safeRecord(skill);
      const name = readString(item, "name");
      const description = readString(item, "description") ?? readString(item, "shortDescription") ?? "";
      const skillPath = readString(item, "path");
      if (!name || !skillPath) continue;
      const scope = readString(item, "scope");
      skills.push({
        name,
        description,
        path: skillPath,
        ...(scope ? { scope } : {}),
        enabled: item.enabled !== false,
      });
    }
  }
  const errors = Array.isArray(record.errors)
    ? record.errors.map((error) => readString(safeRecord(error), "message") ?? String(error)).filter(Boolean)
    : [];
  return { cwd, skills, errors };
}

function normalizeDirectoryEntry(value: unknown, directory: string, workdir: string): AppFsEntryRecord | undefined {
  const record = safeRecord(value);
  const name = readString(record, "fileName");
  if (!name) return undefined;
  const absolutePath = path.join(directory, name);
  return {
    path: relativeToWorkdir(absolutePath, workdir),
    name,
    isDirectory: record.isDirectory === true,
    isFile: record.isFile === true,
    mimeType: record.isFile === true ? mimeTypeFor(name) : undefined,
  };
}

function normalizeFuzzyFile(value: unknown): WorkspaceFileRecord | undefined {
  const record = safeRecord(value);
  const filePath = readString(record, "path");
  if (!filePath) return undefined;
  return {
    path: toPosixPath(filePath),
    name: readString(record, "file_name") ?? path.basename(filePath),
    mimeType: mimeTypeFor(filePath),
  };
}

function messagesFromTurns(turns: unknown[]): StoredChatMessage[] {
  const messages: StoredChatMessage[] = [];
  for (const turn of turns) {
    const turnRecord = safeRecord(turn);
    const turnId = readString(turnRecord, "id") ?? "turn";
    const createdAt = timestampToIso(turnRecord.startedAt);
    const items = Array.isArray(turnRecord.items) ? turnRecord.items : [];
    for (const itemValue of items) {
      const item = safeRecord(itemValue);
      const itemId = readString(item, "id") ?? `${turnId}:${messages.length + 1}`;
      const type = readString(item, "type");
      if (type === "userMessage") {
        const text = userMessageText(item);
        if (text) {
          messages.push({ messageId: `${turnId}:${itemId}`, role: "user", kind: "response", text, createdAt, complete: true });
        }
      }
      if (type === "agentMessage") {
        const text = readString(item, "text");
        if (text) {
          messages.push({ messageId: `${turnId}:${itemId}`, role: "assistant", kind: "response", text, createdAt, complete: true });
        }
      }
      if (type === "commandExecution") {
        const text = [readString(item, "command"), readString(item, "aggregatedOutput")].filter(Boolean).join("\n");
        if (text) {
          messages.push({ messageId: `${turnId}:${itemId}`, role: "system", kind: "executing", title: commandPresentation(item).title, text, createdAt, complete: true });
        }
      }
    }
  }
  return messages;
}

function userMessageText(item: Record<string, unknown>): string {
  const content = Array.isArray(item.content) ? item.content : [];
  return content
    .map((part) => readString(safeRecord(part), "text"))
    .filter(Boolean)
    .join("\n");
}

function countThreadMessages(turns: unknown[]): number {
  return turns.reduce<number>((count, turn) => {
    const items = Array.isArray(safeRecord(turn).items) ? safeRecord(turn).items as unknown[] : [];
    return count + items.filter((item) => {
      const type = readString(safeRecord(item), "type");
      return type === "userMessage" || type === "agentMessage";
    }).length;
  }, 0);
}

function parseUnifiedDiffFiles(diff: string): Array<{ path: string; status: "added" | "modified" | "deleted" | "renamed"; patch?: string }> {
  const lines = diff.split(/\r?\n/);
  const starts: number[] = [];
  for (const [index, line] of lines.entries()) {
    if (line.startsWith("diff --git ")) starts.push(index);
  }
  if (starts.length === 0 && diff.trim()) {
    return [{ path: "workspace", status: "modified", patch: diff }];
  }
  const files: Array<{ path: string; status: "added" | "modified" | "deleted" | "renamed"; patch?: string }> = [];
  for (const [index, start] of starts.entries()) {
    const end = starts[index + 1] ?? lines.length;
    const patch = lines.slice(start, end).join("\n");
    const header = lines[start] ?? "";
    const match = header.match(/^diff --git a\/(.+?) b\/(.+)$/);
    if (!match) continue;
    const isDeleted = patch.includes("\n+++ /dev/null");
    const isAdded = patch.includes("\n--- /dev/null");
    files.push({
      path: isDeleted ? match[1] : match[2],
      status: isAdded ? "added" : isDeleted ? "deleted" : patch.includes("\nrename to ") ? "renamed" : "modified",
      patch,
    });
  }
  return files;
}

function relativeToWorkdir(absolutePath: string, workdir: string): string {
  const relative = path.relative(path.resolve(workdir), path.resolve(absolutePath));
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    return toPosixPath(absolutePath);
  }
  return toPosixPath(relative);
}

function toPosixPath(value: string): string {
  return value.replace(/\\/g, "/");
}

function firstNonEmptyLine(value: string): string | undefined {
  const line = value.split(/\r?\n/).map((item) => item.trim()).find(Boolean);
  if (!line) return undefined;
  return line.length > 80 ? `${line.slice(0, 77)}...` : line;
}

function timestampToIso(value: unknown): string {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(value * 1000).toISOString();
  }
  if (typeof value === "string" && value.trim()) {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return date.toISOString();
  }
  return new Date(0).toISOString();
}

function reasoningSummaryKey(itemId: string, summaryIndex: unknown): string {
  return `reasoning:${itemId}:${typeof summaryIndex === "number" ? summaryIndex : 0}`;
}

function isLikelyText(bytes: Buffer, filePath: string): boolean {
  const mimeType = mimeTypeFor(filePath) ?? "";
  if (mimeType.startsWith("text/") || /json|xml|yaml|javascript|typescript|dart|markdown/.test(mimeType)) return true;
  if (bytes.includes(0)) return false;
  return bytes.byteLength < 512 * 1024;
}

function approvalMessage(sessionId: string, approvalId: string, method: string, params: Record<string, unknown>): ApprovalRequestedMessage {
  const command = readString(params, "command");
  const reason = readString(params, "reason");
  const cwd = readString(params, "cwd");
  const title = method.includes("fileChange")
    ? "Approve file change"
    : method.includes("permissions")
      ? "Approve permissions"
      : "Approve command";
  const body = [
    command,
    cwd ? `cwd: ${cwd}` : undefined,
    reason,
  ].filter(Boolean).join("\n") || title;
  return {
    type: "approval.requested",
    sessionId,
    approvalId,
    title,
    body,
    riskLevel: "medium",
  };
}

function approvalResponse(method: string, params: Record<string, unknown>, decision: "approve" | "reject"): Record<string, unknown> {
  if (method === "item/permissions/requestApproval") {
    return decision === "approve"
      ? {
          permissions: {
            network: safeRecord(params.permissions).network ?? undefined,
            fileSystem: safeRecord(params.permissions).fileSystem ?? undefined,
          },
          scope: "turn",
        }
      : { permissions: {}, scope: "turn" };
  }
  return { decision: decision === "approve" ? "accept" : "decline" };
}

function isApprovalMethod(method: string): boolean {
  return method === "item/commandExecution/requestApproval" ||
    method === "item/fileChange/requestApproval" ||
    method === "item/permissions/requestApproval";
}

function safeRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function readString(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function readNumber(record: Record<string, unknown>, key: string): number | undefined {
  const value = record[key];
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function clampPercent(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value)));
}

function trimmedOrNull(value: string | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function readableTitle(kind: MessageKind): string {
  return kind === "response" ? "Response" : kind === "executing" ? "Running tool" : kind === "thinking" ? "Thinking" : kind === "reasoning" ? "Thinking summary" : "System";
}

function isGoalStatus(value: string | undefined): value is GoalStatus {
  return value === "active" || value === "paused" || value === "blocked" || value === "usageLimited" || value === "budgetLimited" || value === "complete";
}

function isReasoningEffort(value: string | undefined): value is ReasoningEffort {
  return value === "low" || value === "medium" || value === "high" || value === "xhigh";
}

function approvalPolicyForSandbox(sandbox: SandboxMode | undefined): "never" | "on-request" {
  return sandbox === "danger-full-access" ? "never" : "on-request";
}

function isReadCommand(command: string): boolean {
  const payload = command.toLowerCase();
  return /(^|\s)(cat|less|more)\s+/.test(payload) ||
    /(^|\s)(head|tail)\b/.test(payload) ||
    /(^|\s)sed\s+-n\s+/.test(payload);
}

function readCommandPath(command: string): string | undefined {
  const sed = command.match(/(?:^|\s)sed\s+-n\s+['"]?\d+(?:,\d+)?p['"]?\s+(.+?)\s*$/);
  if (sed?.[1]) return stripShellQuotes(sed[1]);
  const cat = command.match(/(?:^|\s)cat\s+(.+?)\s*$/);
  if (cat?.[1]) return stripShellQuotes(cat[1]);
  const headTail = command.match(/(?:^|\s)(?:head|tail)(?:\s+-n\s+\d+)?\s+(.+?)\s*$/);
  return headTail?.[1] ? stripShellQuotes(headTail[1]) : undefined;
}

function skillNameFromPath(filePath: string): string | undefined {
  const normalized = filePath.replace(/\\/g, "/");
  const parts = normalized.split("/").filter(Boolean);
  const fileName = parts.at(-1)?.toLowerCase();
  if (fileName !== "skill.md" && fileName !== "skills.md") return undefined;
  const parent = parts.at(-2);
  if (!parent || parent === "." || parent === "..") return fileName;
  return parent;
}

function stripShellQuotes(value: string): string {
  let output = value.trim();
  if ((output.startsWith('"') && output.endsWith('"')) || (output.startsWith("'") && output.endsWith("'"))) {
    output = output.slice(1, -1);
  }
  return output;
}

function shortPath(value: string): string {
  const normalized = value.replace(/\\/g, "/");
  const parts = normalized.split("/").filter(Boolean);
  return parts.slice(-3).join("/") || normalized;
}
