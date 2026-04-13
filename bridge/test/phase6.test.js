import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createBridgeServer } from "../src/server/bridge-server.js";
import { createLogger } from "../src/logging/logger.js";
import { createFileLogSink } from "../src/logging/file-log-sink.js";
import { BridgeDatabase } from "../src/db/bridge-database.js";

function loadFixture(name) {
  return JSON.parse(readFileSync(resolve("test", "fixtures", `${name}.json`), "utf8"));
}

function createTestLogger() {
  return createLogger({
    level: "error",
    sink: () => {}
  });
}

async function startTestServer(dbPath, options = {}) {
  const server = createBridgeServer({
    host: "127.0.0.1",
    port: 0,
    dbPath,
    logger: createTestLogger(),
    ...options
  });

  await server.start();
  return server;
}

function createResponseCapture() {
  return {
    statusCode: 0,
    headers: null,
    body: "",
    writeHead(statusCode, headers = {}) {
      this.statusCode = statusCode;
      this.headers = headers;
    },
    end(chunk = "") {
      this.body += chunk.toString();
    }
  };
}

function createMockRequest({ method, url, headers = {}, remoteAddress = "10.0.0.25", body = null }) {
  return {
    method,
    url,
    headers,
    socket: {
      remoteAddress
    },
    async *[Symbol.asyncIterator]() {
      if (body !== null) {
        yield Buffer.from(body);
      }
    }
  };
}

function pairTestDevice(server) {
  const pairingSession = server.mobileService.createPairingSession({
    bridgeUrl: "http://127.0.0.1:19876"
  });

  return server.mobileService.completePairing({
    pairingCode: pairingSession.pairingSession.pairingCode,
    deviceName: "Phase 6 Test iPhone",
    platform: "iOS",
    appVersion: "0.1.0"
  });
}

test("non-loopback snapshot requests require device authentication", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase6-auth-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = createBridgeServer({
    host: "127.0.0.1",
    port: 0,
    dbPath,
    logger: createTestLogger(),
    notificationDispatcherOptions: {
      setTimeoutFn: () => 1,
      clearTimeoutFn: () => {}
    }
  });

  try {
    const pairing = pairTestDevice(server);
    await server.service.ingestHook(loadFixture("notification"));

    const unauthorizedResponse = createResponseCapture();
    await server.handleRequest(
      createMockRequest({
        method: "GET",
        url: "/api/sessions"
      }),
      unauthorizedResponse
    );
    assert.equal(unauthorizedResponse.statusCode, 401);

    const authorizedResponse = createResponseCapture();
    await server.handleRequest(
      createMockRequest({
        method: "GET",
        url: "/api/sessions",
        headers: {
          authorization: `Bearer ${pairing.device.authToken}`
        }
      }),
      authorizedResponse
    );
    assert.equal(authorizedResponse.statusCode, 200);
    const body = JSON.parse(authorizedResponse.body);
    assert.equal(body.sessions.length, 1);
  } finally {
    server.notificationDispatcher.close();
    server.database.close();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("push delivery failures do not break hook ingestion", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase6-push-failure-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath, {
    pushGateway: {
      async send() {
        throw new Error("APNs offline");
      }
    }
  });

  try {
    const pairingResponse = await fetch(`${server.baseUrl()}/api/pairing/sessions`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        bridgeUrl: server.baseUrl()
      })
    });
    const pairingBody = await pairingResponse.json();

    const completionResponse = await fetch(`${server.baseUrl()}/api/pairing/complete`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        pairingCode: pairingBody.pairingSession.pairingCode,
        deviceName: "Phase 6 Test iPhone",
        platform: "iOS"
      })
    });
    const completionBody = await completionResponse.json();

    await fetch(`${server.baseUrl()}/api/devices/register`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${completionBody.device.authToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        pushToken: "deadbeef",
        notificationsEnabled: true,
        deviceName: "Phase 6 Test iPhone",
        platform: "iOS"
      })
    });

    const hookResponse = await fetch(`${server.baseUrl()}/api/hooks/permission-request`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify(loadFixture("permission-request"))
    });

    assert.equal(hookResponse.status, 201);
    const body = await hookResponse.json();
    assert.equal(body.pushDispatches[0].status, "failed");
    assert.equal(body.pendingDecision.status, "pending");
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("bridge database and file logs are created with private permissions", () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase6-permissions-"));
  const dbPath = join(tempDirectory, "data", "bridge.sqlite");
  const logPath = join(tempDirectory, "data", "bridge.log");

  try {
    const database = new BridgeDatabase({ dbPath });
    const sink = createFileLogSink({ logPath });
    sink("{\"message\":\"bridge.started\"}");

    const dbMode = statSync(dbPath).mode & 0o777;
    const logMode = statSync(logPath).mode & 0o777;
    const directoryMode = statSync(join(tempDirectory, "data")).mode & 0o777;

    assert.equal(dbMode, 0o600);
    assert.equal(logMode, 0o600);
    assert.equal(directoryMode, 0o700);

    database.close();
  } finally {
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});
