import { randomUUID } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import type { SessionMode, WorkspaceConfig } from "../config.js";
import type { AppAccountLoginCancelledMessage, AppAccountLoginStartedMessage, AppAccountStatusMessage, AppFileSearchResultsMessage, AppFsEntryRecord, AppFsFileMessage, AppFsListMessage, AppModelListMessage, AppModelRecord, AppProviderCapabilitiesRecord, AppReviewStartedMessage, AppSkillListMessage, AppThreadListMessage, AppThreadRecord, CodexAccountInfo, DiffAvailableMessage, ExternalSessionRecord, FileDownloadMessage, FileOfferMessage, PromptAttachment, ReasoningEffort, RunMode, SandboxMode, ServerMessage, SessionGoalRecord, SessionRecord, StoredChatMessage, WorkspaceFileRecord, WorkspaceFileSearchResultsMessage, WorkspaceRecord } from "../protocol/messages.js";
import type { AccountLoginStartInput, CodexEvent, CodexSession, GoalSetInput, PreparedAttachment, SendPromptResult } from "./codexSession.js";
import { AppServerCodexSession } from "./appServerCodexSession.js";
import { findExternalSession, listExternalSessions, readExternalSessionHistory } from "./externalSessions.js";
import { FileTransferManager, mimeTypeFor } from "./fileTransferManager.js";
import { MockCodexSession } from "./mockCodexSession.js";
import { SessionStore } from "./sessionStore.js";

const execFileAsync = promisify(execFile);

type Listener = (event: ServerMessage) => void;

type ManagedAdapter = {
  session: CodexSession;
  unsubscribe: () => void;
};

export type CodexSessionManagerOptions = {
  sessionMode: SessionMode;
  codexCommand: string;
  workspaces: WorkspaceConfig[];
  stateDir: string;
  defaultSandbox: SandboxMode;
  allowYolo: boolean;
};

export class CodexSessionManager {
  private readonly store: SessionStore;
  private readonly listeners = new Set<Listener>();
  private readonly adapters = new Map<string, ManagedAdapter>();
  private readonly fileTransfers: FileTransferManager;
  private sessions = new Map<string, SessionRecord>();
  private messageHistory = new Map<string, StoredChatMessage[]>();
  private workspaces: WorkspaceConfig[] = [];
  private pendingPersistence: Promise<void> = Promise.resolve();
  private activeSessionId?: string;

  private constructor(private readonly options: CodexSessionManagerOptions) {
    this.store = new SessionStore(options.stateDir);
    this.fileTransfers = new FileTransferManager({
      workspaces: options.workspaces,
      maxBytes: 10 * 1024 * 1024,
    });
  }

  static async create(options: CodexSessionManagerOptions): Promise<CodexSessionManager> {
    const manager = new CodexSessionManager(options);
    await manager.init();
    return manager;
  }

  listSessions(): SessionRecord[] {
    return [...this.sessions.values()].sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
  }

  getActiveSessionId(): string | undefined {
    return this.activeSessionId;
  }

  getSessionHistory(sessionId: string): StoredChatMessage[] {
    return [...(this.messageHistory.get(sessionId) ?? [])].map((message) => ({ ...message }));
  }

  async listExternalSessions(): Promise<ExternalSessionRecord[]> {
    return listExternalSessions();
  }

  async listAppModels(sessionId?: string, includeHidden = false): Promise<AppModelListMessage> {
    const adapter = this.optionalAdapter(sessionId);
    if (adapter?.listModels) {
      const result = await adapter.listModels(includeHidden);
      return { type: "app.model.list", ...result };
    }
    return {
      type: "app.model.list",
      models: DEFAULT_APP_MODELS.filter((model) => includeHidden || !model.hidden),
      capabilities: DEFAULT_APP_CAPABILITIES,
    };
  }

  async listAppThreads(sessionId?: string, input: { query?: string; cwd?: string; limit?: number } = {}): Promise<AppThreadListMessage> {
    const adapter = this.optionalAdapter(sessionId);
    if (adapter?.listThreads) {
      return { type: "app.thread.list", threads: await adapter.listThreads(input) };
    }
    const query = input.query?.trim().toLowerCase() ?? "";
    const limit = Math.min(Math.max(Math.trunc(input.limit ?? 40), 1), 80);
    const sessions = await this.listExternalSessions();
    const threads = sessions
      .filter((session) => !query || `${session.title} ${session.workdir}`.toLowerCase().includes(query))
      .slice(0, limit)
      .map(appThreadFromExternalSession);
    return { type: "app.thread.list", threads };
  }

  async importAppThread(threadId: string): Promise<SessionRecord> {
    const adapter = this.optionalAdapter();
    if (!adapter?.readThread) {
      throw new Error("The active Codex adapter does not support native app-server thread import.");
    }
    const thread = await adapter.readThread(threadId, true);
    const workspace = await this.addWorkspace(thread.workdir);
    const now = new Date().toISOString();
    const record: SessionRecord = {
      sessionId: randomUUID(),
      codexThreadId: thread.threadId,
      title: thread.title || "Imported app-server session",
      createdAt: now,
      updatedAt: now,
      workspaceId: workspace.workspaceId,
      workdir: workspace.path,
      lastStatus: "idle",
      mode: this.defaultMode(),
      sandbox: this.sandboxForMode(this.defaultMode()),
    };
    this.sessions.set(record.sessionId, record);
    this.messageHistory.set(record.sessionId, thread.messages.length > 0 ? thread.messages : [
      {
        messageId: randomUUID(),
        role: "system",
        kind: "system",
        title: "Imported app-server session",
        text: `Imported native thread: ${thread.threadId}`,
        createdAt: now,
        complete: true,
      },
    ]);
    this.activeSessionId = record.sessionId;
    await this.saveAndEmit(record);
    return record;
  }

  async runDoctorCommand(sessionId: string): Promise<void> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = record.sessionId;
    const messageId = randomUUID();
    const runId = `doctor-${messageId}`;
    const startedAt = new Date().toISOString();
    this.appendHistory(record.sessionId, {
      messageId,
      role: "system",
      kind: "executing",
      title: "Codex doctor",
      text: "",
      runId,
      createdAt: startedAt,
      complete: false,
    });
    this.emit({
      type: "message.started",
      sessionId: record.sessionId,
      runId,
      messageId,
      role: "system",
      kind: "executing",
      title: "Codex doctor",
    });

