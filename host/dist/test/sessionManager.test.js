import { mkdir, mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { CodexSessionManager } from "../src/codex/sessionManager.js";
const tempDirs = [];
afterEach(async () => {
    await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});
describe("CodexSessionManager", () => {
    it("creates a default persistent session and supports workspace switching", async () => {
        const stateDir = await tempStateDir();
        const manager = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [
                { id: "default", label: "repo", path: "/repo" },
                { id: "workspace-2", label: "other", path: "/other" },
            ],
        });
        const [initial] = manager.listSessions();
        expect(initial.workspaceId).toBe("default");
        expect(initial.sandbox).toBe("workspace-write");
        const updated = await manager.switchWorkspace(initial.sessionId, "workspace-2");
        expect(updated.workspaceId).toBe("workspace-2");
        expect(updated.workdir).toBe("/other");
        expect(updated.codexThreadId).toBeUndefined();
        await manager.close();
    });
    it("requires explicit host permission for yolo mode", async () => {
        const stateDir = await tempStateDir();
        const manager = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [{ id: "default", label: "repo", path: "/repo" }],
        });
        const [session] = manager.listSessions();
        await expect(manager.setSessionMode(session.sessionId, "yolo")).rejects.toThrow(/--allow-yolo/);
        await manager.close();
    });
    it("maps yolo to danger-full-access when allowed", async () => {
        const stateDir = await tempStateDir();
        const manager = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: true,
            workspaces: [{ id: "default", label: "repo", path: "/repo" }],
        });
        const [session] = manager.listSessions();
        const updated = await manager.setSessionMode(session.sessionId, "yolo");
        expect(updated.mode).toBe("yolo");
        expect(updated.sandbox).toBe("danger-full-access");
        await manager.close();
    });
    it("adds a host workspace path and persists it", async () => {
        const stateDir = await tempStateDir();
        const extraWorkspace = await tempStateDir();
        const manager = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [{ id: "default", label: "repo", path: "/repo" }],
        });
        const [session] = manager.listSessions();
        const workspace = await manager.addWorkspace(extraWorkspace, session.sessionId);
        expect(workspace.path).toBe(extraWorkspace);
        expect(manager.getWorkspaces(session.sessionId).some((item) => item.path === extraWorkspace && item.active)).toBe(true);
        await manager.close();
        const restored = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [{ id: "default", label: "repo", path: "/repo" }],
        });
        expect(restored.getWorkspaces().some((item) => item.path === extraWorkspace)).toBe(true);
        await restored.close();
    });
    it("stores user prompts and streamed agent messages as replayable history", async () => {
        vi.useFakeTimers();
        const stateDir = await tempStateDir();
        const workspace = await tempStateDir();
        const manager = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [{ id: "default", label: "repo", path: workspace }],
        });
        const [session] = manager.listSessions();
        await manager.sendPrompt(session.sessionId, "hello history");
        await vi.advanceTimersByTimeAsync(2_000);
        await manager.close();
        const history = manager.getSessionHistory(session.sessionId);
        expect(history.some((message) => message.role === "user" && message.text === "hello history")).toBe(true);
        expect(history.some((message) => message.kind === "executing" && message.text.includes("Checking the LAN bridge"))).toBe(true);
        expect(history.every((message) => message.kind !== "thinking")).toBe(true);
        vi.useRealTimers();
    });
});
async function tempStateDir() {
    const dir = await mkdtemp(path.join(os.tmpdir(), "codex-lan-host-"));
    await mkdir(dir, { recursive: true });
    tempDirs.push(dir);
    return dir;
}
