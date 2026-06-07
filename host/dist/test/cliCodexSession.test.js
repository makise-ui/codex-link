import { describe, expect, it } from "vitest";
import { buildCodexArgs, CliCodexSession } from "../src/codex/cliCodexSession.js";
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
        const events = [];
        session.onEvent((event) => events.push(event));
        await session.sendPrompt("hello from phone");
        await waitForCompletion(events);
        const assistant = outputText(events, "assistant");
        const stderr = outputText(events, "stderr");
        const parsed = JSON.parse(assistant.trim());
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
        const events = [];
        session.onEvent((event) => events.push(event));
        await session.sendPrompt("--say exactly PHONE_PROMPT_OK");
        await waitForCompletion(events);
        const assistant = outputText(events, "assistant");
        const parsed = JSON.parse(assistant.trim());
        expect(parsed.argv).toEqual(["--", "--say exactly PHONE_PROMPT_OK"]);
        expect(parsed.stdin).toBe("");
    });
});
function outputText(events, stream) {
    return events
        .flatMap((event) => (event.type === "output.delta" && event.stream === stream ? [event.text] : []))
        .join("");
}
async function waitForCompletion(events) {
    const startedAt = Date.now();
    while (!events.some((event) => event.type === "run.completed")) {
        if (Date.now() - startedAt > 5_000) {
            throw new Error("Timed out waiting for CLI session completion");
        }
        await new Promise((resolve) => setTimeout(resolve, 25));
    }
}
