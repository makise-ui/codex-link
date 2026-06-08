import { randomUUID } from "node:crypto";
export class MockCodexSession {
    sessionId;
    listeners = new Set();
    activeRun = null;
    goal = null;
    constructor(options = {}) {
        this.sessionId = options.sessionId ?? "default";
    }
    async start() {
        this.emit({ type: "session.started", sessionId: this.sessionId });
        this.emit({ type: "status", status: "connected", sessionId: this.sessionId });
    }
    async sendPrompt(prompt, options = {}) {
        if (this.activeRun) {
            throw new Error("A run is already active; cancel or wait for it to finish.");
        }
        const runId = randomUUID();
        const run = { runId, timers: [], cancelled: false, messageCounter: 0 };
        this.activeRun = run;
        this.emit({ type: "run.started", sessionId: this.sessionId, runId });
        this.emit({ type: "status", status: "running", sessionId: this.sessionId, runId });
        run.timers.push(setTimeout(() => {
            if (run.cancelled)
                return;
            this.emitMessage(run, "thinking", "Thinking", "Thinking…\n");
        }, 150));
        run.timers.push(setTimeout(() => {
            if (run.cancelled)
                return;
            this.emitMessage(run, "executing", "Mock execution", "Checking the host bridge and simulated Codex workspace…\n");
        }, 550));
        run.timers.push(setTimeout(() => {
            if (run.cancelled)
                return;
            this.emitMessage(run, "response", "Response", [
                "Connected to the local Codex Link bridge.",
                "",
                `Prompt received: ${prompt.trim()}`,
                ifAttachments(options.attachments),
                "",
                "```ts",
                "const mode = 'mock-ui-verification';",
                "```",
                "",
            ].join("\n"));
        }, 950));
        run.timers.push(setTimeout(() => {
            if (run.cancelled)
                return;
            this.emit({ type: "status", status: "completed", sessionId: this.sessionId, runId });
            this.emit({ type: "run.completed", sessionId: this.sessionId, runId, exitCode: 0 });
            this.activeRun = null;
        }, 1350));
        return { runId };
    }
    async cancel(runId) {
        const run = this.activeRun;
        if (!run || run.runId !== runId) {
            throw new Error(`No active run found for ${runId}`);
        }
        run.cancelled = true;
        for (const timer of run.timers) {
            clearTimeout(timer);
        }
        this.emit({ type: "status", status: "cancelling", sessionId: this.sessionId, runId });
        this.emit({ type: "status", status: "cancelled", sessionId: this.sessionId, runId });
        this.emit({ type: "run.completed", sessionId: this.sessionId, runId });
        this.activeRun = null;
    }
    async setGoal(input) {
        const now = Date.now();
        this.goal = {
            threadId: this.sessionId,
            objective: input.objective ?? this.goal?.objective ?? "",
            status: input.status ?? this.goal?.status ?? "active",
            tokenBudget: Object.prototype.hasOwnProperty.call(input, "tokenBudget") ? input.tokenBudget ?? null : this.goal?.tokenBudget ?? null,
            tokensUsed: this.goal?.tokensUsed ?? 0,
            timeUsedSeconds: this.goal?.timeUsedSeconds ?? 0,
            createdAt: this.goal?.createdAt ?? now,
            updatedAt: now,
        };
        this.emit({ type: "session.goal.updated", sessionId: this.sessionId, goal: this.goal });
        return this.goal;
    }
    async getGoal() {
        return this.goal;
    }
    async clearGoal() {
        const cleared = this.goal !== null;
        this.goal = null;
        this.emit({ type: "session.goal.cleared", sessionId: this.sessionId });
        return cleared;
    }
    onEvent(listener) {
        this.listeners.add(listener);
        return () => this.listeners.delete(listener);
    }
    async close() {
        if (this.activeRun) {
            for (const timer of this.activeRun.timers) {
                clearTimeout(timer);
            }
            this.activeRun = null;
        }
        this.listeners.clear();
    }
    emitMessage(run, kind, title, text) {
        const messageId = `${run.runId}:${++run.messageCounter}`;
        this.emit({ type: "message.started", sessionId: this.sessionId, runId: run.runId, messageId, kind, role: kind === "response" ? "assistant" : "system", title });
        this.emit({ type: "message.delta", sessionId: this.sessionId, runId: run.runId, messageId, text });
        this.emit({ type: "message.completed", sessionId: this.sessionId, runId: run.runId, messageId });
        this.emit({ type: "output.delta", sessionId: this.sessionId, runId: run.runId, stream: kind === "response" ? "assistant" : "system", text });
    }
    emit(event) {
        for (const listener of this.listeners) {
            listener(event);
        }
    }
}
function ifAttachments(attachments) {
    if (!attachments || attachments.length === 0)
        return "";
    return `Attachments: ${attachments.map((attachment) => `${attachment.kind}:${attachment.name}`).join(", ")}`;
}
