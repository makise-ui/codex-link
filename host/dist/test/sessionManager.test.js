import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
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
    it("can create a new host workspace directory from the client request", async () => {
        const stateDir = await tempStateDir();
        const parent = await tempStateDir();
        const newWorkspace = path.join(parent, "created-from-phone");
        const manager = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [{ id: "default", label: "repo", path: "/repo" }],
        });
        const [session] = manager.listSessions();
        const workspace = await manager.addWorkspace(newWorkspace, session.sessionId, { create: true });
        expect(workspace.path).toBe(newWorkspace);
        expect(workspace.active).toBe(true);
        expect(manager.getWorkspaces(session.sessionId).some((item) => item.path === newWorkspace && item.active)).toBe(true);
        await manager.close();
    });
    it("persists model and reasoning effort with the session", async () => {
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
        const updated = await manager.setSessionConfig(session.sessionId, { model: "gpt-5-codex", reasoningEffort: "xhigh" });
        expect(updated.model).toBe("gpt-5-codex");
        expect(updated.reasoningEffort).toBe("xhigh");
        await manager.close();
        const restored = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [{ id: "default", label: "repo", path: "/repo" }],
        });
        expect(restored.listSessions()[0]).toEqual(expect.objectContaining({ model: "gpt-5-codex", reasoningEffort: "xhigh" }));
        await restored.close();
    });
    it("preserves model when only effort changes and clears model when requested", async () => {
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
        await manager.setSessionConfig(session.sessionId, { model: "gpt-5-codex", reasoningEffort: "medium" });
        const effortOnly = await manager.setSessionConfig(session.sessionId, { reasoningEffort: "low" });
        expect(effortOnly.model).toBe("gpt-5-codex");
        expect(effortOnly.reasoningEffort).toBe("low");
        const cleared = await manager.setSessionConfig(session.sessionId, { model: "" });
        expect(cleared.model).toBeUndefined();
        expect(cleared.reasoningEffort).toBe("low");
        await manager.close();
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
        expect(history.some((message) => message.kind === "executing" && message.text.includes("Checking the host bridge"))).toBe(true);
        expect(history.every((message) => message.kind !== "thinking")).toBe(true);
        expect(history.every((message) => message.text.trim() !== "Thinking…")).toBe(true);
        vi.useRealTimers();
    });
    it("emits file offers for uploaded workspace files and downloads them", async () => {
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
        const events = [];
        manager.onEvent((event) => {
            if (event.type === "file.offer") {
                events.push(event);
            }
        });
        const [session] = manager.listSessions();
        await manager.sendPrompt(session.sessionId, "use this file", [
            {
                name: "notes.txt",
                mimeType: "text/plain",
                dataBase64: Buffer.from("hello from phone").toString("base64"),
            },
        ]);
        const offer = events.find((event) => event.type === "file.offer");
        expect(offer).toMatchObject({ name: "notes.txt" });
        const download = await manager.downloadFile(offer.fileId);
        expect(download.dataBase64).toBe(Buffer.from("hello from phone").toString("base64"));
        await manager.close();
    });
    it("offers requested workspace files without asking the agent to paste contents", async () => {
        const stateDir = await tempStateDir();
        const workspace = await tempStateDir();
        await writeFile(path.join(workspace, "report.txt"), "download me from host");
        const manager = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [{ id: "default", label: "repo", path: workspace }],
        });
        const events = [];
        manager.onEvent((event) => {
            if (event.type === "file.offer") {
                events.push(event);
            }
        });
        const [session] = manager.listSessions();
        const offer = await manager.offerRequestedFile(session.sessionId, "report.txt");
        expect(offer).toMatchObject({ name: "report.txt", reason: "requested" });
        expect(events).toHaveLength(1);
        const download = await manager.downloadFile(offer.fileId);
        expect(Buffer.from(download.dataBase64, "base64").toString("utf8")).toBe("download me from host");
        expect(manager.getSessionHistory(session.sessionId).some((message) => message.kind === "files" && message.text.includes("requested report.txt"))).toBe(true);
        await manager.close();
    });
    it("replays saved history after a manager restart", async () => {
        vi.useFakeTimers();
        const stateDir = await tempStateDir();
        const workspace = await tempStateDir();
        const first = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [{ id: "default", label: "repo", path: workspace }],
        });
        const [session] = first.listSessions();
        await first.sendPrompt(session.sessionId, "persist this after restart");
        await vi.advanceTimersByTimeAsync(2_000);
        await first.close();
        vi.useRealTimers();
        const restarted = await CodexSessionManager.create({
            sessionMode: "mock",
            codexCommand: "codex",
            stateDir,
            defaultSandbox: "workspace-write",
            allowYolo: false,
            workspaces: [{ id: "default", label: "repo", path: workspace }],
        });
        const history = restarted.getSessionHistory(session.sessionId);
        expect(history.some((message) => message.role === "user" && message.text === "persist this after restart")).toBe(true);
        expect(history.some((message) => message.role === "assistant" && message.text.includes("Connected to the local Codex Link bridge"))).toBe(true);
        await restarted.close();
    });
});
async function tempStateDir() {
    const dir = await mkdtemp(path.join(os.tmpdir(), "codex-lan-host-"));
    await mkdir(dir, { recursive: true });
    tempDirs.push(dir);
    return dir;
}