    const command = `${this.options.codexCommand} doctor --json`;
    const lines = [`Command: ${command}`];
    try {
      const { stdout, stderr } = await execFileAsync(this.options.codexCommand, ["doctor", "--json"], {
        cwd: record.workdir,
        timeout: 20_000,
        maxBuffer: 1024 * 1024,
      });
      const summary = summarizeDoctorOutput(stdout, stderr);
      lines.push(...summary);
    } catch (error) {
      lines.push("Codex doctor failed.");
      lines.push(error instanceof Error ? error.message : String(error));
    }

    const text = lines.join("\n");
    const history = this.messageHistory.get(record.sessionId);
    const existing = history?.find((message) => message.messageId === messageId);
    if (existing) {
      existing.text = text;
      existing.complete = true;
    }
    this.emit({
      type: "message.delta",
      sessionId: record.sessionId,
      runId,
      messageId,
      text,
    });
    this.emit({
      type: "message.completed",
      sessionId: record.sessionId,
      runId,
      messageId,
    });
    await this.save();
  }

  async listAppSkills(sessionId: string | undefined, forceReload = false): Promise<AppSkillListMessage> {
    const record = this.requireSession(sessionId ?? this.activeSessionId);
    const adapter = this.adapters.get(record.sessionId)?.session ?? this.adapterFor(record);
    if (adapter.listSkills) {
      const result = await adapter.listSkills({ cwds: [record.workdir], forceReload });
      return { type: "app.skill.list", groups: result.groups };
    }
    return { type: "app.skill.list", groups: [{ cwd: record.workdir, skills: [], errors: [] }] };
  }

  async listAppDirectory(sessionId: string, requestedPath = ""): Promise<AppFsListMessage> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const absolutePath = this.resolveWorkspacePath(record, requestedPath || ".");
    const adapter = this.adapters.get(record.sessionId)?.session ?? this.adapterFor(record);
    const entries = adapter.listDirectory
      ? await adapter.listDirectory(absolutePath)
      : await this.listDirectoryFallback(record, absolutePath);
    return {
      type: "app.fs.list",
      sessionId: record.sessionId,
      path: toPosixPath(path.relative(record.workdir, absolutePath)),
      entries,
    };
  }

  async readAppFile(sessionId: string, requestedPath: string): Promise<AppFsFileMessage> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const absolutePath = this.resolveWorkspacePath(record, requestedPath);
    const adapter = this.adapters.get(record.sessionId)?.session ?? this.adapterFor(record);
    const file = adapter.readFile
      ? await adapter.readFile(absolutePath)
      : await this.readFileFallback(record, absolutePath);
    return { type: "app.fs.file", sessionId: record.sessionId, file };
  }

  async searchAppFiles(sessionId: string, query: string, limit = 40): Promise<AppFileSearchResultsMessage> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const adapter = this.adapters.get(record.sessionId)?.session ?? this.adapterFor(record);
    const normalizedQuery = normalizeFileQuery(query);
    const files = adapter.searchFiles
      ? await adapter.searchFiles({ query: normalizedQuery, roots: [record.workdir], limit })
      : (await this.searchWorkspaceFiles(sessionId, normalizedQuery, limit)).files;
    return {
      type: "app.file.search.results",
      sessionId: record.sessionId,
      query: normalizedQuery,
      files,
    };
  }

  async startReview(sessionId: string, input: { target?: "uncommittedChanges" | "custom"; instructions?: string; delivery?: "inline" | "detached" }): Promise<AppReviewStartedMessage> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const adapter = this.adapters.get(record.sessionId)?.session ?? this.adapterFor(record);
    if (adapter.startReview) {
      const target = input.target === "custom"
        ? { type: "custom" as const, instructions: input.instructions?.trim() || "Review the current workspace." }
        : { type: "uncommittedChanges" as const };
      const result = await adapter.startReview({ target, delivery: input.delivery });
      return { type: "app.review.started", sessionId: record.sessionId, ...result };
    }
    return {
      type: "app.review.started",
      sessionId: record.sessionId,
      runId: `mock-review-${Date.now()}`,
      reviewThreadId: record.codexThreadId ?? record.sessionId,
    };
  }

  async getCodexAccount(refreshToken = false): Promise<CodexAccountInfo> {
    const adapter = this.optionalAdapter();
    if (!adapter?.getAccount) {
      throw new Error("The active Codex adapter does not support account auth.");
    }
    return adapter.getAccount(refreshToken);
  }

  async readCodexAccount(refreshToken = false): Promise<AppAccountStatusMessage> {
    return {
      type: "app.account.status",
      account: await this.getCodexAccount(refreshToken),
    };
  }

  async startCodexAccountLogin(input: AccountLoginStartInput): Promise<AppAccountLoginStartedMessage> {
    const adapter = this.optionalAdapter();
    if (!adapter?.startAccountLogin) {
      throw new Error("The active Codex adapter does not support account login.");
    }
    return {
      type: "app.account.login.started",
      flow: await adapter.startAccountLogin(input),
    };
  }

  async cancelCodexAccountLogin(loginId: string): Promise<AppAccountLoginCancelledMessage> {
    const adapter = this.optionalAdapter();
    if (!adapter?.cancelAccountLogin) {
      throw new Error("The active Codex adapter does not support account login cancel.");
    }
    const result = await adapter.cancelAccountLogin(loginId);
    return {
      type: "app.account.login.cancelled",
      loginId,
      status: result.status,
    };
  }

  async logoutCodexAccount(): Promise<AppAccountStatusMessage> {
    const adapter = this.optionalAdapter();
    if (!adapter?.logoutAccount) {
      throw new Error("The active Codex adapter does not support account logout.");
    }
    await adapter.logoutAccount();
    return {
      type: "app.account.status",
      account: await this.getCodexAccount(false),
    };
  }

  getWorkspaces(activeSessionId = this.activeSessionId): WorkspaceRecord[] {
    const activeWorkspaceId = activeSessionId ? this.sessions.get(activeSessionId)?.workspaceId : undefined;
    return this.workspaces.map((workspace) => ({
      workspaceId: workspace.id,
      label: workspace.label,
      path: workspace.path,
      active: workspace.id === activeWorkspaceId,
    }));
  }

  async addWorkspace(workspacePath: string, sessionId?: string, options: { create?: boolean } = {}): Promise<WorkspaceRecord> {
    const resolvedPath = path.resolve(workspacePath);
    if (options.create) {
      await mkdir(resolvedPath, { recursive: true });
    }
    const stats = await stat(resolvedPath);
    if (!stats.isDirectory()) {
      throw new Error(`Workspace path is not a directory: ${resolvedPath}`);
    }
    let workspace = this.workspaces.find((candidate) => path.resolve(candidate.path) === resolvedPath);
    if (!workspace) {
      workspace = {
        id: nextWorkspaceId(this.workspaces),
        label: path.basename(resolvedPath) || resolvedPath,
        path: resolvedPath,
      };
      this.workspaces.push(workspace);
      this.fileTransfers.setWorkspaces(this.workspaces);
    }
    if (sessionId) {
      await this.switchWorkspace(sessionId, workspace.id);
    } else {
      await this.save();
    }
    return {
      workspaceId: workspace.id,
      label: workspace.label,
      path: workspace.path,
      active: sessionId ? this.sessions.get(sessionId)?.workspaceId === workspace.id : false,
    };
  }

  async importExternalSession(externalSessionId: string): Promise<SessionRecord> {
    const external = await findExternalSession(externalSessionId);
    if (!external) {
      throw new Error(`Unknown external Codex session: ${externalSessionId}`);
    }
    const workspace = await this.addWorkspace(external.workdir);
    const now = new Date().toISOString();
    const record: SessionRecord = {
      sessionId: randomUUID(),
      codexThreadId: external.codexThreadId,
      title: external.title,
      createdAt: now,
      updatedAt: now,
      workspaceId: workspace.workspaceId,
      workdir: workspace.path,
      lastStatus: "idle",
      mode: this.defaultMode(),
      sandbox: this.sandboxForMode(this.defaultMode()),
    };
    this.sessions.set(record.sessionId, record);
    const importedHistory = await readExternalSessionHistory(external);
    this.messageHistory.set(record.sessionId, importedHistory.length > 0 ? importedHistory : [
      {
        messageId: randomUUID(),
        role: "system",
        kind: "system",
        title: "Imported Codex session",
        text: `Imported external session from ${external.path}\nResume thread: ${external.codexThreadId}`,
        createdAt: now,
        complete: true,
      },
    ]);
    this.activeSessionId = record.sessionId;
    await this.saveAndEmit(record);
    return record;
  }

  async createSession(input: { title?: string; workspaceId?: string; mode?: RunMode } = {}): Promise<SessionRecord> {
    const workspace = this.workspaceById(input.workspaceId ?? this.workspaces[0]?.id);
    const mode = input.mode ?? this.defaultMode();
    this.assertModeAllowed(mode);
    await this.ensureWorkspaceReady(workspace);

    const now = new Date().toISOString();
    const record: SessionRecord = {
      sessionId: randomUUID(),
      title: input.title?.trim() || "New session",
      createdAt: now,
      updatedAt: now,
      workspaceId: workspace.id,
      workdir: workspace.path,
      lastStatus: "idle",
      mode,
      sandbox: this.sandboxForMode(mode),
    };

    this.sessions.set(record.sessionId, record);
    this.activeSessionId = record.sessionId;
    await this.save();
    this.emit({ type: "session.updated", session: record });
    return record;
  }

  async startSession(sessionId?: string): Promise<SessionRecord> {
    const record = sessionId ? this.requireSession(sessionId) : this.requireSession(this.activeSessionId ?? this.listSessions()[0]?.sessionId);
    this.activeSessionId = record.sessionId;
    const adapter = this.adapterFor(record);
    await adapter.start();
    return record;
  }

  async renameSession(sessionId: string, title: string): Promise<SessionRecord> {
    const record = this.requireSession(sessionId);
    record.title = title.trim();
    record.updatedAt = new Date().toISOString();
    await this.saveAndEmit(record);
    return record;
  }

  async deleteSession(sessionId: string): Promise<void> {
    const record = this.requireSession(sessionId);
    if (record.activeRunId) {
      throw new Error("Cannot delete a session while a run is active.");
    }

    await this.closeAdapter(sessionId);
    this.sessions.delete(sessionId);
    this.emit({ type: "session.deleted", sessionId });

    if (this.activeSessionId === sessionId) {
      this.activeSessionId = this.listSessions()[0]?.sessionId;
    }

    if (this.sessions.size === 0) {
      await this.createSession({ title: "New session" });
      return;
    }

    await this.save();
  }

  async switchWorkspace(sessionId: string, workspaceId: string): Promise<SessionRecord> {
    const record = this.requireSession(sessionId);
    if (record.activeRunId) {
      throw new Error("Cannot switch workspace while a run is active.");
    }
    const workspace = this.workspaceById(workspaceId);
    await this.ensureWorkspaceReady(workspace);

    await this.closeAdapter(sessionId);
    record.workspaceId = workspace.id;
    record.workdir = workspace.path;
    record.codexThreadId = undefined;
    record.lastStatus = "idle";
    record.updatedAt = new Date().toISOString();
    this.activeSessionId = sessionId;
    await this.saveAndEmit(record);
    this.emit({ type: "workspace.updated", sessionId, workspace: { workspaceId: workspace.id, label: workspace.label, path: workspace.path, active: true } });
    return record;
  }

  async setSessionMode(sessionId: string, mode: RunMode): Promise<SessionRecord> {
    const record = this.requireSession(sessionId);
    this.assertModeAllowed(mode);
    if (record.activeRunId) {
      throw new Error("Cannot switch mode while a run is active.");
    }

    await this.closeAdapter(sessionId);
    record.mode = mode;
    record.sandbox = this.sandboxForMode(mode);
    record.updatedAt = new Date().toISOString();
    this.activeSessionId = sessionId;
    await this.saveAndEmit(record);
    return record;
  }

  async setSessionConfig(sessionId: string, config: { model?: string; reasoningEffort?: ReasoningEffort }): Promise<SessionRecord> {
    const record = this.requireSession(sessionId);
    if (record.activeRunId) {
      throw new Error("Cannot change model settings while a run is active.");
    }

    await this.closeAdapter(sessionId);
    if (Object.prototype.hasOwnProperty.call(config, "model")) {
      const model = config.model?.trim();
      record.model = model || undefined;
    }
    if (Object.prototype.hasOwnProperty.call(config, "reasoningEffort")) {
      record.reasoningEffort = config.reasoningEffort;
    }
    record.updatedAt = new Date().toISOString();
    this.activeSessionId = sessionId;
    await this.saveAndEmit(record);
    return record;
  }

  async sendPrompt(sessionId: string, prompt: string, attachments: PromptAttachment[] = []): Promise<SendPromptResult> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    if (!record.codexThreadId && record.title === "New session") {
      record.title = titleFromPrompt(prompt);
      record.updatedAt = new Date().toISOString();
      await this.saveAndEmit(record);
    }
    const preparedAttachments = await this.prepareAttachments(record, attachments);
    this.appendHistory(record.sessionId, {
      messageId: randomUUID(),
      role: "user",
      kind: "response",
      text: prompt.trim(),
      createdAt: new Date().toISOString(),
      complete: true,
    });
    if (preparedAttachments.length > 0) {
      this.appendHistory(record.sessionId, {
        messageId: randomUUID(),
        role: "system",
        kind: "files",
        title: "Attachments uploaded",
        text: preparedAttachments.map((attachment) => `added ${path.relative(record.workdir, attachment.path) || attachment.name}`).join("\n"),
        createdAt: new Date().toISOString(),
        complete: true,
      });
      this.emit({
        type: "diff.available",
        sessionId: record.sessionId,
        files: preparedAttachments.map((attachment) => ({
          path: path.relative(record.workdir, attachment.path) || attachment.path,
          status: "added",
        })),
      });
      for (const attachment of preparedAttachments) {
        await this.emitFileOffer(record, path.relative(record.workdir, attachment.path) || attachment.path, "attachment");
      }
    }
    await this.save();
    const adapter = this.adapterFor(record);
    return adapter.sendPrompt(augmentPromptWithAttachments(prompt, preparedAttachments), { attachments: preparedAttachments });
  }

  async cancel(sessionId: string, runId: string): Promise<void> {
    const adapter = this.adapters.get(sessionId)?.session;
    if (!adapter) {
      throw new Error(`No active session adapter found for ${sessionId}`);
    }
    await adapter.cancel(runId);
  }

  async setGoal(sessionId: string, input: GoalSetInput): Promise<SessionGoalRecord> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const adapter = this.adapterFor(record);
    if (!adapter.setGoal) {
      throw new Error("The active Codex adapter does not support goals.");
    }
    const goal = await adapter.setGoal(input);
    record.goal = goal;
    record.updatedAt = new Date().toISOString();
    await this.saveAndEmit(record);
    return goal;
  }

  async getGoal(sessionId: string): Promise<SessionGoalRecord | null> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const adapter = this.adapters.get(sessionId)?.session ?? this.adapterFor(record);
    const goal = adapter.getGoal ? await adapter.getGoal() : record.goal ?? null;
    if (goal) {
      record.goal = goal;
      record.updatedAt = new Date().toISOString();
      await this.saveAndEmit(record);
    }
    return goal;
  }

  async clearGoal(sessionId: string): Promise<boolean> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const adapter = this.adapters.get(sessionId)?.session ?? this.adapterFor(record);
    const hadPersistedGoal = record.goal !== undefined;
    const cleared = adapter.clearGoal ? await adapter.clearGoal() || hadPersistedGoal : hadPersistedGoal;
    record.goal = undefined;
    record.updatedAt = new Date().toISOString();
    await this.saveAndEmit(record);
    return cleared;
  }

  async decideApproval(sessionId: string, approvalId: string, decision: "approve" | "reject"): Promise<void> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const adapter = this.adapters.get(sessionId)?.session ?? this.adapterFor(record);
    if (!adapter.decideApproval) {
      throw new Error("The active Codex adapter does not support approval decisions.");
    }
    await adapter.decideApproval(approvalId, decision);
  }

  async downloadFile(fileId: string): Promise<FileDownloadMessage> {
    return this.fileTransfers.download(fileId);
  }

  async offerRequestedFile(sessionId: string, filePath: string): Promise<FileOfferMessage> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const offer = await this.fileTransfers.offerWorkspaceFile({
      sessionId: record.sessionId,
      workspaceRoot: record.workdir,
      relativePath: filePath.trim(),
      reason: "requested",
    });
    this.appendHistory(record.sessionId, {
      messageId: randomUUID(),
      role: "system",
      kind: "files",
      title: "File ready",
      text: `requested ${offer.path}\nsize ${offer.sizeBytes}\nfileId ${offer.fileId}`,
      createdAt: new Date().toISOString(),
      complete: true,
    });
    await this.save();
    this.emit(offer);
    return offer;
  }

  async searchWorkspaceFiles(sessionId: string, query = "", limit = 40): Promise<WorkspaceFileSearchResultsMessage> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    const effectiveLimit = Math.min(Math.max(Math.trunc(limit) || 40, 1), 80);
    const normalizedQuery = normalizeFileQuery(query);
    return {
      type: "workspace.file.search.results",
      sessionId: record.sessionId,
      query: normalizedQuery,
      files: await scanWorkspaceFiles(record.workdir, normalizedQuery, effectiveLimit),
    };
  }

  onEvent(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async close(): Promise<void> {
    for (const sessionId of [...this.adapters.keys()]) {
      await this.closeAdapter(sessionId);
    }
    await this.pendingPersistence;
    this.listeners.clear();
  }

  private async init(): Promise<void> {
    const snapshot = await this.store.load();
    this.workspaces = mergeWorkspaces(this.options.workspaces, snapshot.workspaces ?? []);
    this.fileTransfers.setWorkspaces(this.workspaces);
    this.messageHistory = new Map(Object.entries(snapshot.messages ?? {}).map(([sessionId, messages]) => [sessionId, messages.map((message) => ({ ...message, complete: message.kind === "thinking" ? true : message.complete }))]));
    for (const persisted of snapshot.sessions) {
      const workspace = this.workspaces.find((candidate) => candidate.id === persisted.workspaceId) ?? this.workspaces.find((candidate) => candidate.path === persisted.workdir) ?? this.workspaces[0];
      if (!workspace) continue;
      const mode = persisted.mode === "yolo" && !this.options.allowYolo ? "safe" : persisted.mode;
      const record: SessionRecord = {
        ...persisted,
        workspaceId: workspace.id,
        workdir: workspace.path,
        activeRunId: undefined,
        lastStatus: persisted.lastStatus === "running" || persisted.lastStatus === "cancelling" ? "idle" : persisted.lastStatus,
        mode,
        sandbox: this.sandboxForMode(mode),
      };
      this.sessions.set(record.sessionId, record);
    }

    if (this.sessions.size === 0) {
      await this.createSession({ title: "New session" });
      return;
    }

    this.activeSessionId = this.listSessions()[0]?.sessionId;
    await this.save();
  }

  private adapterFor(record: SessionRecord): CodexSession {
    const existing = this.adapters.get(record.sessionId)?.session;
    if (existing) return existing;

    const session = this.options.sessionMode === "mock"
      ? new MockCodexSession({ sessionId: record.sessionId })
      : new AppServerCodexSession({
          sessionId: record.sessionId,
          command: this.options.codexCommand,
          workdir: record.workdir,
          sandbox: record.sandbox,
          model: record.model,
          reasoningEffort: record.reasoningEffort,
          codexThreadId: record.codexThreadId,
          onThreadStarted: (threadId) => {
            void this.updateThreadId(record.sessionId, threadId).catch((error) => {
              this.emit({ type: "error", code: "session.thread_persist_failed", message: error instanceof Error ? error.message : String(error) });
            });
          },
        });

    const unsubscribe = session.onEvent((event) => {
      this.pendingPersistence = this.pendingPersistence
        .then(() => this.handleAdapterEvent(event))
        .catch((error) => {
          this.emit({ type: "error", code: "session.persist_failed", message: error instanceof Error ? error.message : String(error) });
        });
      this.emit(event as ServerMessage);
    });
    this.adapters.set(record.sessionId, { session, unsubscribe });
    return session;
  }

  private async handleAdapterEvent(event: CodexEvent): Promise<void> {
    if (!("sessionId" in event) || !event.sessionId) return;
    const record = this.sessions.get(event.sessionId);
    if (!record) return;

    let changed = false;
    let historyChanged = false;
    if (event.type === "message.started") {
      historyChanged = this.recordMessageStarted(event);
    }
    if (event.type === "message.delta") {
      historyChanged = this.recordMessageDelta(event) || historyChanged;
    }
    if (event.type === "message.completed") {
      historyChanged = this.recordMessageCompleted(event) || historyChanged;
    }
    if (event.type === "diff.available") {
      historyChanged = this.recordDiffAvailable(event) || historyChanged;
      await this.emitFileOffersForDiff(record, event);
    }
    if (event.type === "session.goal.updated") {
      record.goal = event.goal;
      changed = true;
    }
    if (event.type === "session.goal.cleared") {
      record.goal = undefined;
      changed = true;
    }
    if (event.type === "run.started") {
      record.activeRunId = event.runId;
      record.lastStatus = "running";
      changed = true;
    }
    if (event.type === "status" && event.status) {
      record.lastStatus = event.status;
      if (["completed", "failed", "cancelled"].includes(event.status)) {
        record.activeRunId = undefined;
      }
      changed = true;
    }
    if (event.type === "run.completed") {
      record.activeRunId = undefined;
      record.lastStatus = event.exitCode === 0 ? "completed" : "failed";
      changed = true;
    }

    if (changed) {
      record.updatedAt = new Date().toISOString();
      await this.saveAndEmit(record);
    } else if (historyChanged) {
      await this.save();
    }
  }

  private async updateThreadId(sessionId: string, threadId: string): Promise<void> {
    const record = this.sessions.get(sessionId);
    if (!record || record.codexThreadId === threadId) return;
    record.codexThreadId = threadId;
    record.updatedAt = new Date().toISOString();
    await this.saveAndEmit(record);
  }

  private recordMessageStarted(event: Extract<CodexEvent, { type: "message.started" }>): boolean {
    if (event.kind === "thinking") return false;
    this.appendHistory(event.sessionId, {
      messageId: event.messageId,
      role: event.role,
      kind: event.kind,
      title: event.title,
      text: "",
      runId: event.runId,
      createdAt: new Date().toISOString(),
      complete: false,
    });
    return true;
  }

  private recordMessageDelta(event: Extract<CodexEvent, { type: "message.delta" }>): boolean {
    const history = this.messageHistory.get(event.sessionId);
    const existing = history?.find((message) => message.messageId === event.messageId);
    if (existing) {
      existing.text += event.text;
      return true;
    }
    if (event.text.trim().length === 0 || isThinkingNoise(event.text)) return false;
    this.appendHistory(event.sessionId, {
      messageId: event.messageId,
      role: "system",
      kind: "system",
      text: event.text,
      runId: event.runId,
      createdAt: new Date().toISOString(),
      complete: false,
    });
    return true;
  }

  private recordMessageCompleted(event: Extract<CodexEvent, { type: "message.completed" }>): boolean {
    const existing = this.messageHistory.get(event.sessionId)?.find((message) => message.messageId === event.messageId);
    if (!existing) return false;
    existing.complete = true;
    return true;
  }

  private recordDiffAvailable(event: Extract<CodexEvent, { type: "diff.available" }>): boolean {
    if (event.files.length === 0) return false;
    this.appendHistory(event.sessionId, {
      messageId: randomUUID(),
      role: "system",
      kind: "files",
      title: "Files changed",
      text: event.files.flatMap((file) => [`${file.status} ${file.path}`, ...(file.patch ? file.patch.split(/\r?\n/) : [])]).join("\n"),
      createdAt: new Date().toISOString(),
      complete: true,
    });
    return true;
  }

  private appendHistory(sessionId: string, message: StoredChatMessage): void {
    if (message.kind === "thinking") return;
    const history = this.messageHistory.get(sessionId) ?? [];
    const existingIndex = history.findIndex((candidate) => candidate.messageId === message.messageId);
    if (existingIndex >= 0) {
      history[existingIndex] = message;
    } else {
      history.push(message);
    }
    this.messageHistory.set(sessionId, history.slice(-500));
  }

  private async emitFileOffersForDiff(record: SessionRecord, event: DiffAvailableMessage): Promise<void> {
    for (const file of event.files) {
      if (file.status === "deleted") continue;
      await this.emitFileOffer(record, file.path, "generated");
    }
  }

  private async emitFileOffer(record: SessionRecord, relativePath: string, reason: "requested" | "generated" | "attachment"): Promise<void> {
    try {
      const offer = await this.fileTransfers.offerWorkspaceFile({
        sessionId: record.sessionId,
        workspaceRoot: record.workdir,
        relativePath,
        reason,
      });
      this.emit(offer);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const code = message.includes("too large") ? "file.too_large" : message.includes("outside workspace") ? "file.forbidden" : "file.offer_failed";
      this.emit({ type: "error", code, message });
    }
  }

  private async prepareAttachments(record: SessionRecord, attachments: PromptAttachment[]): Promise<PreparedAttachment[]> {
    if (attachments.length === 0) return [];
    const uploadDir = path.join(record.workdir, ".codex-lan", "uploads", new Date().toISOString().replace(/[:.]/g, "-"));
    await mkdir(uploadDir, { recursive: true });
    const prepared: PreparedAttachment[] = [];
    for (const [index, attachment] of attachments.entries()) {
      const safeFileName = safeAttachmentName(attachment.name, index);
      const targetPath = path.join(uploadDir, safeFileName);
      const bytes = Buffer.from(attachment.dataBase64, "base64");
      await writeFile(targetPath, bytes);
      prepared.push({
        path: targetPath,
        name: safeFileName,
        kind: isImageAttachment(attachment) ? "image" : "file",
      });
    }
    return prepared;
  }

  private optionalAdapter(sessionId?: string): CodexSession | undefined {
    const record = sessionId
      ? this.requireSession(sessionId)
      : this.activeSessionId
        ? this.sessions.get(this.activeSessionId)
        : this.listSessions()[0];
    if (!record) return undefined;
    this.activeSessionId = record.sessionId;
    return this.adapters.get(record.sessionId)?.session ?? this.adapterFor(record);
  }

  private resolveWorkspacePath(record: SessionRecord, requestedPath: string): string {
    const root = path.resolve(record.workdir);
    const target = path.resolve(root, requestedPath || ".");
    if (target !== root && !target.startsWith(`${root}${path.sep}`)) {
      throw new Error(`Path is outside the active workspace: ${requestedPath}`);
    }
    return target;
  }

  private async listDirectoryFallback(record: SessionRecord, absolutePath: string): Promise<AppFsEntryRecord[]> {
    const entries = await readdir(absolutePath, { withFileTypes: true });
    const output: AppFsEntryRecord[] = [];
    for (const entry of entries.sort((left, right) => Number(right.isDirectory()) - Number(left.isDirectory()) || left.name.localeCompare(right.name))) {
      if (entry.isSymbolicLink()) continue;
      const fullPath = path.join(absolutePath, entry.name);
      const stats = await stat(fullPath).catch(() => undefined);
      output.push({
        path: toPosixPath(path.relative(record.workdir, fullPath)),
        name: entry.name,
        isDirectory: entry.isDirectory(),
        isFile: entry.isFile(),
        sizeBytes: stats?.isFile() ? stats.size : undefined,
        mimeType: entry.isFile() ? mimeTypeFor(entry.name) : undefined,
      });
    }
    return output;
  }

  private async readFileFallback(record: SessionRecord, absolutePath: string): Promise<AppFsFileMessage["file"]> {
    const bytes = await readFile(absolutePath);
    const relativePath = toPosixPath(path.relative(record.workdir, absolutePath));
    const mimeType = mimeTypeFor(relativePath);
    return {
      path: relativePath,
      name: path.basename(absolutePath),
      sizeBytes: bytes.byteLength,
      mimeType,
      text: isLikelyTextFile(bytes, relativePath) ? bytes.toString("utf8") : undefined,
      dataBase64: isLikelyTextFile(bytes, relativePath) ? undefined : bytes.toString("base64"),
    };
  }

  private async closeAdapter(sessionId: string): Promise<void> {
    const adapter = this.adapters.get(sessionId);
    if (!adapter) return;
    adapter.unsubscribe();
    await adapter.session.close();
    this.adapters.delete(sessionId);
    await this.pendingPersistence;
  }

  private requireSession(sessionId?: string): SessionRecord {
    if (!sessionId) throw new Error("No session id was provided.");
    const record = this.sessions.get(sessionId);
    if (!record) throw new Error(`Unknown session: ${sessionId}`);
    return record;
  }

  private workspaceById(workspaceId?: string): WorkspaceConfig {
    const workspace = this.workspaces.find((candidate) => candidate.id === workspaceId) ?? this.workspaces[0];
    if (!workspace) throw new Error("No host workspaces are configured.");
    if (workspaceId && workspace.id !== workspaceId) throw new Error(`Unknown workspace: ${workspaceId}`);
    return workspace;
  }

  private async ensureWorkspaceReady(workspace: WorkspaceConfig): Promise<void> {
    if (workspace.id !== "playground") return;
    await mkdir(workspace.path, { recursive: true });
  }

  private assertModeAllowed(mode: RunMode): void {
    if (mode === "yolo" && !this.options.allowYolo) {
      throw new Error("Yolo mode is disabled by the host. Restart with --allow-yolo to permit danger-full-access from paired clients.");
    }
  }

  private defaultMode(): RunMode {
    return this.options.defaultSandbox === "danger-full-access" ? "yolo" : "safe";
  }

  private sandboxForMode(mode: RunMode): SandboxMode {
    if (mode === "yolo") return "danger-full-access";
    return this.options.defaultSandbox === "danger-full-access" ? "workspace-write" : this.options.defaultSandbox;
  }

  private async saveAndEmit(record: SessionRecord): Promise<void> {
    await this.save();
    this.emit({ type: "session.updated", session: { ...record } });
  }

  private async save(): Promise<void> {
    await this.store.save({
      sessions: this.listSessions(),
      messages: Object.fromEntries([...this.messageHistory.entries()].map(([sessionId, messages]) => [sessionId, messages.map((message) => ({ ...message }))])),
      workspaces: this.workspaces.map((workspace) => ({
        workspaceId: workspace.id,
        label: workspace.label,
        path: workspace.path,
        active: false,
      })),
    });
  }

  private emit(event: ServerMessage): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }
}

