import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import type { SessionRecord } from "../protocol/messages.js";

export type SessionStoreSnapshot = {
  sessions: SessionRecord[];
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
        return { sessions: [] };
      }
      return {
        sessions: (parsed as { sessions: unknown[] }).sessions.flatMap((candidate) => (isSessionRecord(candidate) ? [candidate] : [])),
      };
    } catch (error) {
      if (error && typeof error === "object" && "code" in error && (error as { code?: string }).code === "ENOENT") {
        return { sessions: [] };
      }
      throw error;
    }
  }

  async save(snapshot: SessionStoreSnapshot): Promise<void> {
    const frozenSnapshot: SessionStoreSnapshot = {
      sessions: snapshot.sessions.map((session) => ({ ...session })),
    };

    const writeOperation = this.saveQueue.then(() => this.writeSnapshot(frozenSnapshot));
    this.saveQueue = writeOperation.catch(() => undefined);
    return writeOperation;
  }

  private async writeSnapshot(snapshot: SessionStoreSnapshot): Promise<void> {
    await mkdir(this.stateDir, { recursive: true });
    const payload = `${JSON.stringify({ sessions: snapshot.sessions }, null, 2)}\n`;
    const tempPath = path.join(this.stateDir, `sessions.${process.pid}.${randomUUID()}.tmp`);
    await writeFile(tempPath, payload, "utf8");
    await rename(tempPath, this.filePath);
  }
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
