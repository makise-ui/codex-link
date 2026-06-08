import { randomUUID } from "node:crypto";
import { execFile, spawn, type ChildProcess } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import type { ReasoningEffort, SandboxMode } from "../protocol/messages.js";
import type { CodexEvent, CodexSession, SendPromptOptions, SendPromptResult } from "./codexSession.js";
import { JsonLineBuffer, mapCodexJsonEvent, parseCodexJsonLine } from "./codexJsonEvents.js";

type Listener = (event: CodexEvent) => void;

const execFileAsync = promisify(execFile);

export type CliCodexSessionOptions = {
  sessionId?: string;
  command: string;
  workdir: string;
  sandbox?: SandboxMode;
  model?: string;
  reasoningEffort?: ReasoningEffort;
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
  itemMessageIds: Map<string, string>;
  messageKinds: Map<string, "thinking" | "executing" | "response" | "system">;
  pendingFileChanges: Promise<void>[];
  thinkingMessageId?: string;
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

  async sendPrompt(prompt: string, options: SendPromptOptions = {}): Promise<SendPromptResult> {
    if (this.active) {
      throw new Error("A Codex CLI run is already active.");
    }

    const runId = randomUUID();
    const args = buildCodexArgs(prompt, {
      argsPrefix: this.options.argsPrefix,
      codexThreadId: this.codexThreadId,
      sandbox: this.options.sandbox ?? "workspace-write",
      model: this.options.model,
      reasoningEffort: this.options.reasoningEffort,
      imagePaths: options.attachments?.filter((attachment) => attachment.kind === "image").map((attachment) => attachment.path),
    });
    const stdinMode = process.stdin.isTTY ? "inherit" : "ignore";
    const child = spawn(this.options.command, args, {
      cwd: path.resolve(this.options.workdir),
      shell: false,
      env: process.env,
      stdio: [stdinMode, "pipe", "pipe"],
    });

    this.active = { runId, child, finished: false, jsonBuffer: new JsonLineBuffer(), messageCounter: 0, itemMessageIds: new Map(), messageKinds: new Map(), pendingFileChanges: [] };
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
      void this.finishRun(runId, code);
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
      if (!active.finished) {
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
      const active = this.active;
      switch (mapped.kind) {
        case "thread":
          this.codexThreadId = mapped.threadId;
          void this.options.onThreadStarted?.(mapped.threadId);
          return;
        case "turn_started":
          this.ensureThinking(runId);
          return;
        case "message_started":
          this.completeThinking(runId);
          this.emitStartedMessage(runId, mapped.messageKind, mapped.title, mapped.text?.endsWith("\n") ? mapped.text : mapped.text ? `${mapped.text}\n` : undefined, mapped.itemId);
          if (mapped.title === "Editing files" && mapped.text) {
            active?.pendingFileChanges.push(this.emitFileChanges(mapped.text));
          }
          return;
        case "message":
          this.emitCompleteMessage(runId, mapped.messageKind, mapped.title, mapped.text.endsWith("\n") ? mapped.text : `${mapped.text}\n`, mapped.itemId);
          return;
        case "message_completed":
          this.emitCompletedItem(runId, mapped.itemId);
          return;
        case "turn_completed":
          this.completeOpenMessages(runId);
          return;
        case "ignored":
          return;
      }
    } catch (error) {
      const text = line.endsWith("\n") ? line : `${line}\n`;
      this.emit({ type: "output.delta", sessionId: this.sessionId, runId, stream: "stdout", text });
      this.emitSystemMessage(runId, `Unparsed Codex output: ${error instanceof Error ? error.message : String(error)}\n`, "Raw Codex output");
    }
  }

  private emitStartedMessage(runId: string, kind: "thinking" | "executing" | "response" | "system", title: string | undefined, text?: string, itemId?: string): string {
    const active = this.active;
    const messageNumber = active ? ++active.messageCounter : randomUUID();
    const messageId = `${runId}:${messageNumber}`;
    if (active && itemId) {
      active.itemMessageIds.set(itemId, messageId);
    }
    active?.messageKinds.set(messageId, kind);
    if (active && kind === "thinking") {
      active.thinkingMessageId = messageId;
    }
    this.emit({ type: "message.started", sessionId: this.sessionId, runId, messageId, kind, role: kind === "response" ? "assistant" : "system", title });
    if (text) {
      this.emit({ type: "message.delta", sessionId: this.sessionId, runId, messageId, text });
    }
    return messageId;
  }

  private emitCompleteMessage(runId: string, kind: "thinking" | "executing" | "response" | "system", title: string | undefined, text: string, itemId?: string): void {
    const active = this.active;
    if (kind !== "thinking") {
      this.completeThinking(runId);
    }
    const existingMessageId = itemId ? active?.itemMessageIds.get(itemId) : undefined;
    const messageId = existingMessageId ?? this.emitStartedMessage(runId, kind, title, undefined, itemId);
    this.emit({ type: "message.delta", sessionId: this.sessionId, runId, messageId, text });
    this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId });
    active?.messageKinds.set(messageId, kind);

    if (kind === "response") {
      this.emit({ type: "output.delta", sessionId: this.sessionId, runId, stream: "assistant", text });
    }
    if (active && itemId) {
      active.itemMessageIds.delete(itemId);
    }
    if (kind !== "thinking") {
      this.ensureThinking(runId);
    }
  }

  private emitCompletedItem(runId: string, itemId?: string): void {
    const active = this.active;
    if (!active || !itemId) return;
    const messageId = active.itemMessageIds.get(itemId);
    if (!messageId) return;
    this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId });
    const kind = active.messageKinds.get(messageId);
    active.messageKinds.delete(messageId);
    active.itemMessageIds.delete(itemId);
    if (kind && kind !== "thinking") {
      this.ensureThinking(runId);
    }
  }

  private completeOpenMessages(runId: string): void {
    const active = this.active;
    if (!active) return;
    this.completeThinking(runId);
    for (const messageId of active.itemMessageIds.values()) {
      this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId });
      active.messageKinds.delete(messageId);
    }
    active.itemMessageIds.clear();
  }

  private completeThinking(runId: string): void {
    const active = this.active;
    if (!active?.thinkingMessageId) return;
    this.emit({ type: "message.completed", sessionId: this.sessionId, runId, messageId: active.thinkingMessageId });
    active.messageKinds.delete(active.thinkingMessageId);
    active.thinkingMessageId = undefined;
  }

  private ensureThinking(runId: string): void {
    const active = this.active;
    if (!active || active.finished || active.thinkingMessageId) return;
    this.emitStartedMessage(runId, "thinking", "Thinking", "Thinking…\n");
  }

  private emitSystemMessage(runId: string, text: string, title?: string): void {
    this.emitCompleteMessage(runId, "system", title, text);
  }

  private async emitFileChanges(text: string): Promise<void> {
    const parsedFiles = text
      .split(/\r?\n/)
      .flatMap((line) => {
        const match = line.trim().match(/^(added|modified|deleted|renamed)\s+(.+)$/);
        if (!match) return [];
        return [{ status: match[1] as "added" | "modified" | "deleted" | "renamed", path: match[2] ?? "" }];
      })
      .filter((file) => file.path.trim().length > 0);
    const files = await Promise.all(
      parsedFiles.map(async (file) => ({
        ...file,
        patch: await this.filePatchPreview(file.path, file.status),
      })),
    );
    if (files.length > 0) {
      this.emit({ type: "diff.available", sessionId: this.sessionId, files });
    }
  }

  private async filePatchPreview(filePath: string, status: "added" | "modified" | "deleted" | "renamed"): Promise<string | undefined> {
    const workdir = path.resolve(this.options.workdir);
    const normalizedPath = filePath.replace(/\\/g, "/");
    const gitPatch = await gitDiffPreview(workdir, normalizedPath);
    if (gitPatch) return gitPatch;
    if (status !== "added") return undefined;

    const absolutePath = path.resolve(workdir, normalizedPath);
    if (!isInsideDirectory(absolutePath, workdir)) return undefined;
    try {
      const raw = await readFile(absolutePath, "utf8");
      const lines = raw.split(/\r?\n/).slice(0, 80).map((line) => `+${line}`);
      return summarizePatchLines(lines);
    } catch {
      return undefined;
    }
  }

  private emit(event: CodexEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  private async finishRun(runId: string, code: number | null): Promise<void> {
    const active = this.active;
    if (!active || active.runId !== runId || active.finished) return;
    for (const line of active.jsonBuffer.flush()) {
      this.handleJsonLine(runId, line);
    }
    this.completeOpenMessages(runId);
    if (active.pendingFileChanges.length > 0) {
      await Promise.allSettled(active.pendingFileChanges);
    }
    active.finished = true;
    this.emit({ type: "status", status: code === 0 ? "completed" : "failed", sessionId: this.sessionId, runId, detail: `exit=${code ?? "signal"}` });
    this.emit({ type: "run.completed", sessionId: this.sessionId, runId, exitCode: code ?? undefined });
    this.active = null;
  }
}

