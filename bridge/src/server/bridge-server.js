import { createServer } from "node:http";
import { URL } from "node:url";
import { BridgeDatabase } from "../db/bridge-database.js";
import { BridgeService } from "../core/bridge-service.js";
import { WebSocketHub } from "../realtime/websocket-hub.js";
import { renderDiagnosticsPage } from "./diagnostics-page.js";
import { validateHookPayload } from "../domain/normalize-hook-payload.js";
import { PendingHookResponses } from "../integration/pending-hook-responses.js";
import { buildHookResponse } from "../integration/hook-response.js";
import { MobileCompanionService } from "../mobile/mobile-service.js";
import { NoopPushGateway } from "../push/push-gateway.js";
import { NotificationDispatcher } from "../push/notification-dispatcher.js";

const HOOK_PATHS = new Map([
  ["/api/hooks/permission-request", "PermissionRequest"],
  ["/api/hooks/notification", "Notification"],
  ["/api/hooks/elicitation", "Elicitation"],
  ["/api/hooks/task-completed", "TaskCompleted"],
  ["/api/hooks/stop", "Stop"]
]);

const CLAUDE_HOOK_PATHS = new Map([
  ["/hooks/permission-request", "PermissionRequest"],
  ["/hooks/notification", "Notification"],
  ["/hooks/elicitation", "Elicitation"],
  ["/hooks/task-completed", "TaskCompleted"],
  ["/hooks/stop", "Stop"]
]);

const INTERACTIVE_HOOK_EVENTS = new Set(["PermissionRequest", "Elicitation"]);

function parseTimeoutMs(url, fallbackSeconds) {
  const rawSeconds = url.searchParams.get("timeoutSeconds");
  const timeoutSeconds = rawSeconds === null ? fallbackSeconds : Number.parseFloat(rawSeconds);

  if (!Number.isFinite(timeoutSeconds) || timeoutSeconds <= 0) {
    return Math.round(fallbackSeconds * 1000);
  }

  return Math.round(timeoutSeconds * 1000);
}

function decisionStatusCode(error) {
  if (error.message === "Pending decision not found." || error.message === "Pairing session not found.") {
    return 404;
  }

  if (
    error.message === "Unsupported decision." ||
    error.message.startsWith("Unsupported decision for")
  ) {
    return 400;
  }

  if (error.message === "Pending decision is no longer active.") {
    return 409;
  }

  if (error.message === "Unauthorized device.") {
    return 401;
  }

  return 500;
}

async function readJsonBody(request) {
  const chunks = [];

  for await (const chunk of request) {
    chunks.push(chunk);
  }

  if (chunks.length === 0) {
    return null;
  }

  const rawBody = Buffer.concat(chunks).toString("utf8");
  return JSON.parse(rawBody);
}

function readBearerToken(request) {
  const header = request.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) {
    return null;
  }

  return header.slice("Bearer ".length).trim();
}

function readAuthToken(request, url) {
  return readBearerToken(request) ?? url.searchParams.get("authToken")?.trim() ?? null;
}

function isLoopbackAddress(address) {
  return address === "127.0.0.1" || address === "::1" || address === "::ffff:127.0.0.1";
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8"
  });
  response.end(JSON.stringify(payload));
}

function sendHtml(response, statusCode, html) {
  response.writeHead(statusCode, {
    "content-type": "text/html; charset=utf-8"
  });
  response.end(html);
}

function sendNoContent(response, statusCode = 204) {
  response.writeHead(statusCode);
  response.end();
}

function mapHealthPayload(service, startedAt) {
  return {
    status: "ok",
    startedAt: startedAt.toISOString(),
    uptimeMs: Date.now() - startedAt.getTime(),
    ...service.snapshot().summary
  };
}

function baseUrlForRequest(server, request) {
  const host = request.headers.host ?? `${server.host}:${server.address().port}`;
  return `http://${host}`;
}

