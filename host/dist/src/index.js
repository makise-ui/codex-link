import pino from "pino";
import { PairingStore } from "./auth/pairingStore.js";
import { CodexSessionManager } from "./codex/sessionManager.js";
import { resolveConfig } from "./config.js";
import { startBridgeServer } from "./server/websocketServer.js";
import { AuditLog } from "./safety/auditLog.js";
import { startCloudflaredQuickTunnel } from "./tunnel/cloudflaredTunnel.js";
import { printPairingPayload } from "./util/qr.js";
const logger = pino({
    level: process.env.LOG_LEVEL ?? "info",
    transport: process.stdout.isTTY ? { target: "pino/file", options: { destination: 1 } } : undefined,
});
let server;
let cloudflaredTunnel;
try {
    const config = resolveConfig();
    let url = config.publicUrl ?? config.localUrl;
    const pairingStore = new PairingStore({ password: config.password });
    const auditLog = new AuditLog(logger);
    const sessionManager = await CodexSessionManager.create({
        sessionMode: config.sessionMode,
        codexCommand: config.codexCommand,
        workspaces: config.workspaces,
        stateDir: config.stateDir,
        defaultSandbox: config.sandbox,
        allowYolo: config.allowYolo,
    });
    if (config.remoteMode === "tunnel") {
        console.warn("\nREMOTE TUNNEL MODE: keep the host bound locally/private and expose it through your tunnel provider.");
        if (config.publicUrl) {
            console.warn("Tunnel public URL:", config.publicUrl);
        }
        if (config.cloudflaredAuto) {
            console.warn("Cloudflared auto tunnel is enabled; generating the public URL after the local bridge starts.");
        }
        console.warn("Tunnel provider:", config.tunnelProvider);
    }
    else {
        console.warn("\nDEV-ONLY LAN MODE: this bridge uses cleartext ws://. Use only on a trusted local network.");
        console.warn("Do not expose this port to the public internet or a VPS.");
    }
    console.log(`Workspaces: ${config.workspaces.map((workspace) => `${workspace.label}=${workspace.path}`).join(", ")}`);
    console.log(`Session state: ${config.stateDir}`);
    console.log(`Default sandbox: ${config.sandbox}`);
    if (config.allowYolo) {
        console.warn("⚠️  YOLO ENABLED: paired devices can switch sessions to danger-full-access. Use only on a trusted LAN and trusted workspace.\n");
    }
    else {
        console.warn("Yolo mode is disabled. Start with --allow-yolo only if you intentionally want danger-full-access from the app.\n");
    }
    const hostInfo = {
        connectionMode: config.remoteMode,
        tunnelProvider: config.remoteMode === "tunnel" ? config.tunnelProvider : undefined,
        publicUrl: config.publicUrl,
        localUrl: config.localUrl,
        hostLabel: "Codex Link",
        yoloAllowed: config.allowYolo,
    };
    server = await startBridgeServer({
        host: config.host,
        port: config.port,
        url,
        pairingStore,
        sessionManager,
        auditLog,
        logger,
        hostInfo,
    });
    console.log(`\nCodex Link host bridge listening at ${config.localUrl}`);
    console.log("Health check:", `${config.localUrl.replace("ws://", "http://")}/health`);
    if (config.cloudflaredAuto) {
        const originUrl = config.localUrl.replace("ws://", "http://");
        console.log(`\nStarting cloudflared quick tunnel for ${originUrl}...`);
        cloudflaredTunnel = await startCloudflaredQuickTunnel({
            command: config.cloudflaredCommand,
            originUrl,
            onLog: (line) => {
                if (line.includes("trycloudflare.com") || line.includes("ERR")) {
                    console.log(`[cloudflared] ${line}`);
                }
            },
        });
        url = cloudflaredTunnel.publicWebSocketUrl;
        hostInfo.publicUrl = url;
        console.log(`Cloudflared public tunnel URL: ${url}`);
    }
    else if (config.publicUrl) {
        console.log(`Public tunnel URL: ${config.publicUrl}`);
    }
    if (config.pair) {
        const payload = pairingStore.createPairingPayload({
            url,
            localUrl: config.localUrl,
            insecureDevMode: url.startsWith("wss://") ? false : config.insecureWsDev,
            connectionMode: config.remoteMode,
            tunnelProvider: config.remoteMode === "tunnel" ? config.tunnelProvider : undefined,
        });
        auditLog.record({ type: "pairing.created" });
        printPairingPayload(payload);
    }
    else {
        console.log("Pairing is disabled. Start with --pair to create a one-time Android/Flutter pairing token.");
    }
    if (config.password) {
        console.log("Password login is enabled for this Codex Link bridge.");
    }
    const shutdown = async () => {
        console.log("\nShutting down Codex Link host bridge...");
        await server?.close();
        await cloudflaredTunnel?.close();
        process.exit(0);
    };
    process.once("SIGINT", () => void shutdown());
    process.once("SIGTERM", () => void shutdown());
}
catch (error) {
    await cloudflaredTunnel?.close().catch(() => { });
    await server?.close().catch(() => { });
    logger.error({ error }, "Failed to start Codex Link host bridge");
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
}
