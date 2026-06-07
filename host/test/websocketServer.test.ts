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
      version: 3,
      connectionMode: "tunnel",
      tunnelProvider: "cloudflared",
      publicUrl: "wss://unit.trycloudflare.com",
      hostLabel: "Codex Link",
      yoloAllowed: false,
    });

    ws.close();
  });
});

function fakeSessionManager(): CodexSessionManager {
  return {
    onEvent: () => () => {},
    close: async () => {},
    getActiveSessionId: () => "s1",
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
  } as unknown as CodexSessionManager;
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
