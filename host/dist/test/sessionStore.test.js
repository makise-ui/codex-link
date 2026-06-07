import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { SessionStore } from "../src/codex/sessionStore.js";
const tempDirs = [];
afterEach(async () => {
    await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});
describe("SessionStore", () => {
    it("serializes concurrent saves without racing on the temp file", async () => {
        const stateDir = await tempStateDir();
        const store = new SessionStore(stateDir);
        await Promise.all(Array.from({ length: 25 }, (_, index) => store.save({
            sessions: [sessionRecord(`session-${index}`, `Session ${index}`)],
        })));
        const raw = await readFile(path.join(stateDir, "sessions.json"), "utf8");
        const parsed = JSON.parse(raw);
        expect(parsed.sessions).toHaveLength(1);
        expect(parsed.sessions[0]?.sessionId).toBe("session-24");
    });
});
async function tempStateDir() {
    const dir = await mkdtemp(path.join(os.tmpdir(), "codex-lan-store-"));
    tempDirs.push(dir);
    return dir;
}
function sessionRecord(sessionId, title) {
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
