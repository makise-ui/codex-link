import { describe, expect, it } from "vitest";
import { JsonLineBuffer, mapCodexJsonEvent, parseCodexJsonLine } from "../src/codex/codexJsonEvents.js";

describe("Codex JSONL mapping", () => {
  it("buffers partial JSONL chunks", () => {
    const buffer = new JsonLineBuffer();

    expect(buffer.push('{"type":"turn.started"')).toEqual([]);
    expect(buffer.push('}\n{"type":"turn.completed"}\n')).toEqual(['{"type":"turn.started"}', '{"type":"turn.completed"}']);
  });

  it("maps thread and agent messages", () => {
    expect(mapCodexJsonEvent(parseCodexJsonLine('{"type":"thread.started","thread_id":"abc"}'))).toEqual({ kind: "thread", threadId: "abc" });
    expect(
      mapCodexJsonEvent(
        parseCodexJsonLine('{"type":"item.completed","item":{"type":"agent_message","text":"hello"}}'),
      ),
    ).toEqual({ kind: "message", messageKind: "response", title: "Response", text: "hello" });
  });

  it("maps command-like items to executing", () => {
    expect(
      mapCodexJsonEvent(
        parseCodexJsonLine('{"type":"item.completed","item":{"type":"exec_command","output":"pnpm test"}}'),
      ),
    ).toEqual({ kind: "message", messageKind: "executing", title: "Running command", text: "pnpm test", itemId: undefined });
  });

  it("maps raw Codex command completions with aggregated output", () => {
    expect(
      mapCodexJsonEvent(
        parseCodexJsonLine(
          '{"type":"item.completed","item":{"id":"cmd-1","type":"command_execution","command":"/usr/bin/zsh -lc \\"cat notes.txt\\"","aggregated_output":"Line 1\\nLine 2\\n","exit_code":0,"status":"completed"}}',
        ),
      ),
    ).toEqual({
      kind: "message",
      messageKind: "executing",
      title: "Running command",
      text: "Line 1\nLine 2\n",
      itemId: "cmd-1",
    });
  });

  it("maps raw Codex file changes to visible editing activity", () => {
    expect(
      mapCodexJsonEvent(
        parseCodexJsonLine(
          '{"type":"item.started","item":{"id":"edit-1","type":"file_change","changes":[{"path":"/repo/notes.txt","kind":"add"},{"path":"/repo/lib/app.dart","kind":"update"}],"status":"in_progress"}}',
        ),
      ),
    ).toEqual({
      kind: "message_started",
      messageKind: "executing",
      title: "Editing files",
      text: "added notes.txt\nmodified lib/app.dart",
      itemId: "edit-1",
    });
  });

  it("maps started file and command actions to live executing events", () => {
    expect(
      mapCodexJsonEvent(
        parseCodexJsonLine('{"type":"item.started","item":{"id":"read-1","type":"read_file","path":"notes.txt"}}'),
      ),
    ).toEqual({ kind: "message_started", messageKind: "executing", title: "Reading file", text: "notes.txt", itemId: "read-1" });

    expect(
      mapCodexJsonEvent(
        parseCodexJsonLine('{"type":"item.started","item":{"id":"cmd-1","type":"exec_command","command":"pnpm test"}}'),
      ),
    ).toEqual({ kind: "message_started", messageKind: "executing", title: "Running command", text: "pnpm test", itemId: "cmd-1" });
  });
});
