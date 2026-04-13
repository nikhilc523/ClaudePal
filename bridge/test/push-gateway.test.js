import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import {
  APNsPushGateway,
  NoopPushGateway,
  createPushGatewayFromEnv
} from "../src/push/push-gateway.js";

function testPrivateKey() {
  const { privateKey } = generateKeyPairSync("ec", {
    namedCurve: "prime256v1"
  });

  return privateKey.export({
    type: "pkcs8",
    format: "pem"
  });
}

test("APNs gateway signs requests and formats alert payloads", async () => {
  let capturedRequest = null;
  const gateway = new APNsPushGateway({
    keyId: "KEY1234567",
    teamId: "TEAM123456",
    bundleId: "com.nikhilchowdary.ClaudePal",
    privateKey: testPrivateKey(),
    now: () => new Date("2026-04-11T20:00:00Z").getTime(),
    transport: {
      async request(request) {
        capturedRequest = request;
        return {
          status: 200,
          headers: {
            "apns-id": "apns-123"
          },
          body: ""
        };
      }
    }
  });

  const result = await gateway.send({
    deviceId: "device-1",
    deviceToken: "deadbeef",
    title: "Approval Needed",
    body: "Approve Claude Code request",
    category: "PERMISSION_REQUEST",
    sound: "default",
    userInfo: {
      decisionId: "decision-1",
      requiresAuthentication: true
    }
  });

  assert.equal(result.status, "sent");
  assert.equal(result.apnsId, "apns-123");
  assert.equal(capturedRequest.authority, "https://api.sandbox.push.apple.com");
  assert.equal(capturedRequest.headers[":path"], "/3/device/deadbeef");
  assert.equal(capturedRequest.headers["apns-topic"], "com.nikhilchowdary.ClaudePal");
  assert.equal(capturedRequest.headers["apns-push-type"], "alert");
  assert.match(capturedRequest.headers.authorization, /^bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);

  const payload = JSON.parse(capturedRequest.body);
  assert.deepEqual(payload.aps, {
    alert: {
      title: "Approval Needed",
      body: "Approve Claude Code request"
    },
    sound: "default",
    category: "PERMISSION_REQUEST"
  });
  assert.equal(payload.decisionId, "decision-1");
  assert.equal(payload.requiresAuthentication, true);
});

test("push gateway factory falls back to noop without APNs config", () => {
  const gateway = createPushGatewayFromEnv({
    env: {},
    logger: {
      info() {}
    }
  });

  assert.ok(gateway instanceof NoopPushGateway);
});

test("push gateway factory creates APNs gateway when env is present", () => {
  const gateway = createPushGatewayFromEnv({
    env: {
      CLAUDEPAL_APNS_KEY_ID: "KEY1234567",
      CLAUDEPAL_APNS_TEAM_ID: "TEAM123456",
      CLAUDEPAL_APNS_BUNDLE_ID: "com.nikhilchowdary.ClaudePal",
      CLAUDEPAL_APNS_PRIVATE_KEY: testPrivateKey(),
      CLAUDEPAL_APNS_ENV: "production"
    },
    logger: {
      info() {}
    }
  });

  assert.ok(gateway instanceof APNsPushGateway);
  assert.equal(gateway.environment, "production");
});
