import { spawn } from "node:child_process";
import path from "node:path";
import readline from "node:readline";
import { mimeTypeFor } from "./fileTransferManager.js";
export class AppServerCodexSession {
    options;
    sessionId;
    listeners = new Set();
    pending = new Map();
    pendingApprovals = new Map();
    child;
    initialized;
    requestId = 0;
    messageCounter = 0;
    codexThreadId;
    threadLoaded = false;
    activeTurn;
    constructor(options) {
        this.options = options;
        this.sessionId = options.sessionId ?? "default";
        this.codexThreadId = options.codexThreadId;
    }
    async start() {
        await this.ensureInitialized();
        this.emit({ type: "session.started", sessionId: this.sessionId });
        this.emit({
            type: "status",
            status: "connected",
            sessionId: this.sessionId,
            detail: `app-server workdir=${path.resolve(this.options.workdir)}`,
        });
    }
    async sendPrompt(prompt, options = {}) {
        const threadId = await this.ensureThread();
        const input = userInputFromPrompt(prompt, options.attachments);
        if (this.activeTurn?.turnId) {
            const result = await this.request("turn/steer", {
                threadId,
                expectedTurnId: this.activeTurn.turnId,
                input,
            });
            return { runId: result.turnId };
        }
        const result = await this.request("turn/start", {
            threadId,
            input,
            cwd: path.resolve(this.options.workdir),
            model: trimmedOrNull(this.options.model),
            effort: this.options.reasoningEffort ?? null,
        });
        return { runId: result.turn.id };
    }
    async listModels(includeHidden = false) {
        await this.ensureInitialized();
        const [modelsResult, capabilitiesResult] = await Promise.all([
            this.request("model/list", {
                includeHidden,
                limit: 100,
            }),
            this.request("modelProvider/capabilities/read", {}),
        ]);
        return {
            models: modelsResult.data.map(normalizeModel).filter((model) => model !== undefined),
            capabilities: normalizeProviderCapabilities(capabilitiesResult),
        };
    }
    async listThreads(input = {}) {
        await this.ensureInitialized();
        const params = {
            limit: Math.min(Math.max(Math.trunc(input.limit ?? 40), 1), 80),
            sortKey: "updated_at",
            sortDirection: "desc",
        };
        if (input.query?.trim())
            params.searchTerm = input.query.trim();
        if (input.cwd?.trim())
            params.cwd = path.resolve(input.cwd.trim());
        const result = await this.request("thread/list", params);
        return result.data.map(normalizeThread).filter((thread) => thread !== undefined);
    }
    async readThread(threadId, includeTurns = true) {
        await this.ensureInitialized();
        const result = await this.request("thread/read", { threadId, includeTurns });
        const thread = normalizeThreadHistory(result.thread);
        if (!thread) {
            throw new Error(`App-server did not return a readable thread: ${threadId}`);
        }
        return thread;
    }
    async listSkills(input = {}) {
        await this.ensureInitialized();
        const result = await this.request("skills/list", {
            cwds: input.cwds?.map((cwd) => path.resolve(cwd)),
            forceReload: input.forceReload ?? false,
        });
        return {
            groups: result.data.map(normalizeSkillGroup).filter((group) => group !== undefined),
        };
    }
    async listDirectory(absolutePath) {
        await this.ensureInitialized();
        const resolved = path.resolve(absolutePath);
        const result = await this.request("fs/readDirectory", { path: resolved });
        return result.entries
            .map((entry) => normalizeDirectoryEntry(entry, resolved, this.options.workdir))
            .filter((entry) => entry !== undefined);
    }
    async readFile(absolutePath) {
        await this.ensureInitialized();
        const resolved = path.resolve(absolutePath);
        const result = await this.request("fs/readFile", { path: resolved });
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
    async searchFiles(input) {
        await this.ensureInitialized();
        const result = await this.request("fuzzyFileSearch", {
            query: input.query.trim().replace(/^@+/, ""),
            roots: input.roots.map((root) => path.resolve(root)),
            cancellationToken: null,
        });
        return result.files
            .map(normalizeFuzzyFile)
            .filter((file) => file !== undefined)
            .slice(0, Math.min(Math.max(Math.trunc(input.limit ?? 40), 1), 80));
    }
    async startReview(input) {
        const threadId = await this.ensureThread();
        const result = await this.request("review/start", {
            threadId,
            target: input.target,
            delivery: input.delivery ?? "inline",
        });
        return {
            runId: result.turn.id,
            reviewThreadId: result.reviewThreadId,
        };
    }
    async getAccount(refreshToken = false) {
        await this.ensureInitialized();
        const accountResult = await this.request("account/read", { refreshToken });
        let authStatus;
        try {
            authStatus = await this.request("getAuthStatus", { includeToken: false, refreshToken: false });
        }
        catch {
            authStatus = undefined;
        }
        return normalizeAccount(accountResult, authStatus);
    }
    async startAccountLogin(input) {
        await this.ensureInitialized();
        const params = input.type === "apiKey"
            ? { type: "apiKey", apiKey: input.apiKey.trim() }
            : input.type === "chatgpt"
                ? { type: "chatgpt", ...(input.codexStreamlinedLogin === undefined ? {} : { codexStreamlinedLogin: input.codexStreamlinedLogin }) }
                : { type: "chatgptDeviceCode" };
        const result = await this.request("account/login/start", params);
        return normalizeLoginFlow(result);
    }
    async cancelAccountLogin(loginId) {
        await this.ensureInitialized();
        const result = await this.request("account/login/cancel", { loginId });
        return normalizeCancelLogin(result);
    }
    async logoutAccount() {
        await this.ensureInitialized();
        await this.request("account/logout", undefined);
    }
    async setGoal(input) {
        const threadId = await this.ensureThread();
        const result = await this.request("thread/goal/set", {
            threadId,
            objective: input.objective ?? null,
            status: input.status ?? null,
            tokenBudget: input.tokenBudget ?? null,
        });
        return normalizeGoal(result.goal);
    }
    async getGoal() {
        const threadId = await this.ensureThread();
        const result = await this.request("thread/goal/get", { threadId });
        return result.goal ? normalizeGoal(result.goal) : null;
    }
    async clearGoal() {
        const threadId = await this.ensureThread();
        const result = await this.request("thread/goal/clear", { threadId });
        return result.cleared;
    }
    async cancel(runId) {
        const threadId = this.codexThreadId;
        if (!threadId) {
            throw new Error("No active app-server thread is available.");
        }
        this.emit({ type: "status", status: "cancelling", sessionId: this.sessionId, runId });
        await this.request("turn/interrupt", { threadId, turnId: runId });
    }
    async decideApproval(approvalId, decision) {
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
    onEvent(listener) {
        this.listeners.add(listener);
        return () => this.listeners.delete(listener);
    }
    async close() {
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
        this.listeners.clear();
    }
    async ensureThread() {
        await this.ensureInitialized();
        if (this.codexThreadId) {
            if (!this.threadLoaded) {
                const result = await this.request("thread/resume", {
                    threadId: this.codexThreadId,
                    cwd: path.resolve(this.options.workdir),
                    model: trimmedOrNull(this.options.model),
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
        const result = await this.request("thread/start", {
            cwd: path.resolve(this.options.workdir),
            model: trimmedOrNull(this.options.model),
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
    ensureInitialized() {
        if (this.initialized)
            return this.initialized;
        this.initialized = this.startProcessAndInitialize();
        return this.initialized;
    }
    async startProcessAndInitialize() {
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
        child.stderr.on("data", (chunk) => {
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
    request(method, params) {
        const id = ++this.requestId;
        const child = this.child;
        if (!child) {
            throw new Error("App-server process is not started.");
        }
        const request = { id, method, params };
        child.stdin.write(`${JSON.stringify(request)}\n`);
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                this.pending.delete(id);
                reject(new Error(`Timed out waiting for app-server response: ${method}`));
            }, 30_000);
            this.pending.set(id, {
                method,
                resolve: (value) => resolve(value),
                reject,
                timer,
            });
        });
    }
    write(message) {
        const child = this.child;
        if (!child)
            return;
        child.stdin.write(`${JSON.stringify(message)}\n`);
    }
    handleLine(line) {
        if (line.trim().length === 0)
            return;
        let message;
        try {
            message = JSON.parse(line);
        }
        catch (error) {
            this.emitSystemMessage(`Unparsed app-server output: ${error instanceof Error ? error.message : String(error)}\n`, "Raw app-server output");
            return;
        }
        if (!message || typeof message !== "object" || Array.isArray(message))
            return;
        const record = message;
        if (record.id !== undefined && record.method) {
            this.handleServerRequest(record);
            return;
        }
        if (record.id !== undefined) {
            this.handleResponse(record);
            return;
        }
        if (record.method) {
            this.handleNotification(record);
        }
    }
    handleResponse(message) {
        const pending = this.pending.get(message.id);
        if (!pending)
            return;
        this.pending.delete(message.id);
        clearTimeout(pending.timer);
        if (message.error) {
            pending.reject(new Error(`${pending.method}: ${message.error.message ?? "Unknown app-server error"}`));
            return;
        }
        pending.resolve(message.result);
    }
    handleServerRequest(message) {
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
    handleNotification(message) {
        const params = safeRecord(message.params);
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
    async handleThreadStarted(params) {
        const thread = safeRecord(params.thread);
        const threadId = readString(thread, "id");
        if (!threadId)
            return;
        await this.setThreadId(threadId);
    }
    async setThreadId(threadId) {
        if (this.codexThreadId === threadId) {
            this.threadLoaded = true;
            return;
        }
        this.codexThreadId = threadId;
        this.threadLoaded = true;
        await this.options.onThreadStarted?.(threadId);
    }
    handleTurnStarted(params) {
        const turn = safeRecord(params.turn);
        const turnId = readString(turn, "id");
        if (!turnId)
            return;
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
    handleTurnCompleted(params) {
        const turn = safeRecord(params.turn);
        const turnId = readString(turn, "id") ?? this.activeTurn?.turnId;
        if (!turnId)
            return;
        this.completeOpenMessages(turnId);
        const status = readString(turn, "status");
        if (status === "interrupted") {
            this.emit({ type: "status", status: "cancelled", sessionId: this.sessionId, runId: turnId });
            this.emit({ type: "run.completed", sessionId: this.sessionId, runId: turnId, exitCode: 0 });
        }
        else if (status === "failed") {
            this.emit({ type: "status", status: "failed", sessionId: this.sessionId, runId: turnId });
            this.emit({ type: "run.completed", sessionId: this.sessionId, runId: turnId, exitCode: 1 });
        }
        else {
            this.emit({ type: "status", status: "completed", sessionId: this.sessionId, runId: turnId });
            this.emit({ type: "run.completed", sessionId: this.sessionId, runId: turnId, exitCode: 0 });
        }
        this.activeTurn = undefined;
    }
    handleItemStarted(params) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        const item = safeRecord(params.item);
        if (!turnId)
            return;
        if (readString(item, "type") === "reasoning") {
            this.ensureThinking(turnId);
            return;
        }
        const id = readString(item, "id");
        const presentation = itemPresentation(item);
        if (!presentation)
            return;
        if (presentation.kind !== "thinking") {
            this.completeThinking(turnId);
        }
        this.emitStartedMessage(turnId, presentation.kind, presentation.title, presentation.text, id);
    }
    handleItemDelta(params, fallbackKind) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        const itemId = readString(params, "itemId");
        const delta = readString(params, "delta") ?? "";
        if (!turnId || !itemId || delta.length === 0)
            return;
        const messageId = this.messageIdForItem(turnId, itemId, fallbackKind);
        this.emitDelta(turnId, messageId, itemId, delta);
    }
    handleReasoningSummaryPartAdded(params) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        const itemId = readString(params, "itemId");
        if (!turnId || !itemId)
            return;
        this.messageIdForItem(turnId, reasoningSummaryKey(itemId, params.summaryIndex), "reasoning", "Thinking summary");
    }
    handleReasoningSummaryDelta(params) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        const itemId = readString(params, "itemId");
        const delta = readString(params, "delta") ?? "";
        if (!turnId || !itemId || delta.length === 0)
            return;
        const key = reasoningSummaryKey(itemId, params.summaryIndex);
        const messageId = this.messageIdForItem(turnId, key, "reasoning", "Thinking summary");
        this.emitDelta(turnId, messageId, key, delta);
    }
    handleMcpProgress(params) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        const itemId = readString(params, "itemId");
        const message = readString(params, "message");
        if (!turnId || !itemId || !message)
            return;
        const messageId = this.messageIdForItem(turnId, itemId, "executing", "Using MCP tool");
        this.emitDelta(turnId, messageId, itemId, `${message}\n`);
    }
    handleTerminalInteraction(params) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        const itemId = readString(params, "itemId");
        const stdin = readString(params, "stdin");
        if (!turnId || !itemId || !stdin)
            return;
        const messageId = this.messageIdForItem(turnId, itemId, "executing", "Running command");
        this.emitDelta(turnId, messageId, itemId, `\nTerminal input:\n${stdin}\n`);
    }
    handleTurnDiffUpdated(params) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        const diff = readString(params, "diff");
        if (!turnId || !diff)
            return;
        const files = parseUnifiedDiffFiles(diff);
        if (files.length > 0) {
            this.emit({
                type: "diff.available",
                sessionId: this.sessionId,
                files,
            });
        }
    }
    handleWarning(params) {
        const warning = readString(params, "message");
        if (!warning)
            return;
        this.emitSystemMessage(`${warning}\n`, "Warning");
    }
    handleFilePatchUpdated(params) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        const itemId = readString(params, "itemId");
        const changes = readChanges(params.changes);
        if (!turnId || !itemId || changes.length === 0)
            return;
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
    handleItemCompleted(params) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        const item = safeRecord(params.item);
        const itemId = readString(item, "id");
        if (!turnId || !itemId)
            return;
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
    handlePlanUpdated(params) {
        const turnId = readString(params, "turnId") ?? this.activeTurn?.turnId;
        if (!turnId)
            return;
        const explanation = readString(params, "explanation");
        const plan = Array.isArray(params.plan)
            ? params.plan.map((item) => safeRecord(item)).map((item) => `- ${readString(item, "status") ?? "pending"}: ${readString(item, "step") ?? ""}`)
            : [];
        const text = [explanation, ...plan].filter(Boolean).join("\n");
        if (text.trim().length === 0)
            return;
        this.emit({
            type: "session.plan.updated",
            sessionId: this.sessionId,
            runId: turnId,
            title: "Plan",
            text: text.endsWith("\n") ? text : `${text}\n`,
        });
    }
    emitCompletionTextIfNeeded(turnId, itemId, text) {
        if (!text || text.length === 0)
            return;
        const emittedLength = this.activeTurn?.itemTextLengths.get(itemId) ?? 0;
        if (emittedLength >= text.length)
            return;
        const messageId = this.messageIdForItem(turnId, itemId, "response");
        this.emitDelta(turnId, messageId, itemId, text.slice(emittedLength));
    }
    messageIdForItem(turnId, itemId, fallbackKind, title) {
        const existing = this.activeTurn?.itemMessageIds.get(itemId);
        if (existing)
            return existing;
        return this.emitStartedMessage(turnId, fallbackKind, title ?? readableTitle(fallbackKind), undefined, itemId);
    }
    emitStartedMessage(runId, kind, title, text, itemId) {
        const messageId = `${runId}:${++this.messageCounter}`;
        if (this.activeTurn && itemId) {
            this.activeTurn.itemMessageIds.set(itemId, messageId);
            this.activeTurn.itemTextLengths.set(itemId, 0);
        }
        this.activeTurn?.messageKinds.set(messageId, kind);
        if (kind === "thinking") {
            if (this.activeTurn)
                this.activeTurn.thinkingMessageId = messageId;
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
    emitCompleteMessage(runId, kind, title, text) {
        if (kind !== "thinking")
            this.completeThinking(runId);
        const messageId = this.emitStartedMessage(runId, kind, title);
        this.emit({ type: "message.delta", sessionId: this.sessionId, runId, messageId, text });
        this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId });
        if (kind !== "thinking")
            this.ensureThinking(runId);
    }
    emitDelta(runId, messageId, itemId, text) {
        this.emit({ type: "message.delta", sessionId: this.sessionId, runId, messageId, text });
        if (this.activeTurn && itemId) {
            this.activeTurn.itemTextLengths.set(itemId, (this.activeTurn.itemTextLengths.get(itemId) ?? 0) + text.length);
        }
    }
    ensureThinking(runId) {
        if (!this.activeTurn || this.activeTurn.thinkingMessageId)
            return;
        this.emitStartedMessage(runId, "thinking", "Thinking", "Thinking…\n");
    }
    completeThinking(runId) {
        const thinkingMessageId = this.activeTurn?.thinkingMessageId;
        if (!thinkingMessageId)
            return;
        this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId: thinkingMessageId });
        this.activeTurn?.messageKinds.delete(thinkingMessageId);
        if (this.activeTurn)
            this.activeTurn.thinkingMessageId = undefined;
    }
    completeOpenMessages(runId) {
        this.completeThinking(runId);
        const active = this.activeTurn;
        if (!active)
            return;
        for (const messageId of active.itemMessageIds.values()) {
            this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId });
        }
        active.itemMessageIds.clear();
        active.messageKinds.clear();
        active.itemTextLengths.clear();
    }
    emitSystemMessage(text, title) {
        const runId = this.activeTurn?.turnId ?? "app-server";
        this.emitCompleteMessage(runId, "system", title, text);
    }
    rejectAll(error) {
        for (const request of this.pending.values()) {
            clearTimeout(request.timer);
            request.reject(error);
        }
        this.pending.clear();
    }
    emit(event) {
        for (const listener of this.listeners) {
            listener(event);
        }
    }
}
function userInputFromPrompt(prompt, attachments = []) {
    const input = [
        { type: "text", text: prompt, text_elements: [] },
    ];
    for (const attachment of attachments) {
        input.push(attachment.kind === "image"
            ? { type: "localImage", path: attachment.path, detail: "auto" }
            : { type: "mention", name: attachment.name, path: attachment.path });
    }
    return input;
}
function itemPresentation(item) {
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
function commandPresentation(item) {
    const command = readString(item, "command") ?? "";
    const readAction = (Array.isArray(item.commandActions) ? item.commandActions : [])
        .map((action) => safeRecord(action))
        .find((action) => readString(action, "type") === "read");
    if (readAction || isReadCommand(command)) {
        const filePath = readString(readAction ?? {}, "path") ?? readCommandPath(command);
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
function readChanges(value) {
    if (!Array.isArray(value))
        return [];
    return value.flatMap((entry) => {
        const record = safeRecord(entry);
        const filePath = readString(record, "path");
        if (!filePath)
            return [];
        const kind = safeRecord(record.kind);
        const type = readString(kind, "type");
        const status = type === "add" ? "added" : type === "delete" ? "deleted" : type === "update" && readString(kind, "move_path") ? "renamed" : "modified";
        return [{ path: shortPath(filePath), status, diff: readString(record, "diff") ?? "" }];
    });
}
function formatChanges(changes) {
    return changes
        .flatMap((change) => [
        `${change.status} ${change.path}`,
        ...(change.diff ? change.diff.split(/\r?\n/) : []),
    ])
        .filter(Boolean)
        .join("\n");
}
function normalizeAccount(value, authStatusValue) {
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
function normalizeAccountUpdate(value) {
    const record = safeRecord(value);
    const authMode = normalizeAuthMode(readString(record, "authMode"));
    return {
        accountType: accountTypeFromAuthMode(authMode),
        planType: readString(record, "planType") ?? null,
        authMode,
        requiresOpenaiAuth: authMode === null,
    };
}
function normalizeLoginFlow(value) {
    const record = safeRecord(value);
    const type = readString(record, "type");
    if (type === "apiKey")
        return { type: "apiKey" };
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
    if (type === "chatgptAuthTokens")
        return { type: "chatgptAuthTokens" };
    throw new Error(`Unsupported account login response: ${type ?? "unknown"}`);
}
function normalizeCancelLogin(value) {
    const status = readString(safeRecord(value), "status");
    return { status: status === "notFound" ? "notFound" : "canceled" };
}
function normalizeAccountType(value) {
    return value === "apiKey" || value === "chatgpt" || value === "amazonBedrock" ? value : null;
}
function normalizeAuthMode(value) {
    return value === "apikey" || value === "chatgpt" || value === "chatgptAuthTokens" || value === "agentIdentity" ? value : null;
}
function authModeFromAccountType(accountType) {
    if (accountType === "apiKey")
        return "apikey";
    if (accountType === "chatgpt")
        return "chatgpt";
    return null;
}
function accountTypeFromAuthMode(authMode) {
    if (authMode === "apikey")
        return "apiKey";
    if (authMode === "chatgpt" || authMode === "chatgptAuthTokens")
        return "chatgpt";
    return null;
}
function normalizeGoal(value) {
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
function normalizeModel(value) {
    const record = safeRecord(value);
    const id = readString(record, "id") ?? readString(record, "model");
    const model = readString(record, "model") ?? id;
    if (!id || !model)
        return undefined;
    const efforts = Array.isArray(record.supportedReasoningEfforts)
        ? record.supportedReasoningEfforts
            .map((effort) => readString(safeRecord(effort), "reasoningEffort"))
            .filter(isReasoningEffort)
        : [];
    const defaultEffort = readString(record, "defaultReasoningEffort");
    return {
        id,
        model,
        displayName: readString(record, "displayName") ?? id,
        description: readString(record, "description"),
        hidden: record.hidden === true,
        supportedReasoningEfforts: efforts,
        defaultReasoningEffort: isReasoningEffort(defaultEffort) ? defaultEffort : undefined,
        inputModalities: Array.isArray(record.inputModalities) ? record.inputModalities.filter((item) => typeof item === "string") : ["text"],
        supportsPersonality: record.supportsPersonality === true,
        isDefault: record.isDefault === true,
    };
}
function normalizeProviderCapabilities(value) {
    const record = safeRecord(value);
    return {
        namespaceTools: record.namespaceTools === true,
        imageGeneration: record.imageGeneration === true,
        webSearch: record.webSearch === true,
    };
}
function normalizeThread(value) {
    const record = safeRecord(value);
    const threadId = readString(record, "id") ?? readString(record, "sessionId");
    if (!threadId)
        return undefined;
    const preview = readString(record, "preview") ?? "";
    const name = readString(record, "name");
    const cwd = readString(record, "cwd") ?? "";
    const turns = Array.isArray(record.turns) ? record.turns : [];
    return {
        threadId,
        codexSessionId: readString(record, "sessionId"),
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
    };
}
function normalizeThreadHistory(value) {
    const thread = normalizeThread(value);
    if (!thread)
        return undefined;
    const record = safeRecord(value);
    return {
        ...thread,
        messages: Array.isArray(record.turns) ? messagesFromTurns(record.turns) : [],
    };
}
function normalizeSkillGroup(value) {
    const record = safeRecord(value);
    const cwd = readString(record, "cwd");
    if (!cwd)
        return undefined;
    const skills = [];
    if (Array.isArray(record.skills)) {
        for (const skill of record.skills) {
            const item = safeRecord(skill);
            const name = readString(item, "name");
            const description = readString(item, "description") ?? readString(item, "shortDescription") ?? "";
            const skillPath = readString(item, "path");
            if (!name || !skillPath)
                continue;
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
function normalizeDirectoryEntry(value, directory, workdir) {
    const record = safeRecord(value);
    const name = readString(record, "fileName");
    if (!name)
        return undefined;
    const absolutePath = path.join(directory, name);
    return {
        path: relativeToWorkdir(absolutePath, workdir),
        name,
        isDirectory: record.isDirectory === true,
        isFile: record.isFile === true,
        mimeType: record.isFile === true ? mimeTypeFor(name) : undefined,
    };
}
function normalizeFuzzyFile(value) {
    const record = safeRecord(value);
    const filePath = readString(record, "path");
    if (!filePath)
        return undefined;
    return {
        path: toPosixPath(filePath),
        name: readString(record, "file_name") ?? path.basename(filePath),
        mimeType: mimeTypeFor(filePath),
    };
}
function messagesFromTurns(turns) {
    const messages = [];
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
function userMessageText(item) {
    const content = Array.isArray(item.content) ? item.content : [];
    return content
        .map((part) => readString(safeRecord(part), "text"))
        .filter(Boolean)
        .join("\n");
}
function countThreadMessages(turns) {
    return turns.reduce((count, turn) => {
        const items = Array.isArray(safeRecord(turn).items) ? safeRecord(turn).items : [];
        return count + items.filter((item) => {
            const type = readString(safeRecord(item), "type");
            return type === "userMessage" || type === "agentMessage";
        }).length;
    }, 0);
}
function parseUnifiedDiffFiles(diff) {
    const lines = diff.split(/\r?\n/);
    const starts = [];
    for (const [index, line] of lines.entries()) {
        if (line.startsWith("diff --git "))
            starts.push(index);
    }
    if (starts.length === 0 && diff.trim()) {
        return [{ path: "workspace", status: "modified", patch: diff }];
    }
    const files = [];
    for (const [index, start] of starts.entries()) {
        const end = starts[index + 1] ?? lines.length;
        const patch = lines.slice(start, end).join("\n");
        const header = lines[start] ?? "";
        const match = header.match(/^diff --git a\/(.+?) b\/(.+)$/);
        if (!match)
            continue;
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
function relativeToWorkdir(absolutePath, workdir) {
    const relative = path.relative(path.resolve(workdir), path.resolve(absolutePath));
    if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
        return toPosixPath(absolutePath);
    }
    return toPosixPath(relative);
}
function toPosixPath(value) {
    return value.replace(/\\/g, "/");
}
function firstNonEmptyLine(value) {
    const line = value.split(/\r?\n/).map((item) => item.trim()).find(Boolean);
    if (!line)
        return undefined;
    return line.length > 80 ? `${line.slice(0, 77)}...` : line;
}
function timestampToIso(value) {
    if (typeof value === "number" && Number.isFinite(value)) {
        return new Date(value * 1000).toISOString();
    }
    if (typeof value === "string" && value.trim()) {
        const date = new Date(value);
        if (!Number.isNaN(date.getTime()))
            return date.toISOString();
    }
    return new Date(0).toISOString();
}
function reasoningSummaryKey(itemId, summaryIndex) {
    return `reasoning:${itemId}:${typeof summaryIndex === "number" ? summaryIndex : 0}`;
}
function isLikelyText(bytes, filePath) {
    const mimeType = mimeTypeFor(filePath) ?? "";
    if (mimeType.startsWith("text/") || /json|xml|yaml|javascript|typescript|dart|markdown/.test(mimeType))
        return true;
    if (bytes.includes(0))
        return false;
    return bytes.byteLength < 512 * 1024;
}
function approvalMessage(sessionId, approvalId, method, params) {
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
function approvalResponse(method, params, decision) {
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
function isApprovalMethod(method) {
    return method === "item/commandExecution/requestApproval" ||
        method === "item/fileChange/requestApproval" ||
        method === "item/permissions/requestApproval";
}
function safeRecord(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}
function readString(record, key) {
    const value = record[key];
    return typeof value === "string" && value.length > 0 ? value : undefined;
}
function trimmedOrNull(value) {
    const trimmed = value?.trim();
    return trimmed ? trimmed : null;
}
function readableTitle(kind) {
    return kind === "response" ? "Response" : kind === "executing" ? "Running tool" : kind === "thinking" ? "Thinking" : kind === "reasoning" ? "Thinking summary" : "System";
}
function isGoalStatus(value) {
    return value === "active" || value === "paused" || value === "blocked" || value === "usageLimited" || value === "budgetLimited" || value === "complete";
}
function isReasoningEffort(value) {
    return value === "low" || value === "medium" || value === "high" || value === "xhigh";
}
function approvalPolicyForSandbox(sandbox) {
    return sandbox === "danger-full-access" ? "never" : "on-request";
}
function isReadCommand(command) {
    const payload = command.toLowerCase();
    return /(^|\s)(cat|less|more)\s+/.test(payload) ||
        /(^|\s)(head|tail)\b/.test(payload) ||
        /(^|\s)sed\s+-n\s+/.test(payload);
}
function readCommandPath(command) {
    const sed = command.match(/(?:^|\s)sed\s+-n\s+['"]?\d+(?:,\d+)?p['"]?\s+(.+?)\s*$/);
    if (sed?.[1])
        return stripShellQuotes(sed[1]);
    const cat = command.match(/(?:^|\s)cat\s+(.+?)\s*$/);
    if (cat?.[1])
        return stripShellQuotes(cat[1]);
    const headTail = command.match(/(?:^|\s)(?:head|tail)(?:\s+-n\s+\d+)?\s+(.+?)\s*$/);
    return headTail?.[1] ? stripShellQuotes(headTail[1]) : undefined;
}
function stripShellQuotes(value) {
    let output = value.trim();
    if ((output.startsWith('"') && output.endsWith('"')) || (output.startsWith("'") && output.endsWith("'"))) {
        output = output.slice(1, -1);
    }
    return output;
}
function shortPath(value) {
    const normalized = value.replace(/\\/g, "/");
    const parts = normalized.split("/").filter(Boolean);
    return parts.slice(-3).join("/") || normalized;
}
