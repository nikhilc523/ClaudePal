import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createBridgeServer } from "../src/server/bridge-server.js";
import { createLogger } from "../src/logging/logger.js";
import { spawn } from "node:child_process";
import { RecordingPushGateway } from "../src/push/push-gateway.js";

function loadFixture(name) {
  return JSON.parse(readFileSync(resolve("test", "fixtures", `${name}.json`), "utf8"));
}

async function startTestServer(dbPath, options = {}) {
  const logger = createLogger({
    level: "error",
    sink: () => {}
  });
  const server = createBridgeServer({
    host: "127.0.0.1",
    port: 0,
    dbPath,
    logger,
    ...options
  });

  await server.start();

  return server;
}

async function postJson(baseUrl, pathname, payload) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  return {
    status: response.status,
    body: await response.json()
  };
}

function waitForSocketOpen(socket) {
  return new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });
}

function nextSocketMessage(socket) {
  return new Promise((resolve, reject) => {
    socket.addEventListener("message", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });
}

async function runCli(args, cwd) {
  return await new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(process.execPath, ["--disable-warning=ExperimentalWarning", ...args], {
      cwd,
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", rejectPromise);
    child.on("close", (code) => {
      resolvePromise({ code, stdout, stderr });
    });
  });
}

async function waitForPendingDecision(baseUrl, sessionId, timeoutMs = 2000) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const response = await fetch(`${baseUrl}/api/pending-decisions`);
    const body = await response.json();
    const match = body.pendingDecisions.find((candidate) => candidate.sessionId === sessionId);

    if (match) {
      return match;
    }

    await new Promise((resolve) => setTimeout(resolve, 25));
  }

  throw new Error(`Pending decision for session ${sessionId} was not created.`);
}

function authHeaders(authToken) {
  return {
    authorization: `Bearer ${authToken}`,
    "content-type": "application/json"
  };
}

