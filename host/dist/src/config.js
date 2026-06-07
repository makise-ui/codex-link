import { Command } from "commander";
import path from "node:path";
import { findLanAddress } from "./util/lanAddress.js";
export function resolveConfig(argv = process.argv) {
    const program = new Command();
    program
        .name("codex-lan-host")
        .description("Local-network host bridge for the Codex Android/Flutter companion prototype")
        .option("--host <ip>", "LAN IP to bind. Defaults to detected LAN IP in pairing mode, otherwise 127.0.0.1")
        .option("--port <port>", "port to bind", parsePort, 8787)
        .option("--pair", "create a new one-time pairing token and print a QR/manual payload", false)
        .option("--insecure-ws-dev", "explicitly allow dev-only cleartext ws:// mode", false)
        .option("--session-mode <mode>", "session adapter: mock or cli", parseSessionMode, "mock")
        .option("--codex-command <command>", "Codex CLI executable for --session-mode cli", "codex")
        .option("--workdir <path>", "default allowed working directory for Codex sessions", process.cwd())
        .option("--workspace <path>", "additional switchable workspace path. Can be provided multiple times", collectWorkspace, [])
        .option("--state-dir <path>", "directory for LAN bridge session state", ".codex-lan")
        .option("--sandbox <mode>", "Codex sandbox: read-only, workspace-write, or danger-full-access", parseSandboxMode, "workspace-write")
        .option("--allow-yolo", "allow paired clients to switch a session to danger-full-access/yolo mode", false);
    program.parse(stripPnpmSeparator(argv));
    const opts = program.opts();
    if (!opts.insecureWsDev) {
        throw new Error("This prototype currently supports cleartext ws:// only. Re-run with --insecure-ws-dev for trusted LAN testing.");
    }
    const host = opts.host ?? (opts.pair ? findLanAddress() ?? "127.0.0.1" : "127.0.0.1");
    const workdir = path.resolve(opts.workdir);
    const stateDir = path.resolve(workdir, opts.stateDir);
    const workspacePaths = uniquePaths([workdir, ...opts.workspace.map((workspace) => path.resolve(workspace))]);
    return {
        host,
        port: opts.port,
        pair: opts.pair,
        insecureWsDev: opts.insecureWsDev,
        sessionMode: opts.sessionMode,
        codexCommand: opts.codexCommand,
        workdir,
        stateDir,
        sandbox: opts.sandbox,
        allowYolo: opts.allowYolo || opts.sandbox === "danger-full-access",
        workspaces: workspacePaths.map((workspacePath, index) => ({
            id: index === 0 ? "default" : `workspace-${index + 1}`,
            label: path.basename(workspacePath) || workspacePath,
            path: workspacePath,
        })),
    };
}
function stripPnpmSeparator(argv) {
    if (argv[2] === "--") {
        return [argv[0], argv[1], ...argv.slice(3)];
    }
    return argv;
}
function parsePort(value) {
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 65_535) {
        throw new Error(`Invalid port: ${value}`);
    }
    return parsed;
}
function parseSessionMode(value) {
    if (value === "mock" || value === "cli")
        return value;
    throw new Error(`Invalid session mode: ${value}. Expected mock or cli.`);
}
function parseSandboxMode(value) {
    if (value === "read-only" || value === "workspace-write" || value === "danger-full-access")
        return value;
    throw new Error(`Invalid sandbox: ${value}. Expected read-only, workspace-write, or danger-full-access.`);
}
function collectWorkspace(value, previous) {
    return [...previous, value];
}
function uniquePaths(paths) {
    const seen = new Set();
    const unique = [];
    for (const candidate of paths) {
        const resolved = path.resolve(candidate);
        if (seen.has(resolved))
            continue;
        seen.add(resolved);
        unique.push(resolved);
    }
    return unique;
}
