export class AuditLog {
    logger;
    constructor(logger) {
        this.logger = logger;
    }
    record(event) {
        this.logger.info({ audit: true, ...event }, "audit event");
    }
}
