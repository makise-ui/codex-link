export const COMMAND_CATALOG = [
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
