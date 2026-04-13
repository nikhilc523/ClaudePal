import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import {
  createBonjourAdvertiserFromEnv,
  DnsSdBonjourAdvertiser,
  NoopBonjourAdvertiser
} from "../src/mobile/bonjour-advertiser.js";

function createLogger() {
  return {
    info() {},
    warn() {}
  };
}

test("factory returns a noop advertiser when Bonjour is disabled", () => {
  const advertiser = createBonjourAdvertiserFromEnv({
    env: {
      CLAUDEPAL_BONJOUR_DISABLED: "1"
    },
    platform: "darwin",
    logger: createLogger()
  });

  assert.ok(advertiser instanceof NoopBonjourAdvertiser);
});

test("dns-sd advertiser spawns the expected Bonjour registration command", () => {
  const calls = [];
  const fakeChild = new EventEmitter();
  fakeChild.kill = (signal) => {
    calls.push({ type: "kill", signal });
  };

  const advertiser = new DnsSdBonjourAdvertiser({
    logger: createLogger(),
    serviceName: "ClaudePal Test Bridge",
    spawnCommand: (command, args, options) => {
      calls.push({ command, args, options });
      return fakeChild;
    }
  });

  advertiser.start({ port: 19876 });
  advertiser.stop();

  assert.equal(calls[0].command, "dns-sd");
  assert.deepEqual(calls[0].args, [
    "-R",
    "ClaudePal Test Bridge",
    "_claudepal._tcp",
    "local",
    "19876",
    "path=/",
    "version=0.1.0"
  ]);
  assert.deepEqual(calls[0].options, {
    stdio: "ignore"
  });
  assert.deepEqual(calls[1], {
    type: "kill",
    signal: "SIGTERM"
  });
});