function titleFromPrompt(prompt: string): string {
  const compact = prompt.trim().replace(/\s+/g, " ");
  if (!compact) return "New session";
  return compact.length > 50 ? `${compact.slice(0, 47)}…` : compact;
}

function mergeWorkspaces(configured: WorkspaceConfig[], stored: WorkspaceRecord[]): WorkspaceConfig[] {
  const merged: WorkspaceConfig[] = [];
  const seenPaths = new Set<string>();
  for (const workspace of configured) {
    const resolved = path.resolve(workspace.path);
    if (seenPaths.has(resolved)) continue;
    seenPaths.add(resolved);
    merged.push({ ...workspace, path: resolved });
  }
  for (const workspace of stored) {
    const resolved = path.resolve(workspace.path);
    if (seenPaths.has(resolved)) continue;
    seenPaths.add(resolved);
    merged.push({
      id: workspace.workspaceId || nextWorkspaceId(merged),
      label: workspace.label || path.basename(resolved) || resolved,
      path: resolved,
    });
  }
  return merged;
}

function nextWorkspaceId(workspaces: WorkspaceConfig[]): string {
  let index = workspaces.length + 1;
  const used = new Set(workspaces.map((workspace) => workspace.id));
  while (used.has(`workspace-${index}`)) {
    index += 1;
  }
  return index === 1 ? "default" : `workspace-${index}`;
}

