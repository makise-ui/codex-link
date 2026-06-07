import type { DiffAvailableMessage, MessageCompletedMessage, MessageDeltaMessage, MessageStartedMessage, OutputDeltaMessage, RunCompletedMessage, RunStartedMessage, SessionStartedMessage, SessionUpdatedMessage, StatusMessage } from "../protocol/messages.js";

export type CodexEvent =
  | SessionStartedMessage
  | SessionUpdatedMessage
  | RunStartedMessage
  | OutputDeltaMessage
  | MessageStartedMessage
  | MessageDeltaMessage
  | MessageCompletedMessage
  | DiffAvailableMessage
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

export interface CodexSession {
  readonly sessionId: string;
  start(): Promise<void>;
  sendPrompt(prompt: string, options?: SendPromptOptions): Promise<SendPromptResult>;
  cancel(runId: string): Promise<void>;
  onEvent(listener: (event: CodexEvent) => void): () => void;
  close(): Promise<void>;
}

export type CodexSessionFactory = () => CodexSession;
