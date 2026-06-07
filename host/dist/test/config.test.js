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
    it("still requires explicit insecure dev mode", () => {
        expect(() => resolveConfig(["node", "src/index.ts", "--pair"])).toThrow(/--insecure-ws-dev/);
    });
});
