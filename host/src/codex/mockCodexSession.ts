import { randomUUID } from "node:crypto";
import type { CodexEvent, CodexSession, SendPromptOptions, SendPromptResult } from "./codexSession.js";

type Listener = (event: CodexEvent) => void;

type ActiveRun = {
  runId: string;
  timers: NodeJS.Timeout[];
  cancelled: boolean;
  messageCounter: number;
};

export type MockCodexSessionOptions = {
  sessionId?: string;
};

export class MockCodexSession implements CodexSession {
  readonly sessionId: string;
  private readonly listeners = new Set<Listener>();
  private activeRun: ActiveRun | null = null;

  constructor(options: MockCodexSessionOptions = {}) {
    this.sessionId = options.sessionId ?? "default";
  }

  async start(): Promise<void> {
    this.emit({ type: "session.started", sessionId: this.sessionId });
    this.emit({ type: "status", status: "connected", sessionId: this.sessionId });
  }

  async sendPrompt(prompt: string, options: SendPromptOptions = {}): Promise<SendPromptResult> {
    if (this.activeRun) {
      throw new Error("A run is already active; cancel or wait for it to finish.");
    }

    const runId = randomUUID();
    const run: ActiveRun = { runId, timers: [], cancelled: false, messageCounter: 0 };
    this.activeRun = run;

    this.emit({ type: "run.started", sessionId: this.sessionId, runId });
    this.emit({ type: "status", status: "running", sessionId: this.sessionId, runId });

    run.timers.push(
      setTimeout(() => {
        if (run.cancelled) return;
        this.emitMessage(run, "thinking", "Thinking", "Thinking…\n");
      }, 150),
    );

    run.timers.push(
      setTimeout(() => {
        if (run.cancelled) return;
        this.emitMessage(run, "executing", "Mock execution", "Checking the LAN bridge and simulated Codex workspace…\n");
      }, 550),
    );

    run.timers.push(
      setTimeout(() => {
        if (run.cancelled) return;
        this.emitMessage(
          run,
          "response",
          "Response",
          [
            "Connected to the local Codex LAN bridge.",
            "",
            `Prompt received: ${prompt.trim()}`,
            ifAttachments(options.attachments),
            "",
            "```ts",
            "const mode = 'mock-ui-verification';",
            "```",
            "",
          ].join("\n"),
        );
      }, 950),
    );

    run.timers.push(
      setTimeout(() => {
        if (run.cancelled) return;
        this.emit({ type: "status", status: "completed", sessionId: this.sessionId, runId });
        this.emit({ type: "run.completed", sessionId: this.sessionId, runId, exitCode: 0 });
        this.activeRun = null;
      }, 1350),
    );

    return { runId };
  }

  async cancel(runId: string): Promise<void> {
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

  onEvent(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async close(): Promise<void> {
    if (this.activeRun) {
      for (const timer of this.activeRun.timers) {
        clearTimeout(timer);
      }
      this.activeRun = null;
    }
    this.listeners.clear();
  }

  private emitMessage(run: ActiveRun, kind: "thinking" | "executing" | "response" | "system", title: string, text: string): void {
    const messageId = `${run.runId}:${++run.messageCounter}`;
    this.emit({ type: "message.started", sessionId: this.sessionId, runId: run.runId, messageId, kind, role: kind === "response" ? "assistant" : "system", title });
    this.emit({ type: "message.delta", sessionId: this.sessionId, runId: run.runId, messageId, text });
    this.emit({ type: "message.completed", sessionId: this.sessionId, runId: run.runId, messageId });
    this.emit({ type: "output.delta", sessionId: this.sessionId, runId: run.runId, stream: kind === "response" ? "assistant" : "system", text });
  }

  private emit(event: CodexEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }
}

function ifAttachments(attachments: SendPromptOptions["attachments"]): string {
  if (!attachments || attachments.length === 0) return "";
  return `Attachments: ${attachments.map((attachment) => `${attachment.kind}:${attachment.name}`).join(", ")}`;
}
