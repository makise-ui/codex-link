import type { MessageKind } from "../protocol/messages.js";

export type CodexJsonEvent = Record<string, unknown> & { type?: string };

export type CodexJsonBridgeEvent =
  | { kind: "thread"; threadId: string }
  | { kind: "turn_started" }
  | { kind: "message"; messageKind: MessageKind; title?: string; text: string; itemId?: string }
  | { kind: "message_started"; messageKind: MessageKind; title?: string; text?: string; itemId?: string }
  | { kind: "message_completed"; itemId?: string }
  | { kind: "turn_completed" }
  | { kind: "ignored" };

export class JsonLineBuffer {
  private buffered = "";

  push(chunk: string): string[] {
    this.buffered += chunk;
    const lines = this.buffered.split(/\r?\n/);
    this.buffered = lines.pop() ?? "";
    return lines.filter((line) => line.trim().length > 0);
  }

  flush(): string[] {
    const line = this.buffered.trim();
    this.buffered = "";
    return line.length > 0 ? [line] : [];
  }
}

export function parseCodexJsonLine(line: string): CodexJsonEvent {
  const parsed = JSON.parse(line) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Codex JSONL event must be an object.");
  }
  return parsed as CodexJsonEvent;
}

export function mapCodexJsonEvent(event: CodexJsonEvent): CodexJsonBridgeEvent {
  switch (event.type) {
    case "thread.started": {
      const threadId = readString(event, "thread_id") ?? readString(event, "threadId") ?? readString(event, "id");
      return threadId ? { kind: "thread", threadId } : { kind: "ignored" };
    }
    case "turn.started":
      return { kind: "turn_started" };
    case "turn.completed":
      return { kind: "turn_completed" };
    case "item.started":
      return mapStartedItem(event);
    case "item.completed":
      return mapCompletedItem(event);
    default:
      return { kind: "ignored" };
  }
}

function mapStartedItem(event: CodexJsonEvent): CodexJsonBridgeEvent {
  const item = readObject(event, "item") ?? event;
  const itemType = readString(item, "type") ?? readString(event, "item_type") ?? "system";
  const action = classifyItem(itemType, item);
  if (action.messageKind !== "executing") {
    return { kind: "ignored" };
  }
  const fileChangeText = itemType === "file_change" ? formatFileChanges(item) : undefined;
  return {
    kind: "message_started",
    messageKind: action.messageKind,
    title: action.title,
    text: fileChangeText ?? formatActionStartText(item, action) ?? action.fallbackText,
    itemId: readString(item, "id") ?? readString(event, "item_id"),
  };
}

function mapCompletedItem(event: CodexJsonEvent): CodexJsonBridgeEvent {
  const item = readObject(event, "item") ?? event;
  const itemType = readString(item, "type") ?? readString(event, "item_type") ?? "system";
  const itemId = readString(item, "id") ?? readString(event, "item_id");
  if (itemType === "file_change" && itemId) {
    return { kind: "message_completed", itemId };
  }
  const text = formatActionCompletionText(item) ?? formatActionCompletionText(event);

  if (!text || text.trim().length === 0) {
    return itemId ? { kind: "message_completed", itemId } : { kind: "ignored" };
  }

  if (itemType === "agent_message" || itemType === "assistant_message" || itemType === "message") {
    return { kind: "message", messageKind: "response", title: "Response", text, itemId };
  }

  const action = classifyItem(itemType, item);
  if (action.messageKind === "executing") {
    return { kind: "message", messageKind: "executing", title: action.title, text, itemId };
  }

  return { kind: "message", messageKind: "system", title: readableTitle(itemType), text, itemId };
}

function extractText(value: Record<string, unknown>): string | undefined {
  for (const key of ["text", "message", "content", "aggregated_output", "output", "summary", "result"]) {
    const direct = value[key];
    const text = stringifyContent(direct);
    if (text) return text;
  }
  return undefined;
}

