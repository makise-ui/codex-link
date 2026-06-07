import { randomUUID } from "node:crypto";
import type { SessionMode, WorkspaceConfig } from "../config.js";
import type { RunMode, SandboxMode, ServerMessage, SessionRecord, WorkspaceRecord } from "../protocol/messages.js";
import type { CodexEvent, CodexSession, SendPromptResult } from "./codexSession.js";
import { CliCodexSession } from "./cliCodexSession.js";
import { MockCodexSession } from "./mockCodexSession.js";
import { SessionStore } from "./sessionStore.js";

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
  private sessions = new Map<string, SessionRecord>();
  private activeSessionId?: string;

  private constructor(private readonly options: CodexSessionManagerOptions) {
    this.store = new SessionStore(options.stateDir);
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

  getWorkspaces(activeSessionId = this.activeSessionId): WorkspaceRecord[] {
    const activeWorkspaceId = activeSessionId ? this.sessions.get(activeSessionId)?.workspaceId : undefined;
    return this.options.workspaces.map((workspace) => ({
      workspaceId: workspace.id,
      label: workspace.label,
      path: workspace.path,
      active: workspace.id === activeWorkspaceId,
    }));
  }

  async createSession(input: { title?: string; workspaceId?: string; mode?: RunMode } = {}): Promise<SessionRecord> {
    const workspace = this.workspaceById(input.workspaceId ?? this.options.workspaces[0]?.id);
    const mode = input.mode ?? this.defaultMode();
    this.assertModeAllowed(mode);

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

  async sendPrompt(sessionId: string, prompt: string): Promise<SendPromptResult> {
    const record = this.requireSession(sessionId);
    this.activeSessionId = sessionId;
    if (!record.codexThreadId && record.title === "New session") {
      record.title = titleFromPrompt(prompt);
      record.updatedAt = new Date().toISOString();
      await this.saveAndEmit(record);
    }
    const adapter = this.adapterFor(record);
    return adapter.sendPrompt(prompt);
  }

  async cancel(sessionId: string, runId: string): Promise<void> {
    const adapter = this.adapters.get(sessionId)?.session;
    if (!adapter) {
      throw new Error(`No active session adapter found for ${sessionId}`);
    }
    await adapter.cancel(runId);
  }

  onEvent(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async close(): Promise<void> {
    for (const sessionId of [...this.adapters.keys()]) {
      await this.closeAdapter(sessionId);
    }
    this.listeners.clear();
  }

  private async init(): Promise<void> {
    const snapshot = await this.store.load();
    for (const persisted of snapshot.sessions) {
      const workspace = this.options.workspaces.find((candidate) => candidate.id === persisted.workspaceId) ?? this.options.workspaces.find((candidate) => candidate.path === persisted.workdir) ?? this.options.workspaces[0];
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
      : new CliCodexSession({
          sessionId: record.sessionId,
          command: this.options.codexCommand,
          workdir: record.workdir,
          sandbox: record.sandbox,
          codexThreadId: record.codexThreadId,
          onThreadStarted: (threadId) => {
            void this.updateThreadId(record.sessionId, threadId).catch((error) => {
              this.emit({ type: "error", code: "session.thread_persist_failed", message: error instanceof Error ? error.message : String(error) });
            });
          },
        });

    const unsubscribe = session.onEvent((event) => {
      void this.handleAdapterEvent(event).catch((error) => {
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
    }
  }

  private async updateThreadId(sessionId: string, threadId: string): Promise<void> {
    const record = this.sessions.get(sessionId);
    if (!record || record.codexThreadId === threadId) return;
    record.codexThreadId = threadId;
    record.updatedAt = new Date().toISOString();
    await this.saveAndEmit(record);
  }

  private async closeAdapter(sessionId: string): Promise<void> {
    const adapter = this.adapters.get(sessionId);
    if (!adapter) return;
    adapter.unsubscribe();
    await adapter.session.close();
    this.adapters.delete(sessionId);
  }

  private requireSession(sessionId?: string): SessionRecord {
    if (!sessionId) throw new Error("No session id was provided.");
    const record = this.sessions.get(sessionId);
    if (!record) throw new Error(`Unknown session: ${sessionId}`);
    return record;
  }

  private workspaceById(workspaceId?: string): WorkspaceConfig {
    const workspace = this.options.workspaces.find((candidate) => candidate.id === workspaceId) ?? this.options.workspaces[0];
    if (!workspace) throw new Error("No host workspaces are configured.");
    if (workspaceId && workspace.id !== workspaceId) throw new Error(`Unknown workspace: ${workspaceId}`);
    return workspace;
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
    await this.store.save({ sessions: this.listSessions() });
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
