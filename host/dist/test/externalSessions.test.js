import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { listExternalSessions } from "../src/codex/externalSessions.js";
const tempDirs = [];
afterEach(async () => {
    await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});
describe("external Codex sessions", () => {
    it("lists Codex JSONL session metadata with a usable title", async () => {
        const root = await tempStateDir();
        const sessionDir = path.join(root, "2026", "06", "07");
        await mkdir(sessionDir, { recursive: true });
        const filePath = path.join(sessionDir, "rollout-2026-06-07T16-13-59-019ea1ae-ac01-7123-8247-f3f94f79383d.jsonl");
        await writeFile(filePath, [
            JSON.stringify({
                timestamp: "2026-06-07T10:43:59.617Z",
                type: "session_meta",
                payload: {
                    id: "019ea1ae-ac01-7123-8247-f3f94f79383d",
                    cwd: "/tmp/codex-json-probe",
                    timestamp: "2026-06-07T10:43:59.617Z",
                    originator: "codex_exec",
                },
            }),
            JSON.stringify({
                timestamp: "2026-06-07T10:44:05.561Z",
                type: "event_msg",
                payload: { type: "user_message", message: "Create notes.txt" },
            }),
        ].join("\n"), "utf8");
        const sessions = await listExternalSessions({ root, limit: 10 });
        expect(sessions).toHaveLength(1);
        expect(sessions[0]).toEqual(expect.objectContaining({
            externalSessionId: "019ea1ae-ac01-7123-8247-f3f94f79383d",
            title: "Create notes.txt",
            createdAt: "2026-06-07T10:43:59.617Z",
            workdir: "/tmp/codex-json-probe",
            codexThreadId: "019ea1ae-ac01-7123-8247-f3f94f79383d",
            path: filePath,
        }));
        expect(sessions[0]?.updatedAt).toBeTruthy();
    });
    it("skips malformed session files without hiding valid external sessions", async () => {
        const root = await tempStateDir();
        const sessionDir = path.join(root, "2026", "06", "07");
        await mkdir(sessionDir, { recursive: true });
        await writeFile(path.join(sessionDir, "bad.jsonl"), "{not-json}\n", "utf8");
        const goodPath = path.join(sessionDir, "good.jsonl");
        await writeFile(goodPath, JSON.stringify({
            timestamp: "2026-06-07T10:43:59.617Z",
            type: "session_meta",
            payload: {
                id: "good-thread",
                cwd: "/tmp/good",
                timestamp: "2026-06-07T10:43:59.617Z",
            },
        }), "utf8");
        const sessions = await listExternalSessions({ root, limit: 10 });
        expect(sessions).toHaveLength(1);
        expect(sessions[0]).toEqual(expect.objectContaining({ externalSessionId: "good-thread", path: goodPath }));
    });
    it("skips environment context records when choosing external session titles", async () => {
        const root = await tempStateDir();
        const sessionDir = path.join(root, "2026", "06", "07");
        await mkdir(sessionDir, { recursive: true });
        const filePath = path.join(sessionDir, "context-title.jsonl");
        await writeFile(filePath, [
            JSON.stringify({
                timestamp: "2026-06-07T10:43:59.617Z",
                type: "session_meta",
                payload: {
                    id: "context-thread",
                    cwd: "/home/kurisu/project",
                    timestamp: "2026-06-07T10:43:59.617Z",
                },
            }),
            JSON.stringify({
                timestamp: "2026-06-07T10:44:00.000Z",
                type: "event_msg",
                payload: { type: "user_message", message: "<environment_context>\n<cwd>/home/kurisu/project</cwd>\n</environment_context>" },
            }),
            JSON.stringify({
                timestamp: "2026-06-07T10:44:05.000Z",
                type: "event_msg",
                payload: { type: "user_message", message: "Fix the chat UI polish" },
            }),
        ].join("\n"), "utf8");
        const sessions = await listExternalSessions({ root, limit: 10 });
        expect(sessions[0]?.title).toBe("Fix the chat UI polish");
    });
});
async function tempStateDir() {
    const dir = await mkdtemp(path.join(os.tmpdir(), "codex-external-sessions-"));
    tempDirs.push(dir);
    return dir;
}
