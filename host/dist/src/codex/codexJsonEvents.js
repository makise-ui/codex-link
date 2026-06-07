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
        case "item.completed":
            return mapCompletedItem(event);
        default:
            return { kind: "ignored" };
    }
}
function mapCompletedItem(event) {
    const item = readObject(event, "item") ?? event;
    const itemType = readString(item, "type") ?? readString(event, "item_type") ?? "system";
    const text = extractText(item) ?? extractText(event);
    if (!text || text.trim().length === 0) {
        return { kind: "ignored" };
    }
    if (itemType === "agent_message" || itemType === "assistant_message" || itemType === "message") {
        return { kind: "message", messageKind: "response", title: "Response", text };
    }
    if (itemType.includes("command") || itemType.includes("tool") || itemType.includes("exec") || itemType.includes("shell")) {
        return { kind: "message", messageKind: "executing", title: readableTitle(itemType), text };
    }
    return { kind: "message", messageKind: "system", title: readableTitle(itemType), text };
}
function extractText(value) {
    for (const key of ["text", "message", "content", "output", "summary"]) {
        const direct = value[key];
        const text = stringifyContent(direct);
        if (text)
            return text;
    }
    return undefined;
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
        return stringifyContent(record.text ?? record.content ?? record.message);
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
