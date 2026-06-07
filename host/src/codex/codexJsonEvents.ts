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
  return {
    kind: "message_started",
    messageKind: action.messageKind,
    title: action.title,
    text: extractActionText(item) ?? action.fallbackText,
    itemId: readString(item, "id") ?? readString(event, "item_id"),
  };
}

function mapCompletedItem(event: CodexJsonEvent): CodexJsonBridgeEvent {
  const item = readObject(event, "item") ?? event;
  const itemType = readString(item, "type") ?? readString(event, "item_type") ?? "system";
  const text = extractText(item) ?? extractText(event);
  const itemId = readString(item, "id") ?? readString(event, "item_id");

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
  for (const key of ["text", "message", "content", "output", "summary", "result"]) {
    const direct = value[key];
    const text = stringifyContent(direct);
    if (text) return text;
  }
  return undefined;
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
  const haystack = `${itemType} ${readString(item, "name") ?? ""} ${readString(item, "tool_name") ?? ""}`.toLowerCase();
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