export class BridgeServer {
  constructor({
    host,
    port,
    dbPath,
    logger,
    pushGateway = new NoopPushGateway(),
    bonjourAdvertiser = null,
    notificationDispatcherOptions = {}
  }) {
    this.host = host;
    this.port = port;
    this.logger = logger;
    this.bonjourAdvertiser = bonjourAdvertiser;
    this.startedAt = new Date();
    this.pendingHookResponses = new PendingHookResponses();
    this.database = new BridgeDatabase({ dbPath });
    this.websocketHub = new WebSocketHub({
      logger,
      snapshotProvider: () => this.service.snapshot()
    });
    this.notificationDispatcher = new NotificationDispatcher({
      database: this.database,
      pushGateway,
      logger,
      ...notificationDispatcherOptions
    });
    this.service = new BridgeService({
      database: this.database,
      websocketHub: this.websocketHub,
      logger,
      notificationDispatcher: this.notificationDispatcher
    });
    this.mobileService = new MobileCompanionService({
      database: this.database,
      bridgeService: this.service,
      logger
    });
    this.server = createServer((request, response) => {
      this.handleRequest(request, response).catch((error) => {
        this.logger.error("request.failed", {
          message: error.message
        });
        sendJson(response, 500, {
          error: "Internal server error"
        });
      });
    });
    this.server.on("upgrade", (request, socket) => {
      const url = new URL(request.url, `http://${request.headers.host ?? "localhost"}`);
      if (url.pathname !== "/ws") {
        socket.destroy();
        return;
      }

      if (!this.isAuthorizedRequest(request, url, { allowLoopback: true })) {
        socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
        socket.destroy();
        return;
      }

      this.websocketHub.handleUpgrade(request, socket);
    });
  }

  isAuthorizedRequest(request, url, { allowLoopback = false } = {}) {
    if (allowLoopback && isLoopbackAddress(request.socket?.remoteAddress)) {
      return true;
    }

    const authToken = readAuthToken(request, url);
    if (!authToken) {
      return false;
    }

    try {
      this.mobileService.authenticateDevice(authToken);
      return true;
    } catch {
      return false;
    }
  }

