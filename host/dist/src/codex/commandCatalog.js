export const COMMAND_CATALOG = [
    {
        commandId: "codex.goal",
        title: "goal",
        description: "Set or inspect the active goal for this session.",
        category: "agent",
    },
    {
        commandId: "codex.status",
        title: "status",
        description: "Ask Codex for current progress, blockers, and next action.",
        category: "agent",
    },
    {
        commandId: "codex.stop",
        title: "stop",
        description: "Stop the currently running response.",
        category: "session",
    },
    {
        commandId: "codex.sessions",
        title: "sessions",
        description: "Open session history and imported Codex sessions.",
        category: "session",
    },
    {
        commandId: "codex.new",
        title: "new",
        description: "Create a new session in the active workspace.",
        category: "session",
    },
    {
        commandId: "codex.workspace",
        title: "workspace",
        description: "Open workspace selection, add folders, and create workspaces.",
        category: "session",
    },
    {
        commandId: "codex.review",
        title: "review",
        description: "Start a native app-server review for the current workspace.",
        category: "agent",
    },
    {
        commandId: "codex.skills",
        title: "skills",
        description: "Open enabled Codex skills for the active workspace.",
        category: "session",
    },
    {
        commandId: "codex.files",
        title: "files",
        description: "Browse and preview files from the active workspace.",
        category: "session",
    },
    {
        commandId: "codex.history",
        title: "history",
        description: "Open app-server and external Codex session history.",
        category: "session",
    },
    {
        commandId: "codex.approvals",
        title: "approvals",
        description: "Jump to pending command approvals for the current run.",
        category: "session",
    },
    {
        commandId: "codex.tunnel",
        title: "tunnel",
        description: "Open tunnel, local URL, and host connection details.",
        category: "session",
    },
    {
        commandId: "codex.doctor",
        title: "doctor",
        description: "Run codex doctor --json on the host for local auth, config, and runtime status.",
        category: "session",
    },
    {
        commandId: "codex.diff",
        title: "diff",
        description: "Ask Codex to summarize the current workspace diff.",
        category: "agent",
    },
    {
        commandId: "codex.compact",
        title: "compact",
        description: "Ask Codex to compact the session into a concise handoff summary.",
        category: "agent",
    },
    {
        commandId: "codex.model",
        title: "model",
        description: "Open model and reasoning effort settings.",
        category: "session",
    },
    {
        commandId: "codex.explain",
        title: "Explain current project",
        description: "Ask Codex to explain the workspace structure and important files.",
        category: "agent",
    },
    {
        commandId: "codex.fix",
        title: "Fix the current issue",
        description: "Ask Codex to inspect errors, make a focused fix, and report verification.",
        category: "agent",
    },
    {
        commandId: "codex.test",
        title: "Run/check tests",
        description: "Ask Codex to run the relevant tests and summarize failures or success.",
        category: "agent",
    },
    {
        commandId: "codex.summarize",
        title: "Summarize session",
        description: "Ask Codex for a concise status summary of the current session.",
        category: "agent",
    },
    {
        commandId: "mode.safe",
        title: "Safe mode",
        description: "Use the host default sandbox for future prompts in this session.",
        category: "mode",
    },
    {
        commandId: "mode.yolo",
        title: "Yolo mode",
        description: "Use danger-full-access for future prompts, only when the host was started with --allow-yolo.",
        category: "mode",
    },
];
export function promptForCommand(commandId) {
    switch (commandId) {
        case "codex.status":
            return "Summarize the current Codex session status: active goal, latest progress, running or pending work, blockers, changed files, verification status, and the next best action.";
        case "codex.diff":
            return "Inspect the current workspace diff and summarize what changed, grouped by feature or bug fix. Mention risky files and tests that should be run.";
        case "codex.compact":
            return "Compact this session into a concise handoff summary with: current goal, decisions made, changed files, commands run, remaining risks, and exact next steps.";
        case "codex.model":
            return "Explain the currently configured model and reasoning effort for this session if available, then recommend whether to keep or change them for the current task.";
        case "codex.explain":
            return "Explain this workspace like a senior engineer onboarding me. Mention the key folders, what each part does, and any commands I should run next.";
        case "codex.fix":
            return "Inspect the current workspace for the most relevant failing issue, make a focused fix if needed, run the smallest useful verification, and summarize exactly what changed.";
        case "codex.test":
            return "Run the relevant tests or checks for this workspace. If something fails, explain the failure and propose or apply the smallest safe fix.";
        case "codex.summarize":
            return "Summarize the current Codex session: goal, files changed, commands run, open risks, and the next best action.";
        default:
            return undefined;
    }
}
