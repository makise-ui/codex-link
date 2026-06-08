import type { AppFsEntryRecord, AppFsFileRecord, AppModelRecord, AppProviderCapabilitiesRecord, AppSkillGroupRecord, AppThreadHistoryRecord, AppThreadRecord, ApprovalRequestedMessage, DiffAvailableMessage, MessageCompletedMessage, MessageDeltaMessage, MessageStartedMessage, OutputDeltaMessage, ReasoningEffort, RunCompletedMessage, RunStartedMessage, SessionGoalClearedMessage, SessionGoalRecord, SessionGoalUpdatedMessage, SessionPlanUpdatedMessage, SessionStartedMessage, SessionUpdatedMessage, StatusMessage, WorkspaceFileRecord } from "../protocol/messages.js";

export type CodexEvent =
  | SessionStartedMessage
  | SessionUpdatedMessage
  | RunStartedMessage
  | OutputDeltaMessage
  | MessageStartedMessage
  | MessageDeltaMessage
  | MessageCompletedMessage
  | DiffAvailableMessage
  | ApprovalRequestedMessage
  | SessionGoalUpdatedMessage
  | SessionGoalClearedMessage
  | SessionPlanUpdatedMessage
  | StatusMessage
  | RunCompletedMessage;

export type SendPromptResult = {
  runId: string;
};

export type PreparedAttachment = {
  path: string;
  name: string;
  kind: "image" | "file";
};

export type SendPromptOptions = {
  attachments?: PreparedAttachment[];
};

export type GoalSetInput = {
  objective?: string;
  status?: SessionGoalRecord["status"];
  tokenBudget?: number | null;
};

export type AppModelListResult = {
  models: AppModelRecord[];
  capabilities: AppProviderCapabilitiesRecord;
};

export type AppThreadListInput = {
  query?: string;
  cwd?: string;
  limit?: number;
};

export type AppSkillListInput = {
  cwds?: string[];
  forceReload?: boolean;
};

export type AppFileSearchInput = {
  query: string;
  roots: string[];
  limit?: number;
};

export type AppReviewStartInput = {
  target: { type: "uncommittedChanges" } | { type: "custom"; instructions: string };
  delivery?: "inline" | "detached";
};

export type AppReviewStartResult = {
  runId: string;
  reviewThreadId: string;
};

export interface CodexSession {
  readonly sessionId: string;
  start(): Promise<void>;
  sendPrompt(prompt: string, options?: SendPromptOptions): Promise<SendPromptResult>;
  listModels?(includeHidden?: boolean): Promise<AppModelListResult>;
  listThreads?(input?: AppThreadListInput): Promise<AppThreadRecord[]>;
  readThread?(threadId: string, includeTurns?: boolean): Promise<AppThreadHistoryRecord>;
  listSkills?(input?: AppSkillListInput): Promise<{ groups: AppSkillGroupRecord[] }>;
  listDirectory?(absolutePath: string): Promise<AppFsEntryRecord[]>;
  readFile?(absolutePath: string): Promise<AppFsFileRecord>;
  searchFiles?(input: AppFileSearchInput): Promise<WorkspaceFileRecord[]>;
  startReview?(input: AppReviewStartInput): Promise<AppReviewStartResult>;
  setGoal?(input: GoalSetInput): Promise<SessionGoalRecord>;
  getGoal?(): Promise<SessionGoalRecord | null>;
  clearGoal?(): Promise<boolean>;
  cancel(runId: string): Promise<void>;
  decideApproval?(approvalId: string, decision: "approve" | "reject"): Promise<void>;
  onEvent(listener: (event: CodexEvent) => void): () => void;
  close(): Promise<void>;
}

export type CodexSessionFactory = () => CodexSession;
