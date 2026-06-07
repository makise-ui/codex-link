import { randomUUID } from "node:crypto";
import { spawn, type ChildProcess } from "node:child_process";
import path from "node:path";
import type { SandboxMode } from "../protocol/messages.js";
import type { CodexEvent, CodexSession, SendPromptResult } from "./codexSession.js";
import { JsonLineBuffer, mapCodexJsonEvent, parseCodexJsonLine } from "./codexJsonEvents.js";

type Listener = (event: CodexEvent) => void;

export type CliCodexSessionOptions = {
  sessionId?: string;
  command: string;
  workdir: string;
  sandbox?: SandboxMode;
  codexThreadId?: string;
  argsPrefix?: string[];
  cancelGraceMs?: number;
  onThreadStarted?: (threadId: string) => void | Promise<void>;
};

type ActiveProcess = {
  runId: string;
  child: ChildProcess;
  finished: boolean;
  jsonBuffer: JsonLineBuffer;
  messageCounter: number;
};

export class CliCodexSession implements CodexSession {
  readonly sessionId: string;
  private readonly listeners = new Set<Listener>();
  private active: ActiveProcess | null = null;
  private readonly cancelGraceMs: number;
  private codexThreadId?: string;

  constructor(private readonly options: CliCodexSessionOptions) {
    this.sessionId = options.sessionId ?? "default";
    this.cancelGraceMs = options.cancelGraceMs ?? 5_000;
    this.codexThreadId = options.codexThreadId;
  }

  async start(): Promise<void> {
    const resolvedWorkdir = path.resolve(this.options.workdir);
    this.emit({ type: "session.started", sessionId: this.sessionId });
    this.emit({ type: "status", status: "connected", sessionId: this.sessionId, detail: `workdir=${resolvedWorkdir}` });
  }

  async sendPrompt(prompt: string): Promise<SendPromptResult> {
    if (this.active) {
      throw new Error("A Codex CLI run is already active.");
    }

    const runId = randomUUID();
    const args = buildCodexArgs(prompt, {
      argsPrefix: this.options.argsPrefix,
      codexThreadId: this.codexThreadId,
      sandbox: this.options.sandbox ?? "workspace-write",
    });
    const stdinMode = process.stdin.isTTY ? "inherit" : "ignore";
    const child = spawn(this.options.command, args, {
      cwd: path.resolve(this.options.workdir),
      shell: false,
      env: process.env,
      stdio: [stdinMode, "pipe", "pipe"],
    });

    this.active = { runId, child, finished: false, jsonBuffer: new JsonLineBuffer(), messageCounter: 0 };
    this.emit({ type: "run.started", sessionId: this.sessionId, runId });
    this.emit({ type: "status", status: "running", sessionId: this.sessionId, runId });

    child.stdout.on("data", (chunk: Buffer) => {
      const text = removeCodexStdinNotice(chunk.toString("utf8"));
      if (text.length > 0) {
        this.handleStdout(runId, text);
      }
    });

    child.stderr.on("data", (chunk: Buffer) => {
      const text = removeCodexStdinNotice(chunk.toString("utf8"));
      if (text.length > 0) {
        this.emit({ type: "output.delta", sessionId: this.sessionId, runId, stream: "stderr", text });
      }
    });

    child.on("error", (error) => {
      this.emitSystemMessage(runId, `Failed to start Codex CLI: ${error.message}\n`, "Codex CLI error");
      this.emit({ type: "status", status: "failed", sessionId: this.sessionId, runId, detail: error.message });
      this.active = null;
    });

    child.on("close", (code) => {
      const active = this.active;
      if (!active || active.runId !== runId || active.finished) return;
      for (const line of active.jsonBuffer.flush()) {
        this.handleJsonLine(runId, line);
      }
      active.finished = true;
      this.emit({ type: "status", status: code === 0 ? "completed" : "failed", sessionId: this.sessionId, runId, detail: `exit=${code ?? "signal"}` });
      this.emit({ type: "run.completed", sessionId: this.sessionId, runId, exitCode: code ?? undefined });
      this.active = null;
    });

    return { runId };
  }

