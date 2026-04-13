function hasOwn(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

export function buildHookResponse(event, resolution) {
  if (!event || !resolution) {
    return null;
  }

  if (event.hookEventName === "PermissionRequest") {
    if (resolution.decision === "approve") {
      const decision = {
        behavior: "allow"
      };

      if (hasOwn(resolution, "updatedInput")) {
        decision.updatedInput = resolution.updatedInput;
      }

      if (hasOwn(resolution, "updatedPermissions")) {
        decision.updatedPermissions = resolution.updatedPermissions;
      }

      return {
        hookSpecificOutput: {
          hookEventName: "PermissionRequest",
          decision
        }
      };
    }

    if (resolution.decision === "deny") {
      const decision = {
        behavior: "deny"
      };

      if (typeof resolution.message === "string" && resolution.message.length > 0) {
        decision.message = resolution.message;
      }

      if (typeof resolution.interrupt === "boolean") {
        decision.interrupt = resolution.interrupt;
      }

      return {
        hookSpecificOutput: {
          hookEventName: "PermissionRequest",
          decision
        }
      };
    }

    return null;
  }

  if (event.hookEventName === "Elicitation") {
    if (resolution.decision === "submit_input") {
      return {
        hookSpecificOutput: {
          hookEventName: "Elicitation",
          action: "accept",
          content: resolution.content ?? {}
        }
      };
    }

    if (resolution.decision === "deny") {
      return {
        hookSpecificOutput: {
          hookEventName: "Elicitation",
          action: "decline"
        }
      };
    }

    if (resolution.decision === "cancel") {
      return {
        hookSpecificOutput: {
          hookEventName: "Elicitation",
          action: "cancel"
        }
      };
    }
  }

  return null;
}
