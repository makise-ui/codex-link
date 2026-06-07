import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
export class SessionStore {
    stateDir;
    filePath;
    saveQueue = Promise.resolve();
    constructor(stateDir) {
        this.stateDir = stateDir;
        this.filePath = path.join(stateDir, "sessions.json");
    }
    async load() {
        try {
            const raw = await readFile(this.filePath, "utf8");
            const parsed = JSON.parse(raw);
            if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.sessions)) {
                return { sessions: [] };
            }
            return {
                sessions: parsed.sessions.flatMap((candidate) => (isSessionRecord(candidate) ? [candidate] : [])),
            };
        }
        catch (error) {
            if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") {
                return { sessions: [] };
            }
            throw error;
        }
    }
    async save(snapshot) {
        const frozenSnapshot = {
            sessions: snapshot.sessions.map((session) => ({ ...session })),
        };
        const writeOperation = this.saveQueue.then(() => this.writeSnapshot(frozenSnapshot));
        this.saveQueue = writeOperation.catch(() => undefined);
        return writeOperation;
    }
    async writeSnapshot(snapshot) {
        await mkdir(this.stateDir, { recursive: true });
        const payload = `${JSON.stringify({ sessions: snapshot.sessions }, null, 2)}\n`;
        const tempPath = path.join(this.stateDir, `sessions.${process.pid}.${randomUUID()}.tmp`);
        await writeFile(tempPath, payload, "utf8");
        await rename(tempPath, this.filePath);
    }
}
function isSessionRecord(value) {
    if (!value || typeof value !== "object")
        return false;
    const record = value;
    return (typeof record.sessionId === "string" &&
        typeof record.title === "string" &&
        typeof record.createdAt === "string" &&
        typeof record.updatedAt === "string" &&
        typeof record.workspaceId === "string" &&
        typeof record.workdir === "string" &&
        typeof record.lastStatus === "string" &&
        (record.mode === "safe" || record.mode === "yolo") &&
        (record.sandbox === "read-only" || record.sandbox === "workspace-write" || record.sandbox === "danger-full-access"));
}