  async cancel(runId: string): Promise<void> {
    const active = this.active;
    if (!active || active.runId !== runId) {
      throw new Error(`No active Codex CLI run found for ${runId}`);
    }

    this.emit({ type: "status", status: "cancelling", sessionId: this.sessionId, runId });
    active.child.kill("SIGINT");

    setTimeout(() => {
      if (!active.finished && !active.child.killed) {
        active.child.kill("SIGTERM");
      }
    }, this.cancelGraceMs).unref();
  }

  onEvent(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async close(): Promise<void> {
    if (this.active && !this.active.finished) {
      this.active.child.kill("SIGTERM");
      this.active = null;
    }
    this.listeners.clear();
  }

  private handleStdout(runId: string, text: string): void {
    const active = this.active;
    if (!active || active.runId !== runId) return;

    for (const line of active.jsonBuffer.push(text)) {
      this.handleJsonLine(runId, line);
    }
  }

  private handleJsonLine(runId: string, line: string): void {
    try {
      const codexEvent = parseCodexJsonLine(line);
      const mapped = mapCodexJsonEvent(codexEvent);
      switch (mapped.kind) {
        case "thread":
          this.codexThreadId = mapped.threadId;
          void this.options.onThreadStarted?.(mapped.threadId);
          return;
        case "turn_started":
          this.emitCompleteMessage(runId, "thinking", "Thinking", "Thinking…\n");
          return;
        case "message":
          this.emitCompleteMessage(runId, mapped.messageKind, mapped.title, mapped.text.endsWith("\n") ? mapped.text : `${mapped.text}\n`);
          return;
        case "turn_completed":
        case "ignored":
          return;
      }
    } catch (error) {
      const text = line.endsWith("\n") ? line : `${line}\n`;
      this.emit({ type: "output.delta", sessionId: this.sessionId, runId, stream: "stdout", text });
      this.emitSystemMessage(runId, `Unparsed Codex output: ${error instanceof Error ? error.message : String(error)}\n`, "Raw Codex output");
    }
  }

  private emitCompleteMessage(runId: string, kind: "thinking" | "executing" | "response" | "system", title: string | undefined, text: string): void {
    const active = this.active;
    const messageNumber = active ? ++active.messageCounter : randomUUID();
    const messageId = `${runId}:${messageNumber}`;
    this.emit({ type: "message.started", sessionId: this.sessionId, runId, messageId, kind, role: kind === "response" ? "assistant" : "system", title });
    this.emit({ type: "message.delta", sessionId: this.sessionId, runId, messageId, text });
    this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId });

    const stream = kind === "response" ? "assistant" : "system";
    this.emit({ type: "output.delta", sessionId: this.sessionId, runId, stream, text });
  }

  private emitSystemMessage(runId: string, text: string, title?: string): void {
    this.emitCompleteMessage(runId, "system", title, text);
  }

  private emit(event: CodexEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }
}

export type BuildCodexArgsOptions = {
  argsPrefix?: string[];
  codexThreadId?: string;
  sandbox?: SandboxMode;
};

export function buildCodexArgs(prompt: string, options: BuildCodexArgsOptions = {}): string[] {
  if (options.argsPrefix) {
    return [...options.argsPrefix, "--", prompt];
  }

  const sandbox = options.sandbox ?? "workspace-write";
  const globalArgs = sandbox === "danger-full-access"
    ? ["--json", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox"]
    : ["--json", "--skip-git-repo-check", "--sandbox", sandbox];
  if (options.codexThreadId) {
    return ["exec", ...globalArgs, "resume", options.codexThreadId, "--", prompt];
  }
  return ["exec", ...globalArgs, "--", prompt];
}

function removeCodexStdinNotice(text: string): string {
  return text.replace(/(^|\r?\n)Reading additional input from stdin\.\.\.\r?\n?/g, "$1");
}
