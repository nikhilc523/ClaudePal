import { normalizeHookPayload } from "../domain/normalize-hook-payload.js";

const RESOLUTION_STATUSES = {
  approve: "approved",
  deny: "denied",
  submit_input: "submitted",
  cancel: "cancelled",
  timeout: "expired"
};

const SESSION_STATUSES = {
  approve: "active",
  deny: "active",
  submit_input: "active",
  cancel: "active",
  timeout: "idle"
};

const ALLOWED_DECISIONS = {
  PermissionRequest: new Set(["approve", "deny", "timeout"]),
  Elicitation: new Set(["submit_input", "deny", "cancel", "timeout"])
};

export class BridgeService {
  constructor({ database, websocketHub, logger, notificationDispatcher = null }) {
    this.database = database;
    this.websocketHub = websocketHub;
    this.logger = logger;
    this.notificationDispatcher = notificationDispatcher;
  }

  async ingestHook(payload, now = new Date()) {
    const normalized = normalizeHookPayload(payload, now);
    const session = this.database.upsertSession(normalized.session);
    const event = this.database.insertEvent(normalized.event);
    const pendingDecision = normalized.pendingDecision
      ? this.database.insertPendingDecision(normalized.pendingDecision)
      : null;
    const pushDispatches = this.notificationDispatcher
      ? await this.notificationDispatcher.dispatchEvent({
          session,
          event,
          pendingDecision
        })
      : [];

    const summary = this.database.getSummary();
    const result = {
      session,
      event,
      pendingDecision,
      pushDispatches,
      summary
    };

    this.logger.info("hook.ingested", {
      hookEventName: payload.hook_event_name,
      sessionId: payload.session_id,
      eventId: event.id,
      pendingDecisionId: pendingDecision?.id ?? null
    });
    this.websocketHub.broadcast({
      type: "event.created",
      ...result
    });

    return result;
  }

  resolvePendingDecision(decisionId, payload, now = new Date()) {
    if (!RESOLUTION_STATUSES[payload.decision]) {
      throw new Error("Unsupported decision.");
    }

    const pendingDecision = this.database.getPendingDecision(decisionId);
    if (!pendingDecision) {
      throw new Error("Pending decision not found.");
    }

    if (pendingDecision.status !== "pending") {
      throw new Error("Pending decision is no longer active.");
    }

    const event = this.database.getEvent(pendingDecision.eventId);
    const allowedDecisions = ALLOWED_DECISIONS[event?.hookEventName];
    if (allowedDecisions && !allowedDecisions.has(payload.decision)) {
      throw new Error(`Unsupported decision for ${event.hookEventName}.`);
    }

    const resolvedAt = now.toISOString();
    const updatedPendingDecision = this.database.resolvePendingDecision({
      id: decisionId,
      status: RESOLUTION_STATUSES[payload.decision],
      resolvedAt,
      resolution: payload
    });
    this.notificationDispatcher?.onPendingDecisionResolved(updatedPendingDecision);
    const session = this.database.updateSessionStatus(
      pendingDecision.sessionId,
      SESSION_STATUSES[payload.decision],
      resolvedAt
    );
    const summary = this.database.getSummary();

    const result = {
      pendingDecision: updatedPendingDecision,
      event,
      session,
      summary
    };

    this.logger.info("decision.resolved", {
      decisionId,
      sessionId: pendingDecision.sessionId,
      decision: payload.decision
    });
    this.websocketHub.broadcast({
      type: "decision.resolved",
      ...result
    });

    return result;
  }

  snapshot() {
    return {
      summary: this.database.getSummary(),
      sessions: this.database.listSessions(),
      pendingDecisions: this.database.listPendingDecisions(),
      recentEvents: this.database.listEvents(20)
    };
  }
}
