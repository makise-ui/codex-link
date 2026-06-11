import { execFile } from "node:child_process";
import { chmod, mkdir, mkdtemp, readFile, rm, stat, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { afterEach, describe, expect, it, vi } from "vitest";
import { CodexSessionManager, summarizeDoctorOutput } from "../src/codex/sessionManager.js";

const tempDirs: string[] = [];
const execFileAsync = promisify(execFile);

afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

describe("CodexSessionManager", () => {
  it("creates a default persistent session and supports workspace switching", async () => {
    const stateDir = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [
        { id: "default", label: "repo", path: "/repo" },
        { id: "workspace-2", label: "other", path: "/other" },
      ],
    });

    const [initial] = manager.listSessions();
    expect(initial.workspaceId).toBe("default");
    expect(initial.sandbox).toBe("workspace-write");

    const updated = await manager.switchWorkspace(initial.sessionId, "workspace-2");
    expect(updated.workspaceId).toBe("workspace-2");
    expect(updated.workdir).toBe("/other");
    expect(updated.codexThreadId).toBeUndefined();

    await manager.close();
  });

  it("runs shell commands in the session workspace", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    await writeFile(path.join(workspace, "marker.txt"), "workspace marker\n");
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: true,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = manager.listSessions();
    await manager.setSessionMode(session.sessionId, "yolo");

    const result = await manager.runShellCommand(session.sessionId, "pwd && cat marker.txt");

    expect(result.type).toBe("shell.command.result");
    expect(result.exitCode).toBe(0);
    expect(result.cwd).toBe(workspace);
    expect(result.stdout).toContain(workspace);
    expect(result.stdout).toContain("workspace marker");
    await manager.close();
  });

  it("rejects shell commands unless the session is in yolo mode", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = manager.listSessions();

    await expect(manager.runShellCommand(session.sessionId, "pwd")).rejects.toThrow(/yolo/i);

    await manager.close();
  });

  it("requires explicit host permission for yolo mode", async () => {
    const stateDir = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });
    const [session] = manager.listSessions();

    await expect(manager.setSessionMode(session.sessionId, "yolo")).rejects.toThrow(/--allow-yolo/);
    await manager.close();
  });

  it("maps yolo to danger-full-access when allowed", async () => {
    const stateDir = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: true,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });
    const [session] = manager.listSessions();

    const updated = await manager.setSessionMode(session.sessionId, "yolo");
    expect(updated.mode).toBe("yolo");
    expect(updated.sandbox).toBe("danger-full-access");
    await manager.close();
  });

  it("adds a host workspace path and persists it", async () => {
    const stateDir = await tempStateDir();
    const extraWorkspace = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });
    const [session] = manager.listSessions();

    const workspace = await manager.addWorkspace(extraWorkspace, session.sessionId);

    expect(workspace.path).toBe(extraWorkspace);
    expect(manager.getWorkspaces(session.sessionId).some((item) => item.path === extraWorkspace && item.active)).toBe(true);

    await manager.close();
    const restored = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });

    expect(restored.getWorkspaces().some((item) => item.path === extraWorkspace)).toBe(true);
    await restored.close();
  });

  it("can create a new host workspace directory from the client request", async () => {
    const stateDir = await tempStateDir();
    const parent = await tempStateDir();
    const newWorkspace = path.join(parent, "created-from-phone");
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });
    const [session] = manager.listSessions();

    const workspace = await manager.addWorkspace(newWorkspace, session.sessionId, { create: true });

    expect(workspace.path).toBe(newWorkspace);
    expect(workspace.active).toBe(true);
    expect(manager.getWorkspaces(session.sessionId).some((item) => item.path === newWorkspace && item.active)).toBe(true);
    await manager.close();
  });

  it("clones a git url when adding a workspace from the client", async () => {
    const stateDir = await tempStateDir();
    const source = await tempStateDir();
    await execFileAsync("git", ["init"], { cwd: source });
    await writeFile(path.join(source, "README.md"), "# cloned\n");
    await execFileAsync("git", ["add", "README.md"], { cwd: source });
    await execFileAsync("git", ["-c", "user.name=Unit", "-c", "user.email=unit@example.com", "commit", "-m", "init"], { cwd: source });
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });
    const [session] = manager.listSessions();

    const workspace = await manager.addWorkspace(`file://${source}`, session.sessionId);
    tempDirs.push(workspace.path);

    expect(workspace.active).toBe(true);
    await expect(readFile(path.join(workspace.path, "README.md"), "utf8")).resolves.toBe("# cloned\n");
    await manager.close();
  });

  it("clones same-name git repositories into distinct workspace directories", async () => {
    const stateDir = await tempStateDir();
    const firstSource = await tempStateDir();
    const secondParent = await tempStateDir();
    const secondSource = path.join(secondParent, path.basename(firstSource));
    await mkdir(secondSource, { recursive: true });
    await initGitRepo(firstSource, "FIRST");
    await initGitRepo(secondSource, "SECOND");
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });
    const [session] = manager.listSessions();

    const firstWorkspace = await manager.addWorkspace(`file://${firstSource}`, session.sessionId);
    const secondWorkspace = await manager.addWorkspace(`file://${secondSource}`, session.sessionId);
    tempDirs.push(firstWorkspace.path, secondWorkspace.path);

    expect(firstWorkspace.path).not.toBe(secondWorkspace.path);
    await expect(readFile(path.join(firstWorkspace.path, "README.md"), "utf8")).resolves.toBe("FIRST\n");
    await expect(readFile(path.join(secondWorkspace.path, "README.md"), "utf8")).resolves.toBe("SECOND\n");
    await manager.close();
  });

  it("creates the playground directory when switching into it", async () => {
    const stateDir = await tempStateDir();
    const parent = await tempStateDir();
    const playground = path.join(parent, "playground");
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [
        { id: "default", label: "repo", path: "/repo" },
        { id: "playground", label: "Playground", path: playground },
      ],
    });
    const [session] = manager.listSessions();

    const updated = await manager.switchWorkspace(session.sessionId, "playground");

    expect(updated.workdir).toBe(playground);
    const stats = await stat(playground);
    expect(stats.isDirectory()).toBe(true);
    await manager.close();
  });

  it("persists model reasoning effort and service tier with the session", async () => {
    const stateDir = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });
    const [session] = manager.listSessions();

    const updated = await manager.setSessionConfig(session.sessionId, { model: "gpt-5-codex", reasoningEffort: "xhigh", serviceTier: "priority" });

    expect(updated.model).toBe("gpt-5-codex");
    expect(updated.reasoningEffort).toBe("xhigh");
    expect(updated.serviceTier).toBe("priority");

    await manager.close();
    const restored = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });

    expect(restored.listSessions()[0]).toEqual(expect.objectContaining({ model: "gpt-5-codex", reasoningEffort: "xhigh", serviceTier: "priority" }));
    await restored.close();
  });

  it("preserves model when only effort changes and clears model or service tier when requested", async () => {
    const stateDir = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });
    const [session] = manager.listSessions();

    await manager.setSessionConfig(session.sessionId, { model: "gpt-5-codex", reasoningEffort: "medium", serviceTier: "priority" });
    const effortOnly = await manager.setSessionConfig(session.sessionId, { reasoningEffort: "low" });

    expect(effortOnly.model).toBe("gpt-5-codex");
    expect(effortOnly.reasoningEffort).toBe("low");
    expect(effortOnly.serviceTier).toBe("priority");
    const cleared = await manager.setSessionConfig(session.sessionId, { model: "" });
    expect(cleared.model).toBeUndefined();
    expect(cleared.reasoningEffort).toBe("low");
    const tierCleared = await manager.setSessionConfig(session.sessionId, { serviceTier: null });
    expect(tierCleared.serviceTier).toBeUndefined();
    await manager.close();
  });

  it("sets, gets, clears, and persists native session goals", async () => {
    const stateDir = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });
    const events: Array<{ type: string }> = [];
    manager.onEvent((event) => {
      if (event.type === "session.goal.updated" || event.type === "session.goal.cleared") {
        events.push(event);
      }
    });
    const [session] = manager.listSessions();

    const goal = await manager.setGoal(session.sessionId, {
      objective: "Finish the app-server adapter",
      status: "active",
      tokenBudget: 20000,
    });

    expect(goal.objective).toBe("Finish the app-server adapter");
    expect(goal.status).toBe("active");
    expect(manager.listSessions()[0].goal).toEqual(expect.objectContaining({ objective: "Finish the app-server adapter" }));
    expect(await manager.getGoal(session.sessionId)).toEqual(expect.objectContaining({ objective: "Finish the app-server adapter" }));
    expect(events.some((event) => event.type === "session.goal.updated")).toBe(true);

    await manager.close();
    const restored = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: "/repo" }],
    });

    expect(restored.listSessions()[0].goal).toEqual(expect.objectContaining({ objective: "Finish the app-server adapter" }));
    expect(await restored.clearGoal(restored.listSessions()[0].sessionId)).toBe(true);
    expect(restored.listSessions()[0].goal).toBeUndefined();
    await restored.close();
  });

  it("stores user prompts and streamed agent messages as replayable history", async () => {
    vi.useFakeTimers();
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = manager.listSessions();

    await manager.sendPrompt(session.sessionId, "hello history");
    await vi.advanceTimersByTimeAsync(2_000);
    await manager.close();

    const history = manager.getSessionHistory(session.sessionId);
    expect(history.some((message) => message.role === "user" && message.text === "hello history")).toBe(true);
    expect(history.some((message) => message.kind === "executing" && message.text.includes("Checking the host bridge"))).toBe(true);
    expect(history.every((message) => message.kind !== "thinking")).toBe(true);
    expect(history.every((message) => message.text.trim() !== "Thinking…")).toBe(true);

    vi.useRealTimers();
  });

  it("emits file offers for uploaded workspace files and downloads them", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const events: Array<{ type: string; fileId?: string; name?: string }> = [];
    manager.onEvent((event) => {
      if (event.type === "file.offer") {
        events.push(event);
      }
    });
    const [session] = manager.listSessions();

    await manager.sendPrompt(session.sessionId, "use this file", [
      {
        name: "notes.txt",
        mimeType: "text/plain",
        dataBase64: Buffer.from("hello from phone").toString("base64"),
      },
    ]);

    const offer = events.find((event) => event.type === "file.offer");
    expect(offer).toMatchObject({ name: "notes.txt" });
    const download = await manager.downloadFile(offer!.fileId!);
    expect(download.dataBase64).toBe(Buffer.from("hello from phone").toString("base64"));
    await manager.close();
  });

  it("offers requested workspace files without asking the agent to paste contents", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    await writeFile(path.join(workspace, "report.txt"), "download me from host");
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const events: Array<{ type: string; fileId?: string; name?: string; reason?: string }> = [];
    manager.onEvent((event) => {
      if (event.type === "file.offer") {
        events.push(event);
      }
    });
    const [session] = manager.listSessions();

    const offer = await manager.offerRequestedFile(session.sessionId, "report.txt");

    expect(offer).toMatchObject({ name: "report.txt", reason: "requested" });
    expect(events).toHaveLength(1);
    const download = await manager.downloadFile(offer.fileId);
    expect(Buffer.from(download.dataBase64, "base64").toString("utf8")).toBe("download me from host");
    expect(manager.getSessionHistory(session.sessionId).some((message) => message.kind === "files" && message.text.includes("requested report.txt"))).toBe(true);
    await manager.close();
  });

  it("offers a requested nested workspace file by unique basename", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    await mkdir(path.join(workspace, "assets", "screens"), { recursive: true });
    await writeFile(path.join(workspace, "assets", "screens", "flutter_03.png"), "png bytes");
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = manager.listSessions();

    const offer = await manager.offerRequestedFile(session.sessionId, "@flutter_03.png");

    expect(offer).toMatchObject({
      name: "flutter_03.png",
      path: "assets/screens/flutter_03.png",
      reason: "requested",
    });
    await manager.close();
  });

  it("writes pasted env secrets into the active workspace env file", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    await writeFile(path.join(workspace, ".env.local"), "OLD=value\nKEEP=yes\n");
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = manager.listSessions();

    const result = await manager.setWorkspaceEnv(session.sessionId, [
      "OPENAI_API_KEY=sk-unit",
      "LIST=value1,value2",
      "export OLD=replaced",
      "bad key=nope",
      "# comment",
    ].join("\n"));

    expect(result).toEqual({
      type: "workspace.env.updated",
      sessionId: session.sessionId,
      path: ".env.local",
      variableNames: ["OPENAI_API_KEY", "LIST", "OLD"],
      skippedLineCount: 2,
    });
    await expect(readFile(path.join(workspace, ".env.local"), "utf8")).resolves.toBe(
      "OLD=replaced\nKEEP=yes\nOPENAI_API_KEY=sk-unit\nLIST=value1,value2\n",
    );
    await manager.close();
  });

  it("tightens existing env secret file permissions to owner-only", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    const envPath = path.join(workspace, ".env.local");
    await writeFile(envPath, "OLD=value\n");
    await chmod(envPath, 0o644);
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = manager.listSessions();

    await manager.setWorkspaceEnv(session.sessionId, "OPENAI_API_KEY=sk-unit");

    expect((await stat(envPath)).mode & 0o777).toBe(0o600);
    await manager.close();
  });

  it("searches active workspace files for mobile mentions", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    await mkdir(path.join(workspace, "lib"), { recursive: true });
    await mkdir(path.join(workspace, "node_modules", "pkg"), { recursive: true });
    await writeFile(path.join(workspace, "lib", "main.dart"), "void main() {}\n");
    await writeFile(path.join(workspace, "node_modules", "pkg", "main.dart"), "ignored\n");
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = manager.listSessions();

    const results = await manager.searchWorkspaceFiles(session.sessionId, "@main", 10);

    expect(results).toMatchObject({
      type: "workspace.file.search.results",
      sessionId: session.sessionId,
      query: "main",
    });
    expect(results.files).toEqual([
      expect.objectContaining({
        path: "lib/main.dart",
        name: "main.dart",
        mimeType: "text/plain",
      }),
    ]);
    expect(results.files.some((file) => file.path.includes("node_modules"))).toBe(false);
    await manager.close();
  });

  it("rejects fallback app file writes through symlinks outside the workspace", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    const outside = await tempStateDir();
    const outsideFile = path.join(outside, "secret.txt");
    await writeFile(outsideFile, "outside\n");
    await symlink(outsideFile, path.join(workspace, "linked-secret.txt"));
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = manager.listSessions();

    await expect(
      manager.writeAppFile(session.sessionId, "linked-secret.txt", Buffer.from("owned\n").toString("base64")),
    ).rejects.toThrow(/outside the active workspace|Refusing to write through a symlink/);
    await expect(readFile(outsideFile, "utf8")).resolves.toBe("outside\n");
    await manager.close();
  });

  it("exposes app-server capability fallbacks for models, files, skills, search, and review", async () => {
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    await mkdir(path.join(workspace, "lib"), { recursive: true });
    await writeFile(path.join(workspace, "README.md"), "# Unit\n");
    await writeFile(path.join(workspace, "lib", "main.dart"), "void main() {}\n");
    const manager = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = manager.listSessions();

    const models = await manager.listAppModels(session.sessionId, false);
    const skills = await manager.listAppSkills(session.sessionId, false);
    const entries = await manager.listAppDirectory(session.sessionId, "");
    const file = await manager.readAppFile(session.sessionId, "README.md");
    const written = await manager.writeAppFile(session.sessionId, "notes/unit.txt", Buffer.from("from phone\n").toString("base64"));
    const created = await manager.createAppDirectory(session.sessionId, "scratch/new-folder");
    const search = await manager.searchAppFiles(session.sessionId, "@main", 10);
    const review = await manager.startReview(session.sessionId, { target: "custom", instructions: "Review current changes", delivery: "inline" });

    expect(models.models.some((model) => model.id === "gpt-5.5")).toBe(true);
    expect(skills.groups[0]).toMatchObject({ cwd: workspace });
    expect(entries.entries).toContainEqual(expect.objectContaining({ name: "README.md", path: "README.md", isFile: true }));
    expect(file.file).toMatchObject({ name: "README.md", text: "# Unit\n" });
    expect(written.file).toMatchObject({ path: "notes/unit.txt", name: "unit.txt", text: "from phone\n" });
    await expect(readFile(path.join(workspace, "notes", "unit.txt"), "utf8")).resolves.toBe("from phone\n");
    expect(created).toMatchObject({ path: "scratch/new-folder" });
    expect((await stat(path.join(workspace, "scratch", "new-folder"))).isDirectory()).toBe(true);
    expect(search.files).toEqual([expect.objectContaining({ path: "lib/main.dart", name: "main.dart" })]);
    expect(review).toMatchObject({ sessionId: session.sessionId, runId: expect.stringMatching(/^mock-review-/), reviewThreadId: session.sessionId });

    await manager.close();
  });

  it("replays saved history after a manager restart", async () => {
    vi.useFakeTimers();
    const stateDir = await tempStateDir();
    const workspace = await tempStateDir();
    const first = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });
    const [session] = first.listSessions();

    await first.sendPrompt(session.sessionId, "persist this after restart");
    await vi.advanceTimersByTimeAsync(2_000);
    await first.close();
    vi.useRealTimers();

    const restarted = await CodexSessionManager.create({
      sessionMode: "mock",
      codexCommand: "codex",
      stateDir,
      defaultSandbox: "workspace-write",
      allowYolo: false,
      workspaces: [{ id: "default", label: "repo", path: workspace }],
    });

    const history = restarted.getSessionHistory(session.sessionId);
    expect(history.some((message) => message.role === "user" && message.text === "persist this after restart")).toBe(true);
    expect(history.some((message) => message.role === "assistant" && message.text.includes("Connected to the local Codex Link bridge"))).toBe(true);
    await restarted.close();
  });

  it("formats codex doctor json as a readable mobile report", () => {
    const report = summarizeDoctorOutput(
      JSON.stringify({
        schemaVersion: 1,
        overallStatus: "ok",
        codexVersion: "0.137.0",
        checks: {
          "config.load": {
            id: "config.load",
            category: "config",
            status: "ok",
            summary: "config loaded",
            details: {
              cwd: "/repo/flutter",
              model: "gpt-5.5",
              "model provider": "openai",
              "mcp servers": "0",
            },
          },
          "sandbox.helpers": {
            id: "sandbox.helpers",
            category: "sandbox",
            status: "ok",
            summary: "sandbox configuration is readable",
            details: {
              "approval policy": "OnRequest",
              "filesystem sandbox": "restricted",
              "network sandbox": "restricted",
            },
          },
          "auth.credentials": {
            id: "auth.credentials",
            category: "auth",
            status: "ok",
            summary: "auth is configured",
            details: {
              "stored auth mode": "chatgpt",
              "stored ChatGPT tokens": "true",
              "stored API key": "false",
            },
          },
          "app_server.status": {
            id: "app_server.status",
            category: "app-server",
            status: "ok",
            summary: "background server is not running",
            details: {
              mode: "ephemeral",
              status: "not running",
            },
          },
          "network.websocket_reachability": {
            id: "network.websocket_reachability",
            category: "websocket",
            status: "ok",
            summary: "Responses WebSocket handshake succeeded",
            details: {
              "handshake result": "HTTP 101 Switching Protocols",
              endpoint: "wss://chatgpt.com/backend-api/<redacted>",
            },
          },
        },
      }),
      "",
    ).join("\n");

    expect(report).toContain("Codex version:       0.137.0");
    expect(report).toContain("Model:               gpt-5.5 (provider openai)");
    expect(report).toContain("Directory:           /repo/flutter");
    expect(report).toContain("Permissions:         restricted filesystem, restricted network");
    expect(report).toContain("Account:             chatgpt auth, ChatGPT tokens stored");
    expect(report).toContain("WebSocket:           HTTP 101 Switching Protocols");
    expect(report).toContain("OK   config.load - config loaded");
    expect(report).not.toContain("\"checks\"");
  });
});

async function tempStateDir(): Promise<string> {
  const dir = await mkdtemp(path.join(os.tmpdir(), "codex-lan-host-"));
  await mkdir(dir, { recursive: true });
  tempDirs.push(dir);
  return dir;
}

async function initGitRepo(directory: string, readme: string): Promise<void> {
  await execFileAsync("git", ["init"], { cwd: directory });
  await writeFile(path.join(directory, "README.md"), `${readme}\n`);
  await execFileAsync("git", ["add", "README.md"], { cwd: directory });
  await execFileAsync("git", ["-c", "user.name=Unit", "-c", "user.email=unit@example.com", "commit", "-m", "init"], { cwd: directory });
}