function augmentPromptWithAttachments(prompt: string, attachments: PreparedAttachment[]): string {
  if (attachments.length === 0) return prompt;
  const lines = attachments.map((attachment) => `- ${attachment.kind}: ${attachment.name} at ${attachment.path}`);
  return `${prompt.trim()}\n\nUploaded files available in the workspace:\n${lines.join("\n")}`;
}

function safeAttachmentName(name: string, index: number): string {
  const base = path.basename(name).replace(/[^A-Za-z0-9._-]/g, "_").replace(/^_+/, "");
  return base || `upload-${index + 1}`;
}

function isImageAttachment(attachment: PromptAttachment): boolean {
  const mimeType = attachment.mimeType?.toLowerCase() ?? "";
  if (mimeType.startsWith("image/")) return true;
  return /\.(png|jpe?g|webp|gif|bmp|heic|heif)$/i.test(attachment.name);
}

function isThinkingNoise(text: string): boolean {
  return text.trim().replace(/\.+$/, "").replace(/…$/, "").toLowerCase() === "thinking";
}

type DoctorCheckRecord = {
  id?: unknown;
  category?: unknown;
  status?: unknown;
  summary?: unknown;
  details?: unknown;
  remediation?: unknown;
};

type DoctorReportRecord = {
  overallStatus?: unknown;
  codexVersion?: unknown;
  checks?: unknown;
};

