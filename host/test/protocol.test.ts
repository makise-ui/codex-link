import { describe, expect, it } from "vitest";
import { PROTOCOL_VERSION } from "../src/protocol/messages.js";
import { parseClientMessage } from "../src/protocol/schemas.js";

describe("protocol schemas", () => {
  it("uses protocol version 12", () => {
    expect(PROTOCOL_VERSION).toBe(12);
  });

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
    expect(parseClientMessage({ type: "workspace.add", sessionId: "s1", path: "/tmp/other-repo", create: true })).toEqual({
      type: "workspace.add",
      sessionId: "s1",
      path: "/tmp/other-repo",
      create: true,
    });
    expect(parseClientMessage({ type: "workspace.file.search", sessionId: "s1", query: "main", limit: 12 })).toEqual({
      type: "workspace.file.search",
      sessionId: "s1",
      query: "main",
      limit: 12,
    });
    expect(parseClientMessage({ type: "workspace.env.set", sessionId: "s1", content: "OPENAI_API_KEY=sk-unit\nLIST=value1,value2" })).toEqual({
      type: "workspace.env.set",
      sessionId: "s1",
      content: "OPENAI_API_KEY=sk-unit\nLIST=value1,value2",
    });
    expect(parseClientMessage({ type: "session.mode.set", sessionId: "s1", mode: "yolo" })).toEqual({
      type: "session.mode.set",
      sessionId: "s1",
      mode: "yolo",
    });
    expect(parseClientMessage({ type: "session.config.set", sessionId: "s1", model: "gpt-5-codex", reasoningEffort: "high", serviceTier: "priority" })).toEqual({
      type: "session.config.set",
      sessionId: "s1",
      model: "gpt-5-codex",
      reasoningEffort: "high",
      serviceTier: "priority",
    });
    expect(parseClientMessage({ type: "session.goal.set", sessionId: "s1", objective: "Ship app-server adapter", status: "active", tokenBudget: 20000 })).toEqual({
      type: "session.goal.set",
      sessionId: "s1",
      objective: "Ship app-server adapter",
      status: "active",
      tokenBudget: 20000,
    });
    expect(parseClientMessage({ type: "session.goal.get", sessionId: "s1" })).toEqual({
      type: "session.goal.get",
      sessionId: "s1",
    });
    expect(parseClientMessage({ type: "session.goal.clear", sessionId: "s1" })).toEqual({
      type: "session.goal.clear",
      sessionId: "s1",
    });
    expect(parseClientMessage({ type: "command.run", sessionId: "s1", commandId: "codex.test" })).toEqual({
      type: "command.run",
      sessionId: "s1",
      commandId: "codex.test",
    });
  });

  it("accepts password auth without exposing it through other auth messages", () => {
    expect(parseClientMessage({ type: "auth.password", password: "local-pass", deviceName: "Pixel" })).toEqual({
      type: "auth.password",
      password: "local-pass",
      deviceName: "Pixel",
    });
  });

  it("accepts prompt attachments and external session controls", () => {
    expect(
      parseClientMessage({
        type: "prompt.send",
        sessionId: "default",
        prompt: "use this screenshot",
        attachments: [
          {
            name: "screen.png",
            mimeType: "image/png",
            dataBase64: Buffer.from("fake-image").toString("base64"),
          },
        ],
      }),
    ).toEqual({
      type: "prompt.send",
      sessionId: "default",
      prompt: "use this screenshot",
      attachments: [
        {
          name: "screen.png",
          mimeType: "image/png",
          dataBase64: Buffer.from("fake-image").toString("base64"),
        },
      ],
    });
    expect(parseClientMessage({ type: "external.session.list" })).toEqual({ type: "external.session.list" });
    expect(parseClientMessage({ type: "external.session.import", externalSessionId: "019ea1ae-ac01-7123-8247-f3f94f79383d" })).toEqual({
      type: "external.session.import",
      externalSessionId: "019ea1ae-ac01-7123-8247-f3f94f79383d",
    });
  });

  it("accepts native app-server capability controls", () => {
    expect(parseClientMessage({ type: "app.model.list", sessionId: "s1", includeHidden: true })).toEqual({
      type: "app.model.list",
      sessionId: "s1",
      includeHidden: true,
    });
    expect(parseClientMessage({ type: "app.thread.list", sessionId: "s1", query: "flutter", cwd: "/repo", limit: 12 })).toEqual({
      type: "app.thread.list",
      sessionId: "s1",
      query: "flutter",
      cwd: "/repo",
      limit: 12,
    });
    expect(parseClientMessage({ type: "app.thread.import", threadId: "019ea136-cff9-7a00-bf21-62056dd9a1e7" })).toEqual({
      type: "app.thread.import",
      threadId: "019ea136-cff9-7a00-bf21-62056dd9a1e7",
    });
    expect(parseClientMessage({ type: "app.skill.list", sessionId: "s1", forceReload: true })).toEqual({
      type: "app.skill.list",
      sessionId: "s1",
      forceReload: true,
    });
    expect(parseClientMessage({ type: "app.fs.list", sessionId: "s1", path: "lib" })).toEqual({
      type: "app.fs.list",
      sessionId: "s1",
      path: "lib",
    });
    expect(parseClientMessage({ type: "app.fs.read", sessionId: "s1", path: "README.md" })).toEqual({
      type: "app.fs.read",
      sessionId: "s1",
      path: "README.md",
    });
    expect(parseClientMessage({ type: "app.fs.write", sessionId: "s1", path: "notes.txt", dataBase64: "aGVsbG8=" })).toEqual({
      type: "app.fs.write",
      sessionId: "s1",
      path: "notes.txt",
      dataBase64: "aGVsbG8=",
    });
    expect(parseClientMessage({ type: "app.fs.createDirectory", sessionId: "s1", path: "notes" })).toEqual({
      type: "app.fs.createDirectory",
      sessionId: "s1",
      path: "notes",
    });
    expect(parseClientMessage({ type: "app.file.search", sessionId: "s1", query: "@main", limit: 20 })).toEqual({
      type: "app.file.search",
      sessionId: "s1",
      query: "@main",
      limit: 20,
    });
    expect(parseClientMessage({ type: "app.review.start", sessionId: "s1", target: "uncommittedChanges", delivery: "inline" })).toEqual({
      type: "app.review.start",
      sessionId: "s1",
      target: "uncommittedChanges",
      delivery: "inline",
    });
    expect(parseClientMessage({ type: "app.account.read", refreshToken: true })).toEqual({
      type: "app.account.read",
      refreshToken: true,
    });
    expect(parseClientMessage({ type: "app.account.login.start", loginType: "chatgptDeviceCode" })).toEqual({
      type: "app.account.login.start",
      loginType: "chatgptDeviceCode",
    });
    expect(parseClientMessage({ type: "app.account.login.start", loginType: "apiKey", apiKey: "sk-unit" })).toEqual({
      type: "app.account.login.start",
      loginType: "apiKey",
      apiKey: "sk-unit",
    });
    expect(parseClientMessage({ type: "app.account.login.cancel", loginId: "login-1" })).toEqual({
      type: "app.account.login.cancel",
      loginId: "login-1",
    });
    expect(parseClientMessage({ type: "app.account.logout" })).toEqual({
      type: "app.account.logout",
    });
  });

  it("accepts interactive app-server action controls", () => {
    expect(parseClientMessage({ type: "app.plugin.list", sessionId: "s1" })).toEqual({
      type: "app.plugin.list",
      sessionId: "s1",
    });
    expect(parseClientMessage({ type: "app.plugin.read", pluginName: "github", marketplacePath: "/tmp/marketplace" })).toEqual({
      type: "app.plugin.read",
      pluginName: "github",
      marketplacePath: "/tmp/marketplace",
    });
    expect(parseClientMessage({ type: "app.plugin.install", pluginName: "github", marketplacePath: "/tmp/marketplace" })).toEqual({
      type: "app.plugin.install",
      pluginName: "github",
      marketplacePath: "/tmp/marketplace",
    });
    expect(parseClientMessage({ type: "app.plugin.uninstall", pluginName: "github" })).toEqual({
      type: "app.plugin.uninstall",
      pluginName: "github",
    });
    expect(parseClientMessage({ type: "app.mcp.status.list", sessionId: "s1", detail: "toolsAndAuthOnly" })).toEqual({
      type: "app.mcp.status.list",
      sessionId: "s1",
      detail: "toolsAndAuthOnly",
    });
    expect(parseClientMessage({ type: "app.mcp.oauth.login", serverName: "github" })).toEqual({
      type: "app.mcp.oauth.login",
      serverName: "github",
    });
    expect(parseClientMessage({ type: "app.remote.status.read" })).toEqual({
      type: "app.remote.status.read",
    });
    expect(parseClientMessage({ type: "app.remote.pairing.start", manualPairingCode: "123456" })).toEqual({
      type: "app.remote.pairing.start",
      manualPairingCode: "123456",
    });
    expect(parseClientMessage({ type: "app.account.rateLimits.read" })).toEqual({
      type: "app.account.rateLimits.read",
    });
  });

  it("accepts file request client messages", () => {
    expect(parseClientMessage({ type: "file.request", fileId: "file-1" })).toEqual({
      type: "file.request",
      fileId: "file-1",
    });
    expect(parseClientMessage({ type: "file.offer.request", sessionId: "default", path: "notes.txt" })).toEqual({
      type: "file.offer.request",
      sessionId: "default",
      path: "notes.txt",
    });
  });

  it("rejects empty prompts", () => {
    expect(() => parseClientMessage({ type: "prompt.send", sessionId: "default", prompt: "" })).toThrow();
  });

  it("rejects unknown message types", () => {
    expect(() => parseClientMessage({ type: "shell.exec", command: "rm -rf /" })).toThrow();
  });
});
