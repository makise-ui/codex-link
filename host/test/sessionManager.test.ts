import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { CodexSessionManager } from "../src/codex/sessionManager.js";

const tempDirs: string[] = [];

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
});

async function tempStateDir(): Promise<string> {
  const dir = await mkdtemp(path.join(os.tmpdir(), "codex-lan-host-"));
  tempDirs.push(dir);
  return dir;
}
