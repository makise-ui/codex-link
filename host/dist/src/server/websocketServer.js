import http from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import { ZodError } from "zod";
import { COMMAND_CATALOG, promptForCommand } from "../codex/commandCatalog.js";
import { PROTOCOL_VERSION } from "../protocol/messages.js";
import { parseClientMessage } from "../protocol/schemas.js";
import { assertAllowedRemoteAddress } from "../safety/networkGuard.js";
export async function startBridgeServer(options) {
    const clients = new Map();
    const server = http.createServer((req, res) => {
        if (req.url === "/health") {
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ ok: true, version: PROTOCOL_VERSION }));
            return;
        }
        res.writeHead(404);
        res.end("not found");
    });
    const wss = new WebSocketServer({ server, maxPayload: 16 * 1024 * 1024 });
    const unsubscribe = options.sessionManager.onEvent((event) => {
        broadcast(event);
        if (event.type === "run.completed") {
            options.auditLog.record({ type: "run.completed", sessionId: event.sessionId, runId: event.runId });
        }
        if (event.type === "status" && event.status === "failed") {
            options.auditLog.record({ type: "run.failed", sessionId: event.sessionId, runId: event.runId, detail: event.detail });
        }
    });
    wss.on("connection", (ws, req) => {
        try {
            assertAllowedRemoteAddress(req.socket.remoteAddress, { remoteMode: options.hostInfo.connectionMode });
        }
        catch (error) {
            send(ws, { type: "error", code: "network.rejected", message: error instanceof Error ? error.message : "Remote address rejected" });
            ws.close(1008, "LAN/private sources only");
            return;
        }
        clients.set(ws, { authenticated: false });
        send(ws, { type: "status", status: "connected", detail: "Pair or resume auth to control the bridge." });
        ws.on("message", async (data) => {
            try {
                const message = decodeMessage(data);
                await handleMessage(ws, message);
            }
            catch (error) {
                sendError(ws, error);
            }
        });
        ws.on("close", () => {
            const state = clients.get(ws);
            if (state?.device) {
                options.auditLog.record({ type: "device.disconnected", deviceId: state.device.id });
            }
            clients.delete(ws);
        });
    });
    await new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(options.port, options.host, () => {
            server.off("error", reject);
            resolve();
        });
    });
    options.logger.info({ url: options.url }, "Codex Link host bridge listening");
    return {
        async close() {
            unsubscribe();
            for (const client of clients.keys()) {
                client.close(1001, "server shutting down");
            }
            await options.sessionManager.close();
            await new Promise((resolve) => wss.close(() => resolve()));
            await new Promise((resolve) => server.close(() => resolve()));
        },
    };
    async function handleMessage(ws, message) {
        const state = clients.get(ws);
        if (!state) {
            throw new Error("Unknown client connection.");
        }
        if (message.type === "ping") {
            send(ws, { type: "pong", nonce: message.nonce });
            return;
        }
        if (!state.authenticated) {
            if (message.type === "pairing.claim") {
                const device = options.pairingStore.claimPairing(message.pairingToken, message.deviceName);
                if (!device) {
                    send(ws, { type: "error", code: "pairing.invalid", message: "Invalid, expired, or already-used pairing token." });
                    return;
                }
                state.authenticated = true;
                state.device = device;
                options.auditLog.record({ type: "device.paired", deviceId: device.id });
                send(ws, {
                    type: "pairing.accepted",
                    version: PROTOCOL_VERSION,
                    deviceId: device.id,
                    deviceToken: device.token,
                    sessionId: options.sessionManager.getActiveSessionId() ?? "",
                });
                sendBootstrap(ws);
                return;
            }
            if (message.type === "auth.resume") {
                const device = options.pairingStore.resume(message.deviceToken);
                if (!device) {
                    send(ws, { type: "error", code: "auth.invalid", message: "Invalid device token." });
                    return;
                }
                state.authenticated = true;
                state.device = device;
                options.auditLog.record({ type: "device.authenticated", deviceId: device.id });
                send(ws, { type: "auth.accepted", version: PROTOCOL_VERSION, deviceId: device.id, sessionId: options.sessionManager.getActiveSessionId() ?? "" });
                sendBootstrap(ws);
                return;
            }
            if (message.type === "auth.password") {
                const device = options.pairingStore.claimPassword(message.password, message.deviceName);
                if (!device) {
                    send(ws, { type: "error", code: "auth.invalid", message: "Invalid host password." });
                    return;
                }
                state.authenticated = true;
                state.device = device;
                options.auditLog.record({ type: "device.authenticated", deviceId: device.id });
                send(ws, { type: "auth.accepted", version: PROTOCOL_VERSION, deviceId: device.id, sessionId: options.sessionManager.getActiveSessionId() ?? "", deviceToken: device.token });
                sendBootstrap(ws);
                return;
            }
            send(ws, { type: "error", code: "auth.required", message: "Pairing, auth.resume, or auth.password is required before operational messages." });
            return;
        }
        switch (message.type) {
            case "session.start": {
                const record = await options.sessionManager.startSession(message.sessionId);
                options.auditLog.record({ type: "session.started", deviceId: state.device?.id, sessionId: record.sessionId });
                sendSessionList(ws);
                sendWorkspaceList(ws, record.sessionId);
                sendSessionHistory(ws, record.sessionId);
                return;
            }
            case "session.list": {
                sendSessionList(ws);
                return;
            }
            case "session.create": {
                await options.sessionManager.createSession({ title: message.title, workspaceId: message.workspaceId, mode: message.mode });
                sendSessionList(ws);
                return;
            }
            case "session.rename": {
                await options.sessionManager.renameSession(message.sessionId, message.title);
                sendSessionList(ws);
                return;
            }
            case "session.delete": {
                await options.sessionManager.deleteSession(message.sessionId);
                sendSessionList(ws);
                return;
            }
            case "session.mode.set": {
                await options.sessionManager.setSessionMode(message.sessionId, message.mode);
                sendSessionList(ws);
                return;
            }
            case "session.config.set": {
                await options.sessionManager.setSessionConfig(message.sessionId, {
                    model: message.model,
                    reasoningEffort: message.reasoningEffort,
                });
                sendSessionList(ws);
                return;
            }
            case "session.goal.set": {
                await options.sessionManager.setGoal(message.sessionId, {
                    objective: message.objective,
                    status: message.status,
                    tokenBudget: message.tokenBudget,
                });
                sendSessionList(ws);
                return;
            }
            case "session.goal.get": {
                const goal = await options.sessionManager.getGoal(message.sessionId);
                if (goal) {
                    send(ws, { type: "session.goal.updated", sessionId: message.sessionId, goal });
                }
                else {
                    send(ws, { type: "session.goal.cleared", sessionId: message.sessionId });
                }
                sendSessionList(ws);
                return;
            }
            case "session.goal.clear": {
                await options.sessionManager.clearGoal(message.sessionId);
                sendSessionList(ws);
                return;
            }
            case "workspace.list": {
                sendWorkspaceList(ws);
                return;
            }
            case "workspace.add": {
                await options.sessionManager.addWorkspace(message.path, message.sessionId, { create: message.create });
                sendWorkspaceList(ws, message.sessionId);
                sendSessionList(ws);
                return;
            }
            case "workspace.switch": {
                await options.sessionManager.switchWorkspace(message.sessionId, message.workspaceId);
                sendWorkspaceList(ws, message.sessionId);
                sendSessionList(ws);
                sendSessionHistory(ws, message.sessionId);
                return;
            }
            case "workspace.file.search": {
                send(ws, await options.sessionManager.searchWorkspaceFiles(message.sessionId, message.query, message.limit));
                return;
            }
            case "external.session.list": {
                await sendExternalSessionList(ws);
                return;
            }
            case "external.session.import": {
                const record = await options.sessionManager.importExternalSession(message.externalSessionId);
                sendSessionList(ws);
                sendWorkspaceList(ws, record.sessionId);
                sendSessionHistory(ws, record.sessionId);
                return;
            }
            case "app.model.list": {
                send(ws, await options.sessionManager.listAppModels(message.sessionId, message.includeHidden));
                return;
            }
            case "app.thread.list": {
                send(ws, await options.sessionManager.listAppThreads(message.sessionId, {
                    query: message.query,
                    cwd: message.cwd,
                    limit: message.limit,
                }));
                return;
            }
            case "app.thread.import": {
                const record = await options.sessionManager.importAppThread(message.threadId);
                sendSessionList(ws);
                sendWorkspaceList(ws, record.sessionId);
                sendSessionHistory(ws, record.sessionId);
                return;
            }
            case "app.skill.list": {
                send(ws, await options.sessionManager.listAppSkills(message.sessionId, message.forceReload));
                return;
            }
            case "app.fs.list": {
                send(ws, await options.sessionManager.listAppDirectory(message.sessionId, message.path));
                return;
            }
            case "app.fs.read": {
                send(ws, await options.sessionManager.readAppFile(message.sessionId, message.path));
                return;
            }
            case "app.file.search": {
                send(ws, await options.sessionManager.searchAppFiles(message.sessionId, message.query, message.limit));
                return;
            }
            case "app.review.start": {
                send(ws, await options.sessionManager.startReview(message.sessionId, {
                    target: message.target,
                    instructions: message.instructions,
                    delivery: message.delivery,
                }));
                return;
            }
            case "command.list": {
                sendCommandList(ws);
                return;
            }
            case "command.run": {
                await runCommand(message.commandId, message.sessionId, state.device?.id);
                return;
            }
            case "prompt.send": {
                options.auditLog.record({ type: "prompt.submitted", deviceId: state.device?.id, sessionId: message.sessionId });
                await options.sessionManager.sendPrompt(message.sessionId, message.prompt, message.attachments);
                return;
            }
            case "file.offer.request": {
                await options.sessionManager.offerRequestedFile(message.sessionId, message.path);
                return;
            }
            case "file.request": {
                send(ws, await options.sessionManager.downloadFile(message.fileId));
                return;
            }
            case "run.cancel": {
                await options.sessionManager.cancel(message.sessionId, message.runId);
                options.auditLog.record({ type: "run.cancelled", deviceId: state.device?.id, sessionId: message.sessionId, runId: message.runId });
                return;
            }
            case "approval.decision": {
                await options.sessionManager.decideApproval(message.sessionId, message.approvalId, message.decision);
                options.auditLog.record({ type: "approval.decided", deviceId: state.device?.id, sessionId: message.sessionId, detail: `${message.approvalId}:${message.decision}` });
                return;
            }
            case "pairing.claim":
            case "auth.resume": {
                send(ws, { type: "error", code: "auth.already_authenticated", message: "This socket is already authenticated." });
                return;
            }
            case "auth.password": {
                send(ws, { type: "error", code: "auth.already_authenticated", message: "This socket is already authenticated." });
                return;
            }
        }
    }
    async function runCommand(commandId, sessionId, deviceId) {
        const targetSessionId = sessionId ?? options.sessionManager.getActiveSessionId();
        if (!targetSessionId) {
            throw new Error("No active session is available for this command.");
        }
        if (commandId === "mode.safe") {
            await options.sessionManager.setSessionMode(targetSessionId, "safe");
            return;
        }
        if (commandId === "mode.yolo") {
            await options.sessionManager.setSessionMode(targetSessionId, "yolo");
            return;
        }
        if (commandId === "codex.doctor") {
            options.auditLog.record({ type: "prompt.submitted", deviceId, sessionId: targetSessionId, detail: "command=codex.doctor" });
            await options.sessionManager.runDoctorCommand(targetSessionId);
            return;
        }
        const prompt = promptForCommand(commandId);
        if (!prompt) {
            throw new Error(`Unknown command: ${commandId}`);
        }
        options.auditLog.record({ type: "prompt.submitted", deviceId, sessionId: targetSessionId, detail: `command=${commandId}` });
        await options.sessionManager.sendPrompt(targetSessionId, prompt);
    }
    function sendBootstrap(ws) {
        sendHostInfo(ws);
        sendSessionList(ws);
        sendWorkspaceList(ws);
        sendCommandList(ws);
        const activeSessionId = options.sessionManager.getActiveSessionId();
        if (activeSessionId)
            sendSessionHistory(ws, activeSessionId);
        void sendExternalSessionList(ws).catch((error) => {
            send(ws, { type: "error", code: "external_sessions.failed", message: error instanceof Error ? error.message : String(error) });
        });
    }
    function sendSessionList(ws) {
        send(ws, { type: "session.list", sessions: options.sessionManager.listSessions(), activeSessionId: options.sessionManager.getActiveSessionId() });
    }
    function sendHostInfo(ws) {
        send(ws, {
            type: "host.info",
            version: PROTOCOL_VERSION,
            ...options.hostInfo,
        });
    }
    function sendWorkspaceList(ws, activeSessionId = options.sessionManager.getActiveSessionId()) {
        send(ws, { type: "workspace.list", workspaces: options.sessionManager.getWorkspaces(activeSessionId) });
    }
    function sendSessionHistory(ws, sessionId) {
        send(ws, { type: "message.history", sessionId, messages: options.sessionManager.getSessionHistory(sessionId) });
    }
    async function sendExternalSessionList(ws) {
        send(ws, { type: "external.session.list", sessions: await options.sessionManager.listExternalSessions() });
    }
    function sendCommandList(ws) {
        send(ws, { type: "command.list", commands: COMMAND_CATALOG });
    }
    function broadcast(message) {
        for (const [client, state] of clients) {
            if (state.authenticated && client.readyState === WebSocket.OPEN) {
                send(client, message);
            }
        }
    }
}
function decodeMessage(data) {
    const rawText = data.toString("utf8");
    let json;
    try {
        json = JSON.parse(rawText);
    }
    catch {
        throw new Error("Malformed JSON message.");
    }
    return parseClientMessage(json);
}
function send(ws, message) {
    if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(message));
    }
}
function sendError(ws, error) {
    if (error instanceof ZodError) {
        send(ws, { type: "error", code: "protocol.invalid", message: error.issues.map((issue) => issue.message).join("; ") });
        return;
    }
    send(ws, { type: "error", code: "bridge.error", message: error instanceof Error ? error.message : String(error) });
}
