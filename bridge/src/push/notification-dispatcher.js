function isDestructivePermission(payload) {
  if (payload?.tool_name !== "Bash") {
    return false;
  }

  const command = payload.tool_input?.command ?? "";
  return /rm\s+-rf|git\s+push|git\s+reset|git\s+checkout\s+--|mv\s+.*\/dev\/null/i.test(command);
}

function isInteractiveNotification(event, pendingDecision) {
  return Boolean(
    pendingDecision
    && pendingDecision.status === "pending"
    && (event.hookEventName === "PermissionRequest" || event.hookEventName === "Elicitation")
  );
}

function reminderBody(event) {
  return `Reminder: ${event.message}`;
}

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }

  if (value && typeof value === "object") {
    const entries = Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`);
    return `{${entries.join(",")}}`;
  }

  return JSON.stringify(value);
}

function notificationCategory(event) {
  if (event.hookEventName === "PermissionRequest") {
    return "PERMISSION_REQUEST";
  }

  if (event.hookEventName === "Elicitation") {
    return "INPUT_NEEDED";
  }

  if (event.hookEventName === "TaskCompleted") {
    return "TASK_COMPLETE";
  }

  return null;
}

function notificationFingerprint({ stage, device, session, event, pendingDecision }) {
  return stableStringify({
    stage,
    deviceId: device.id,
    sessionId: session.id,
    hookEventName: event.hookEventName,
    type: event.type,
    title: event.title,
    message: event.message,
    payload: pendingDecision?.payload ?? event.payload ?? null
  });
}

function buildNotification({ session, event, pendingDecision, device, reminder = false }) {
  const category = notificationCategory(event);
  if (!category) {
    return null;
  }

  return {
    deviceId: device.id,
    deviceToken: device.pushToken,
    title: reminder ? `Reminder: ${event.title}` : event.title,
    body: reminder ? reminderBody(event) : event.message,
    category,
    sound: "default",
    userInfo: {
      sessionId: session.id,
      eventId: event.id,
      eventType: event.type,
      decisionId: pendingDecision?.id ?? null,
      reminder,
      requiresAuthentication: pendingDecision
        ? isDestructivePermission(pendingDecision.payload)
        : false
    }
  };
}

export class NotificationDispatcher {
  constructor({
    database,
    pushGateway,
    logger,
    dedupWindowMs = 30_000,
    reminderLeadMs = 60_000,
    pushRetryAttempts = 3,
    pushRetryDelayMs = 250,
    now = () => Date.now(),
    setTimeoutFn = setTimeout,
    clearTimeoutFn = clearTimeout,
    sleep = (delayMs) => new Promise((resolve) => setTimeoutFn(resolve, delayMs))
  }) {
    this.database = database;
    this.pushGateway = pushGateway;
    this.logger = logger;
    this.dedupWindowMs = dedupWindowMs;
    this.reminderLeadMs = reminderLeadMs;
    this.pushRetryAttempts = Math.max(1, pushRetryAttempts);
    this.pushRetryDelayMs = Math.max(0, pushRetryDelayMs);
    this.now = now;
    this.setTimeoutFn = setTimeoutFn;
    this.clearTimeoutFn = clearTimeoutFn;
    this.sleep = sleep;
    this.recentNotifications = new Map();
    this.reminderTimers = new Map();
  }

  async dispatchEvent({ session, event, pendingDecision }) {
    const notification = buildNotification({
      session,
      event,
      pendingDecision,
      device: { id: "", pushToken: "" }
    });

    if (!notification) {
      return [];
    }

    const devices = this.database.listPushDevices();
    const results = [];

    for (const device of devices) {
      const deviceNotification = buildNotification({
        session,
        event,
        pendingDecision,
        device,
        reminder: false
      });

      if (!deviceNotification) {
        continue;
      }

      const result = await this.deliverNotification({
        stage: "initial",
        session,
        event,
        pendingDecision,
        device,
        notification: deviceNotification
      });
      results.push(result);
    }

    if (isInteractiveNotification(event, pendingDecision)) {
      this.scheduleReminder({ session, event, pendingDecision });
    }

    if (results.length > 0) {
      this.logger.info("push.dispatched", {
        eventId: event.id,
        deliveries: results.length,
        sent: results.filter((result) => result.status === "sent").length,
        failed: results.filter((result) => result.status === "failed").length,
        deduplicated: results.filter((result) => result.status === "deduplicated").length
      });
    }

    return results;
  }

  restorePendingDecisionReminders() {
    for (const pendingDecision of this.database.listPendingDecisions()) {
      if (pendingDecision.status !== "pending") {
        continue;
      }

      const event = this.database.getEvent(pendingDecision.eventId);
      const session = this.database.getSession(pendingDecision.sessionId);
      if (!event || !session || !isInteractiveNotification(event, pendingDecision)) {
        continue;
      }

      this.scheduleReminder({ session, event, pendingDecision });
    }
  }

  onPendingDecisionResolved(pendingDecision) {
    this.cancelReminder(pendingDecision.id);
  }

  close() {
    for (const timeoutId of this.reminderTimers.values()) {
      this.clearTimeoutFn(timeoutId);
    }

    this.reminderTimers.clear();
    this.recentNotifications.clear();
  }

  async deliverNotification({ stage, session, event, pendingDecision, device, notification }) {
    this.pruneRecentNotifications();

    const fingerprint = notificationFingerprint({
      stage,
      device,
      session,
      event,
      pendingDecision
    });
    const lastSentAt = this.recentNotifications.get(fingerprint);
    if (lastSentAt !== undefined && this.now() - lastSentAt < this.dedupWindowMs) {
      this.logger.info("push.deduplicated", {
        stage,
        eventId: event.id,
        decisionId: pendingDecision?.id ?? null,
        deviceId: device.id
      });
      return {
        status: "deduplicated",
        notification
      };
    }

    let attempt = 0;

    while (attempt < this.pushRetryAttempts) {
      attempt += 1;

      try {
        const result = await this.pushGateway.send(notification);
        this.recentNotifications.set(fingerprint, this.now());
        return {
          attempts: attempt,
          ...result
        };
      } catch (error) {
        if (attempt >= this.pushRetryAttempts) {
          this.logger.warn("push.delivery_failed", {
            stage,
            eventId: event.id,
            decisionId: pendingDecision?.id ?? null,
            deviceId: device.id,
            attempts: attempt,
            message: error.message
          });
          return {
            status: "failed",
            attempts: attempt,
            notification,
            error: error.message
          };
        }

        this.logger.warn("push.retrying", {
          stage,
          eventId: event.id,
          decisionId: pendingDecision?.id ?? null,
          deviceId: device.id,
          attempt,
          message: error.message
        });
        await this.sleep(this.pushRetryDelayMs * attempt);
      }
    }

    return {
      status: "failed",
      attempts: attempt,
      notification,
      error: "Notification delivery exhausted retries."
    };
  }

  scheduleReminder({ session, event, pendingDecision }) {
    if (!pendingDecision.expiresAt) {
      return;
    }

    this.cancelReminder(pendingDecision.id);

    const expiresAtMs = Date.parse(pendingDecision.expiresAt);
    if (!Number.isFinite(expiresAtMs) || expiresAtMs <= this.now()) {
      return;
    }

    const delayMs = Math.max(0, expiresAtMs - this.now() - this.reminderLeadMs);
    const timeoutId = this.setTimeoutFn(() => {
      this.reminderTimers.delete(pendingDecision.id);
      this.dispatchReminder({
        sessionId: session.id,
        eventId: event.id,
        decisionId: pendingDecision.id
      }).catch((error) => {
        this.logger.warn("push.reminder_failed", {
          eventId: event.id,
          decisionId: pendingDecision.id,
          message: error.message
        });
      });
    }, delayMs);

    this.reminderTimers.set(pendingDecision.id, timeoutId);
  }

  cancelReminder(decisionId) {
    const timeoutId = this.reminderTimers.get(decisionId);
    if (!timeoutId) {
      return;
    }

    this.clearTimeoutFn(timeoutId);
    this.reminderTimers.delete(decisionId);
  }

  async dispatchReminder({ sessionId, eventId, decisionId }) {
    const pendingDecision = this.database.getPendingDecision(decisionId);
    if (!pendingDecision || pendingDecision.status !== "pending") {
      return [];
    }

    const session = this.database.getSession(sessionId);
    const event = this.database.getEvent(eventId);
    if (!session || !event) {
      return [];
    }

    const devices = this.database.listPushDevices();
    const results = [];

    for (const device of devices) {
      const notification = buildNotification({
        session,
        event,
        pendingDecision,
        device,
        reminder: true
      });
      if (!notification) {
        continue;
      }

      const result = await this.deliverNotification({
        stage: "reminder",
        session,
        event,
        pendingDecision,
        device,
        notification
      });
      results.push(result);
    }

    if (results.length > 0) {
      this.logger.info("push.reminder_dispatched", {
        eventId,
        decisionId,
        deliveries: results.length,
        sent: results.filter((result) => result.status === "sent").length
      });
    }

    return results;
  }

  pruneRecentNotifications() {
    const cutoff = this.now() - this.dedupWindowMs;

    for (const [fingerprint, timestamp] of this.recentNotifications.entries()) {
      if (timestamp < cutoff) {
        this.recentNotifications.delete(fingerprint);
      }
    }
  }
}
