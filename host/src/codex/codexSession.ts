import type { MessageCompletedMessage, MessageDeltaMessage, MessageStartedMessage, OutputDeltaMessage, RunCompletedMessage, RunStartedMessage, SessionStartedMessage, SessionUpdatedMessage, StatusMessage } from "../protocol/messages.js";

export type CodexEvent =
  | SessionStartedMessage
  | SessionUpdatedMessage
  | RunStartedMessage
  | OutputDeltaMessage
  | MessageStartedMessage
  | MessageDeltaMessage
  | MessageCompletedMessage
  | StatusMessage
  | RunCompletedMessage;

export type SendPromptResult = {
  runId: string;
};

export interface CodexSession {
  readonly sessionId: string;
  start(): Promise<void>;
  sendPrompt(prompt: string): Promise<SendPromptResult>;
  cancel(runId: string): Promise<void>;
  onEvent(listener: (event: CodexEvent) => void): () => void;
  close(): Promise<void>;
}

export type CodexSessionFactory = () => CodexSession;