function formatActionStartText(
  value: Record<string, unknown>,
  action: { title: string },
): string | undefined {
  const command = extractActionText(value);
  if (!command) return undefined;
  if (action.title !== "Reading file") return command;
  const metadata = readCommandMetadata(command);
  if (!metadata) return command;
  return [
    `Reading file: ${metadata.filePath}`,
    metadata.lines ? `Lines: ${metadata.lines}` : undefined,
    `Command: ${command}`,
  ].filter(Boolean).join("\n");
}

function formatActionCompletionText(value: Record<string, unknown>): string | undefined {
  const text = extractText(value);
  return text ? summarizeLongOutput(text) : undefined;
}

function formatFileChanges(value: Record<string, unknown>): string | undefined {
  const changes = value.changes;
  if (!Array.isArray(changes)) return undefined;
  const lines = changes.flatMap((change) => {
    if (!change || typeof change !== "object" || Array.isArray(change)) return [];
    const record = change as Record<string, unknown>;
    const rawPath = readString(record, "path") ?? readString(record, "file") ?? readString(record, "filename");
    if (!rawPath) return [];
    const status = normalizeFileChangeKind(readString(record, "kind") ?? readString(record, "status"));
    return [`${status} ${shortPath(rawPath)}`];
  });
  return lines.length > 0 ? lines.join("\n") : undefined;
}

function normalizeFileChangeKind(kind?: string): "added" | "modified" | "deleted" | "renamed" {
  switch (kind) {
    case "add":
    case "added":
    case "create":
    case "created":
      return "added";
    case "delete":
    case "deleted":
    case "remove":
    case "removed":
      return "deleted";
    case "rename":
    case "renamed":
      return "renamed";
    default:
      return "modified";
  }
}

function shortPath(value: string): string {
  const normalized = value.replace(/\\/g, "/");
  const marker = normalized.match(/(?:^|\/)(?:lib|src|test|host|flutter|shared|notes\.txt)(?:\/|$)/);
  if (!marker?.index) {
    const parts = normalized.split("/").filter(Boolean);
    return parts.slice(-2).join("/") || normalized;
  }
  const start = marker[0].startsWith("/") ? marker.index + 1 : marker.index;
  return normalized.slice(start);
}

function extractActionText(value: Record<string, unknown>): string | undefined {
  for (const key of ["command", "cmd", "path", "file", "filename", "name", "input", "arguments", "args"]) {
    const direct = value[key];
    const text = stringifyContent(direct);
    if (text) return text;
  }
  const nested = readObject(value, "tool") ?? readObject(value, "call") ?? readObject(value, "function");
  return nested ? extractActionText(nested) ?? extractText(nested) : undefined;
}

function summarizeLongOutput(text: string): string {
  const lineEnding = text.endsWith("\n") ? "\n" : "";
  const lines = text.replace(/\n$/, "").split(/\r?\n/);
  if (lines.length > 80) {
    const first = lines.slice(0, 30);
    const last = lines.slice(-30);
    const omitted = lines.length - first.length - last.length;
    return [...first, `... ${omitted} lines omitted ...`, ...last].join("\n") + lineEnding;
  }
  if (text.length <= 10_000) return text;
  return `${text.slice(0, 5_000)}\n... ${text.length - 10_000} characters omitted ...\n${text.slice(-5_000)}`;
}

function stringifyContent(value: unknown): string | undefined {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    const parts = value.flatMap((part) => {
      if (typeof part === "string") return [part];
      if (part && typeof part === "object") {
        const record = part as Record<string, unknown>;
        const nested = stringifyContent(record.text ?? record.content ?? record.message);
        return nested ? [nested] : [];
      }
      return [];
    });
    return parts.length > 0 ? parts.join("\n") : undefined;
  }
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const nested = stringifyContent(record.text ?? record.content ?? record.message ?? record.path ?? record.command ?? record.name);
    if (nested) return nested;
    try {
      return JSON.stringify(record);
    } catch {
      return undefined;
    }
  }
  return undefined;
}

