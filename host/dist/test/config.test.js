import { describe, expect, it } from "vitest";
import { resolveConfig } from "../src/config.js";
describe("resolveConfig", () => {
    it("parses flags passed through pnpm with a literal -- separator", () => {
        const config = resolveConfig([
            "node",
            "src/index.ts",
            "--",
            "--pair",
            "--insecure-ws-dev",
            "--session-mode",
            "cli",
            "--codex-command",
            "codex",
            "--workdir",
            ".",
            "--workspace",
            "/tmp/other-project",
            "--sandbox",
            "workspace-write",
        ]);
        expect(config.pair).toBe(true);
        expect(config.insecureWsDev).toBe(true);
        expect(config.sessionMode).toBe("cli");
        expect(config.codexCommand).toBe("codex");
        expect(config.sandbox).toBe("workspace-write");
        expect(config.workspaces).toHaveLength(2);
    });
    it("supports explicit yolo host opt-in", () => {
        const config = resolveConfig(["node", "src/index.ts", "--insecure-ws-dev", "--allow-yolo"]);
        expect(config.allowYolo).toBe(true);
        expect(config.sandbox).toBe("workspace-write");
    });
    it("parses tunnel remote mode with public url and provider", () => {
        const config = resolveConfig([
            "node",
            "src/index.ts",
            "--insecure-ws-dev",
            "--remote-mode",
            "tunnel",
            "--public-url",
            "wss://unit.trycloudflare.com",
            "--tunnel-provider",
            "cloudflared",
            "--password",
            "secret",
        ]);
        expect(config.remoteMode).toBe("tunnel");
        expect(config.publicUrl).toBe("wss://unit.trycloudflare.com");
        expect(config.tunnelProvider).toBe("cloudflared");
    });
    it("allows cloudflared auto tunnel mode without a manual public url", () => {
        const config = resolveConfig([
            "node",
            "src/index.ts",
            "--insecure-ws-dev",
            "--remote-mode",
            "tunnel",
            "--cloudflared-auto",
            "--password",
            "secret",
        ]);
        expect(config.remoteMode).toBe("tunnel");
        expect(config.tunnelProvider).toBe("cloudflared");
        expect(config.cloudflaredAuto).toBe(true);
        expect(config.publicUrl).toBeUndefined();
    });
    it("requires password in tunnel mode", () => {
        expect(() => resolveConfig([
            "node",
            "src/index.ts",
            "--insecure-ws-dev",
            "--remote-mode",
            "tunnel",
            "--public-url",
            "wss://unit.trycloudflare.com",
        ])).toThrow(/--password/);
    });
    it("requires public url in tunnel mode", () => {
        expect(() => resolveConfig([
            "node",
            "src/index.ts",
            "--insecure-ws-dev",
            "--remote-mode",
            "tunnel",
            "--password",
            "secret",
        ])).toThrow(/--public-url/);
    });
    it("does not require a public url when cloudflared auto mode is enabled", () => {
        expect(() => resolveConfig([
            "node",
            "src/index.ts",
            "--insecure-ws-dev",
            "--remote-mode",
            "tunnel",
            "--cloudflared-auto",
            "--password",
            "secret",
        ])).not.toThrow();
    });
    it("still requires explicit insecure dev mode", () => {
        expect(() => resolveConfig(["node", "src/index.ts", "--pair"])).toThrow(/--insecure-ws-dev/);
    });
});
