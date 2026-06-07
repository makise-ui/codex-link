import net from "node:net";
import { WebSocket } from "ws";
import { afterEach, describe, expect, it } from "vitest";
import { PairingStore } from "../src/auth/pairingStore.js";
import { startBridgeServer } from "../src/server/websocketServer.js";
describe("startBridgeServer", () => {
    let server;
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
            auditLog: { record() { } },
            logger: { info() { } },
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
        const messages = [];
        ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));
        await opened(ws);
        ws.send(JSON.stringify({
            type: "auth.password",
            password: "secret",
            deviceName: "Pixel",
        }));
        await eventually(() => {
            expect(messages.some((message) => message.type === "host.info")).toBe(true);
        });
        const hostInfo = messages.find((message) => message.type === "host.info");
        expect(hostInfo).toMatchObject({
            version: 4,
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
            auditLog: { record() { } },
            logger: { info() { } },
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
        const messages = [];
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
});
function fakeSessionManager() {
    const requestedFiles = [];
    let listener;
    return {
        requestedFiles,
        onEvent: (callback) => {
            listener = callback;
            return () => {
                listener = undefined;
            };
        },
        close: async () => { },
        getActiveSessionId: () => "s1",
        offerRequestedFile: async (sessionId, filePath) => {
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
    };
}
async function freePort() {
    const probe = net.createServer();
    await new Promise((resolve, reject) => {
        probe.once("error", reject);
        probe.listen(0, "127.0.0.1", () => resolve());
    });
    const address = probe.address();
    await new Promise((resolve) => probe.close(() => resolve()));
    if (!address || typeof address === "string") {
        throw new Error("Could not allocate a local port");
    }
    return address.port;
}
async function opened(ws) {
    if (ws.readyState === WebSocket.OPEN)
        return;
    await new Promise((resolve, reject) => {
        ws.once("open", resolve);
        ws.once("error", reject);
    });
}
async function eventually(assertion) {
    const deadline = Date.now() + 1_000;
    let lastError;
    while (Date.now() < deadline) {
        try {
            assertion();
            return;
        }
        catch (error) {
            lastError = error;
            await new Promise((resolve) => setTimeout(resolve, 20));
        }
    }
    if (lastError)
        throw lastError;
    assertion();
}
