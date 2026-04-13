import { basename } from "node:path";
import { randomUUID } from "node:crypto";

const FIVE_MINUTES_IN_MS = 5 * 60 * 1000;

function sessionDisplayName(cwd) {
  return basename(cwd) || "claudepal-session";
}

function notificationStatus(notificationType) {
  if (notificationType === "idle_prompt") {
    return "idle";
  }

  if (notificationType === "permission_prompt" || notificationType === "elicitation_dialog") {
    return "waiting";
  }

  return "active";
}

function describePermissionRequest(payload) {
  if (payload.tool_name === "Bash") {
    return payload.tool_input?.command ?? "Bash requested permission";
  }

  if (payload.tool_name) {
    return `${payload.tool_name} requested permission`;
  }

  return "A tool requested permission";
}

function describeElicitation(payload) {
  if (typeof payload.message === "string" && payload.message.length > 0) {
    return payload.message;
  }

  if (payload.mode === "form" && payload.mcp_server_name) {
    return `Input requested by ${payload.mcp_server_name}`;
  }

  if (payload.mode === "text") {
    return "Claude is waiting for text input";
  }

  return "Claude is waiting for user input";
}

export function validateHookPayload(expectedHookEventName, payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return "Hook payload must be a JSON object.";
  }

  if (payload.hook_event_name !== expectedHookEventName) {
    return `Expected hook_event_name to be ${expectedHookEventName}.`;
  }

  if (typeof payload.session_id !== "string" || payload.session_id.length === 0) {
    return "session_id is required.";
  }

  if (typeof payload.cwd !== "string" || payload.cwd.length === 0) {
    return "cwd is required.";
  }

  return null;
}

export function normalizeHookPayload(payload, now = new Date()) {
  const timestamp = now.toISOString();
  const eventId = randomUUID();
  const sessionId = payload.session_id;
  const session = {
    id: sessionId,
    cwd: payload.cwd,
    displayName: sessionDisplayName(payload.cwd),
    status: "active",
    lastEventType: payload.hook_event_name,
    createdAt: timestamp,
    updatedAt: timestamp
  };

  let eventType = "notification_received";
  let title = "Claude Event";
  let message = "Claude emitted an event";
  let pendingDecision = null;

  switch (payload.hook_event_name) {
    case "PermissionRequest": {
      session.status = "waiting";
      eventType = "permission_requested";
      title = payload.tool_name ? `Permission Request: ${payload.tool_name}` : "Permission Request";
      message = describePermissionRequest(payload);
      pendingDecision = {
        id: randomUUID(),
        sessionId,
        eventId,
        decisionType: "approve",
        status: "pending",
        payload: payload,
        createdAt: timestamp,
        expiresAt: new Date(now.getTime() + FIVE_MINUTES_IN_MS).toISOString(),
        resolvedAt: null,
        resolution: null
      };
      break;
    }
    case "Elicitation": {
      session.status = "waiting";
      eventType = "input_requested";
      title = "Input Required";
      message = describeElicitation(payload);
      pendingDecision = {
        id: randomUUID(),
        sessionId,
        eventId,
        decisionType: "submit_input",
        status: "pending",
        payload: payload,
        createdAt: timestamp,
        expiresAt: new Date(now.getTime() + FIVE_MINUTES_IN_MS).toISOString(),
        resolvedAt: null,
        resolution: null
      };
      break;
    }
    case "Notification": {
      session.status = notificationStatus(payload.notification_type);
      eventType = "notification_received";
      title = payload.notification_type ? `Notification: ${payload.notification_type}` : "Notification";
      message = payload.message ?? "Claude sent a notification";
      break;
    }
    case "TaskCompleted": {
      session.status = "active";
      eventType = "task_completed";
      title = "Task Completed";
      message = payload.task_subject ?? payload.task_id ?? "Claude marked a task as completed";
      break;
    }
    case "Stop": {
      session.status = "completed";
      eventType = "session_ended";
      title = "Session Stopped";
      message = payload.last_assistant_message ?? "Claude completed the current turn";
      break;
    }
    default: {
      session.status = "active";
    }
  }

  const event = {
    id: eventId,
    sessionId,
    hookEventName: payload.hook_event_name,
    type: eventType,
    title,
    message,
    payload,
    createdAt: timestamp
  };

  return {
    session,
    event,
    pendingDecision
  };
}
