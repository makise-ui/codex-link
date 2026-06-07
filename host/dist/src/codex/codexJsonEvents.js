export class JsonLineBuffer {
    buffered = "";
    push(chunk) {
        this.buffered += chunk;
        const lines = this.buffered.split(/\r?\n/);
        this.buffered = lines.pop() ?? "";
        return lines.filter((line) => line.trim().length > 0);
    }
    flush() {
        const line = this.buffered.trim();
        this.buffered = "";
        return line.length > 0 ? [line] : [];
    }
}
export function parseCodexJsonLine(line) {
    const parsed = JSON.parse(line);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        throw new Error("Codex JSONL event must be an object.");
    }
    return parsed;
}
export function mapCodexJsonEvent(event) {
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
function mapStartedItem(event) {
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
        text: fileChangeText ?? extractActionText(item) ?? action.fallbackText,
        itemId: readString(item, "id") ?? readString(event, "item_id"),
    };
}
function mapCompletedItem(event) {
    const item = readObject(event, "item") ?? event;
    const itemType = readString(item, "type") ?? readString(event, "item_type") ?? "system";
    const itemId = readString(item, "id") ?? readString(event, "item_id");
    if (itemType === "file_change" && itemId) {
        return { kind: "message_completed", itemId };
    }
    const text = extractText(item) ?? extractText(event);
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
function extractText(value) {
    for (const key of ["text", "message", "content", "aggregated_output", "output", "summary", "result"]) {
        const direct = value[key];
        const text = stringifyContent(direct);
        if (text)
            return text;
    }
    return undefined;
}
function formatFileChanges(value) {
    const changes = value.changes;
    if (!Array.isArray(changes))
        return undefined;
    const lines = changes.flatMap((change) => {
        if (!change || typeof change !== "object" || Array.isArray(change))
            return [];
        const record = change;
        const rawPath = readString(record, "path") ?? readString(record, "file") ?? readString(record, "filename");
        if (!rawPath)
            return [];
        const status = normalizeFileChangeKind(readString(record, "kind") ?? readString(record, "status"));
        return [`${status} ${shortPath(rawPath)}`];
    });
    return lines.length > 0 ? lines.join("\n") : undefined;
}
function normalizeFileChangeKind(kind) {
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
function shortPath(value) {
    const normalized = value.replace(/\\/g, "/");
    const marker = normalized.match(/(?:^|\/)(?:lib|src|test|host|flutter|shared|notes\.txt)(?:\/|$)/);
    if (!marker?.index) {
        const parts = normalized.split("/").filter(Boolean);
        return parts.slice(-2).join("/") || normalized;
    }
    const start = marker[0].startsWith("/") ? marker.index + 1 : marker.index;
    return normalized.slice(start);
}
function extractActionText(value) {
    for (const key of ["command", "cmd", "path", "file", "filename", "name", "input", "arguments", "args"]) {
        const direct = value[key];
        const text = stringifyContent(direct);
        if (text)
            return text;
    }
    const nested = readObject(value, "tool") ?? readObject(value, "call") ?? readObject(value, "function");
    return nested ? extractActionText(nested) ?? extractText(nested) : undefined;
}
function stringifyContent(value) {
    if (typeof value === "string")
        return value;
    if (Array.isArray(value)) {
        const parts = value.flatMap((part) => {
            if (typeof part === "string")
                return [part];
            if (part && typeof part === "object") {
                const record = part;
                const nested = stringifyContent(record.text ?? record.content ?? record.message);
                return nested ? [nested] : [];
            }
            return [];
        });
        return parts.length > 0 ? parts.join("\n") : undefined;
    }
    if (value && typeof value === "object") {
        const record = value;
        const nested = stringifyContent(record.text ?? record.content ?? record.message ?? record.path ?? record.command ?? record.name);
        if (nested)
            return nested;
        try {
            return JSON.stringify(record);
        }
        catch {
            return undefined;
        }
    }
    return undefined;
}
function readString(record, key) {
    const value = record[key];
    return typeof value === "string" && value.length > 0 ? value : undefined;
}
function readObject(record, key) {
    const value = record[key];
    if (!value || typeof value !== "object" || Array.isArray(value))
        return undefined;
    return value;
}
function readableTitle(value) {
    return value
        .split(/[._-]/g)
        .filter(Boolean)
        .map((part) => part.slice(0, 1).toUpperCase() + part.slice(1))
        .join(" ") || "Codex Event";
}
function classifyItem(itemType, item) {
    const haystack = `${itemType} ${readString(item, "name") ?? ""} ${readString(item, "tool_name") ?? ""}`.toLowerCase();
    if (itemType === "file_change") {
        return { messageKind: "executing", title: "Editing files", fallbackText: "Applying file changes..." };
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
