import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import type { SessionRecord, StoredChatMessage, WorkspaceRecord } from "../protocol/messages.js";

export type SessionStoreSnapshot = {
  sessions: SessionRecord[];
  messages?: Record<string, StoredChatMessage[]>;
  workspaces?: WorkspaceRecord[];
};

export class SessionStore {
  private readonly filePath: string;
  private saveQueue: Promise<void> = Promise.resolve();

  constructor(private readonly stateDir: string) {
    this.filePath = path.join(stateDir, "sessions.json");
  }

  async load(): Promise<SessionStoreSnapshot> {
    try {
      const raw = await readFile(this.filePath, "utf8");
      const parsed = JSON.parse(raw) as unknown;
      if (!parsed || typeof parsed !== "object" || !Array.isArray((parsed as { sessions?: unknown }).sessions)) {
        return emptySnapshot();
      }
      const record = parsed as { sessions: unknown[]; messages?: unknown; workspaces?: unknown };
      return {
        sessions: record.sessions.flatMap((candidate) => (isSessionRecord(candidate) ? [candidate] : [])),
        messages: parseMessageMap(record.messages),
        workspaces: Array.isArray(record.workspaces) ? record.workspaces.flatMap((candidate) => (isWorkspaceRecord(candidate) ? [candidate] : [])) : [],
      };
    } catch (error) {
      if (error && typeof error === "object" && "code" in error && (error as { code?: string }).code === "ENOENT") {
        return emptySnapshot();
      }
      throw error;
    }
  }

  async save(snapshot: SessionStoreSnapshot): Promise<void> {
    const frozenSnapshot: SessionStoreSnapshot = {
      sessions: snapshot.sessions.map((session) => ({ ...session })),
      messages: Object.fromEntries(Object.entries(snapshot.messages ?? {}).map(([sessionId, messages]) => [sessionId, messages.map((message) => ({ ...message }))])),
      workspaces: (snapshot.workspaces ?? []).map((workspace) => ({ ...workspace, active: false })),
    };

    const writeOperation = this.saveQueue.then(() => this.writeSnapshot(frozenSnapshot));
    this.saveQueue = writeOperation.catch(() => undefined);
    return writeOperation;
  }

  private async writeSnapshot(snapshot: SessionStoreSnapshot): Promise<void> {
    await mkdir(this.stateDir, { recursive: true });
    const payload = `${JSON.stringify({ sessions: snapshot.sessions, messages: snapshot.messages, workspaces: snapshot.workspaces }, null, 2)}\n`;
    const tempPath = path.join(this.stateDir, `sessions.${process.pid}.${randomUUID()}.tmp`);
    await writeFile(tempPath, payload, "utf8");
    await rename(tempPath, this.filePath);
  }
}

function emptySnapshot(): SessionStoreSnapshot {
  return { sessions: [], messages: {}, workspaces: [] };
}

function isSessionRecord(value: unknown): value is SessionRecord {
  if (!value || typeof value !== "object") return false;
  const record = value as Partial<SessionRecord>;
  return (
    typeof record.sessionId === "string" &&
    typeof record.title === "string" &&
    typeof record.createdAt === "string" &&
    typeof record.updatedAt === "string" &&
    typeof record.workspaceId === "string" &&
    typeof record.workdir === "string" &&
    typeof record.lastStatus === "string" &&
    (record.mode === "safe" || record.mode === "yolo") &&
    (record.sandbox === "read-only" || record.sandbox === "workspace-write" || record.sandbox === "danger-full-access")
  );
}

function parseMessageMap(value: unknown): Record<string, StoredChatMessage[]> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const output: Record<string, StoredChatMessage[]> = {};
  for (const [sessionId, messages] of Object.entries(value as Record<string, unknown>)) {
    if (!Array.isArray(messages)) continue;
    const parsed = messages.flatMap((candidate) => (isStoredChatMessage(candidate) ? [candidate] : []));
    if (parsed.length > 0) output[sessionId] = parsed;
  }
  return output;
}

function isStoredChatMessage(value: unknown): value is StoredChatMessage {
  if (!value || typeof value !== "object") return false;
  const record = value as Partial<StoredChatMessage>;
  return (
    typeof record.messageId === "string" &&
    (record.role === "user" || record.role === "assistant" || record.role === "system") &&
    (record.kind === "thinking" || record.kind === "executing" || record.kind === "response" || record.kind === "system" || record.kind === "files" || record.kind === "error") &&
    typeof record.text === "string" &&
    typeof record.createdAt === "string" &&
    typeof record.complete === "boolean"
  );
}

function isWorkspaceRecord(value: unknown): value is WorkspaceRecord {
  if (!value || typeof value !== "object") return false;
  const record = value as Partial<WorkspaceRecord>;
  return (
    typeof record.workspaceId === "string" &&
    typeof record.label === "string" &&
    typeof record.path === "string" &&
    typeof record.active === "boolean"
  );
}