export function summarizeDoctorOutput(stdout: string, stderr: string): string[] {
  const trimmedStdout = stdout.trim();
  const trimmedStderr = stderr.trim();
  if (!trimmedStdout && !trimmedStderr) return ["Codex doctor finished with no output."];

  if (trimmedStdout) {
    try {
      const parsed = JSON.parse(trimmedStdout) as DoctorReportRecord;
      const formatted = formatDoctorReport(parsed);
      if (formatted.length > 0) {
        if (trimmedStderr) {
          formatted.push("", "Warnings:", ...trimmedStderr.split(/\r?\n/).map((line) => `- ${line}`));
        }
        return formatted;
      }
    } catch {
      // Fall back to compact raw output below when Codex changes shape or prints non-JSON.
    }
  }

  const output = [trimmedStdout, trimmedStderr].filter(Boolean).join("\n");
  const lines = output.split(/\r?\n/);
  if (lines.length <= 36) return lines;
  return [
    ...lines.slice(0, 24),
    `... ${lines.length - 36} lines omitted ...`,
    ...lines.slice(-12),
  ];
}

function formatDoctorReport(report: DoctorReportRecord): string[] {
  const checks = doctorChecks(report);
  if (!report || checks.size === 0) return [];

  const config = checks.get("config.load");
  const sandbox = checks.get("sandbox.helpers");
  const auth = checks.get("auth.credentials");
  const appServer = checks.get("app_server.status");
  const git = checks.get("git.environment");
  const providerNetwork = checks.get("network.provider_reachability");
  const webSocket = checks.get("network.websocket_reachability");
  const updates = checks.get("updates.status");

  const lines: string[] = [];
  pushDoctorField(lines, "Status", stringValue(report.overallStatus));
  pushDoctorField(lines, "Codex version", stringValue(report.codexVersion));

  const model = detailValue(config, "model");
  const provider = detailValue(config, "model provider");
  pushDoctorField(lines, "Model", model && provider ? `${model} (provider ${provider})` : model);
  pushDoctorField(lines, "Directory", detailValue(config, "cwd"));

  const filesystem = detailValue(sandbox, "filesystem sandbox");
  const network = detailValue(sandbox, "network sandbox");
  const permissions = [
    filesystem ? `${filesystem} filesystem` : undefined,
    network ? `${network} network` : undefined,
  ].filter(Boolean).join(", ");
  pushDoctorField(lines, "Permissions", permissions);
  pushDoctorField(lines, "Approval policy", detailValue(sandbox, "approval policy"));
  pushDoctorField(lines, "Account", authSummary(auth));

  const appServerStatus = detailValue(appServer, "status");
  const appServerMode = detailValue(appServer, "mode");
  pushDoctorField(
    lines,
    "App server",
    [appServerStatus, appServerMode ? `mode ${appServerMode}` : undefined].filter(Boolean).join(", ") ||
      stringValue(appServer?.summary),
  );

  const branch = detailValue(git, "git branch");
  const repoRoot = detailValue(git, "repo root");
  pushDoctorField(lines, "Git", [branch, repoRoot ? `at ${repoRoot}` : undefined].filter(Boolean).join(" "));
  pushDoctorField(lines, "MCP servers", detailValue(config, "mcp servers"));
  pushDoctorField(lines, "Provider network", stringValue(providerNetwork?.summary));
  pushDoctorField(lines, "WebSocket", detailValue(webSocket, "handshake result") || stringValue(webSocket?.summary));
  pushDoctorField(lines, "Updates", detailValue(updates, "latest version status") || stringValue(updates?.summary));

  lines.push("", "Checks:");
  for (const [id, check] of [...checks.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    const status = doctorStatusLabel(stringValue(check.status));
    const summary = stringValue(check.summary) || "no summary";
    lines.push(`${status.padEnd(4)} ${id} - ${summary}`);
    const remediation = stringValue(check.remediation);
    if (remediation) lines.push(`     Fix: ${remediation}`);
  }
  return lines;
}

function doctorChecks(report: DoctorReportRecord): Map<string, DoctorCheckRecord> {
  if (!isRecord(report.checks)) return new Map();
  const checks = new Map<string, DoctorCheckRecord>();
  for (const [key, value] of Object.entries(report.checks)) {
    if (!isRecord(value)) continue;
    const check = value as DoctorCheckRecord;
    checks.set(stringValue(check.id) || key, check);
  }
  return checks;
}

function pushDoctorField(lines: string[], label: string, value: string | undefined): void {
  if (!value) return;
  lines.push(`${`${label}:`.padEnd(21)}${value}`);
}

function authSummary(check: DoctorCheckRecord | undefined): string | undefined {
  const parts = [
    detailValue(check, "stored auth mode") ? `${detailValue(check, "stored auth mode")} auth` : undefined,
    detailValue(check, "stored ChatGPT tokens") === "true" ? "ChatGPT tokens stored" : undefined,
    detailValue(check, "stored API key") === "true" ? "API key stored" : undefined,
    detailValue(check, "stored agent identity") === "true" ? "agent identity stored" : undefined,
  ].filter(Boolean);
  return parts.join(", ") || stringValue(check?.summary);
}

function detailValue(check: DoctorCheckRecord | undefined, key: string): string | undefined {
  if (!check || !isRecord(check.details)) return undefined;
  return stringValue(check.details[key]);
}

function doctorStatusLabel(status: string | undefined): string {
  switch (status?.toLowerCase()) {
    case "ok":
      return "OK";
    case "warning":
    case "warn":
      return "WARN";
    case "error":
    case "failed":
    case "fail":
      return "FAIL";
    default:
      return status?.toUpperCase() || "INFO";
  }
}

function stringValue(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  if (typeof value === "string") return value.trim() || undefined;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const DEFAULT_APP_CAPABILITIES: AppProviderCapabilitiesRecord = {
  namespaceTools: true,
  imageGeneration: true,
  webSearch: true,
};

const DEFAULT_APP_MODELS: AppModelRecord[] = [
  {
    id: "gpt-5.5",
    model: "gpt-5.5",
    displayName: "GPT-5.5",
    description: "Default Codex app-server model.",
    hidden: false,
    supportedReasoningEfforts: ["low", "medium", "high", "xhigh"],
    defaultReasoningEffort: "medium",
    inputModalities: ["text", "image"],
    supportsPersonality: true,
    isDefault: true,
  },
  {
    id: "gpt-5.4-mini",
    model: "gpt-5.4-mini",
    displayName: "GPT-5.4 Mini",
    description: "Fast model for smaller tasks.",
    hidden: false,
    supportedReasoningEfforts: ["low", "medium", "high", "xhigh"],
    defaultReasoningEffort: "medium",
    inputModalities: ["text", "image"],
    supportsPersonality: true,
    isDefault: false,
  },
];

function appThreadFromExternalSession(session: ExternalSessionRecord): AppThreadRecord {
  return {
    threadId: session.codexThreadId,
    codexSessionId: session.externalSessionId,
    title: session.title,
    preview: session.title,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
    workdir: session.workdir,
    path: session.path,
    source: "cli",
  };
}

function isLikelyTextFile(bytes: Buffer, filePath: string): boolean {
  const mimeType = mimeTypeFor(filePath) ?? "";
  if (mimeType.startsWith("text/") || /json|xml|yaml|javascript|typescript|dart|markdown/.test(mimeType)) return true;
  if (bytes.includes(0)) return false;
  return bytes.byteLength < 512 * 1024;
}

const SKIPPED_WORKSPACE_DIRS = new Set([
  ".codex-lan",
  ".dart_tool",
  ".git",
  ".gradle",
  ".idea",
  ".next",
  ".turbo",
  ".vscode",
  "build",
  "coverage",
  "dist",
  "node_modules",
]);
const MAX_WORKSPACE_SEARCH_DEPTH = 8;
const MAX_WORKSPACE_SEARCH_FILES = 5_000;

type ScoredWorkspaceFile = WorkspaceFileRecord & { score: number };

async function scanWorkspaceFiles(workdir: string, query: string, limit: number): Promise<WorkspaceFileRecord[]> {
  const root = path.resolve(workdir);
  const rootStats = await stat(root);
  if (!rootStats.isDirectory()) {
    throw new Error(`Workspace path is not a directory: ${workdir}`);
  }

  const candidates: ScoredWorkspaceFile[] = [];
  const queue: Array<{ dir: string; depth: number }> = [{ dir: root, depth: 0 }];
  let visitedFiles = 0;

  while (queue.length > 0 && visitedFiles < MAX_WORKSPACE_SEARCH_FILES && (query || candidates.length < limit)) {
    const { dir, depth } = queue.shift()!;
    const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);
    entries.sort((left, right) => left.name.localeCompare(right.name));

    for (const entry of entries) {
      if (entry.isSymbolicLink()) continue;
      const absolutePath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (depth < MAX_WORKSPACE_SEARCH_DEPTH && !shouldSkipWorkspaceDirectory(entry.name)) {
          queue.push({ dir: absolutePath, depth: depth + 1 });
        }
        continue;
      }
      if (!entry.isFile()) continue;
      visitedFiles += 1;
      const relativePath = toPosixPath(path.relative(root, absolutePath));
      if (!relativePath || !matchesFileQuery(relativePath, query)) continue;
      const stats = await stat(absolutePath).catch(() => undefined);
      candidates.push({
        path: relativePath,
        name: path.basename(relativePath),
        sizeBytes: stats?.isFile() ? stats.size : undefined,
        mimeType: mimeTypeFor(relativePath),
        score: scoreWorkspaceFile(relativePath, query),
      });
      if (!query && candidates.length >= limit) break;
    }
  }

  return candidates
    .sort((left, right) => right.score - left.score || left.path.localeCompare(right.path))
    .slice(0, limit)
    .map(({ score: _score, ...file }) => file);
}

