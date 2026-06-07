import { spawn } from "node:child_process";
const QUICK_TUNNEL_URL_PATTERN = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/iu;
export async function startCloudflaredQuickTunnel(options) {
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
export function extractCloudflaredQuickTunnelUrl(output) {
    return output.match(QUICK_TUNNEL_URL_PATTERN)?.[0];
}
export function toWebSocketTunnelUrl(url) {
    if (url.startsWith("https://"))
        return `wss://${url.slice("https://".length)}`;
    if (url.startsWith("http://"))
        return `ws://${url.slice("http://".length)}`;
    return url;
}
async function waitForQuickTunnelUrl(child, options) {
    const timeoutMs = options.timeoutMs ?? 30_000;
    let output = "";
    return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
            void stopProcess(child);
            reject(new Error(`Timed out waiting for cloudflared quick tunnel URL after ${timeoutMs}ms.`));
        }, timeoutMs);
        const finish = (value) => {
            clearTimeout(timeout);
            cleanup();
            resolve(value);
        };
        const fail = (error) => {
            clearTimeout(timeout);
            cleanup();
            reject(error);
        };
        const onData = (chunk) => {
            const text = chunk.toString("utf8");
            output += text;
            for (const line of text.split(/\r?\n/)) {
                const trimmed = line.trim();
                if (trimmed)
                    options.onLog?.(trimmed);
            }
            const url = extractCloudflaredQuickTunnelUrl(output);
            if (url)
                finish(url);
        };
        const onError = (error) => {
            fail(new Error(`Failed to start cloudflared: ${error.message}`));
        };
        const onExit = (code, signal) => {
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
async function stopProcess(child) {
    if (child.exitCode !== null || child.signalCode !== null)
        return;
    child.kill("SIGTERM");
    await new Promise((resolve) => {
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
