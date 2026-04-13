import test from "node:test";
import assert from "node:assert/strict";
import { NotificationDispatcher } from "../src/push/notification-dispatcher.js";

function createLogger() {
  return {
    info() {},
    warn() {}
  };
}

function createFixture(nowIso = "2026-04-11T20:00:00.000Z") {
  const session = {
    id: "session-1",
    cwd: "/tmp/project",
    displayName: "project",
    status: "waiting",
    lastEventType: "PermissionRequest",
    createdAt: nowIso,
    updatedAt: nowIso
  };
  const event = {
    id: "event-1",
    sessionId: session.id,
    hookEventName: "PermissionRequest",
    type: "permission_requested",
    title: "Permission Request: Bash",
    message: "rm -rf node_modules",
    payload: {
      hook_event_name: "PermissionRequest",
      session_id: session.id,
      cwd: session.cwd,
      tool_name: "Bash",
      tool_input: {
        command: "rm -rf node_modules"
      }
    },
    createdAt: nowIso
  };
  const pendingDecision = {
    id: "decision-1",
    sessionId: session.id,
    eventId: event.id,
    decisionType: "approve",
    status: "pending",
    payload: event.payload,
    createdAt: nowIso,
    expiresAt: new Date(Date.parse(nowIso) + 120_000).toISOString(),
    resolvedAt: null,
    resolution: null
  };
  const device = {
    id: "device-1",
    pushToken: "deadbeef"
  };

  return {
    session,
    event,
    pendingDecision,
    device
  };
}

function createDatabase(fixture) {
  const state = {
    pendingDecision: fixture.pendingDecision
  };

  return {
    state,
    listPushDevices() {
      return [fixture.device];
    },
    listPendingDecisions() {
      return [state.pendingDecision];
    },
    getPendingDecision(decisionId) {
      return decisionId === state.pendingDecision.id ? state.pendingDecision : null;
    },
    getEvent(eventId) {
      return eventId === fixture.event.id ? fixture.event : null;
    },
    getSession(sessionId) {
      return sessionId === fixture.session.id ? fixture.session : null;
    }
  };
}

function createManualScheduler(startTimeMs) {
  let nowMs = startTimeMs;
  let nextTimerId = 1;
  const timers = new Map();

  return {
    now: () => nowMs,
    setTimeout(callback, delayMs) {
      const timer = {
        id: nextTimerId,
        runAt: nowMs + delayMs,
        callback
      };
      nextTimerId += 1;
      timers.set(timer.id, timer);
      return timer.id;
    },
    clearTimeout(timerId) {
      timers.delete(timerId);
    },
    async advance(ms) {
      nowMs += ms;
      const readyTimers = [...timers.values()]
        .filter((timer) => timer.runAt <= nowMs)
        .sort((left, right) => left.runAt - right.runAt);

      for (const timer of readyTimers) {
        timers.delete(timer.id);
        await timer.callback();
      }
    },
    timerCount() {
      return timers.size;
    }
  };
}

test("dispatcher deduplicates repeated notification bursts within the dedup window", async () => {
  const fixture = createFixture();
  const database = createDatabase(fixture);
  const gateway = {
    sent: [],
    async send(notification) {
      this.sent.push(notification);
      return {
        status: "sent",
        notification
      };
    }
  };

  const dispatcher = new NotificationDispatcher({
    database,
    pushGateway: gateway,
    logger: createLogger(),
    now: () => Date.parse(fixture.event.createdAt),
    setTimeoutFn: () => 1,
    clearTimeoutFn: () => {},
    sleep: async () => {}
  });

  const first = await dispatcher.dispatchEvent(fixture);
  const second = await dispatcher.dispatchEvent(fixture);

  assert.equal(first[0].status, "sent");
  assert.equal(second[0].status, "deduplicated");
  assert.equal(gateway.sent.length, 1);
  dispatcher.close();
});

test("dispatcher retries transient push failures before succeeding", async () => {
  const fixture = createFixture();
  const database = createDatabase(fixture);
  let attempts = 0;
  const dispatcher = new NotificationDispatcher({
    database,
    pushGateway: {
      async send(notification) {
        attempts += 1;
        if (attempts < 3) {
          throw new Error("temporary APNs outage");
        }

        return {
          status: "sent",
          notification
        };
      }
    },
    logger: createLogger(),
    pushRetryAttempts: 3,
    pushRetryDelayMs: 1,
    now: () => Date.parse(fixture.event.createdAt) + attempts,
    setTimeoutFn: () => 1,
    clearTimeoutFn: () => {},
    sleep: async () => {}
  });

  const results = await dispatcher.dispatchEvent(fixture);

  assert.equal(results[0].status, "sent");
  assert.equal(results[0].attempts, 3);
  assert.equal(attempts, 3);
  dispatcher.close();
});

test("dispatcher schedules reminder notifications before pending decisions expire", async () => {
  const fixture = createFixture();
  const database = createDatabase(fixture);
  const scheduler = createManualScheduler(Date.parse(fixture.event.createdAt));
  const gateway = {
    sent: [],
    async send(notification) {
      this.sent.push(notification);
      return {
        status: "sent",
        notification
      };
    }
  };

  const dispatcher = new NotificationDispatcher({
    database,
    pushGateway: gateway,
    logger: createLogger(),
    reminderLeadMs: 60_000,
    now: scheduler.now,
    setTimeoutFn: scheduler.setTimeout,
    clearTimeoutFn: scheduler.clearTimeout,
    sleep: async () => {}
  });

  await dispatcher.dispatchEvent(fixture);
  assert.equal(scheduler.timerCount(), 1);

  await scheduler.advance(59_000);
  assert.equal(gateway.sent.length, 1);

  await scheduler.advance(1_000);
  assert.equal(gateway.sent.length, 2);
  assert.equal(gateway.sent[1].userInfo.reminder, true);
  dispatcher.close();
});

test("dispatcher restores reminders on restart and cancels them after resolution", async () => {
  const fixture = createFixture();
  const database = createDatabase(fixture);
  const scheduler = createManualScheduler(Date.parse(fixture.event.createdAt));
  const gateway = {
    sent: [],
    async send(notification) {
      this.sent.push(notification);
      return {
        status: "sent",
        notification
      };
    }
  };

  const dispatcher = new NotificationDispatcher({
    database,
    pushGateway: gateway,
    logger: createLogger(),
    reminderLeadMs: 60_000,
    now: scheduler.now,
    setTimeoutFn: scheduler.setTimeout,
    clearTimeoutFn: scheduler.clearTimeout,
    sleep: async () => {}
  });

  dispatcher.restorePendingDecisionReminders();
  assert.equal(scheduler.timerCount(), 1);

  dispatcher.onPendingDecisionResolved(fixture.pendingDecision);
  database.state.pendingDecision = {
    ...fixture.pendingDecision,
    status: "approved",
    resolvedAt: fixture.event.createdAt,
    resolution: {
      decision: "approve"
    }
  };

  assert.equal(scheduler.timerCount(), 0);
  await scheduler.advance(61_000);
  assert.equal(gateway.sent.length, 0);
  dispatcher.close();
});
