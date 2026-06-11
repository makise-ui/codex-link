import net from "node:net";
import type pino from "pino";
import { WebSocket } from "ws";
import { afterEach, describe, expect, it } from "vitest";
import { PairingStore } from "../src/auth/pairingStore.js";
import type { CodexSessionManager } from "../src/codex/sessionManager.js";
import type { AuditLog } from "../src/safety/auditLog.js";
import { startBridgeServer, type BridgeServer } from "../src/server/websocketServer.js";

describe("startBridgeServer", () => {
  let server: BridgeServer | undefined;

  afterEach(async () => {
    await server?.close();
    server = undefined;
  });

  it("sends host info during password-auth bootstrap", async () => {
    const port = await freePort();
    server = await startBridgeServer({
      host: "127.0.0.1",
      port,
      url: `ws://127.0.0.1:${port}`,
      pairingStore: new PairingStore({ password: "secret" }),
      sessionManager: fakeSessionManager(),
      auditLog: { record() {} } as unknown as AuditLog,
      logger: { info() {} } as unknown as pino.Logger,
      hostInfo: {
        connectionMode: "tunnel",
        tunnelProvider: "cloudflared",
        publicUrl: "wss://unit.trycloudflare.com",
        localUrl: `ws://127.0.0.1:${port}`,
        hostLabel: "Codex Link",
        yoloAllowed: false,
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const messages: Array<Record<string, unknown>> = [];
    ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

    await opened(ws);
    ws.send(
      JSON.stringify({
        type: "auth.password",
        password: "secret",
        deviceName: "Pixel",
      }),
    );

    await eventually(() => {
      expect(messages.some((message) => message.type === "host.info")).toBe(true);
    });
    const hostInfo = messages.find((message) => message.type === "host.info");
    expect(hostInfo).toMatchObject({
      version: 14,
      connectionMode: "tunnel",
      tunnelProvider: "cloudflared",
      publicUrl: "wss://unit.trycloudflare.com",
      hostLabel: "Codex Link",
      yoloAllowed: false,
    });

    ws.close();
  });

  it("forwards file offer requests to the session manager", async () => {
    const port = await freePort();
    const sessionManager = fakeSessionManager();
    server = await startBridgeServer({
      host: "127.0.0.1",
      port,
      url: `ws://127.0.0.1:${port}`,
      pairingStore: new PairingStore({ password: "secret" }),
      sessionManager,
      auditLog: { record() {} } as unknown as AuditLog,
      logger: { info() {} } as unknown as pino.Logger,
      hostInfo: {
        connectionMode: "tunnel",
        tunnelProvider: "cloudflared",
        publicUrl: "wss://unit.trycloudflare.com",
        localUrl: `ws://127.0.0.1:${port}`,
        hostLabel: "Codex Link",
        yoloAllowed: false,
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const messages: Array<Record<string, unknown>> = [];
    ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

    await opened(ws);
    ws.send(JSON.stringify({ type: "auth.password", password: "secret", deviceName: "Pixel" }));
    await eventually(() => {
      expect(messages.some((message) => message.type === "auth.accepted")).toBe(true);
    });
    ws.send(JSON.stringify({ type: "file.offer.request", sessionId: "s1", path: "notes.txt" }));

    await eventually(() => {
      expect(messages.some((message) => message.type === "file.offer")).toBe(true);
    });
    expect(sessionManager.requestedFiles).toEqual([{ sessionId: "s1", path: "notes.txt" }]);
    expect(messages.find((message) => message.type === "file.offer")).toMatchObject({
      name: "notes.txt",
      reason: "requested",
    });

    ws.close();
  });

  it("forwards workspace file searches to the session manager", async () => {
    const port = await freePort();
    const sessionManager = fakeSessionManager();
    server = await startBridgeServer({
      host: "127.0.0.1",
      port,
      url: `ws://127.0.0.1:${port}`,
      pairingStore: new PairingStore({ password: "secret" }),
      sessionManager,
      auditLog: { record() {} } as unknown as AuditLog,
      logger: { info() {} } as unknown as pino.Logger,
      hostInfo: {
        connectionMode: "tunnel",
        tunnelProvider: "cloudflared",
        publicUrl: "wss://unit.trycloudflare.com",
        localUrl: `ws://127.0.0.1:${port}`,
        hostLabel: "Codex Link",
        yoloAllowed: false,
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const messages: Array<Record<string, unknown>> = [];
    ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

    await opened(ws);
    ws.send(JSON.stringify({ type: "auth.password", password: "secret", deviceName: "Pixel" }));
    await eventually(() => {
      expect(messages.some((message) => message.type === "auth.accepted")).toBe(true);
    });
    ws.send(JSON.stringify({ type: "workspace.file.search", sessionId: "s1", query: "main", limit: 8 }));

    await eventually(() => {
      expect(messages.some((message) => message.type === "workspace.file.search.results")).toBe(true);
    });
    expect(sessionManager.fileSearches).toEqual([{ sessionId: "s1", query: "main", limit: 8 }]);
    expect(messages.find((message) => message.type === "workspace.file.search.results")).toMatchObject({
      sessionId: "s1",
      query: "main",
      files: [{ path: "lib/main.dart", name: "main.dart" }],
    });

    ws.close();
  });

  it("forwards workspace env secret updates to the session manager", async () => {
    const port = await freePort();
    const sessionManager = fakeSessionManager();
    server = await startBridgeServer({
      host: "127.0.0.1",
      port,
      url: `ws://127.0.0.1:${port}`,
      pairingStore: new PairingStore({ password: "secret" }),
      sessionManager,
      auditLog: { record() {} } as unknown as AuditLog,
      logger: { info() {} } as unknown as pino.Logger,
      hostInfo: {
        connectionMode: "tunnel",
        tunnelProvider: "cloudflared",
        publicUrl: "wss://unit.trycloudflare.com",
        localUrl: `ws://127.0.0.1:${port}`,
        hostLabel: "Codex Link",
        yoloAllowed: false,
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const messages: Array<Record<string, unknown>> = [];
    ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

    await opened(ws);
    ws.send(JSON.stringify({ type: "auth.password", password: "secret", deviceName: "Pixel" }));
    await eventually(() => {
      expect(messages.some((message) => message.type === "auth.accepted")).toBe(true);
    });
    ws.send(JSON.stringify({ type: "workspace.env.set", sessionId: "s1", content: "OPENAI_API_KEY=sk-unit" }));

    await eventually(() => {
      expect(messages.some((message) => message.type === "workspace.env.updated")).toBe(true);
    });
    expect(sessionManager.envSets).toEqual([{ sessionId: "s1", content: "OPENAI_API_KEY=sk-unit", targetPath: undefined }]);
    expect(messages.find((message) => message.type === "workspace.env.updated")).toMatchObject({
      sessionId: "s1",
      path: ".env.local",
      variableNames: ["OPENAI_API_KEY"],
    });
    expect(messages.filter((message) => message.type === "workspace.env.updated")).toHaveLength(1);

    ws.close();
  });

  it("forwards shell commands to the session manager", async () => {
    const port = await freePort();
    const sessionManager = fakeSessionManager();
    server = await startBridgeServer({
      host: "127.0.0.1",
      port,
      url: `ws://127.0.0.1:${port}`,
      pairingStore: new PairingStore({ password: "secret" }),
      sessionManager,
      auditLog: { record() {} } as unknown as AuditLog,
      logger: { info() {} } as unknown as pino.Logger,
      hostInfo: {
        connectionMode: "tunnel",
        tunnelProvider: "cloudflared",
        publicUrl: "wss://unit.trycloudflare.com",
        localUrl: `ws://127.0.0.1:${port}`,
        hostLabel: "Codex Link",
        yoloAllowed: false,
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const messages: Array<Record<string, unknown>> = [];
    ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

    await opened(ws);
    ws.send(JSON.stringify({ type: "auth.password", password: "secret", deviceName: "Pixel" }));
    await eventually(() => {
      expect(messages.some((message) => message.type === "auth.accepted")).toBe(true);
    });
    ws.send(JSON.stringify({ type: "shell.command.run", sessionId: "s1", command: "pwd" }));

    await eventually(() => {
      expect(messages.some((message) => message.type === "shell.command.result")).toBe(true);
    });
    expect(sessionManager.shellCommands).toEqual([{ sessionId: "s1", command: "pwd" }]);
    expect(messages.find((message) => message.type === "shell.command.result")).toMatchObject({
      sessionId: "s1",
      command: "pwd",
      exitCode: 0,
      stdout: "/tmp/unit\n",
    });

    ws.close();
  });

  it("forwards goal and approval messages to the session manager", async () => {
    const port = await freePort();
    const sessionManager = fakeSessionManager();
    server = await startBridgeServer({
      host: "127.0.0.1",
      port,
      url: `ws://127.0.0.1:${port}`,
      pairingStore: new PairingStore({ password: "secret" }),
      sessionManager,
      auditLog: { record() {} } as unknown as AuditLog,
      logger: { info() {} } as unknown as pino.Logger,
      hostInfo: {
        connectionMode: "tunnel",
        tunnelProvider: "cloudflared",
        publicUrl: "wss://unit.trycloudflare.com",
        localUrl: `ws://127.0.0.1:${port}`,
        hostLabel: "Codex Link",
        yoloAllowed: false,
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const messages: Array<Record<string, unknown>> = [];
    ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

    await opened(ws);
    ws.send(JSON.stringify({ type: "auth.password", password: "secret", deviceName: "Pixel" }));
    await eventually(() => {
      expect(messages.some((message) => message.type === "auth.accepted")).toBe(true);
    });

    ws.send(JSON.stringify({ type: "session.goal.set", sessionId: "s1", objective: "Finish replacement", status: "active" }));
    ws.send(JSON.stringify({ type: "session.goal.get", sessionId: "s1" }));
    ws.send(JSON.stringify({ type: "approval.decision", sessionId: "s1", approvalId: "approval-1", decision: "approve" }));
    ws.send(JSON.stringify({ type: "session.goal.clear", sessionId: "s1" }));

    await eventually(() => {
      expect(sessionManager.goalSets).toHaveLength(1);
      expect(sessionManager.goalGets).toEqual(["s1"]);
      expect(sessionManager.approvals).toEqual([{ sessionId: "s1", approvalId: "approval-1", decision: "approve" }]);
      expect(sessionManager.goalClears).toEqual(["s1"]);
      expect(messages.some((message) => message.type === "session.goal.updated")).toBe(true);
      expect(messages.some((message) => message.type === "session.goal.cleared")).toBe(true);
    });
    expect(messages.some((message) => message.type === "error" && message.code === "approval.not_implemented")).toBe(false);

    ws.close();
  });

  it("forwards native app-server capability messages to the session manager", async () => {
    const port = await freePort();
    const sessionManager = fakeSessionManager();
    server = await startBridgeServer({
      host: "127.0.0.1",
      port,
      url: `ws://127.0.0.1:${port}`,
      pairingStore: new PairingStore({ password: "secret" }),
      sessionManager,
      auditLog: { record() {} } as unknown as AuditLog,
      logger: { info() {} } as unknown as pino.Logger,
      hostInfo: {
        connectionMode: "tunnel",
        tunnelProvider: "cloudflared",
        publicUrl: "wss://unit.trycloudflare.com",
        localUrl: `ws://127.0.0.1:${port}`,
        hostLabel: "Codex Link",
        yoloAllowed: false,
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const messages: Array<Record<string, unknown>> = [];
    ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

    await opened(ws);
    ws.send(JSON.stringify({ type: "auth.password", password: "secret", deviceName: "Pixel" }));
    await eventually(() => {
      expect(messages.some((message) => message.type === "auth.accepted")).toBe(true);
    });

    ws.send(JSON.stringify({ type: "app.model.list", sessionId: "s1", includeHidden: true }));
    ws.send(JSON.stringify({ type: "app.thread.list", sessionId: "s1", query: "native", limit: 5 }));
    ws.send(JSON.stringify({ type: "app.skill.list", sessionId: "s1", forceReload: true }));
    ws.send(JSON.stringify({ type: "app.fs.list", sessionId: "s1", path: "lib" }));
    ws.send(JSON.stringify({ type: "app.fs.read", sessionId: "s1", path: "README.md" }));
    ws.send(JSON.stringify({ type: "app.file.search", sessionId: "s1", query: "@main", limit: 8 }));
    ws.send(JSON.stringify({ type: "app.review.start", sessionId: "s1", target: "custom", instructions: "review", delivery: "inline" }));
    ws.send(JSON.stringify({ type: "app.thread.import", threadId: "native-thread" }));

    await eventually(() => {
      expect(messages.some((message) => message.type === "app.model.list")).toBe(true);
      expect(messages.some((message) => message.type === "app.thread.list")).toBe(true);
      expect(messages.some((message) => message.type === "app.skill.list")).toBe(true);
      expect(messages.some((message) => message.type === "app.fs.list")).toBe(true);
      expect(messages.some((message) => message.type === "app.fs.file")).toBe(true);
      expect(messages.some((message) => message.type === "app.file.search.results")).toBe(true);
      expect(messages.some((message) => message.type === "app.review.started")).toBe(true);
      expect(sessionManager.importedAppThreads).toEqual(["native-thread"]);
    });

    ws.close();
  });

  it("forwards Codex account auth messages to the session manager", async () => {
    const port = await freePort();
    const sessionManager = fakeSessionManager();
    server = await startBridgeServer({
      host: "127.0.0.1",
      port,
      url: `ws://127.0.0.1:${port}`,
      pairingStore: new PairingStore({ password: "secret" }),
      sessionManager,
      auditLog: { record() {} } as unknown as AuditLog,
      logger: { info() {} } as unknown as pino.Logger,
      hostInfo: {
        connectionMode: "tunnel",
        tunnelProvider: "cloudflared",
        publicUrl: "wss://unit.trycloudflare.com",
        localUrl: `ws://127.0.0.1:${port}`,
        hostLabel: "Codex Link",
        yoloAllowed: false,
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const messages: Array<Record<string, unknown>> = [];
    ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

    await opened(ws);
    ws.send(JSON.stringify({ type: "auth.password", password: "secret", deviceName: "Pixel" }));
    await eventually(() => {
      expect(messages.some((message) => message.type === "auth.accepted")).toBe(true);
    });
    messages.length = 0;
    sessionManager.accountReads.length = 0;

    ws.send(JSON.stringify({ type: "app.account.read", refreshToken: true }));
    ws.send(JSON.stringify({ type: "app.account.login.start", loginType: "chatgptDeviceCode" }));
    ws.send(JSON.stringify({ type: "app.account.login.start", loginType: "chatgpt" }));
    ws.send(JSON.stringify({ type: "app.account.login.start", loginType: "apiKey", apiKey: "sk-unit-secret" }));
    ws.send(JSON.stringify({ type: "app.account.login.cancel", loginId: "login-device" }));
    ws.send(JSON.stringify({ type: "app.account.logout" }));

    await eventually(() => {
      expect(messages.some((message) => message.type === "app.account.status")).toBe(true);
      expect(messages.filter((message) => message.type === "app.account.login.started")).toHaveLength(3);
      expect(messages.some((message) => message.type === "app.account.login.cancelled")).toBe(true);
      expect(sessionManager.accountReads).toEqual([true]);
      expect(sessionManager.accountLoginStarts).toEqual([
        { type: "chatgptDeviceCode" },
        { type: "chatgpt" },
        { type: "apiKey", apiKey: "sk-unit-secret" },
      ]);
      expect(sessionManager.accountLoginCancels).toEqual(["login-device"]);
      expect(sessionManager.accountLogouts).toBe(1);
    });
    expect(messages.find((message) => message.type === "app.account.status")).toMatchObject({
      account: {
        accountType: "chatgpt",
        email: "unit@example.com",
        planType: "pro",
        authMode: "chatgpt",
      },
    });

    ws.close();
  });

  it("forwards interactive app-server action messages to the session manager", async () => {
    const port = await freePort();
    const sessionManager = fakeSessionManager();
    server = await startBridgeServer({
      host: "127.0.0.1",
      port,
      url: `ws://127.0.0.1:${port}`,
      pairingStore: new PairingStore({ password: "secret" }),
      sessionManager,
      auditLog: { record() {} } as unknown as AuditLog,
      logger: { info() {} } as unknown as pino.Logger,
      hostInfo: {
        connectionMode: "tunnel",
        tunnelProvider: "cloudflared",
        publicUrl: "wss://unit.trycloudflare.com",
        localUrl: `ws://127.0.0.1:${port}`,
        hostLabel: "Codex Link",
        yoloAllowed: false,
      },
    });

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const messages: Array<Record<string, unknown>> = [];
    ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

    await opened(ws);
    ws.send(JSON.stringify({ type: "auth.password", password: "secret", deviceName: "Pixel" }));
    await eventually(() => {
      expect(messages.some((message) => message.type === "auth.accepted")).toBe(true);
    });
    messages.length = 0;

    ws.send(JSON.stringify({ type: "app.plugin.list", sessionId: "s1" }));
    ws.send(JSON.stringify({ type: "app.plugin.read", pluginName: "github", marketplacePath: "/tmp/marketplace" }));
    ws.send(JSON.stringify({ type: "app.plugin.install", pluginName: "github", marketplacePath: "/tmp/marketplace" }));
    ws.send(JSON.stringify({ type: "app.plugin.uninstall", pluginName: "github" }));
    ws.send(JSON.stringify({ type: "app.mcp.status.list", sessionId: "s1", detail: "toolsAndAuthOnly" }));
    ws.send(JSON.stringify({ type: "app.mcp.oauth.login", serverName: "github" }));
    ws.send(JSON.stringify({ type: "app.remote.status.read" }));
    ws.send(JSON.stringify({ type: "app.remote.pairing.start", manualPairingCode: "123456" }));
    ws.send(JSON.stringify({ type: "app.account.rateLimits.read" }));
    ws.send(JSON.stringify({ type: "host.update.check" }));
    ws.send(JSON.stringify({ type: "host.update.run" }));

    await eventually(() => {
      expect(messages.some((message) => message.type === "app.plugin.list")).toBe(true);
      expect(messages.some((message) => message.type === "app.plugin.detail")).toBe(true);
      expect(messages.some((message) => message.type === "app.plugin.install.result")).toBe(true);
      expect(messages.some((message) => message.type === "app.plugin.uninstall.result")).toBe(true);
      expect(messages.some((message) => message.type === "app.mcp.status.list")).toBe(true);
      expect(messages.some((message) => message.type === "app.mcp.oauth.login.started")).toBe(true);
      expect(messages.some((message) => message.type === "app.remote.status")).toBe(true);
      expect(messages.some((message) => message.type === "app.remote.pairing.started")).toBe(true);
      expect(messages.some((message) => message.type === "app.account.rateLimits")).toBe(true);
      expect(messages.some((message) => message.type === "host.update.status")).toBe(true);
      expect(messages.some((message) => message.type === "host.update.progress")).toBe(true);
      expect(messages.some((message) => message.type === "host.update.result")).toBe(true);
    });
    expect(sessionManager.pluginActions.map((action) => action.type)).toEqual(["list", "read", "install", "uninstall"]);
    expect(sessionManager.mcpActions).toEqual(["list:toolsAndAuthOnly", "oauth:github"]);
    expect(sessionManager.remoteActions).toEqual(["status", "pair:123456"]);
    expect(sessionManager.rateLimitReads).toBe(1);
    expect(sessionManager.hostUpdateActions).toEqual(["check", "run"]);
    expect(messages.find((message) => message.type === "host.update.status")).toMatchObject({
      packageName: "codex-link-host",
      currentVersion: "0.1.1",
      latestVersion: "0.1.2",
      updateAvailable: true,
    });
    expect(messages.find((message) => message.type === "host.update.result")).toMatchObject({
      packageName: "codex-link-host",
      previousVersion: "0.1.1",
      latestVersion: "0.1.2",
      updated: true,
      restartRequired: true,
    });

    ws.close();
  });
});

function fakeSessionManager(): CodexSessionManager & {
  requestedFiles: Array<{ sessionId: string; path: string }>;
  fileSearches: Array<{ sessionId: string; query?: string; limit?: number }>;
  envSets: Array<{ sessionId: string; content: string; targetPath?: string }>;
  goalSets: Array<{ sessionId: string; objective?: string; status?: string; tokenBudget?: number | null }>;
  goalGets: string[];
  goalClears: string[];
  approvals: Array<{ sessionId: string; approvalId: string; decision: "approve" | "reject" }>;
  importedAppThreads: string[];
  accountReads: boolean[];
  accountLoginStarts: Array<Record<string, unknown>>;
  accountLoginCancels: string[];
  accountLogouts: number;
  pluginActions: Array<Record<string, unknown>>;
  mcpActions: string[];
  remoteActions: string[];
  shellCommands: Array<{ sessionId: string; command: string }>;
  hostUpdateActions: string[];
  rateLimitReads: number;
} {
  const requestedFiles: Array<{ sessionId: string; path: string }> = [];
  const fileSearches: Array<{ sessionId: string; query?: string; limit?: number }> = [];
  const envSets: Array<{ sessionId: string; content: string; targetPath?: string }> = [];
  const goalSets: Array<{ sessionId: string; objective?: string; status?: string; tokenBudget?: number | null }> = [];
  const goalGets: string[] = [];
  const goalClears: string[] = [];
  const approvals: Array<{ sessionId: string; approvalId: string; decision: "approve" | "reject" }> = [];
  const importedAppThreads: string[] = [];
  const accountReads: boolean[] = [];
  const accountLoginStarts: Array<Record<string, unknown>> = [];
  const accountLoginCancels: string[] = [];
  const pluginActions: Array<Record<string, unknown>> = [];
  const mcpActions: string[] = [];
  const remoteActions: string[] = [];
  const shellCommands: Array<{ sessionId: string; command: string }> = [];
  const hostUpdateActions: string[] = [];
  let rateLimitReads = 0;
  let accountLogouts = 0;
  let listener: ((event: unknown) => void) | undefined;
  return {
    requestedFiles,
    fileSearches,
    envSets,
    goalSets,
    goalGets,
    goalClears,
    approvals,
    importedAppThreads,
    accountReads,
    accountLoginStarts,
    accountLoginCancels,
    pluginActions,
    mcpActions,
    remoteActions,
    shellCommands,
    hostUpdateActions,
    get accountLogouts() {
      return accountLogouts;
    },
    get rateLimitReads() {
      return rateLimitReads;
    },
    onEvent: (callback: (event: unknown) => void) => {
      listener = callback;
      return () => {
        listener = undefined;
      };
    },
    close: async () => {},
    getActiveSessionId: () => "s1",
    offerRequestedFile: async (sessionId: string, filePath: string) => {
      requestedFiles.push({ sessionId, path: filePath });
      const offer = {
        type: "file.offer",
        fileId: "file-1",
        sessionId,
        path: filePath,
        name: "notes.txt",
        sizeBytes: 12,
        reason: "requested",
      };
      listener?.(offer);
      return offer;
    },
    searchWorkspaceFiles: async (sessionId: string, query?: string, limit?: number) => {
      fileSearches.push({ sessionId, query, limit });
      return {
        type: "workspace.file.search.results",
        sessionId,
        query: query ?? "",
        files: [{ path: "lib/main.dart", name: "main.dart", sizeBytes: 14, mimeType: "text/plain" }],
      };
    },
    setWorkspaceEnv: async (sessionId: string, content: string, targetPath?: string) => {
      envSets.push({ sessionId, content, targetPath });
      const result = {
        type: "workspace.env.updated",
        sessionId,
        path: targetPath ?? ".env.local",
        variableNames: ["OPENAI_API_KEY"],
        skippedLineCount: 0,
      };
      listener?.(result);
      return result;
    },
    runShellCommand: async (sessionId: string, command: string) => {
      shellCommands.push({ sessionId, command });
      return {
        type: "shell.command.result",
        sessionId,
        command,
        exitCode: 0,
        stdout: "/tmp/unit\n",
        stderr: "",
        durationMs: 12,
        cwd: "/tmp/unit",
      };
    },
    setGoal: async (sessionId: string, input: { objective?: string; status?: string; tokenBudget?: number | null }) => {
      goalSets.push({ sessionId, ...input });
      const goal = {
        threadId: "thread-1",
        objective: input.objective ?? "Finish replacement",
        status: input.status ?? "active",
        tokenBudget: input.tokenBudget ?? null,
        tokensUsed: 0,
        timeUsedSeconds: 0,
        createdAt: 1,
        updatedAt: 1,
      };
      listener?.({ type: "session.goal.updated", sessionId, goal });
      return goal;
    },
    getGoal: async (sessionId: string) => {
      goalGets.push(sessionId);
      return {
        threadId: "thread-1",
        objective: "Finish replacement",
        status: "active",
        tokenBudget: null,
        tokensUsed: 0,
        timeUsedSeconds: 0,
        createdAt: 1,
        updatedAt: 1,
      };
    },
    clearGoal: async (sessionId: string) => {
      goalClears.push(sessionId);
      listener?.({ type: "session.goal.cleared", sessionId });
      return true;
    },
    decideApproval: async (sessionId: string, approvalId: string, decision: "approve" | "reject") => {
      approvals.push({ sessionId, approvalId, decision });
    },
    listAppModels: async (_sessionId?: string, _includeHidden?: boolean) => ({
      type: "app.model.list",
      models: [{ id: "gpt-test", model: "gpt-test", displayName: "GPT Test", hidden: false, supportedReasoningEfforts: ["low"], inputModalities: ["text"], supportsPersonality: false, serviceTiers: [], defaultServiceTier: null, isDefault: true }],
      capabilities: { namespaceTools: true, imageGeneration: true, webSearch: true },
    }),
    listAppThreads: async () => ({
      type: "app.thread.list",
      threads: [{ threadId: "native-thread", title: "Native", preview: "Native", createdAt: "2026-06-07T00:00:00.000Z", updatedAt: "2026-06-07T00:00:00.000Z", workdir: "/tmp/unit" }],
    }),
    importAppThread: async (threadId: string) => {
      importedAppThreads.push(threadId);
      return {
        sessionId: "imported",
        title: "Imported native",
        createdAt: "2026-06-07T00:00:00.000Z",
        updatedAt: "2026-06-07T00:00:00.000Z",
        workspaceId: "default",
        workdir: "/tmp/unit",
        lastStatus: "idle",
        mode: "safe",
        sandbox: "workspace-write",
        codexThreadId: threadId,
      };
    },
    listAppSkills: async () => ({
      type: "app.skill.list",
      groups: [{ cwd: "/tmp/unit", skills: [{ name: "flutter-design-system", description: "Token discipline", path: "/tmp/SKILL.md", enabled: true }], errors: [] }],
    }),
    listAppDirectory: async (sessionId: string, directoryPath = "") => ({
      type: "app.fs.list",
      sessionId,
      path: directoryPath,
      entries: [{ path: "lib/main.dart", name: "main.dart", isDirectory: false, isFile: true }],
    }),
    readAppFile: async (sessionId: string, filePath: string) => ({
      type: "app.fs.file",
      sessionId,
      file: { path: filePath, name: "README.md", sizeBytes: 7, mimeType: "text/plain", text: "# Unit\n" },
    }),
    searchAppFiles: async (sessionId: string, query: string, limit?: number) => ({
      type: "app.file.search.results",
      sessionId,
      query,
      files: [{ path: "lib/main.dart", name: "main.dart", sizeBytes: limit, mimeType: "text/plain" }],
    }),
    startReview: async (sessionId: string) => ({
      type: "app.review.started",
      sessionId,
      runId: "review-1",
      reviewThreadId: "thread-review",
    }),
    getCodexAccount: async (refreshToken?: boolean) => {
      accountReads.push(refreshToken === true);
      return {
        accountType: "chatgpt",
        email: "unit@example.com",
        planType: "pro",
        authMode: "chatgpt",
        requiresOpenaiAuth: false,
      };
    },
    readCodexAccount: async (refreshToken?: boolean) => {
      accountReads.push(refreshToken === true);
      return {
        type: "app.account.status",
        account: {
          accountType: "chatgpt",
          email: "unit@example.com",
          planType: "pro",
          authMode: "chatgpt",
          requiresOpenaiAuth: false,
        },
      };
    },
    startCodexAccountLogin: async (input: Record<string, unknown>) => {
      accountLoginStarts.push({ ...input });
      if (input.type === "chatgptDeviceCode") {
        const flow = {
          type: "chatgptDeviceCode",
          loginId: "login-device",
          verificationUrl: "https://auth.openai.com/activate",
          userCode: "CODE-123",
        };
        listener?.({ type: "app.account.login.completed", loginId: "login-device", success: true, error: null });
        return { type: "app.account.login.started", flow };
      }
      if (input.type === "chatgpt") {
        return {
          type: "app.account.login.started",
          flow: {
            type: "chatgpt",
            loginId: "login-browser",
            authUrl: "https://chatgpt.com/backend-api/codex/login?state=unit",
          },
        };
      }
      return { type: "app.account.login.started", flow: { type: "apiKey" } };
    },
    cancelCodexAccountLogin: async (loginId: string) => {
      accountLoginCancels.push(loginId);
      return { type: "app.account.login.cancelled", loginId, status: "canceled" };
    },
    logoutCodexAccount: async () => {
      accountLogouts += 1;
      listener?.({ type: "app.account.updated", account: { accountType: null, authMode: null, requiresOpenaiAuth: true } });
      return {
        type: "app.account.status",
        account: { accountType: null, authMode: null, requiresOpenaiAuth: true },
      };
    },
    listAppPlugins: async (sessionId?: string) => {
      pluginActions.push({ type: "list", sessionId });
      return {
        type: "app.plugin.list",
        marketplaces: [
          {
            name: "openai-curated",
            displayName: "OpenAI curated",
            path: "/tmp/marketplace",
            plugins: [{ name: "github", displayName: "GitHub", description: "GitHub integration", installed: false, enabled: true }],
          },
        ],
      };
    },
    readAppPlugin: async (input: Record<string, unknown>) => {
      pluginActions.push({ type: "read", ...input });
      return {
        type: "app.plugin.detail",
        plugin: { name: input.pluginName, displayName: "GitHub", description: "GitHub integration", skills: [], apps: [], mcpServers: [] },
      };
    },
    installAppPlugin: async (input: Record<string, unknown>) => {
      pluginActions.push({ type: "install", ...input });
      return {
        type: "app.plugin.install.result",
        pluginName: input.pluginName,
        installed: true,
        appsNeedingAuth: [],
      };
    },
    uninstallAppPlugin: async (pluginName: string) => {
      pluginActions.push({ type: "uninstall", pluginName });
      return {
        type: "app.plugin.uninstall.result",
        pluginName,
        uninstalled: true,
      };
    },
    listAppMcpServers: async (_sessionId?: string, detail?: string) => {
      mcpActions.push(`list:${detail ?? "toolsAndAuthOnly"}`);
      return {
        type: "app.mcp.status.list",
        servers: [{ name: "github", status: "enabled", authStatus: "unauthenticated", toolCount: 2, tools: ["search_issues"], resourceCount: 0 }],
      };
    },
    startAppMcpOauthLogin: async (serverName: string) => {
      mcpActions.push(`oauth:${serverName}`);
      return {
        type: "app.mcp.oauth.login.started",
        serverName,
        loginUrl: "https://github.com/login/oauth/authorize",
      };
    },
    readAppRemoteControlStatus: async () => {
      remoteActions.push("status");
      return {
        type: "app.remote.status",
        status: { enabled: true, serverName: "unit-host", environmentId: "env-1" },
      };
    },
    startAppRemotePairing: async (manualPairingCode?: string) => {
      remoteActions.push(`pair:${manualPairingCode ?? ""}`);
      return {
        type: "app.remote.pairing.started",
        pairing: { pairingCode: "PAIR-123", manualPairingCode, environmentId: "env-1" },
      };
    },
    readAppRateLimits: async () => {
      rateLimitReads += 1;
      return {
        type: "app.account.rateLimits",
        limits: [{ limitId: "codex", planType: "pro", usedPercent: 5, remainingPercent: 95, windowDurationMins: 43200 }],
      };
    },
    checkHostUpdate: async () => {
      hostUpdateActions.push("check");
      return {
        type: "host.update.status",
        packageName: "codex-link-host",
        currentVersion: "0.1.1",
        latestVersion: "0.1.2",
        updateAvailable: true,
        updateRunning: false,
      };
    },
    runHostUpdate: async (onProgress: (event: unknown) => void) => {
      hostUpdateActions.push("run");
      onProgress({
        type: "host.update.progress",
        packageName: "codex-link-host",
        phase: "installing",
        line: "installing codex-link-host@latest",
      });
      return {
        type: "host.update.result",
        packageName: "codex-link-host",
        previousVersion: "0.1.1",
        latestVersion: "0.1.2",
        updated: true,
        exitCode: 0,
        stdout: "updated\n",
        stderr: "",
        restartRequired: true,
        message: "Host package updated. Restart the host bridge to use the new version.",
      };
    },
    listSessions: () => [
      {
        sessionId: "s1",
        title: "Unit",
        createdAt: "2026-06-07T00:00:00.000Z",
        updatedAt: "2026-06-07T00:00:00.000Z",
        workspaceId: "default",
        workdir: "/tmp/unit",
        lastStatus: "idle",
        mode: "safe",
        sandbox: "workspace-write",
      },
    ],
    getWorkspaces: () => [],
    getSessionHistory: () => [],
    listExternalSessions: async () => [],
  } as unknown as CodexSessionManager & {
    requestedFiles: Array<{ sessionId: string; path: string }>;
    fileSearches: Array<{ sessionId: string; query?: string; limit?: number }>;
    envSets: Array<{ sessionId: string; content: string; targetPath?: string }>;
    goalSets: Array<{ sessionId: string; objective?: string; status?: string; tokenBudget?: number | null }>;
    goalGets: string[];
    goalClears: string[];
    approvals: Array<{ sessionId: string; approvalId: string; decision: "approve" | "reject" }>;
    importedAppThreads: string[];
    accountReads: boolean[];
    accountLoginStarts: Array<Record<string, unknown>>;
    accountLoginCancels: string[];
    accountLogouts: number;
    pluginActions: Array<Record<string, unknown>>;
    mcpActions: string[];
    remoteActions: string[];
    shellCommands: Array<{ sessionId: string; command: string }>;
    hostUpdateActions: string[];
    rateLimitReads: number;
  };
}

async function freePort(): Promise<number> {
  const probe = net.createServer();
  await new Promise<void>((resolve, reject) => {
    probe.once("error", reject);
    probe.listen(0, "127.0.0.1", () => resolve());
  });
  const address = probe.address();
  await new Promise<void>((resolve) => probe.close(() => resolve()));
  if (!address || typeof address === "string") {
    throw new Error("Could not allocate a local port");
  }
  return address.port;
}

async function opened(ws: WebSocket): Promise<void> {
  if (ws.readyState === WebSocket.OPEN) return;
  await new Promise<void>((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });
}

async function eventually(assertion: () => void): Promise<void> {
  const deadline = Date.now() + 1_000;
  let lastError: unknown;
  while (Date.now() < deadline) {
    try {
      assertion();
      return;
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  if (lastError) throw lastError;
  assertion();
}