export type BuildCodexArgsOptions = {
  argsPrefix?: string[];
  codexThreadId?: string;
  sandbox?: SandboxMode;
  model?: string;
  reasoningEffort?: ReasoningEffort;
  imagePaths?: string[];
};

export function buildCodexArgs(prompt: string, options: BuildCodexArgsOptions = {}): string[] {
  if (options.argsPrefix) {
    return [...options.argsPrefix, ...imageArgs(options.imagePaths), "--", prompt];
  }

  const sandbox = options.sandbox ?? "workspace-write";
  const configArgs = [
    ...(options.model?.trim() ? ["--model", options.model.trim()] : []),
    ...(options.reasoningEffort ? ["-c", `model_reasoning_effort="${options.reasoningEffort}"`] : []),
  ];
  const globalArgs = sandbox === "danger-full-access"
    ? ["--json", "--skip-git-repo-check", ...configArgs, "--dangerously-bypass-approvals-and-sandbox"]
    : ["--json", "--skip-git-repo-check", ...configArgs, "--sandbox", sandbox];
  const images = imageArgs(options.imagePaths);
  if (options.codexThreadId) {
    return ["exec", ...globalArgs, ...images, "resume", options.codexThreadId, "--", prompt];
  }
  return ["exec", ...globalArgs, ...images, "--", prompt];
}

