import { describe, expect, it } from "vitest";
import { PROTOCOL_VERSION } from "../src/protocol/messages.js";
import { parseClientMessage } from "../src/protocol/schemas.js";
describe("protocol schemas", () => {
    it("uses protocol version 3", () => {
        expect(PROTOCOL_VERSION).toBe(3);
    });
    it("accepts a valid prompt", () => {
        expect(parseClientMessage({
            type: "prompt.send",
            sessionId: "default",
            prompt: "hello",
        })).toEqual({ type: "prompt.send", sessionId: "default", prompt: "hello" });
    });
    it("accepts session, workspace, mode, and command controls", () => {
        expect(parseClientMessage({ type: "session.create", title: "Phone session", workspaceId: "default", mode: "safe" })).toEqual({
            type: "session.create",
            title: "Phone session",
            workspaceId: "default",
            mode: "safe",
        });
        expect(parseClientMessage({ type: "workspace.switch", sessionId: "s1", workspaceId: "workspace-2" })).toEqual({
            type: "workspace.switch",
            sessionId: "s1",
            workspaceId: "workspace-2",
        });
        expect(parseClientMessage({ type: "workspace.add", sessionId: "s1", path: "/tmp/other-repo", create: true })).toEqual({
            type: "workspace.add",
            sessionId: "s1",
            path: "/tmp/other-repo",
            create: true,
        });
        expect(parseClientMessage({ type: "session.mode.set", sessionId: "s1", mode: "yolo" })).toEqual({
            type: "session.mode.set",
            sessionId: "s1",
            mode: "yolo",
        });
        expect(parseClientMessage({ type: "session.config.set", sessionId: "s1", model: "gpt-5-codex", reasoningEffort: "high" })).toEqual({
            type: "session.config.set",
            sessionId: "s1",
            model: "gpt-5-codex",
            reasoningEffort: "high",
        });
        expect(parseClientMessage({ type: "command.run", sessionId: "s1", commandId: "codex.test" })).toEqual({
            type: "command.run",
            sessionId: "s1",
            commandId: "codex.test",
        });
    });
    it("accepts password auth without exposing it through other auth messages", () => {
        expect(parseClientMessage({ type: "auth.password", password: "local-pass", deviceName: "Pixel" })).toEqual({
            type: "auth.password",
            password: "local-pass",
            deviceName: "Pixel",
        });
    });
    it("accepts prompt attachments and external session controls", () => {
        expect(parseClientMessage({
            type: "prompt.send",
            sessionId: "default",
            prompt: "use this screenshot",
            attachments: [
                {
                    name: "screen.png",
                    mimeType: "image/png",
                    dataBase64: Buffer.from("fake-image").toString("base64"),
                },
            ],
        })).toEqual({
            type: "prompt.send",
            sessionId: "default",
            prompt: "use this screenshot",
            attachments: [
                {
                    name: "screen.png",
                    mimeType: "image/png",
                    dataBase64: Buffer.from("fake-image").toString("base64"),
                },
            ],
        });
        expect(parseClientMessage({ type: "external.session.list" })).toEqual({ type: "external.session.list" });
        expect(parseClientMessage({ type: "external.session.import", externalSessionId: "019ea1ae-ac01-7123-8247-f3f94f79383d" })).toEqual({
            type: "external.session.import",
            externalSessionId: "019ea1ae-ac01-7123-8247-f3f94f79383d",
        });
    });
    it("accepts file request client messages", () => {
        expect(parseClientMessage({ type: "file.request", fileId: "file-1" })).toEqual({
            type: "file.request",
            fileId: "file-1",
        });
    });
    it("rejects empty prompts", () => {
        expect(() => parseClientMessage({ type: "prompt.send", sessionId: "default", prompt: "" })).toThrow();
    });
    it("rejects unknown message types", () => {
        expect(() => parseClientMessage({ type: "shell.exec", command: "rm -rf /" })).toThrow();
    });
});
