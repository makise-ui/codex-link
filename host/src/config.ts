import { Command } from "commander";
import path from "node:path";
import { findLanAddress } from "./util/lanAddress.js";

export type SessionMode = "mock" | "cli";
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
export type RemoteMode = "lan" | "tunnel";
export type TunnelProvider = "ngrok" | "cloudflared" | "tailscale" | "other";

export type WorkspaceConfig = {
  id: string;
  label: string;
  path: string;
};

export type HostConfig = {
  host: string;
  port: number;
  pair: boolean;
  insecureWsDev: boolean;
  sessionMode: SessionMode;
  codexCommand: string;
  workdir: string;
  stateDir: string;
  sandbox: SandboxMode;
  allowYolo: boolean;
  remoteMode: RemoteMode;
  publicUrl?: string;
  tunnelProvider: TunnelProvider;
  localUrl: string;
  workspaces: WorkspaceConfig[];
  password?: string;
};

export function resolveConfig(argv = process.argv): HostConfig {
  const program = new Command();
  program
    .name("codex-link-host")
    .description("Local/tunnel host bridge for the Codex Link Flutter controller")
    .option("--host <ip>", "LAN IP to bind. Defaults to detected LAN IP in pairing mode, otherwise 127.0.0.1")
    .option("--port <port>", "port to bind", parsePort, 8787)
    .option("--pair", "create a new one-time pairing token and print a QR/manual payload", false)
    .option("--insecure-ws-dev", "explicitly allow dev-only cleartext ws:// mode", false)
    .option("--session-mode <mode>", "session adapter: mock or cli", parseSessionMode, "mock")
    .option("--codex-command <command>", "Codex CLI executable for --session-mode cli", "codex")
    .option("--workdir <path>", "default allowed working directory for Codex sessions", process.cwd())
    .option("--workspace <path>", "additional switchable workspace path. Can be provided multiple times", collectWorkspace, [] as string[])
    .option("--state-dir <path>", "directory for LAN bridge session state", ".codex-lan")
    .option("--sandbox <mode>", "Codex sandbox: read-only, workspace-write, or danger-full-access", parseSandboxMode, "workspace-write")
    .option("--allow-yolo", "allow paired clients to switch a session to danger-full-access/yolo mode", false)
    .option("--remote-mode <mode>", "remote access mode: lan or tunnel", parseRemoteMode, "lan")
    .option("--public-url <url>", "public tunnel WebSocket URL, for example wss://name.trycloudflare.com")
    .option("--tunnel-provider <provider>", "tunnel provider: ngrok, cloudflared, tailscale, or other", parseTunnelProvider, "other")
    .option("--password <password>", "optional host password for app login; can also use CODEX_LINK_PASSWORD or CODEX_LAN_PASSWORD");

  program.parse(stripPnpmSeparator(argv));
  const opts = program.opts<{
    host?: string;
    port: number;
    pair: boolean;
    insecureWsDev: boolean;
    sessionMode: SessionMode;
    codexCommand: string;
    workdir: string;
    workspace: string[];
    stateDir: string;
    sandbox: SandboxMode;
    allowYolo: boolean;
    remoteMode: RemoteMode;
    publicUrl?: string;
    tunnelProvider: TunnelProvider;
    password?: string;
  }>();

  if (!opts.insecureWsDev) {
    throw new Error("This prototype currently supports cleartext ws:// only. Re-run with --insecure-ws-dev for trusted LAN testing.");
  }

  const host = opts.host ?? (opts.pair ? findLanAddress() ?? "127.0.0.1" : "127.0.0.1");
  const workdir = path.resolve(opts.workdir);
  const stateDir = path.resolve(workdir, opts.stateDir);
  const workspacePaths = uniquePaths([workdir, ...opts.workspace.map((workspace) => path.resolve(workspace))]);
  const localUrl = `ws://${host}:${opts.port}`;
  const password = opts.password ?? process.env.CODEX_LINK_PASSWORD ?? process.env.CODEX_LAN_PASSWORD;
  const publicUrl = opts.publicUrl?.trim();

  if (opts.remoteMode === "tunnel") {
    if (!password) {
      throw new Error("--password or CODEX_LINK_PASSWORD is required when --remote-mode tunnel is used.");
    }
    if (!publicUrl) {
      throw new Error("--public-url is required when --remote-mode tunnel is used.");
    }
    validatePublicUrl(publicUrl);
  }

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
    remoteMode: opts.remoteMode,
    publicUrl,
    tunnelProvider: opts.tunnelProvider,
    localUrl,
    password,
    workspaces: workspacePaths.map((workspacePath, index) => ({
      id: index === 0 ? "default" : `workspace-${index + 1}`,
      label: path.basename(workspacePath) || workspacePath,
      path: workspacePath,
    })),
  };
}

function stripPnpmSeparator(argv: string[]): string[] {
  if (argv[2] === "--") {
    return [argv[0], argv[1], ...argv.slice(3)];
  }
  return argv;
}

function parsePort(value: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 65_535) {
    throw new Error(`Invalid port: ${value}`);
  }
  return parsed;
}

function parseSessionMode(value: string): SessionMode {
  if (value === "mock" || value === "cli") return value;
  throw new Error(`Invalid session mode: ${value}. Expected mock or cli.`);
}

function parseSandboxMode(value: string): SandboxMode {
  if (value === "read-only" || value === "workspace-write" || value === "danger-full-access") return value;
  throw new Error(`Invalid sandbox: ${value}. Expected read-only, workspace-write, or danger-full-access.`);
}

function parseRemoteMode(value: string): RemoteMode {
  if (value === "lan" || value === "tunnel") return value;
  throw new Error(`Invalid remote mode: ${value}. Expected lan or tunnel.`);
}

function parseTunnelProvider(value: string): TunnelProvider {
  if (value === "ngrok" || value === "cloudflared" || value === "tailscale" || value === "other") return value;
  throw new Error(`Invalid tunnel provider: ${value}. Expected ngrok, cloudflared, tailscale, or other.`);
}

function validatePublicUrl(value: string): void {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error(`Invalid --public-url: ${value}`);
  }
  if (parsed.protocol !== "ws:" && parsed.protocol !== "wss:") {
    throw new Error("--public-url must use ws:// or wss://.");
  }
  const localhost = parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1" || parsed.hostname === "::1";
  if (parsed.protocol !== "wss:" && !localhost) {
    throw new Error("--public-url must use wss:// for tunnel mode.");
  }
}

function collectWorkspace(value: string, previous: string[]): string[] {
  return [...previous, value];
}

function uniquePaths(paths: string[]): string[] {
  const seen = new Set<string>();
  const unique: string[] = [];
  for (const candidate of paths) {
    const resolved = path.resolve(candidate);
    if (seen.has(resolved)) continue;
    seen.add(resolved);
    unique.push(resolved);
  }
  return unique;
}
