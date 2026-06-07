import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { SessionStore } from "../src/codex/sessionStore.js";
import type { SessionRecord, StoredChatMessage, WorkspaceRecord } from "../src/protocol/messages.js";

const tempDirs: string[] = [];

afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

describe("SessionStore", () => {
  it("serializes concurrent saves without racing on the temp file", async () => {
    const stateDir = await tempStateDir();
    const store = new SessionStore(stateDir);

    await Promise.all(
      Array.from({ length: 25 }, (_, index) =>
        store.save({
          sessions: [sessionRecord(`session-${index}`, `Session ${index}`)],
        }),
      ),
    );

    const raw = await readFile(path.join(stateDir, "sessions.json"), "utf8");
    const parsed = JSON.parse(raw) as { sessions: SessionRecord[] };
    expect(parsed.sessions).toHaveLength(1);
    expect(parsed.sessions[0]?.sessionId).toBe("session-24");
  });

  it("persists message history and dynamic workspaces", async () => {
    const stateDir = await tempStateDir();
    const store = new SessionStore(stateDir);
    const messages: Record<string, StoredChatMessage[]> = {
      "session-1": [
        {
          messageId: "user-1",
          role: "user",
          kind: "response",
          text: "hello",
          createdAt: "2026-06-07T00:00:00.000Z",
          complete: true,
        },
        {
          messageId: "cmd-1",
          role: "system",
          kind: "executing",
          title: "Running command",
          text: "pnpm test\n2 tests passed\n",
          createdAt: "2026-06-07T00:00:01.000Z",
          runId: "run-1",
          complete: true,
        },
      ],
    };
    const workspaces: WorkspaceRecord[] = [
      { workspaceId: "default", label: "repo", path: "/tmp/repo", active: false },
      { workspaceId: "workspace-2", label: "other", path: "/tmp/other", active: false },
    ];

    await store.save({ sessions: [sessionRecord("session-1", "Session 1")], messages, workspaces });

    await expect(store.load()).resolves.toEqual({
      sessions: [sessionRecord("session-1", "Session 1")],
      messages,
      workspaces,
    });
  });
});

async function tempStateDir(): Promise<string> {
  const dir = await mkdtemp(path.join(os.tmpdir(), "codex-lan-store-"));
  tempDirs.push(dir);
  return dir;
}

function sessionRecord(sessionId: string, title: string): SessionRecord {
  return {
    sessionId,
    title,
    createdAt: "2026-06-07T00:00:00.000Z",
    updatedAt: "2026-06-07T00:00:00.000Z",
    workspaceId: "default",
    workdir: "/tmp/workspace",
    lastStatus: "idle",
    mode: "safe",
    sandbox: "workspace-write",
  };
}