function readString(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function readObject(record: Record<string, unknown>, key: string): Record<string, unknown> | undefined {
  const value = record[key];
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  return value as Record<string, unknown>;
}

function readableTitle(value: string): string {
  return value
    .split(/[._-]/g)
    .filter(Boolean)
    .map((part) => part.slice(0, 1).toUpperCase() + part.slice(1))
    .join(" ") || "Codex Event";
}

function classifyItem(itemType: string, item: Record<string, unknown>): { messageKind: MessageKind; title: string; fallbackText: string } {
  const actionText = extractActionText(item) ?? "";
  const haystack = `${itemType} ${readString(item, "name") ?? ""} ${readString(item, "tool_name") ?? ""} ${actionText}`.toLowerCase();
  if (itemType === "file_change") {
    return { messageKind: "executing", title: "Editing files", fallbackText: "Applying file changes..." };
  }
  if (isReadCommand(actionText)) {
    return { messageKind: "executing", title: "Reading file", fallbackText: "Reading file..." };
  }
  if (haystack.includes("read") || haystack.includes("open") || haystack.includes("cat")) {
    return { messageKind: "executing", title: "Reading file", fallbackText: "Reading file..." };
  }
  if (haystack.includes("write") || haystack.includes("edit") || haystack.includes("patch") || haystack.includes("create")) {
    return { messageKind: "executing", title: "Editing files", fallbackText: "Applying file changes..." };
  }
  if (haystack.includes("command") || haystack.includes("tool") || haystack.includes("exec") || haystack.includes("shell") || haystack.includes("function")) {
    return { messageKind: "executing", title: haystack.includes("command") || haystack.includes("shell") || haystack.includes("exec") ? "Running command" : readableTitle(itemType), fallbackText: "Running tool..." };
  }
  return { messageKind: "system", title: readableTitle(itemType), fallbackText: "" };
}

function isReadCommand(command: string): boolean {
  if (!command.trim()) return false;
  const payload = shellPayload(command).toLowerCase();
  return /(^|\s)(cat|less|more)\s+/.test(payload) ||
    /(^|\s)(head|tail)\b/.test(payload) ||
    /(^|\s)sed\s+-n\s+/.test(payload);
}

function readCommandMetadata(command: string): { filePath: string; lines?: string } | undefined {
  const payload = shellPayload(command);
  const sed = payload.match(/(?:^|\s)sed\s+-n\s+['"]?(\d+)(?:,(\d+))?p['"]?\s+(.+?)\s*$/);
  if (sed) {
    const filePath = stripShellQuotes(sed[3] ?? "");
    if (filePath) {
      return {
        filePath,
        lines: sed[2] ? `${sed[1]}-${sed[2]}` : `${sed[1]}`,
      };
    }
  }

  const cat = payload.match(/(?:^|\s)cat\s+(.+?)\s*$/);
  if (cat) {
    const filePath = stripShellQuotes(cat[1] ?? "");
    if (filePath) return { filePath };
  }

  const headTail = payload.match(/(?:^|\s)(head|tail)(?:\s+-n\s+(\d+))?\s+(.+?)\s*$/);
  if (headTail) {
    const filePath = stripShellQuotes(headTail[3] ?? "");
    if (filePath) {
      return {
        filePath,
        lines: headTail[2] ? `${headTail[1] === "tail" ? "last " : "first "}${headTail[2]}` : undefined,
      };
    }
  }
  return undefined;
}

function shellPayload(command: string): string {
  const trimmed = command.trim();
  const shell = trimmed.match(/(?:^|\s)(?:\/usr\/bin\/|\/bin\/)?(?:zsh|bash|sh)\s+-lc\s+(.+)$/);
  return shell ? stripShellQuotes(shell[1] ?? trimmed) : trimmed;
}

function stripShellQuotes(value: string): string {
  let output = value.trim();
  if ((output.startsWith('"') && output.endsWith('"')) || (output.startsWith("'") && output.endsWith("'"))) {
    output = output.slice(1, -1);
  }
  return output.replace(/\\"/g, '"').replace(/\\'/g, "'").trim();
}