  async handleRequest(request, response) {
    const url = new URL(request.url, `http://${request.headers.host ?? "localhost"}`);

    if (request.method === "GET" && url.pathname === "/health") {
      sendJson(response, 200, mapHealthPayload(this.service, this.startedAt));
      return;
    }

    if (request.method === "GET" && url.pathname === "/diagnostics") {
      sendHtml(response, 200, renderDiagnosticsPage());
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/sessions") {
      if (!this.isAuthorizedRequest(request, url, { allowLoopback: true })) {
        sendJson(response, 401, {
          error: "Unauthorized device."
        });
        return;
      }

      sendJson(response, 200, {
        sessions: this.database.listSessions()
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/events") {
      if (!this.isAuthorizedRequest(request, url, { allowLoopback: true })) {
        sendJson(response, 401, {
          error: "Unauthorized device."
        });
        return;
      }

      const limit = Number.parseInt(url.searchParams.get("limit") ?? "50", 10);
      sendJson(response, 200, {
        events: this.database.listEvents(Number.isNaN(limit) ? 50 : limit)
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/pending-decisions") {
      if (!this.isAuthorizedRequest(request, url, { allowLoopback: true })) {
        sendJson(response, 401, {
          error: "Unauthorized device."
        });
        return;
      }

      sendJson(response, 200, {
        pendingDecisions: this.database.listPendingDecisions()
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/pairing/sessions") {
      const payload = (await readJsonBody(request)) ?? {};
      const bridgeUrl = payload.bridgeUrl ?? baseUrlForRequest(this, request);
      const result = this.mobileService.createPairingSession({
        bridgeUrl,
        expiresInSeconds: payload.expiresInSeconds ?? 600
      });
      sendJson(response, 201, result);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/pairing/complete") {
      const payload = await readJsonBody(request);

      try {
        const result = this.mobileService.completePairing({
          pairingCode: payload?.pairingCode,
          deviceName: payload?.deviceName ?? "iPhone",
          platform: payload?.platform ?? "iOS",
          appVersion: payload?.appVersion ?? null
        });
        sendJson(response, 201, result);
      } catch (error) {
        sendJson(response, decisionStatusCode(error), {
          error: error.message
        });
      }
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/devices/register") {
      const payload = await readJsonBody(request);
      const authToken = readBearerToken(request);

      if (!authToken) {
        sendJson(response, 401, {
          error: "Unauthorized device."
        });
        return;
      }

      try {
        const device = this.mobileService.registerDevice({
          authToken,
          pushToken: payload?.pushToken ?? null,
          notificationsEnabled: Boolean(payload?.notificationsEnabled),
          deviceName: payload?.deviceName ?? null,
          platform: payload?.platform ?? null,
          appVersion: payload?.appVersion ?? null
        });
        sendJson(response, 200, { device });
      } catch (error) {
        sendJson(response, decisionStatusCode(error), {
          error: error.message
        });
      }
      return;
    }

    if (request.method === "POST" && /^\/api\/device\/decisions\/[^/]+$/.test(url.pathname)) {
      const payload = await readJsonBody(request);
      const authToken = readBearerToken(request);

      if (!authToken) {
        sendJson(response, 401, {
          error: "Unauthorized device."
        });
        return;
      }

      const decisionId = decodeURIComponent(url.pathname.split("/").pop());

      try {
        const result = this.mobileService.resolveDeviceDecision({
          authToken,
          decisionId,
          payload
        });
        this.pendingHookResponses.resolve(decisionId, result);
        sendJson(response, 200, result);
      } catch (error) {
        sendJson(response, decisionStatusCode(error), {
          error: error.message
        });
      }
      return;
    }

    if (request.method === "POST" && HOOK_PATHS.has(url.pathname)) {
      const payload = await readJsonBody(request);
      const expectedHookEventName = HOOK_PATHS.get(url.pathname);
      const validationError = validateHookPayload(expectedHookEventName, payload);

      if (validationError) {
        sendJson(response, 400, {
          error: validationError
        });
        return;
      }

      const result = await this.service.ingestHook(payload);
      sendJson(response, 201, result);
      return;
    }

    if (request.method === "POST" && CLAUDE_HOOK_PATHS.has(url.pathname)) {
      const payload = await readJsonBody(request);
      const expectedHookEventName = CLAUDE_HOOK_PATHS.get(url.pathname);
      const validationError = validateHookPayload(expectedHookEventName, payload);

      if (validationError) {
        sendJson(response, 400, {
          error: validationError
        });
        return;
      }

      const result = await this.service.ingestHook(payload);
      if (!INTERACTIVE_HOOK_EVENTS.has(expectedHookEventName) || !result.pendingDecision) {
        sendNoContent(response);
        return;
      }

      const timeoutMs = parseTimeoutMs(url, 295);
      const pendingHookResult = await this.pendingHookResponses.waitForDecision(
        result.pendingDecision.id,
        timeoutMs
      );

      if (pendingHookResult.type === "resolved") {
        const hookResponse = buildHookResponse(
          pendingHookResult.payload.event,
          pendingHookResult.payload.pendingDecision.resolution
        );

        if (hookResponse) {
          sendJson(response, 200, hookResponse);
          return;
        }
      }

      if (pendingHookResult.type === "timeout") {
        try {
          this.service.resolvePendingDecision(result.pendingDecision.id, {
            decision: "timeout"
          });
        } catch (error) {
          this.logger.warn("hook.timeout_resolution_failed", {
            decisionId: result.pendingDecision.id,
            message: error.message
          });
        }
      }

      sendNoContent(response);
      return;
    }

    if (request.method === "POST" && /^\/api\/decisions\/[^/]+$/.test(url.pathname)) {
      if (!this.isAuthorizedRequest(request, url, { allowLoopback: true })) {
        sendJson(response, 401, {
          error: "Unauthorized device."
        });
        return;
      }

      const payload = await readJsonBody(request);
      if (!payload || typeof payload.decision !== "string") {
        sendJson(response, 400, {
          error: "decision is required."
        });
        return;
      }

      const decisionId = decodeURIComponent(url.pathname.split("/").pop());

      try {
        const result = this.service.resolvePendingDecision(decisionId, payload);
        this.pendingHookResponses.resolve(decisionId, result);
        sendJson(response, 200, result);
      } catch (error) {
        sendJson(response, decisionStatusCode(error), {
          error: error.message
        });
      }
      return;
    }

    sendJson(response, 404, {
      error: "Not found"
    });
  }

  async start() {
    await new Promise((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(this.port, this.host, () => {
        this.server.off("error", reject);
        resolve();
      });
    });

    this.logger.info("bridge.started", {
      host: this.host,
      port: this.address().port
    });

    this.notificationDispatcher.restorePendingDecisionReminders();
    this.bonjourAdvertiser?.start({
      port: this.address().port
    });
  }

  async stop() {
    this.pendingHookResponses.close();
    this.websocketHub.close();
    this.notificationDispatcher.close();
    this.bonjourAdvertiser?.stop();
    await new Promise((resolve, reject) => {
      this.server.close((error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });
    this.database.close();
  }

  address() {
    return this.server.address();
  }

  baseUrl() {
    const address = this.address();
    return `http://${this.host}:${address.port}`;
  }
}

export function createBridgeServer(options) {
  return new BridgeServer(options);
}
