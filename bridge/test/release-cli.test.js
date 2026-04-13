import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";
import { createBridgeServer } from "../src/server/bridge-server.js";
import { createLogger } from "../src/logging/logger.js";
import { buildInstalledSettings } from "../src/install/claude-hooks-config.js";

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

async function startTestServer(dbPath) {
  const logger = createLogger({
    level: "error",
    sink: () => {}
  });
  const server = createBridgeServer({
    host: "127.0.0.1",
    port: 0,
    dbPath,
    logger
  });

  await server.start();
  return server;
}

test("uninstall command removes ClaudePal-managed hooks without touching unrelated settings", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase7-uninstall-"));

  try {
    const settingsDirectory = join(tempDirectory, ".claude");
    mkdirSync(settingsDirectory, { recursive: true });

    const installedSettings = buildInstalledSettings(
      {
        permissions: {
          allow: ["Bash(curl:*)"]
        },
        hooks: {
          Notification: [
            {
              matcher: "custom-alert",
              hooks: [
                {
                  type: "command",
                  command: "echo custom"
                }
              ]
            }
          ]
        }
      },
      {
        projectDir: tempDirectory,
        bridgeUrl: "http://127.0.0.1:19876"
      }
    );

    writeFileSync(
      join(settingsDirectory, "settings.local.json"),
      JSON.stringify(installedSettings, null, 2)
    );

    const result = await runCli(
      [
        "src/cli/bridge.js",
        "uninstall",
        "--scope",
        "local",
        "--project-dir",
        tempDirectory
      ],
      resolve(".")
    );

    assert.equal(result.code, 0, result.stderr);
    const settings = JSON.parse(readFileSync(join(settingsDirectory, "settings.local.json"), "utf8"));
    assert.deepEqual(settings.permissions.allow, ["Bash(curl:*)"]);
    assert.equal(settings.hooks.Notification.length, 1);
    assert.equal(settings.hooks.Notification[0].matcher, "custom-alert");
    assert.equal(settings.hooks.PermissionRequest, undefined);
    assert.equal(settings.hooks.Elicitation, undefined);
    assert.equal(settings.allowedHttpHookUrls, undefined);
  } finally {
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("status command reports installed hooks and reachable bridge health", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase7-status-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);

  try {
    const installResult = await runCli(
      [
        "src/cli/bridge.js",
        "install",
        "--scope",
        "local",
        "--project-dir",
        tempDirectory,
        "--bridge-url",
        server.baseUrl()
      ],
      resolve(".")
    );
    assert.equal(installResult.code, 0, installResult.stderr);

    const statusResult = await runCli(
      [
        "src/cli/bridge.js",
        "status",
        "--scope",
        "local",
        "--project-dir",
        tempDirectory,
        "--base-url",
        server.baseUrl()
      ],
      resolve(".")
    );

    assert.equal(statusResult.code, 0, statusResult.stderr);
    const statusBody = JSON.parse(statusResult.stdout);
    assert.equal(statusBody.hooks.installed, true);
    assert.equal(statusBody.bridge.reachable, true);
    assert.equal(statusBody.bridge.health.body.status, "ok");
    assert.equal(statusBody.hooks.events.PermissionRequest.installed, true);
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("doctor command warns when APNs config is missing but core bridge checks pass", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase7-doctor-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const server = await startTestServer(dbPath);

  try {
    const installResult = await runCli(
      [
        "src/cli/bridge.js",
        "install",
        "--scope",
        "local",
        "--project-dir",
        tempDirectory,
        "--bridge-url",
        server.baseUrl()
      ],
      resolve(".")
    );
    assert.equal(installResult.code, 0, installResult.stderr);

    const doctorResult = await runCli(
      [
        "src/cli/bridge.js",
        "doctor",
        "--scope",
        "local",
        "--project-dir",
        tempDirectory,
        "--base-url",
        server.baseUrl()
      ],
      resolve(".")
    );

    assert.equal(doctorResult.code, 0, doctorResult.stderr);
    const doctorBody = JSON.parse(doctorResult.stdout);
    assert.equal(doctorBody.status, "warn");
    assert.equal(doctorBody.checks.find((check) => check.name === "bridge-health").status, "pass");
    assert.equal(doctorBody.checks.find((check) => check.name === "hooks-installed").status, "pass");
    assert.equal(doctorBody.checks.find((check) => check.name === "apns-config").status, "warn");
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