function normalizeFileQuery(query: string): string {
  return query.trim().replace(/^@+/, "").replace(/\\/g, "/");
}

function shouldSkipWorkspaceDirectory(name: string): boolean {
  return SKIPPED_WORKSPACE_DIRS.has(name);
}

function matchesFileQuery(relativePath: string, query: string): boolean {
  if (!query) return true;
  const lowerPath = relativePath.toLowerCase();
  const lowerQuery = query.toLowerCase();
  if (lowerPath.includes(lowerQuery)) return true;
  const tokens = lowerQuery.split(/[\s/.-]+/).filter(Boolean);
  return tokens.length > 0 && tokens.every((token) => lowerPath.includes(token));
}

function scoreWorkspaceFile(relativePath: string, query: string): number {
  const lowerPath = relativePath.toLowerCase();
  const lowerName = path.basename(relativePath).toLowerCase();
  const lowerQuery = query.toLowerCase();
  const depth = relativePath.split("/").length;
  if (!query) return 900 - depth * 20 - relativePath.length / 100;
  if (lowerName === lowerQuery || lowerPath === lowerQuery) return 1_000;
  if (lowerName.startsWith(lowerQuery)) return 940 - depth;
  if (lowerPath.startsWith(lowerQuery)) return 900 - depth;
  if (lowerName.includes(lowerQuery)) return 820 - depth;
  if (lowerPath.includes(lowerQuery)) return 760 - depth;
  return 600 - depth;
}

function toPosixPath(filePath: string): string {
  return filePath.split(path.sep).join("/");
}
