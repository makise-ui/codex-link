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
  process.stdout.write(JSON.stringify({ type: 'item.started', item: { id: 'cmd-1', type: 'exec_command', command: 'pnpm test' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'item.completed', item: { id: 'cmd-1', type: 'exec_command', output: '2 tests passed' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'item.completed', item: { type: 'agent_message', text: 'Done.' } }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');
}, 20);
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
    const thinkingStarted = events.find((event): event is Extract<CodexEvent, { type: "message.started" }> => event.type === "message.started" && event.kind === "thinking");
    const duplicatedSystemThinking = events.some((event) => event.type === "output.delta" && event.stream === "system" && event.text.includes("Thinking"));

    expect(readStarted).toBeDefined();
    expect(readCompleted).toBeDefined();
    expect(commandStarted).toBeDefined();
    expect(thinkingStarted).toBeDefined();
    expect(thinkingStarted && events.some((event) => event.type === "message.completed" && event.messageId === thinkingStarted.messageId)).toBe(true);
    expect(events.some((event) => event.type === "message.delta" && event.text.includes("notes.txt"))).toBe(true);
    expect(events.some((event) => event.type === "message.delta" && event.text.includes("2 tests passed"))).toBe(true);
    expect(duplicatedSystemThinking).toBe(false);
  });
});

function outputText(events: CodexEvent[], stream: "assistant" | "stderr"): string {
  return events
    .flatMap((event) => (event.type === "output.delta" && event.stream === stream ? [event.text] : []))
    .join("");
}

async function waitForCompletion(events: CodexEvent[]): Promise<void> {
  const startedAt = Date.now();
  while (!events.some((event) => event.type === "run.completed")) {
    if (Date.now() - startedAt > 5_000) {
      throw new Error("Timed out waiting for CLI session completion");
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}
