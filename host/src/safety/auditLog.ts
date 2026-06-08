import type pino from "pino";

export type AuditEvent = {
  type:
    | "pairing.created"
    | "device.paired"
    | "device.authenticated"
    | "device.disconnected"
    | "session.started"
    | "prompt.submitted"
    | "approval.decided"
    | "run.cancelled"
    | "run.failed"
    | "run.completed";
  deviceId?: string;
  sessionId?: string;
  runId?: string;
  detail?: string;
};

export class AuditLog {
  constructor(private readonly logger: pino.Logger) {}

  record(event: AuditEvent): void {
    this.logger.info({ audit: true, ...event }, "audit event");
  }
}
