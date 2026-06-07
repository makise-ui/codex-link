import { describe, expect, it } from "vitest";
import { parseClientMessage } from "../src/protocol/schemas.js";

describe("protocol schemas", () => {
  it("accepts a valid prompt", () => {
    expect(
      parseClientMessage({
        type: "prompt.send",
        sessionId: "default",
        prompt: "hello",
      }),
    ).toEqual({ type: "prompt.send", sessionId: "default", prompt: "hello" });
  });

  it("accepts session, workspace, mode, and command controls", () => {
    expect(parseClientMessage({ type: "session.create", title: "Phone session", workspaceId: "default", mode: "safe" })).toEqual({
      type: "session.create",
      title: "Phone session",
      workspaceId: "default",
      mode: "safe",
    });
    expect(parseClientMessage({ type: "workspace.switch", sessionId: "s1", workspaceId: "workspace-2" })).toEqual({
      type: "workspace.switch",
      sessionId: "s1",
      workspaceId: "workspace-2",
    });
    expect(parseClientMessage({ type: "session.mode.set", sessionId: "s1", mode: "yolo" })).toEqual({
      type: "session.mode.set",
      sessionId: "s1",
      mode: "yolo",
    });
    expect(parseClientMessage({ type: "command.run", sessionId: "s1", commandId: "codex.test" })).toEqual({
      type: "command.run",
      sessionId: "s1",
      commandId: "codex.test",
    });
  });

  it("rejects empty prompts", () => {
    expect(() => parseClientMessage({ type: "prompt.send", sessionId: "default", prompt: "" })).toThrow();
  });

  it("rejects unknown message types", () => {
    expect(() => parseClientMessage({ type: "shell.exec", command: "rm -rf /" })).toThrow();
  });
});
