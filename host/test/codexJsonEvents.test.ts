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

  it("maps raw Codex read-command completions with aggregated output", () => {
    expect(
      mapCodexJsonEvent(
        parseCodexJsonLine(
          '{"type":"item.completed","item":{"id":"cmd-1","type":"command_execution","command":"/usr/bin/zsh -lc \\"cat notes.txt\\"","aggregated_output":"Line 1\\nLine 2\\n","exit_code":0,"status":"completed"}}',
        ),
      ),
    ).toEqual({
      kind: "message",
      messageKind: "executing",
      title: "Reading file",
      text: "Line 1\nLine 2\n",
      itemId: "cmd-1",
    });
  });

  it("formats sed read commands with file and line range metadata", () => {
    expect(
      mapCodexJsonEvent(
        {
          type: "item.started",
          item: {
            id: "cmd-1",
            type: "command_execution",
            command: "/usr/bin/zsh -lc \"sed -n '1,20p' notes.txt\"",
          },
        },
      ),
    ).toEqual({
      kind: "message_started",
      messageKind: "executing",
      title: "Reading file",
      text: "Reading file: notes.txt\nLines: 1-20\nCommand: /usr/bin/zsh -lc \"sed -n '1,20p' notes.txt\"",
      itemId: "cmd-1",
    });
  });

  it("labels SKILL.md reads as skill usage instead of generic file reads", () => {
    expect(
      mapCodexJsonEvent({
        type: "item.started",
        item: {
          id: "skill-1",
          type: "command_execution",
          command: "/usr/bin/zsh -lc \"sed -n '1,120p' /home/kurisu/.codex/skills/flutter/SKILL.md\"",
        },
      }),
    ).toEqual({
      kind: "message_started",
      messageKind: "executing",
      title: "Using skill",
      text: 'Using skill: flutter\nPath: /home/kurisu/.codex/skills/flutter/SKILL.md\nCommand: /usr/bin/zsh -lc "sed -n \'1,120p\' /home/kurisu/.codex/skills/flutter/SKILL.md"',
      itemId: "skill-1",
    });
  });

  it("labels lowercase skills.md reads as skill usage", () => {
    expect(
      mapCodexJsonEvent({
        type: "item.started",
        item: {
          id: "skill-2",
          type: "command_execution",
          command: "/usr/bin/zsh -lc \"sed -n '1,120p' /home/kurisu/.codex/skills/flutter/skills.md\"",
        },
      }),
    ).toEqual({
      kind: "message_started",
      messageKind: "executing",
      title: "Using skill",
      text: 'Using skill: flutter\nPath: /home/kurisu/.codex/skills/flutter/skills.md\nCommand: /usr/bin/zsh -lc "sed -n \'1,120p\' /home/kurisu/.codex/skills/flutter/skills.md"',
      itemId: "skill-2",
    });
  });

  it("summarizes very long command output with first and last lines", () => {
    const output = Array.from({ length: 95 }, (_, index) => `line ${index + 1}`).join("\n");

    const mapped = mapCodexJsonEvent({
      type: "item.completed",
      item: {
        id: "cmd-1",
        type: "command_execution",
        command: "seq 1 95",
        aggregated_output: output,
      },
    });

    expect(mapped).toEqual(
      expect.objectContaining({
        kind: "message",
        messageKind: "executing",
        title: "Running command",
      }),
    );
    expect(mapped.kind === "message" ? mapped.text : "").toContain("line 1");
    expect(mapped.kind === "message" ? mapped.text : "").toContain("line 95");
    expect(mapped.kind === "message" ? mapped.text : "").toContain("... 35 lines omitted ...");
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
