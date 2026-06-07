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
        expect(mapCodexJsonEvent(parseCodexJsonLine('{"type":"item.completed","item":{"type":"agent_message","text":"hello"}}'))).toEqual({ kind: "message", messageKind: "response", title: "Response", text: "hello" });
    });
    it("maps command-like items to executing", () => {
        expect(mapCodexJsonEvent(parseCodexJsonLine('{"type":"item.completed","item":{"type":"exec_command","output":"pnpm test"}}'))).toEqual({ kind: "message", messageKind: "executing", title: "Running command", text: "pnpm test", itemId: undefined });
    });
    it("maps started file and command actions to live executing events", () => {
        expect(mapCodexJsonEvent(parseCodexJsonLine('{"type":"item.started","item":{"id":"read-1","type":"read_file","path":"notes.txt"}}'))).toEqual({ kind: "message_started", messageKind: "executing", title: "Reading file", text: "notes.txt", itemId: "read-1" });
        expect(mapCodexJsonEvent(parseCodexJsonLine('{"type":"item.started","item":{"id":"cmd-1","type":"exec_command","command":"pnpm test"}}'))).toEqual({ kind: "message_started", messageKind: "executing", title: "Running command", text: "pnpm test", itemId: "cmd-1" });
    });
});
