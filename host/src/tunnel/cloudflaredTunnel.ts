import { spawn, type ChildProcessByStdio } from "node:child_process";
import type { Readable } from "node:stream";

type CloudflaredProcess = ChildProcessByStdio<null, Readable, Readable>;

export type CloudflaredQuickTunnel = {
  publicHttpUrl: string;
  publicWebSocketUrl: string;
  close(): Promise<void>;
};

export type StartCloudflaredQuickTunnelOptions = {
  command: string;
  originUrl: string;
  timeoutMs?: number;
  onLog?: (line: string) => void;
};

const QUICK_TUNNEL_URL_PATTERN = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/iu;

export async function startCloudflaredQuickTunnel(options: StartCloudflaredQuickTunnelOptions): Promise<CloudflaredQuickTunnel> {
  const child = spawn(options.command, ["tunnel", "--url", options.originUrl], {
    stdio: ["ignore", "pipe", "pipe"],
  });
  const publicHttpUrl = await waitForQuickTunnelUrl(child, options);
  return {
    publicHttpUrl,
    publicWebSocketUrl: toWebSocketTunnelUrl(publicHttpUrl),
    close: () => stopProcess(child),
  };
}

export function extractCloudflaredQuickTunnelUrl(output: string): string | undefined {
  return output.match(QUICK_TUNNEL_URL_PATTERN)?.[0];
}

export function toWebSocketTunnelUrl(url: string): string {
  if (url.startsWith("https://")) return `wss://${url.slice("https://".length)}`;
  if (url.startsWith("http://")) return `ws://${url.slice("http://".length)}`;
  return url;
}

async function waitForQuickTunnelUrl(child: CloudflaredProcess, options: StartCloudflaredQuickTunnelOptions): Promise<string> {
  const timeoutMs = options.timeoutMs ?? 30_000;
  let output = "";

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      void stopProcess(child);
      reject(new Error(`Timed out waiting for cloudflared quick tunnel URL after ${timeoutMs}ms.`));
    }, timeoutMs);

    const finish = (value: string) => {
      clearTimeout(timeout);
      cleanup();
      resolve(value);
    };

    const fail = (error: Error) => {
      clearTimeout(timeout);
      cleanup();
      reject(error);
    };

    const onData = (chunk: Buffer) => {
      const text = chunk.toString("utf8");
      output += text;
      for (const line of text.split(/\r?\n/)) {
        const trimmed = line.trim();
        if (trimmed) options.onLog?.(trimmed);
      }
      const url = extractCloudflaredQuickTunnelUrl(output);
      if (url) finish(url);
    };

    const onError = (error: Error) => {
      fail(new Error(`Failed to start cloudflared: ${error.message}`));
    };

    const onExit = (code: number | null, signal: NodeJS.Signals | null) => {
      fail(new Error(`cloudflared exited before a quick tunnel URL was generated: exit=${code ?? signal ?? "unknown"}\n${output.trim()}`));
    };

    const cleanup = () => {
      child.stdout.off("data", onData);
      child.stderr.off("data", onData);
      child.off("error", onError);
      child.off("exit", onExit);
    };

    child.stdout.on("data", onData);
    child.stderr.on("data", onData);
    child.once("error", onError);
    child.once("exit", onExit);
  });
}

async function stopProcess(child: CloudflaredProcess): Promise<void> {
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill("SIGTERM");
  await new Promise<void>((resolve) => {
    const timeout = setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill("SIGKILL");
      }
      resolve();
    }, 2_000);
    child.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });
  });
}
