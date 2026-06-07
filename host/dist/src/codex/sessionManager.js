import { randomUUID } from "node:crypto";
import { mkdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { CliCodexSession } from "./cliCodexSession.js";
import { findExternalSession, listExternalSessions, readExternalSessionHistory } from "./externalSessions.js";
import { MockCodexSession } from "./mockCodexSession.js";
import { SessionStore } from "./sessionStore.js";
export class CodexSessionManager {
    options;
    store;
    listeners = new Set();
    adapters = new Map();
    sessions = new Map();
    messageHistory = new Map();
    workspaces = [];
    pendingPersistence = Promise.resolve();
    activeSessionId;
    constructor(options) {
        this.options = options;
        this.store = new SessionStore(options.stateDir);
    }
    static async create(options) {
        const manager = new CodexSessionManager(options);
        await manager.init();
        return manager;
    }
    listSessions() {
        return [...this.sessions.values()].sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
    }
    getActiveSessionId() {
        return this.activeSessionId;
    }
    getSessionHistory(sessionId) {
        return [...(this.messageHistory.get(sessionId) ?? [])].map((message) => ({ ...message }));
    }
    async listExternalSessions() {
        return listExternalSessions();
    }
    getWorkspaces(activeSessionId = this.activeSessionId) {
        const activeWorkspaceId = activeSessionId ? this.sessions.get(activeSessionId)?.workspaceId : undefined;
        return this.workspaces.map((workspace) => ({
            workspaceId: workspace.id,
            label: workspace.label,
            path: workspace.path,
            active: workspace.id === activeWorkspaceId,
        }));
    }
    async addWorkspace(workspacePath, sessionId, options = {}) {
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
        }
        if (sessionId) {
            await this.switchWorkspace(sessionId, workspace.id);
        }
        else {
            await this.save();
        }
        return {
            workspaceId: workspace.id,
            label: workspace.label,
            path: workspace.path,
            active: sessionId ? this.sessions.get(sessionId)?.workspaceId === workspace.id : false,
        };
    }
    async importExternalSession(externalSessionId) {
        const external = await findExternalSession(externalSessionId);
        if (!external) {
            throw new Error(`Unknown external Codex session: ${externalSessionId}`);
        }
        const workspace = await this.addWorkspace(external.workdir);
        const now = new Date().toISOString();
        const record = {
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
    async createSession(input = {}) {
        const workspace = this.workspaceById(input.workspaceId ?? this.workspaces[0]?.id);
        const mode = input.mode ?? this.defaultMode();
        this.assertModeAllowed(mode);
        const now = new Date().toISOString();
        const record = {
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
    async startSession(sessionId) {
        const record = sessionId ? this.requireSession(sessionId) : this.requireSession(this.activeSessionId ?? this.listSessions()[0]?.sessionId);
        this.activeSessionId = record.sessionId;
        const adapter = this.adapterFor(record);
        await adapter.start();
        return record;
    }
    async renameSession(sessionId, title) {
        const record = this.requireSession(sessionId);
        record.title = title.trim();
        record.updatedAt = new Date().toISOString();
        await this.saveAndEmit(record);
        return record;
    }
    async deleteSession(sessionId) {
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
    async switchWorkspace(sessionId, workspaceId) {
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
    async setSessionMode(sessionId, mode) {
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
    async setSessionConfig(sessionId, config) {
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
    async sendPrompt(sessionId, prompt, attachments = []) {
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
        }
        await this.save();
        const adapter = this.adapterFor(record);
        return adapter.sendPrompt(augmentPromptWithAttachments(prompt, preparedAttachments), { attachments: preparedAttachments });
    }
    async cancel(sessionId, runId) {
        const adapter = this.adapters.get(sessionId)?.session;
        if (!adapter) {
            throw new Error(`No active session adapter found for ${sessionId}`);
        }
        await adapter.cancel(runId);
    }
    onEvent(listener) {
        this.listeners.add(listener);
        return () => this.listeners.delete(listener);
    }
    async close() {
        for (const sessionId of [...this.adapters.keys()]) {
            await this.closeAdapter(sessionId);
        }
        await this.pendingPersistence;
        this.listeners.clear();
    }
    async init() {
        const snapshot = await this.store.load();
        this.workspaces = mergeWorkspaces(this.options.workspaces, snapshot.workspaces ?? []);
        this.messageHistory = new Map(Object.entries(snapshot.messages ?? {}).map(([sessionId, messages]) => [sessionId, messages.map((message) => ({ ...message, complete: message.kind === "thinking" ? true : message.complete }))]));
        for (const persisted of snapshot.sessions) {
            const workspace = this.workspaces.find((candidate) => candidate.id === persisted.workspaceId) ?? this.workspaces.find((candidate) => candidate.path === persisted.workdir) ?? this.workspaces[0];
            if (!workspace)
                continue;
            const mode = persisted.mode === "yolo" && !this.options.allowYolo ? "safe" : persisted.mode;
            const record = {
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
    adapterFor(record) {
        const existing = this.adapters.get(record.sessionId)?.session;
        if (existing)
            return existing;
        const session = this.options.sessionMode === "mock"
            ? new MockCodexSession({ sessionId: record.sessionId })
            : new CliCodexSession({
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
            this.emit(event);
        });
        this.adapters.set(record.sessionId, { session, unsubscribe });
        return session;
    }
    async handleAdapterEvent(event) {
        if (!("sessionId" in event) || !event.sessionId)
            return;
        const record = this.sessions.get(event.sessionId);
        if (!record)
            return;
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
        }
        else if (historyChanged) {
            await this.save();
        }
    }
    async updateThreadId(sessionId, threadId) {
        const record = this.sessions.get(sessionId);
        if (!record || record.codexThreadId === threadId)
            return;
        record.codexThreadId = threadId;
        record.updatedAt = new Date().toISOString();
        await this.saveAndEmit(record);
    }
    recordMessageStarted(event) {
        if (event.kind === "thinking")
            return false;
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
    recordMessageDelta(event) {
        const history = this.messageHistory.get(event.sessionId);
        const existing = history?.find((message) => message.messageId === event.messageId);
        if (existing) {
            existing.text += event.text;
            return true;
        }
        if (event.text.trim().length === 0 || isThinkingNoise(event.text))
            return false;
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
    recordMessageCompleted(event) {
        const existing = this.messageHistory.get(event.sessionId)?.find((message) => message.messageId === event.messageId);
        if (!existing)
            return false;
        existing.complete = true;
        return true;
    }
    recordDiffAvailable(event) {
        if (event.files.length === 0)
            return false;
        this.appendHistory(event.sessionId, {
            messageId: randomUUID(),
            role: "system",
            kind: "files",
            title: "Files changed",
            text: event.files.map((file) => `${file.status} ${file.path}`).join("\n"),
            createdAt: new Date().toISOString(),
            complete: true,
        });
        return true;
    }
    appendHistory(sessionId, message) {
        if (message.kind === "thinking")
            return;
        const history = this.messageHistory.get(sessionId) ?? [];
        const existingIndex = history.findIndex((candidate) => candidate.messageId === message.messageId);
        if (existingIndex >= 0) {
            history[existingIndex] = message;
        }
        else {
            history.push(message);
        }
        this.messageHistory.set(sessionId, history.slice(-500));
    }
    async prepareAttachments(record, attachments) {
        if (attachments.length === 0)
            return [];
        const uploadDir = path.join(record.workdir, ".codex-lan", "uploads", new Date().toISOString().replace(/[:.]/g, "-"));
        await mkdir(uploadDir, { recursive: true });
        const prepared = [];
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
    async closeAdapter(sessionId) {
        const adapter = this.adapters.get(sessionId);
        if (!adapter)
            return;
        adapter.unsubscribe();
        await adapter.session.close();
        this.adapters.delete(sessionId);
        await this.pendingPersistence;
    }
    requireSession(sessionId) {
        if (!sessionId)
            throw new Error("No session id was provided.");
        const record = this.sessions.get(sessionId);
        if (!record)
            throw new Error(`Unknown session: ${sessionId}`);
        return record;
    }
    workspaceById(workspaceId) {
        const workspace = this.workspaces.find((candidate) => candidate.id === workspaceId) ?? this.workspaces[0];
        if (!workspace)
            throw new Error("No host workspaces are configured.");
        if (workspaceId && workspace.id !== workspaceId)
            throw new Error(`Unknown workspace: ${workspaceId}`);
        return workspace;
    }
    assertModeAllowed(mode) {
        if (mode === "yolo" && !this.options.allowYolo) {
            throw new Error("Yolo mode is disabled by the host. Restart with --allow-yolo to permit danger-full-access from paired clients.");
        }
    }
    defaultMode() {
        return this.options.defaultSandbox === "danger-full-access" ? "yolo" : "safe";
    }
    sandboxForMode(mode) {
        if (mode === "yolo")
            return "danger-full-access";
        return this.options.defaultSandbox === "danger-full-access" ? "workspace-write" : this.options.defaultSandbox;
    }
    async saveAndEmit(record) {
        await this.save();
        this.emit({ type: "session.updated", session: { ...record } });
    }
    async save() {
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
    emit(event) {
        for (const listener of this.listeners) {
            listener(event);
        }
    }
}
function titleFromPrompt(prompt) {
    const compact = prompt.trim().replace(/\s+/g, " ");
    if (!compact)
        return "New session";
    return compact.length > 50 ? `${compact.slice(0, 47)}…` : compact;
}
function mergeWorkspaces(configured, stored) {
    const merged = [];
    const seenPaths = new Set();
    for (const workspace of configured) {
        const resolved = path.resolve(workspace.path);
        if (seenPaths.has(resolved))
            continue;
        seenPaths.add(resolved);
        merged.push({ ...workspace, path: resolved });
    }
    for (const workspace of stored) {
        const resolved = path.resolve(workspace.path);
        if (seenPaths.has(resolved))
            continue;
        seenPaths.add(resolved);
        merged.push({
            id: workspace.workspaceId || nextWorkspaceId(merged),
            label: workspace.label || path.basename(resolved) || resolved,
            path: resolved,
        });
    }
    return merged;
}
function nextWorkspaceId(workspaces) {
    let index = workspaces.length + 1;
    const used = new Set(workspaces.map((workspace) => workspace.id));
    while (used.has(`workspace-${index}`)) {
        index += 1;
    }
    return index === 1 ? "default" : `workspace-${index}`;
}
function augmentPromptWithAttachments(prompt, attachments) {
    if (attachments.length === 0)
        return prompt;
    const lines = attachments.map((attachment) => `- ${attachment.kind}: ${attachment.name} at ${attachment.path}`);
    return `${prompt.trim()}\n\nUploaded files available in the workspace:\n${lines.join("\n")}`;
}
function safeAttachmentName(name, index) {
    const base = path.basename(name).replace(/[^A-Za-z0-9._-]/g, "_").replace(/^_+/, "");
    return base || `upload-${index + 1}`;
}
function isImageAttachment(attachment) {
    const mimeType = attachment.mimeType?.toLowerCase() ?? "";
    if (mimeType.startsWith("image/"))
        return true;
    return /\.(png|jpe?g|webp|gif|bmp|heic|heif)$/i.test(attachment.name);
}
function isThinkingNoise(text) {
    return text.trim().replace(/\.+$/, "").replace(/…$/, "").toLowerCase() === "thinking";
}
