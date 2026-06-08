import { describe, expect, it } from "vitest";
import { buildCodexArgs, CliCodexSession } from "../src/codex/cliCodexSession.js";
import type { CodexEvent } from "../src/codex/codexSession.js";

const fakeChildScript = `
const chunks = [];
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => chunks.push(chunk));
process.stdin.on('end', () => {
  process.stderr.write('stderr-ok\\n');
  process.stdout.write(JSON.stringify({ type: 'thread.started', thread_id: 'thread-test' }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'turn.started' }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'item.completed', item: { type: 'agent_message', text: JSON.stringify({ argv: process.argv.slice(2), stdin: chunks.join('') }) } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');
});
process.stdin.resume();
`;

const fakeToolLifecycleScript = `
process.stdout.write(JSON.stringify({ type: 'turn.started' }) + '\\n');
process.stdout.write(JSON.stringify({ type: 'item.started', item: { id: 'read-1', type: 'read_file', path: 'notes.txt' } }) + '\\n');
setTimeout(() => {
  process.stdout.write(JSON.stringify({ type: 'item.completed', item: { id: 'read-1', type: 'read_file', output: 'notes content' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'item.started', item: { id: 'edit-1', type: 'file_change', changes: [{ path: process.cwd() + '/notes.txt', kind: 'add' }], status: 'in_progress' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'item.completed', item: { id: 'edit-1', type: 'file_change', changes: [{ path: process.cwd() + '/notes.txt', kind: 'add' }], status: 'completed' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'item.started', item: { id: 'cmd-1', type: 'exec_command', command: 'pnpm test' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'item.completed', item: { id: 'cmd-1', type: 'command_execution', aggregated_output: '2 tests passed' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'item.completed', item: { type: 'agent_message', text: 'Done.' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');
}, 20);
`;

const fakeSignalIgnoringScript = `
process.stderr.write('ready\\n');
process.on('SIGINT', () => {
  process.stdout.write(JSON.stringify({ type: 'turn.started' }) + '\\n');
});
process.on('SIGTERM', () => {
  process.stdout.write(JSON.stringify({ type: 'item.completed', item: { type: 'agent_message', text: 'terminated by fallback' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');
  process.exit(143);
});
setInterval(() => {}, 1_000);
`;

describe("buildCodexArgs", () => {
  it("adds json, skip-git-repo-check, and workspace-write by default", () => {
    expect(buildCodexArgs("hello")).toEqual(["exec", "--json", "--skip-git-repo-check", "--sandbox", "workspace-write", "--", "hello"]);
  });

  it("uses Codex resume when a thread id exists", () => {
    expect(buildCodexArgs("again", { codexThreadId: "thread-1", sandbox: "read-only" })).toEqual([
      "exec",
      "--json",
      "--skip-git-repo-check",
      "--sandbox",
      "read-only",
      "resume",
      "thread-1",
      "--",
      "again",
    ]);
  });

  it("maps yolo sandbox to the Codex bypass flag", () => {
    expect(buildCodexArgs("go", { sandbox: "danger-full-access" })).toEqual([
      "exec",
      "--json",
      "--skip-git-repo-check",
      "--dangerously-bypass-approvals-and-sandbox",
      "--",
      "go",
    ]);
  });

  it("passes images to codex exec before the prompt separator", () => {
    expect(buildCodexArgs("see image", { imagePaths: ["/tmp/screen.png"] })).toEqual([
      "exec",
      "--json",
      "--skip-git-repo-check",
      "--sandbox",
      "workspace-write",
      "--image",
      "/tmp/screen.png",
      "--",
      "see image",
    ]);
  });

  it("passes model and reasoning effort to codex exec", () => {
    expect(buildCodexArgs("think hard", { model: "gpt-5-codex", reasoningEffort: "high" })).toEqual([
      "exec",
      "--json",
      "--skip-git-repo-check",
      "--model",
      "gpt-5-codex",
      "-c",
      'model_reasoning_effort="high"',
      "--sandbox",
      "workspace-write",
      "--",
      "think hard",
    ]);
  });
});

