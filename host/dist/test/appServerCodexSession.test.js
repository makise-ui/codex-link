import { describe, expect, it } from "vitest";
import { AppServerCodexSession } from "../src/codex/appServerCodexSession.js";
const fakeAppServerScript = String.raw `
const readline = require("node:readline");
const rl = readline.createInterface({ input: process.stdin });
const threadId = "thread-test";
const makeThread = () => ({
  id: threadId,
  sessionId: "session-test",
  forkedFromId: null,
  parentThreadId: null,
  preview: "",
  ephemeral: false,
  modelProvider: "openai",
  createdAt: 1,
  updatedAt: 1,
  status: { type: "idle" },
  path: null,
  cwd: process.cwd(),
  cliVersion: "test",
  source: "app_server",
  threadSource: null,
  agentNickname: null,
  agentRole: null,
  gitInfo: null,
  name: null,
  turns: [],
});
const makeTurn = (id, status = "inProgress") => ({
  id,
  items: [],
  itemsView: { type: "all" },
  status,
  error: null,
  startedAt: 1,
  completedAt: status === "inProgress" ? null : 2,
  durationMs: status === "inProgress" ? null : 1000,
});
const makeNativeThread = () => ({
  ...makeThread(),
  id: "native-thread",
  sessionId: "native-thread",
  preview: "Native app-server history",
  createdAt: 10,
  updatedAt: 20,
  path: "/tmp/codex/sessions/native-thread.jsonl",
  source: "cli",
  turns: [
    {
      id: "native-turn-1",
      itemsView: "full",
      status: "completed",
      error: null,
      startedAt: 10,
      completedAt: 12,
      durationMs: 2000,
      items: [
        { type: "userMessage", id: "native-user-1", content: [{ type: "text", text: "Review the bridge", text_elements: [] }] },
        { type: "agentMessage", id: "native-agent-1", text: "Bridge reviewed.", phase: "final_answer", memoryCitation: null },
      ],
    },
  ],
});
function write(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}
function respond(id, result) {
  write({ id, result });
}
rl.on("line", (line) => {
  const message = JSON.parse(line);
  if (message.method === "initialize") {
    respond(message.id, {
      userAgent: "test",
      codexHome: "/tmp/codex-test",
      platformFamily: "linux",
      platformOs: "linux",
    });
    return;
  }
  if (message.method === "initialized") return;
  if (message.method === "model/list") {
    respond(message.id, {
      data: [
        {
          id: "gpt-test",
          model: "gpt-test",
          displayName: "GPT Test",
          description: "Unit model",
          hidden: false,
          supportedReasoningEfforts: [
            { reasoningEffort: "low", description: "fast" },
            { reasoningEffort: "high", description: "deep" },
          ],
          defaultReasoningEffort: "low",
          inputModalities: ["text", "image"],
          supportsPersonality: true,
          additionalSpeedTiers: [],
          serviceTiers: [],
          defaultServiceTier: null,
          isDefault: true,
          upgrade: null,
          upgradeInfo: null,
          availabilityNux: null,
        },
      ],
      nextCursor: null,
    });
    return;
  }
  if (message.method === "modelProvider/capabilities/read") {
    respond(message.id, { namespaceTools: true, imageGeneration: true, webSearch: true });
    return;
  }
  if (message.method === "thread/list") {
    respond(message.id, { data: [makeNativeThread()], nextCursor: null, backwardsCursor: null });
    return;
  }
  if (message.method === "thread/read") {
    respond(message.id, { thread: makeNativeThread() });
    return;
  }
  if (message.method === "skills/list") {
    respond(message.id, {
      data: [
        {
          cwd: process.cwd(),
          skills: [{ name: "flutter-design-system", description: "Token discipline", path: process.cwd() + "/SKILL.md", scope: "user", enabled: true }],
          errors: [],
        },
      ],
    });
    return;
  }
  if (message.method === "fs/readDirectory") {
    respond(message.id, {
      entries: [
        { fileName: "lib", isDirectory: true, isFile: false },
        { fileName: "README.md", isDirectory: false, isFile: true },
      ],
    });
    return;
  }
  if (message.method === "fs/readFile") {
    respond(message.id, { dataBase64: Buffer.from("hello native file\n").toString("base64") });
    return;
  }
  if (message.method === "fuzzyFileSearch") {
    respond(message.id, {
      files: [
        { root: process.cwd(), path: "lib/main.dart", match_type: "fuzzy", file_name: "main.dart", score: 99, indices: [4, 5] },
      ],
    });
    return;
  }
  if (message.method === "review/start") {
    const turn = makeTurn("review-turn", "inProgress");
    respond(message.id, { turn, reviewThreadId: threadId });
    write({ method: "turn/started", params: { threadId, turn } });
    return;
  }
  if (message.method === "thread/start" || message.method === "thread/resume") {
    write({ method: "thread/started", params: { thread: makeThread() } });
    respond(message.id, {
      thread: makeThread(),
      model: "gpt-test",
      modelProvider: "openai",
      serviceTier: null,
      cwd: process.cwd(),
      instructionSources: [],
      approvalPolicy: "on-request",
      approvalsReviewer: "user",
      sandbox: { type: "workspaceWrite", writableRoots: [process.cwd()], networkAccess: false, excludeTmpdirEnvVar: false, excludeSlashTmp: false },
      reasoningEffort: "medium",
    });
    return;
  }
  if (message.method === "turn/start") {
    const text = message.params.input.find((item) => item.type === "text")?.text ?? "";
    const turnId = text.includes("stay running") ? "turn-running" : "turn-1";
    respond(message.id, { turn: makeTurn(turnId) });
    write({ method: "turn/started", params: { threadId, turn: makeTurn(turnId) } });
    if (turnId === "turn-running") return;
    write({ method: "item/started", params: { threadId, turnId, startedAtMs: 1, item: { type: "reasoning", id: "reason-1" } } });
    write({ method: "item/reasoning/summaryPartAdded", params: { threadId, turnId, itemId: "reason-1", summaryIndex: 0 } });
    write({ method: "item/reasoning/summaryTextDelta", params: { threadId, turnId, itemId: "reason-1", summaryIndex: 0, delta: "Checked repository shape." } });
    write({ method: "item/completed", params: { threadId, turnId, completedAtMs: 1, item: { type: "reasoning", id: "reason-1" } } });
    write({
      method: "turn/plan/updated",
      params: {
        threadId,
        turnId,
        explanation: "Checking the mobile bridge polish",
        plan: [
          { step: "Move plan out of the chat timeline", status: "completed" },
          { step: "Render it as a collapsible composer bar", status: "in_progress" },
        ],
      },
    });
    write({ method: "item/started", params: { threadId, turnId, startedAtMs: 1, item: { type: "mcpToolCall", id: "mcp-1", server: "files", tool: "read" } } });
    write({ method: "item/mcpToolCall/progress", params: { threadId, turnId, itemId: "mcp-1", message: "Reading project metadata" } });
    write({ method: "item/completed", params: { threadId, turnId, completedAtMs: 1, item: { type: "mcpToolCall", id: "mcp-1", server: "files", tool: "read" } } });
    write({
      method: "item/started",
      params: {
        threadId,
        turnId,
        startedAtMs: 1,
        item: {
          type: "commandExecution",
          id: "cmd-1",
          command: "sed -n '1,20p' notes.txt",
          cwd: process.cwd(),
          processId: "proc-1",
          source: "exec",
          status: "inProgress",
          commandActions: [{ type: "read", command: "sed", name: "notes.txt", path: "notes.txt" }],
          aggregatedOutput: null,
          exitCode: null,
          durationMs: null,
        },
      },
    });
    write({ method: "item/commandExecution/outputDelta", params: { threadId, turnId, itemId: "cmd-1", delta: "notes content\n" } });
    write({ method: "item/commandExecution/terminalInteraction", params: { threadId, turnId, itemId: "cmd-1", processId: "proc-1", stdin: "q" } });
    write({
      method: "item/completed",
      params: {
        threadId,
        turnId,
        completedAtMs: 2,
        item: {
          type: "commandExecution",
          id: "cmd-1",
          command: "sed -n '1,20p' notes.txt",
          cwd: process.cwd(),
          processId: "proc-1",
          source: "exec",
          status: "completed",
          commandActions: [{ type: "read", command: "sed", name: "notes.txt", path: "notes.txt" }],
          aggregatedOutput: "notes content\n",
          exitCode: 0,
          durationMs: 12,
        },
      },
    });
    write({ method: "turn/diff/updated", params: { threadId, turnId, diff: "diff --git a/notes.txt b/notes.txt\n--- a/notes.txt\n+++ b/notes.txt\n@@ -1 +1 @@\n-old\n+new\n" } });
    write({ method: "warning", params: { threadId, message: "Unit warning" } });
    write({ method: "item/started", params: { threadId, turnId, startedAtMs: 3, item: { type: "agentMessage", id: "msg-1", text: "", phase: "final_answer", memoryCitation: null } } });
    write({ method: "item/agentMessage/delta", params: { threadId, turnId, itemId: "msg-1", delta: "Done from app-server." } });
    write({ method: "item/completed", params: { threadId, turnId, completedAtMs: 4, item: { type: "agentMessage", id: "msg-1", text: "Done from app-server.", phase: "final_answer", memoryCitation: null } } });
    write({ method: "turn/completed", params: { threadId, turn: makeTurn(turnId, "completed") } });
    return;
  }
  if (message.method === "turn/interrupt") {
    respond(message.id, {});
    write({ method: "turn/completed", params: { threadId, turn: makeTurn(message.params.turnId, "interrupted") } });
    return;
  }
  if (message.method === "thread/goal/set") {
    const goal = {
      threadId,
      objective: message.params.objective,
      status: message.params.status ?? "active",
      tokenBudget: message.params.tokenBudget ?? null,
      tokensUsed: 0,
      timeUsedSeconds: 0,
      createdAt: 1,
      updatedAt: 1,
    };
    write({ method: "thread/goal/updated", params: { threadId, turnId: null, goal } });
    respond(message.id, { goal });
    return;
  }
  if (message.method === "thread/goal/clear") {
    write({ method: "thread/goal/cleared", params: { threadId, turnId: null } });
    respond(message.id, { cleared: true });
    return;
  }
  if (message.method === "account/read") {
    respond(message.id, {
      account: { type: "chatgpt", email: "unit@example.com", planType: "pro" },
      requiresOpenaiAuth: false,
    });
    return;
  }
  if (message.method === "getAuthStatus") {
    respond(message.id, {
      authMethod: "chatgpt",
      authToken: message.params.includeToken ? "redacted-token" : null,
      requiresOpenaiAuth: false,
    });
    return;
  }
  if (message.method === "account/login/start") {
    if (message.params.type === "chatgptDeviceCode") {
      respond(message.id, {
        type: "chatgptDeviceCode",
        loginId: "login-device",
        verificationUrl: "https://auth.openai.com/activate",
        userCode: "CODE-123",
      });
      write({ method: "account/login/completed", params: { loginId: "login-device", success: true, error: null } });
      write({ method: "account/updated", params: { authMode: "chatgpt", planType: "pro" } });
      return;
    }
    if (message.params.type === "chatgpt") {
      respond(message.id, {
        type: "chatgpt",
        loginId: "login-browser",
        authUrl: "https://chatgpt.com/backend-api/codex/login?state=unit",
      });
      return;
    }
    if (message.params.type === "apiKey") {
      respond(message.id, { type: "apiKey" });
      write({ method: "account/updated", params: { authMode: "apikey", planType: null } });
      return;
    }
  }
  if (message.method === "account/login/cancel") {
    respond(message.id, { status: message.params.loginId === "missing" ? "notFound" : "canceled" });
    return;
  }
  if (message.method === "account/logout") {
    respond(message.id, {});
    write({ method: "account/updated", params: { authMode: null, planType: null } });
    return;
  }
  respond(message.id, {});
});
`;
describe("AppServerCodexSession", () => {
    it("streams app-server thread and turn notifications as Codex bridge events", async () => {
        let savedThreadId = "";
        const session = new AppServerCodexSession({
            command: process.execPath,
            argsPrefix: ["-e", fakeAppServerScript],
            workdir: process.cwd(),
            sandbox: "workspace-write",
            onThreadStarted: (threadId) => {
                savedThreadId = threadId;
            },
        });
        const events = [];
        session.onEvent((event) => events.push(event));
        const result = await session.sendPrompt("read notes");
        await waitForCompletion(events);
        expect(result.runId).toBe("turn-1");
        expect(savedThreadId).toBe("thread-test");
        expect(events.some((event) => event.type === "run.started" && event.runId === "turn-1")).toBe(true);
        expect(events.some((event) => event.type === "message.started" && event.title === "Reading file")).toBe(true);
        expect(events.some((event) => event.type === "message.started" && event.title === "Thinking summary")).toBe(true);
        expect(events).toContainEqual({
            type: "session.plan.updated",
            sessionId: session.sessionId,
            runId: "turn-1",
            title: "Plan",
            text: expect.stringContaining("Checking the mobile bridge polish"),
        });
        expect(events.some((event) => event.type === "message.started" && event.title === "Plan")).toBe(false);
        expect(events.some((event) => event.type === "message.delta" && event.text.includes("Checked repository shape"))).toBe(true);
        expect(events.some((event) => event.type === "message.delta" && event.text.includes("Reading project metadata"))).toBe(true);
        expect(events.some((event) => event.type === "message.delta" && event.text.includes("Terminal input"))).toBe(true);
        expect(events.some((event) => event.type === "message.delta" && event.text.includes("notes content"))).toBe(true);
        expect(events.some((event) => event.type === "diff.available" && event.files.some((file) => file.path === "notes.txt" && file.patch?.includes("+new")))).toBe(true);
        expect(events.some((event) => event.type === "message.delta" && event.text.includes("Unit warning"))).toBe(true);
        expect(events.some((event) => event.type === "message.delta" && event.text.includes("Done from app-server"))).toBe(true);
        expect(events.some((event) => event.type === "run.completed" && event.exitCode === 0)).toBe(true);
        await session.close();
    });
    it("sets and clears app-server goals through native thread goal RPC", async () => {
        const session = new AppServerCodexSession({
            command: process.execPath,
            argsPrefix: ["-e", fakeAppServerScript],
            workdir: process.cwd(),
        });
        const events = [];
        session.onEvent((event) => events.push(event));
        const goal = await session.setGoal({ objective: "Finish the migration", status: "active" });
        await session.clearGoal();
        expect(goal.objective).toBe("Finish the migration");
        expect(events).toContainEqual({
            type: "session.goal.updated",
            sessionId: session.sessionId,
            goal: expect.objectContaining({ objective: "Finish the migration", status: "active" }),
        });
        expect(events).toContainEqual({
            type: "session.goal.cleared",
            sessionId: session.sessionId,
        });
        await session.close();
    });
    it("reads account status and starts native account login flows", async () => {
        const session = new AppServerCodexSession({
            command: process.execPath,
            argsPrefix: ["-e", fakeAppServerScript],
            workdir: process.cwd(),
        });
        const events = [];
        session.onEvent((event) => events.push(event));
        const account = await session.getAccount();
        const deviceFlow = await session.startAccountLogin({ type: "chatgptDeviceCode" });
        const browserFlow = await session.startAccountLogin({ type: "chatgpt" });
        const apiKeyFlow = await session.startAccountLogin({ type: "apiKey", apiKey: "sk-unit-secret" });
        const cancel = await session.cancelAccountLogin("login-device");
        await session.logoutAccount();
        expect(account).toMatchObject({
            accountType: "chatgpt",
            email: "unit@example.com",
            planType: "pro",
            authMode: "chatgpt",
            requiresOpenaiAuth: false,
        });
        expect(deviceFlow).toMatchObject({
            type: "chatgptDeviceCode",
            loginId: "login-device",
            verificationUrl: "https://auth.openai.com/activate",
            userCode: "CODE-123",
        });
        expect(browserFlow).toMatchObject({
            type: "chatgpt",
            loginId: "login-browser",
            authUrl: "https://chatgpt.com/backend-api/codex/login?state=unit",
        });
        expect(apiKeyFlow).toMatchObject({ type: "apiKey" });
        expect(cancel).toEqual({ status: "canceled" });
        expect(events).toContainEqual({
            type: "app.account.login.completed",
            loginId: "login-device",
            success: true,
            error: null,
        });
        expect(events.some((event) => event.type === "app.account.updated")).toBe(true);
        await session.close();
    });
    it("exposes native app-server models, threads, skills, filesystem, fuzzy search, and review", async () => {
        const session = new AppServerCodexSession({
            command: process.execPath,
            argsPrefix: ["-e", fakeAppServerScript],
            workdir: process.cwd(),
        });
        const models = await session.listModels(true);
        const threads = await session.listThreads({ query: "Native", cwd: process.cwd(), limit: 5 });
        const thread = await session.readThread("native-thread", true);
        const skills = await session.listSkills({ cwds: [process.cwd()], forceReload: true });
        const entries = await session.listDirectory(process.cwd());
        const file = await session.readFile(process.cwd() + "/README.md");
        const fuzzy = await session.searchFiles({ query: "main", roots: [process.cwd()], limit: 5 });
        const review = await session.startReview({ target: { type: "uncommittedChanges" }, delivery: "inline" });
        expect(models).toMatchObject({
            models: [expect.objectContaining({ id: "gpt-test", displayName: "GPT Test", supportedReasoningEfforts: ["low", "high"] })],
            capabilities: { namespaceTools: true, imageGeneration: true, webSearch: true },
        });
        expect(threads).toEqual([expect.objectContaining({ threadId: "native-thread", title: "Native app-server history", workdir: process.cwd() })]);
        expect(thread.messages.some((message) => message.text.includes("Bridge reviewed"))).toBe(true);
        expect(skills.groups[0].skills[0]).toMatchObject({ name: "flutter-design-system", enabled: true });
        expect(entries).toContainEqual(expect.objectContaining({ name: "README.md", path: "README.md", isFile: true }));
        expect(file).toMatchObject({ name: "README.md", text: "hello native file\n" });
        expect(fuzzy).toEqual([expect.objectContaining({ path: "lib/main.dart", name: "main.dart" })]);
        expect(review).toMatchObject({ runId: "review-turn", reviewThreadId: "thread-test" });
        await session.close();
    });
    it("cancels the active app-server turn with turn interrupt", async () => {
        const session = new AppServerCodexSession({
            command: process.execPath,
            argsPrefix: ["-e", fakeAppServerScript],
            workdir: process.cwd(),
        });
        const events = [];
        session.onEvent((event) => events.push(event));
        const { runId } = await session.sendPrompt("stay running");
        await waitForRunStarted(events, runId);
        await session.cancel(runId);
        await waitForCompletion(events);
        expect(events.some((event) => event.type === "status" && event.status === "cancelling")).toBe(true);
        expect(events.some((event) => event.type === "status" && event.status === "cancelled")).toBe(true);
        expect(events.some((event) => event.type === "run.completed" && event.runId === runId)).toBe(true);
        await session.close();
    });
});
async function waitForCompletion(events, timeoutMs = 2_000) {
    const startedAt = Date.now();
    while (!events.some((event) => event.type === "run.completed")) {
        if (Date.now() - startedAt > timeoutMs) {
            throw new Error("Timed out waiting for app-server session completion");
        }
        await new Promise((resolve) => setTimeout(resolve, 25));
    }
}
async function waitForRunStarted(events, runId, timeoutMs = 1_000) {
    const startedAt = Date.now();
    while (!events.some((event) => event.type === "run.started" && event.runId === runId)) {
        if (Date.now() - startedAt > timeoutMs) {
            throw new Error(`Timed out waiting for run start: ${runId}`);
        }
        await new Promise((resolve) => setTimeout(resolve, 25));
    }
}
