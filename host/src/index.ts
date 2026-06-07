import pino from "pino";
import { PairingStore } from "./auth/pairingStore.js";
import { CodexSessionManager } from "./codex/sessionManager.js";
import { resolveConfig } from "./config.js";
import { startBridgeServer } from "./server/websocketServer.js";
import { AuditLog } from "./safety/auditLog.js";
import { printPairingPayload } from "./util/qr.js";

const logger = pino({
  level: process.env.LOG_LEVEL ?? "info",
  transport: process.stdout.isTTY ? { target: "pino/file", options: { destination: 1 } } : undefined,
});

try {
  const config = resolveConfig();
  const url = `ws://${config.host}:${config.port}`;
  const pairingStore = new PairingStore();
  const auditLog = new AuditLog(logger);
  const sessionManager = await CodexSessionManager.create({
    sessionMode: config.sessionMode,
    codexCommand: config.codexCommand,
    workspaces: config.workspaces,
    stateDir: config.stateDir,
    defaultSandbox: config.sandbox,
    allowYolo: config.allowYolo,
  });

  console.warn("\n⚠️  DEV-ONLY LAN MODE: this bridge uses cleartext ws://. Use only on a trusted local network.");
  console.warn("⚠️  Do not expose this port to the public internet or a VPS.");
  console.log(`Workspaces: ${config.workspaces.map((workspace) => `${workspace.label}=${workspace.path}`).join(", ")}`);
  console.log(`Session state: ${config.stateDir}`);
  console.log(`Default sandbox: ${config.sandbox}`);
  if (config.allowYolo) {
    console.warn("⚠️  YOLO ENABLED: paired devices can switch sessions to danger-full-access. Use only on a trusted LAN and trusted workspace.\n");
  } else {
    console.warn("Yolo mode is disabled. Start with --allow-yolo only if you intentionally want danger-full-access from the app.\n");
  }

  if (config.pair) {
    const payload = pairingStore.createPairingPayload(url, config.insecureWsDev);
    auditLog.record({ type: "pairing.created" });
    printPairingPayload(payload);
  } else {
    console.log("Pairing is disabled. Start with --pair to create a one-time Android/Flutter pairing token.");
  }

  const server = await startBridgeServer({
    host: config.host,
    port: config.port,
    url,
    pairingStore,
    sessionManager,
    auditLog,
    logger,
  });

  console.log(`\nCodex LAN host bridge listening at ${url}`);
  console.log("Health check:", `${url.replace("ws://", "http://")}/health`);

  const shutdown = async () => {
    console.log("\nShutting down Codex LAN host bridge...");
    await server.close();
    process.exit(0);
  };

  process.once("SIGINT", () => void shutdown());
  process.once("SIGTERM", () => void shutdown());
} catch (error) {
  logger.error({ error }, "Failed to start Codex LAN host bridge");
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