test("health endpoint reports bridge summary", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase1-health-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);

  try {
    const response = await fetch(`${server.baseUrl()}/health`);
    assert.equal(response.status, 200);

    const body = await response.json();
    assert.equal(body.status, "ok");
    assert.equal(body.sessionsCount, 0);
    assert.equal(body.eventsCount, 0);
    assert.equal(body.unresolvedDecisionsCount, 0);
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("permission requests are persisted and can be resolved locally", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase1-decision-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);

  try {
    const createResponse = await postJson(
      server.baseUrl(),
      "/api/hooks/permission-request",
      loadFixture("permission-request")
    );

    assert.equal(createResponse.status, 201);
    assert.equal(createResponse.body.event.type, "permission_requested");
    assert.equal(createResponse.body.session.status, "waiting");
    assert.equal(createResponse.body.pendingDecision.status, "pending");

    const pendingResponse = await fetch(`${server.baseUrl()}/api/pending-decisions`);
    const pendingBody = await pendingResponse.json();
    assert.equal(pendingBody.pendingDecisions.length, 1);

    const resolveResponse = await postJson(
      server.baseUrl(),
      `/api/decisions/${createResponse.body.pendingDecision.id}`,
      { decision: "approve" }
    );

    assert.equal(resolveResponse.status, 200);
    assert.equal(resolveResponse.body.pendingDecision.status, "approved");
    assert.equal(resolveResponse.body.session.status, "active");
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("websocket subscribers receive live event broadcasts", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase1-websocket-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);

  try {
    const websocket = new WebSocket(server.baseUrl().replace("http", "ws") + "/ws");
    await waitForSocketOpen(websocket);

    const snapshotEvent = await nextSocketMessage(websocket);
    const snapshotPayload = JSON.parse(String(snapshotEvent.data));
    assert.equal(snapshotPayload.type, "snapshot");

    const requestPromise = nextSocketMessage(websocket);
    const createResponse = await postJson(
      server.baseUrl(),
      "/api/hooks/notification",
      loadFixture("notification")
    );
    assert.equal(createResponse.status, 201);

    const eventMessage = await requestPromise;
    const eventPayload = JSON.parse(String(eventMessage.data));
    assert.equal(eventPayload.type, "event.created");
    assert.equal(eventPayload.event.type, "notification_received");

    websocket.close();
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("bridge state survives restart with the same SQLite file", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase1-restart-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const fixture = loadFixture("permission-request");

  let server = await startTestServer(dbPath);

  try {
    const createResponse = await postJson(server.baseUrl(), "/api/hooks/permission-request", fixture);
    assert.equal(createResponse.status, 201);
    assert.equal(createResponse.body.summary.unresolvedDecisionsCount, 1);
  } finally {
    await server.stop();
  }

  server = await startTestServer(dbPath);

  try {
    const pendingResponse = await fetch(`${server.baseUrl()}/api/pending-decisions`);
    const pendingBody = await pendingResponse.json();
    assert.equal(pendingBody.pendingDecisions.length, 1);
    assert.equal(pendingBody.pendingDecisions[0].status, "pending");

    const sessionsResponse = await fetch(`${server.baseUrl()}/api/sessions`);
    const sessionsBody = await sessionsResponse.json();
    assert.equal(sessionsBody.sessions.length, 1);
    assert.equal(sessionsBody.sessions[0].status, "waiting");
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("mock event CLI injects fixtures without server-side errors", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase1-cli-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);

  try {
    const result = await runCli(
      [
        "src/cli/mock-event.js",
        "--base-url",
        server.baseUrl(),
        "--fixture",
        "test/fixtures/task-completed.json"
      ],
      resolve(".")
    );

    assert.equal(result.code, 0, result.stderr);

    const eventsResponse = await fetch(`${server.baseUrl()}/api/events`);
    const eventsBody = await eventsResponse.json();
    assert.equal(eventsBody.events.length, 1);
    assert.equal(eventsBody.events[0].type, "task_completed");
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("ClaudePal installer writes hybrid hook config without losing existing settings", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase2-install-"));

  try {
    const settingsDirectory = join(tempDirectory, ".claude");
    mkdirSync(settingsDirectory, { recursive: true });
    writeFileSync(
      join(settingsDirectory, "settings.local.json"),
      JSON.stringify(
        {
          permissions: {
            allow: ["Bash(curl:*)"]
          },
          allowedHttpHookUrls: ["http://localhost:*"]
        },
        null,
        2
      )
    );

    const result = await runCli(
      [
        "src/cli/bridge.js",
        "install",
        "--scope",
        "local",
        "--project-dir",
        tempDirectory,
        "--bridge-url",
        "http://127.0.0.1:19876"
      ],
      resolve(".")
    );

    assert.equal(result.code, 0, result.stderr);

    const installedSettings = JSON.parse(
      readFileSync(join(settingsDirectory, "settings.local.json"), "utf8")
    );

    assert.deepEqual(installedSettings.permissions.allow, ["Bash(curl:*)"]);
    assert.ok(installedSettings.allowedHttpHookUrls.includes("http://localhost:*"));
    assert.ok(installedSettings.allowedHttpHookUrls.includes("http://127.0.0.1:19876/*"));
    assert.equal(installedSettings.hooks.PermissionRequest[0].hooks[0].type, "http");
    assert.equal(installedSettings.hooks.Elicitation[0].hooks[0].type, "http");
    assert.equal(installedSettings.hooks.Notification[0].hooks[0].type, "command");
    assert.equal(installedSettings.hooks.Notification[0].hooks[0].async, true);
    assert.equal(installedSettings.hooks.TaskCompleted[0].hooks[0].type, "command");
    assert.equal(installedSettings.hooks.Stop[0].hooks[0].type, "command");
  } finally {
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("interactive permission hooks wait for approval and return Claude-compatible JSON", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase2-permission-hook-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);
  const fixture = loadFixture("permission-request");

  try {
    const hookResponsePromise = fetch(
      `${server.baseUrl()}/hooks/permission-request?timeoutSeconds=1`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json"
        },
        body: JSON.stringify(fixture)
      }
    );

    const pendingDecision = await waitForPendingDecision(server.baseUrl(), fixture.session_id);
    const resolveResponse = await postJson(
      server.baseUrl(),
      `/api/decisions/${pendingDecision.id}`,
      { decision: "approve" }
    );
    assert.equal(resolveResponse.status, 200);

    const hookResponse = await hookResponsePromise;
    assert.equal(hookResponse.status, 200);
    const body = await hookResponse.json();
    assert.deepEqual(body, {
      hookSpecificOutput: {
        hookEventName: "PermissionRequest",
        decision: {
          behavior: "allow"
        }
      }
    });
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("interactive elicitation hooks wait for submitted input and return Claude-compatible JSON", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase2-elicitation-hook-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);
  const fixture = loadFixture("elicitation");

  try {
    const hookResponsePromise = fetch(`${server.baseUrl()}/hooks/elicitation?timeoutSeconds=1`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify(fixture)
    });

    const pendingDecision = await waitForPendingDecision(server.baseUrl(), fixture.session_id);
    const resolveResponse = await postJson(
      server.baseUrl(),
      `/api/decisions/${pendingDecision.id}`,
      {
        decision: "submit_input",
        content: {
          owner: "openai"
        }
      }
    );
    assert.equal(resolveResponse.status, 200);

    const hookResponse = await hookResponsePromise;
    assert.equal(hookResponse.status, 200);
    const body = await hookResponse.json();
    assert.deepEqual(body, {
      hookSpecificOutput: {
        hookEventName: "Elicitation",
        action: "accept",
        content: {
          owner: "openai"
        }
      }
    });
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("interactive hooks time out cleanly and fall back without a blocking response", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase2-timeout-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);
  const fixture = loadFixture("permission-request");

  try {
    const hookResponse = await fetch(
      `${server.baseUrl()}/hooks/permission-request?timeoutSeconds=0.05`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json"
        },
        body: JSON.stringify(fixture)
      }
    );

    assert.equal(hookResponse.status, 204);
    assert.equal(await hookResponse.text(), "");

    const pendingDecision = await waitForPendingDecision(server.baseUrl(), fixture.session_id);
    assert.equal(pendingDecision.status, "expired");
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("shell fallback hook forwards payloads and prints Claude hook JSON on approval", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase2-shell-fallback-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);
  const fixture = loadFixture("permission-request");

  try {
    const scriptPath = resolve("hooks", "forward-hook.sh");
    const child = spawn("bash", [scriptPath, `${server.baseUrl()}/hooks/permission-request?timeoutSeconds=1`, "1"], {
      cwd: resolve("."),
      stdio: ["pipe", "pipe", "pipe"]
    });

    child.stdin.write(JSON.stringify(fixture));
    child.stdin.end();

    const pendingDecision = await waitForPendingDecision(server.baseUrl(), fixture.session_id);
    const resolveResponse = await postJson(
      server.baseUrl(),
      `/api/decisions/${pendingDecision.id}`,
      { decision: "approve" }
    );
    assert.equal(resolveResponse.status, 200);

    const result = await new Promise((resolvePromise, rejectPromise) => {
      let stdout = "";
      let stderr = "";

      child.stdout.on("data", (chunk) => {
        stdout += chunk.toString();
      });
      child.stderr.on("data", (chunk) => {
        stderr += chunk.toString();
      });
      child.on("error", rejectPromise);
      child.on("close", (code) => {
        resolvePromise({ code, stdout, stderr });
      });
    });

    assert.equal(result.code, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), {
      hookSpecificOutput: {
        hookEventName: "PermissionRequest",
        decision: {
          behavior: "allow"
        }
      }
    });
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("pairing session, pairing completion, and device registration succeed end to end", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase3-pairing-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);

  try {
    const pairingSessionResponse = await postJson(server.baseUrl(), "/api/pairing/sessions", {
      bridgeUrl: server.baseUrl(),
      expiresInSeconds: 600
    });
    assert.equal(pairingSessionResponse.status, 201);
    assert.match(pairingSessionResponse.body.qrPayload, /^claudepal:\/\/pair\?/);

    const pairingCompleteResponse = await postJson(server.baseUrl(), "/api/pairing/complete", {
      pairingCode: pairingSessionResponse.body.pairingSession.pairingCode,
      deviceName: "Nikhil's iPhone",
      platform: "iOS",
      appVersion: "0.1.0"
    });
    assert.equal(pairingCompleteResponse.status, 201);
    assert.equal(pairingCompleteResponse.body.bridgeUrl, server.baseUrl());
    assert.ok(pairingCompleteResponse.body.device.authToken);

    const registrationResponse = await fetch(`${server.baseUrl()}/api/devices/register`, {
      method: "POST",
      headers: authHeaders(pairingCompleteResponse.body.device.authToken),
      body: JSON.stringify({
        pushToken: "deadbeef",
        notificationsEnabled: true,
        deviceName: "Nikhil's iPhone",
        platform: "iOS",
        appVersion: "0.1.0"
      })
    });
    assert.equal(registrationResponse.status, 200);
    const registrationBody = await registrationResponse.json();
    assert.equal(registrationBody.device.pushToken, "deadbeef");
    assert.equal(registrationBody.device.notificationsEnabled, true);
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("registered devices receive actionable push payloads for permission requests", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase3-push-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const pushGateway = new RecordingPushGateway();
  const server = await startTestServer(dbPath, { pushGateway });

  try {
    const pairingSessionResponse = await postJson(server.baseUrl(), "/api/pairing/sessions", {
      bridgeUrl: server.baseUrl()
    });
    const pairingCompleteResponse = await postJson(server.baseUrl(), "/api/pairing/complete", {
      pairingCode: pairingSessionResponse.body.pairingSession.pairingCode,
      deviceName: "Nikhil's iPhone",
      platform: "iOS"
    });

    await fetch(`${server.baseUrl()}/api/devices/register`, {
      method: "POST",
      headers: authHeaders(pairingCompleteResponse.body.device.authToken),
      body: JSON.stringify({
        pushToken: "deadbeef",
        notificationsEnabled: true,
        deviceName: "Nikhil's iPhone",
        platform: "iOS"
      })
    });

    const createResponse = await postJson(
      server.baseUrl(),
      "/api/hooks/permission-request",
      loadFixture("permission-request")
    );
    assert.equal(createResponse.status, 201);
    assert.equal(pushGateway.sent.length, 1);
    assert.equal(pushGateway.sent[0].category, "PERMISSION_REQUEST");
    assert.equal(pushGateway.sent[0].userInfo.decisionId, createResponse.body.pendingDecision.id);
    assert.equal(pushGateway.sent[0].userInfo.requiresAuthentication, true);
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("authenticated device decisions resolve pending approvals", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase3-device-decision-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);

  try {
    const pairingSessionResponse = await postJson(server.baseUrl(), "/api/pairing/sessions", {
      bridgeUrl: server.baseUrl()
    });
    const pairingCompleteResponse = await postJson(server.baseUrl(), "/api/pairing/complete", {
      pairingCode: pairingSessionResponse.body.pairingSession.pairingCode,
      deviceName: "Nikhil's iPhone",
      platform: "iOS"
    });

    const createResponse = await postJson(
      server.baseUrl(),
      "/api/hooks/permission-request",
      loadFixture("permission-request")
    );

    const decisionResponse = await fetch(
      `${server.baseUrl()}/api/device/decisions/${createResponse.body.pendingDecision.id}`,
      {
        method: "POST",
        headers: authHeaders(pairingCompleteResponse.body.device.authToken),
        body: JSON.stringify({
          decision: "approve"
        })
      }
    );

    assert.equal(decisionResponse.status, 200);
    const decisionBody = await decisionResponse.json();
    assert.equal(decisionBody.pendingDecision.status, "approved");
    assert.equal(decisionBody.device.id, pairingCompleteResponse.body.device.id);
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});
