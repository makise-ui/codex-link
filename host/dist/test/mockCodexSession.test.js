import { describe, expect, it, vi } from "vitest";
import { MockCodexSession } from "../src/codex/mockCodexSession.js";
describe("MockCodexSession", () => {
    it("streams output and completes", async () => {
        vi.useFakeTimers();
        const session = new MockCodexSession();
        const events = [];
        session.onEvent((event) => events.push(event.type));
        await session.start();
        const { runId } = await session.sendPrompt("hello");
        expect(runId).toBeTruthy();
        await vi.advanceTimersByTimeAsync(2_000);
        expect(events).toContain("run.started");
        expect(events).toContain("output.delta");
        expect(events).toContain("run.completed");
        vi.useRealTimers();
    });
    it("cancels an active run", async () => {
        vi.useFakeTimers();
        const session = new MockCodexSession();
        const statuses = [];
        session.onEvent((event) => {
            if (event.type === "status")
                statuses.push(event.status);
        });
        const { runId } = await session.sendPrompt("cancel me");
        await session.cancel(runId);
        expect(statuses).toContain("cancelling");
        expect(statuses).toContain("cancelled");
        vi.useRealTimers();
    });
});