function imageArgs(imagePaths: string[] | undefined): string[] {
  return imagePaths?.flatMap((imagePath) => ["--image", imagePath]) ?? [];
}

function removeCodexStdinNotice(text: string): string {
  return text.replace(/(^|\r?\n)Reading additional input from stdin\.\.\.\r?\n?/g, "$1");
}

async function gitDiffPreview(workdir: string, filePath: string): Promise<string | undefined> {
  try {
    const { stdout } = await execFileAsync("git", ["diff", "--", filePath], {
      cwd: workdir,
      timeout: 1_500,
      maxBuffer: 256 * 1024,
    });
    const lines = stdout
      .split(/\r?\n/)
      .filter((line) => line.startsWith("@@") || line.startsWith("+") || line.startsWith("-"))
      .filter((line) => !line.startsWith("+++") && !line.startsWith("---"));
    return summarizePatchLines(lines);
  } catch {
    return undefined;
  }
}

function summarizePatchLines(lines: string[]): string | undefined {
  const meaningful = lines.filter((line) => line.trim().length > 0);
  if (meaningful.length === 0) return undefined;
  if (meaningful.length <= 80) return meaningful.join("\n");
  return [...meaningful.slice(0, 40), `... ${meaningful.length - 80} diff lines omitted ...`, ...meaningful.slice(-40)].join("\n");
}

function isInsideDirectory(targetPath: string, parentPath: string): boolean {
  const relative = path.relative(parentPath, targetPath);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}
