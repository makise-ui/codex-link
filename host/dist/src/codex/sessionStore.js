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
                return emptySnapshot();
            }
            const record = parsed;
            return {
                sessions: record.sessions.flatMap((candidate) => (isSessionRecord(candidate) ? [candidate] : [])),
                messages: parseMessageMap(record.messages),
                workspaces: Array.isArray(record.workspaces) ? record.workspaces.flatMap((candidate) => (isWorkspaceRecord(candidate) ? [candidate] : [])) : [],
            };
        }
        catch (error) {
            if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") {
                return emptySnapshot();
            }
            throw error;
        }
    }
    async save(snapshot) {
        const frozenSnapshot = {
            sessions: snapshot.sessions.map((session) => ({ ...session })),
            messages: Object.fromEntries(Object.entries(snapshot.messages ?? {}).map(([sessionId, messages]) => [sessionId, messages.map((message) => ({ ...message }))])),
            workspaces: (snapshot.workspaces ?? []).map((workspace) => ({ ...workspace, active: false })),
        };
        const writeOperation = this.saveQueue.then(() => this.writeSnapshot(frozenSnapshot));
        this.saveQueue = writeOperation.catch(() => undefined);
        return writeOperation;
    }
    async writeSnapshot(snapshot) {
        await mkdir(this.stateDir, { recursive: true });
        const payload = `${JSON.stringify({ sessions: snapshot.sessions, messages: snapshot.messages, workspaces: snapshot.workspaces }, null, 2)}\n`;
        const tempPath = path.join(this.stateDir, `sessions.${process.pid}.${randomUUID()}.tmp`);
        await writeFile(tempPath, payload, "utf8");
        await rename(tempPath, this.filePath);
    }
}
function emptySnapshot() {
    return { sessions: [], messages: {}, workspaces: [] };
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
        (record.sandbox === "read-only" || record.sandbox === "workspace-write" || record.sandbox === "danger-full-access") &&
        (record.model === undefined || typeof record.model === "string") &&
        (record.reasoningEffort === undefined || record.reasoningEffort === "low" || record.reasoningEffort === "medium" || record.reasoningEffort === "high" || record.reasoningEffort === "xhigh") &&
        (record.serviceTier === undefined || typeof record.serviceTier === "string" || record.serviceTier === null));
}
function parseMessageMap(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return {};
    const output = {};
    for (const [sessionId, messages] of Object.entries(value)) {
        if (!Array.isArray(messages))
            continue;
        const parsed = messages.flatMap((candidate) => (isStoredChatMessage(candidate) ? [candidate] : []));
        if (parsed.length > 0)
            output[sessionId] = parsed;
    }
    return output;
}
function isStoredChatMessage(value) {
    if (!value || typeof value !== "object")
        return false;
    const record = value;
    return (typeof record.messageId === "string" &&
        (record.role === "user" || record.role === "assistant" || record.role === "system") &&
        (record.kind === "thinking" || record.kind === "executing" || record.kind === "response" || record.kind === "system" || record.kind === "files" || record.kind === "error") &&
        typeof record.text === "string" &&
        typeof record.createdAt === "string" &&
        typeof record.complete === "boolean");
}
function isWorkspaceRecord(value) {
    if (!value || typeof value !== "object")
        return false;
    const record = value;
    return (typeof record.workspaceId === "string" &&
        typeof record.label === "string" &&
        typeof record.path === "string" &&
        typeof record.active === "boolean");
}