describe("CliCodexSession", () => {
  it("passes the prompt as argv after -- and does not pipe stdin", async () => {
    let savedThreadId = "";
    const session = new CliCodexSession({
      command: process.execPath,
      argsPrefix: ["-e", fakeChildScript, "exec"],
      workdir: process.cwd(),
      onThreadStarted: (threadId) => {
        savedThreadId = threadId;
      },
    });
    const events: CodexEvent[] = [];
    session.onEvent((event) => events.push(event));

    await session.sendPrompt("hello from phone");
    await waitForCompletion(events);

    const assistant = outputText(events, "assistant");
    const stderr = outputText(events, "stderr");
    const parsed = JSON.parse(assistant.trim()) as { argv: string[]; stdin: string };

    expect(parsed.argv).toEqual(["--", "hello from phone"]);
    expect(parsed.stdin).toBe("");
    expect(savedThreadId).toBe("thread-test");
    expect(stderr).toContain("stderr-ok");
    expect(events.some((event) => event.type === "message.started" && event.kind === "thinking")).toBe(true);
    expect(events.some((event) => event.type === "message.started" && event.kind === "response")).toBe(true);
    expect(events.some((event) => event.type === "run.completed" && event.exitCode === 0)).toBe(true);
  });

  it("protects prompts that look like CLI flags", async () => {
    const session = new CliCodexSession({
      command: process.execPath,
      argsPrefix: ["-e", fakeChildScript, "exec"],
      workdir: process.cwd(),
    });
    const events: CodexEvent[] = [];
    session.onEvent((event) => events.push(event));

    await session.sendPrompt("--say exactly PHONE_PROMPT_OK");
    await waitForCompletion(events);

    const assistant = outputText(events, "assistant");
    const parsed = JSON.parse(assistant.trim()) as { argv: string[]; stdin: string };

    expect(parsed.argv).toEqual(["--", "--say exactly PHONE_PROMPT_OK"]);
    expect(parsed.stdin).toBe("");
  });

  it("streams tool lifecycle events as visible started, delta, and completed messages", async () => {
    const session = new CliCodexSession({
      command: process.execPath,
      argsPrefix: ["-e", fakeToolLifecycleScript, "exec"],
      workdir: process.cwd(),
    });
    const events: CodexEvent[] = [];
    session.onEvent((event) => events.push(event));

    await session.sendPrompt("read notes and test");
    await waitForCompletion(events);

    const readStarted = events.find((event): event is Extract<CodexEvent, { type: "message.started" }> => event.type === "message.started" && event.title === "Reading file");
    const readCompleted = readStarted
      ? events.find((event) => event.type === "message.completed" && event.messageId === readStarted.messageId)
      : undefined;
    const commandStarted = events.find((event) => event.type === "message.started" && event.title === "Running command");
    const editStarted = events.find((event) => event.type === "message.started" && event.title === "Editing files");
    const thinkingStarted = events.filter((event): event is Extract<CodexEvent, { type: "message.started" }> => event.type === "message.started" && event.kind === "thinking");
    const duplicatedSystemThinking = events.some((event) => event.type === "output.delta" && event.stream === "system" && event.text.includes("Thinking"));

    expect(readStarted).toBeDefined();
    expect(readCompleted).toBeDefined();
    expect(commandStarted).toBeDefined();
    expect(editStarted).toBeDefined();
    expect(thinkingStarted.length).toBeGreaterThan(1);
    expect(thinkingStarted.every((message) => events.some((event) => event.type === "message.completed" && event.messageId === message.messageId))).toBe(true);
    expect(events.some((event) => event.type === "message.delta" && event.text.includes("notes.txt"))).toBe(true);
    expect(events.some((event) => event.type === "message.delta" && event.text.includes("added") && event.text.includes("notes.txt"))).toBe(true);
    expect(events.some((event) => event.type === "diff.available" && event.files.some((file) => file.path.endsWith("notes.txt") && file.status === "added"))).toBe(true);
    expect(events.some((event) => event.type === "message.delta" && event.text.includes("2 tests passed"))).toBe(true);
    expect(duplicatedSystemThinking).toBe(false);
  });

  it("escalates cancel to SIGTERM when Codex ignores SIGINT", async () => {
    const session = new CliCodexSession({
      command: process.execPath,
      argsPrefix: ["-e", fakeSignalIgnoringScript, "exec"],
      workdir: process.cwd(),
      cancelGraceMs: 20,
    });
    const events: CodexEvent[] = [];
    session.onEvent((event) => events.push(event));

    const { runId } = await session.sendPrompt("cancel stubborn run");
    try {
      await waitForOutput(events, "ready");
      await session.cancel(runId);
      await waitForCompletion(events, 1_000);
    } finally {
      await session.close();
    }

    expect(events.some((event) => event.type === "status" && event.status === "cancelling")).toBe(true);
    expect(events.some((event) => event.type === "message.delta" && event.text.includes("terminated by fallback"))).toBe(true);
    expect(events.some((event) => event.type === "run.completed" && event.runId === runId)).toBe(true);
  });
});

function outputText(events: CodexEvent[], stream: "assistant" | "stderr"): string {
  return events
    .flatMap((event) => (event.type === "output.delta" && event.stream === stream ? [event.text] : []))
    .join("");
}

async function waitForCompletion(events: CodexEvent[], timeoutMs = 5_000): Promise<void> {
  const startedAt = Date.now();
  while (!events.some((event) => event.type === "run.completed")) {
    if (Date.now() - startedAt > timeoutMs) {
      throw new Error("Timed out waiting for CLI session completion");
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

async function waitForOutput(events: CodexEvent[], text: string, timeoutMs = 1_000): Promise<void> {
  const startedAt = Date.now();
  while (!events.some((event) => event.type === "output.delta" && event.text.includes(text))) {
    if (Date.now() - startedAt > timeoutMs) {
      throw new Error(`Timed out waiting for output: ${text}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}
