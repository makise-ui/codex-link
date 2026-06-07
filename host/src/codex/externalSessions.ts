import { randomUUID } from "node:crypto";
import { readdir, readFile, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import type { ExternalSessionRecord, StoredChatMessage } from "../protocol/messages.js";

export type ListExternalSessionsOptions = {
  root?: string;
  limit?: number;
};

export async function listExternalSessions(options: ListExternalSessionsOptions = {}): Promise<ExternalSessionRecord[]> {
  const root = options.root ?? path.join(os.homedir(), ".codex", "sessions");
  const limit = options.limit ?? 80;
  const files = await listJsonlFiles(root).catch(() => []);
  const records = await Promise.all(files.map((filePath) => readExternalSession(filePath)));
  return records
    .flatMap((record) => (record ? [record] : []))
    .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))
    .slice(0, limit);
}

export async function findExternalSession(externalSessionId: string, options: ListExternalSessionsOptions = {}): Promise<ExternalSessionRecord | undefined> {
  const sessions = await listExternalSessions({ ...options, limit: Math.max(options.limit ?? 300, 300) });
  return sessions.find((session) => session.externalSessionId === externalSessionId);
}

export async function readExternalSessionHistory(session: ExternalSessionRecord, limit = 160): Promise<StoredChatMessage[]> {
  const raw = await readFile(session.path, "utf8");
  const messages: StoredChatMessage[] = [];
  const callMessages = new Map<string, StoredChatMessage>();
  for (const line of raw.split(/\r?\n/).filter(Boolean)) {
    const event = safeJson(line);
    if (!event || !isRecord(event.payload)) continue;
    const timestamp = readString(event, "timestamp") ?? session.updatedAt;
    const payload = event.payload;
    if (event.type === "event_msg" && payload.type === "user_message") {
      const text = readString(payload, "message") ?? readString(payload, "text");
      if (text) messages.push(storedMessage({ role: "user", text, timestamp }));
      continue;
    }
    if (event.type !== "response_item") continue;
    if (payload.type === "message") {
      const role = payload.role === "user" ? "user" : payload.role === "assistant" ? "assistant" : undefined;
      if (!role) continue;
      const text = contentText(payload.content);
      if (text) messages.push(storedMessage({ role, text, timestamp, title: role === "assistant" ? "Response" : undefined }));
      continue;
    }
    if (payload.type === "function_call" || payload.type === "custom_tool_call") {
      const callId = readString(payload, "call_id");
      if (!callId) continue;
      const title = payload.type === "custom_tool_call" ? "Editing files" : payload.name === "exec_command" ? "Running command" : String(payload.name ?? "Tool call");
      const text = payload.type === "function_call" ? functionCallText(payload) : readString(payload, "input") ?? "";
      const message = storedMessage({ role: "system", kind: "executing", text, timestamp, title, complete: false });
      messages.push(message);
      callMessages.set(callId, message);
      continue;
    }
    if (payload.type === "function_call_output" || payload.type === "custom_tool_call_output") {
      const callId = readString(payload, "call_id");
      const output = readString(payload, "output");
      if (!callId || !output) continue;
      const message = callMessages.get(callId);
      if (message) {
        message.text = [message.text.trimEnd(), output.trimEnd()].filter(Boolean).join("\n");
        message.complete = true;
      }
    }
  }
  return messages.slice(-limit);
}

async function listJsonlFiles(root: string): Promise<string[]> {
  const entries = await readdir(root, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = path.join(root, entry.name);
      if (entry.isDirectory()) return listJsonlFiles(entryPath);
      if (entry.isFile() && entry.name.endsWith(".jsonl")) return [entryPath];
      return [];
    }),
  );
  return files.flat();
}

async function readExternalSession(filePath: string): Promise<ExternalSessionRecord | undefined> {
  const raw = await readFile(filePath, "utf8");
  const lines = raw.split(/\r?\n/).filter(Boolean);
  const metaLine = lines.find((line) => safeJson(line)?.type === "session_meta");
  const meta = metaLine ? safeJson(metaLine) : undefined;
  if (!meta || !isRecord(meta.payload)) return undefined;
  const payload = meta.payload;
  const id = readString(payload, "id");
  const cwd = readString(payload, "cwd");
  const timestamp = readString(payload, "timestamp") ?? readString(meta, "timestamp");
  if (!id || !cwd || !timestamp) return undefined;

  const fileStat = await stat(filePath);
  return {
    externalSessionId: id,
    title: titleFromLines(lines) ?? (path.basename(cwd) || "Codex session"),
    createdAt: timestamp,
    updatedAt: fileStat.mtime.toISOString(),
    workdir: cwd,
    codexThreadId: id,
    path: filePath,
  };
}

function titleFromLines(lines: string[]): string | undefined {
  for (const line of lines) {
    const event = safeJson(line);
    if (!event || !isRecord(event.payload)) continue;
    const payload = event.payload;
    if (payload.type === "user_message") {
      const text = readString(payload, "message") ?? readString(payload, "text");
      if (text) return compactTitle(text);
    }
    if (payload.type === "message" && payload.role === "user" && Array.isArray(payload.content)) {
      const text = payload.content.flatMap((part) => (isRecord(part) ? [readString(part, "text") ?? ""] : [])).join(" ");
      if (text.trim()) return compactTitle(text);
    }
  }
  return undefined;
}

function compactTitle(value: string): string {
  const compact = value.trim().replace(/\s+/g, " ");
  return compact.length > 58 ? `${compact.slice(0, 55)}...` : compact;
}

function contentText(value: unknown): string | undefined {
  if (!Array.isArray(value)) return undefined;
  const text = value
    .flatMap((part) => (isRecord(part) ? [readString(part, "text") ?? ""] : []))
    .join("\n")
    .trim();
  return text || undefined;
}

function functionCallText(payload: Record<string, unknown>): string {
  const name = readString(payload, "name") ?? "tool";
  const args = readString(payload, "arguments");
  if (name === "exec_command" && args) {
    const parsed = safeJson(args);
    if (parsed) {
      return readString(parsed, "cmd") ?? args;
    }
  }
  return args ? `${name} ${args}` : name;
}

function storedMessage(input: {
  role: "user" | "assistant" | "system";
  text: string;
  timestamp: string;
  title?: string;
  kind?: StoredChatMessage["kind"];
  complete?: boolean;
}): StoredChatMessage {
  return {
    messageId: `external-${randomUUID()}`,
    role: input.role,
    kind: input.kind ?? "response",
    title: input.title,
    text: input.text,
    createdAt: input.timestamp,
    complete: input.complete ?? true,
  };
}

function safeJson(line: string): Record<string, unknown> | undefined {
  try {
    const parsed = JSON.parse(line) as unknown;
    return isRecord(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function readString(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}
