import { describe, expect, it } from "vitest";
import { COMMAND_CATALOG, promptForCommand } from "../src/codex/commandCatalog.js";
describe("command catalog", () => {
    it("exposes the minimal mobile slash command set before mode toggles", () => {
        expect(COMMAND_CATALOG.map((command) => command.commandId)).toEqual([
            "codex.goal",
            "codex.status",
            "codex.stop",
            "codex.sessions",
            "codex.new",
            "codex.workspace",
            "codex.review",
            "codex.skills",
            "codex.files",
            "codex.history",
            "codex.approvals",
            "codex.tunnel",
            "codex.doctor",
            "codex.diff",
            "codex.compact",
            "codex.model",
            "codex.explain",
            "codex.fix",
            "codex.test",
            "codex.summarize",
            "mode.safe",
            "mode.yolo",
        ]);
    });
    it("maps host-run command ids to focused prompts", () => {
        expect(promptForCommand("codex.status")?.toLowerCase()).toContain("current codex session");
        expect(promptForCommand("codex.diff")?.toLowerCase()).toContain("diff");
        expect(promptForCommand("codex.compact")?.toLowerCase()).toContain("compact");
        expect(promptForCommand("codex.model")?.toLowerCase()).toContain("model");
    });
    it("leaves app-only commands without host prompt fallbacks", () => {
        expect(promptForCommand("codex.goal")).toBeUndefined();
        expect(promptForCommand("codex.stop")).toBeUndefined();
        expect(promptForCommand("codex.sessions")).toBeUndefined();
        expect(promptForCommand("codex.new")).toBeUndefined();
        expect(promptForCommand("codex.workspace")).toBeUndefined();
        expect(promptForCommand("codex.review")).toBeUndefined();
        expect(promptForCommand("codex.skills")).toBeUndefined();
        expect(promptForCommand("codex.files")).toBeUndefined();
        expect(promptForCommand("codex.history")).toBeUndefined();
        expect(promptForCommand("codex.approvals")).toBeUndefined();
        expect(promptForCommand("codex.tunnel")).toBeUndefined();
        expect(promptForCommand("codex.doctor")).toBeUndefined();
    });
});
