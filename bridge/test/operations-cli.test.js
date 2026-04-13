import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";
import { createBridgeServer } from "../src/server/bridge-server.js";
import { createLogger } from "../src/logging/logger.js";

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

test("launchd CLI prints and installs a launch agent plist", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase6-launchd-"));
  const dataDirectory = join(tempDirectory, "data");
  const plistDirectory = join(tempDirectory, "LaunchAgents");
  const bridgeRoot = resolve(".");

  try {
    const printResult = await runCli(
      [
        "src/cli/bridge.js",
        "launchd",
        "print",
        "--working-dir",
        bridgeRoot,
        "--data-dir",
        dataDirectory,
        "--plist-dir",
        plistDirectory
      ],
      resolve(".")
    );

    assert.equal(printResult.code, 0, printResult.stderr);
    assert.match(printResult.stdout, /<key>Label<\/key>/);
    assert.match(printResult.stdout, /CLAUDEPAL_DB_PATH/);

    const installResult = await runCli(
      [
        "src/cli/bridge.js",
        "launchd",
        "install",
        "--working-dir",
        bridgeRoot,
        "--data-dir",
        dataDirectory,
        "--plist-dir",
        plistDirectory
      ],
      resolve(".")
    );

    assert.equal(installResult.code, 0, installResult.stderr);
    const installBody = JSON.parse(installResult.stdout);
    assert.equal(installBody.status, "installed");
    assert.equal(existsSync(installBody.plistPath), true);

    const uninstallResult = await runCli(
      [
        "src/cli/bridge.js",
        "launchd",
        "uninstall",
        "--working-dir",
        bridgeRoot,
        "--data-dir",
        dataDirectory,
        "--plist-dir",
        plistDirectory
      ],
      resolve(".")
    );

    assert.equal(uninstallResult.code, 0, uninstallResult.stderr);
    const uninstallBody = JSON.parse(uninstallResult.stdout);
    assert.equal(uninstallBody.status, "removed");
    assert.equal(existsSync(uninstallBody.plistPath), false);
  } finally {
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

test("logs export CLI writes a debug bundle with bridge data", async () => {
  const tempDirectory = mkdtempSync(join(tmpdir(), "claudepal-phase6-logs-"));
  const dbPath = join(tempDirectory, "bridge.sqlite");
  const logPath = join(tempDirectory, "bridge.log");
  const outputDirectory = join(tempDirectory, "debug-bundle");
  const server = await startTestServer(dbPath);

  try {
    writeFileSync(logPath, "{\"message\":\"bridge.started\"}\n");

    const result = await runCli(
      [
        "src/cli/bridge.js",
        "logs",
        "export",
        "--output-dir",
        outputDirectory,
        "--log-path",
        logPath,
        "--base-url",
        server.baseUrl()
      ],
      resolve(".")
    );

    assert.equal(result.code, 0, result.stderr);
    const body = JSON.parse(result.stdout);
    assert.equal(body.status, "exported");

    const manifest = JSON.parse(readFileSync(join(outputDirectory, "manifest.json"), "utf8"));
    assert.ok(manifest.files.includes("bridge.log"));
    assert.ok(manifest.files.includes("health.json"));

    const health = JSON.parse(readFileSync(join(outputDirectory, "health.json"), "utf8"));
    assert.equal(health.ok, true);
    assert.equal(health.body.status, "ok");
  } finally {
    await server.stop();
    rmSync(tempDirectory, { recursive: true, force: true });
  }
});

