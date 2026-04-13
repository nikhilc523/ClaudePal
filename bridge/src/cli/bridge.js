#!/usr/bin/env node

import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { runInstallCommand } from "./install.js";
import { runPairCommand } from "./pair.js";
import { runLaunchdCommand } from "./launchd.js";
import { runLogsCommand } from "./logs.js";
import { runStatusCommand } from "./status.js";
import { runDoctorCommand } from "./doctor.js";
import { runUninstallCommand } from "./uninstall.js";

const currentFilePath = fileURLToPath(import.meta.url);
const mockEventPath = resolve(dirname(currentFilePath), "mock-event.js");

async function main() {
  const [command, ...rest] = process.argv.slice(2);

  if (!command || command === "start") {
    await import("../index.js");
    return;
  }

  if (command === "install") {
    await runInstallCommand(rest);
    return;
  }

  if (command === "mock:event") {
    process.argv = [process.argv[0], mockEventPath, ...rest];
    await import("./mock-event.js");
    return;
  }

  if (command === "pair") {
    await runPairCommand(rest);
    return;
  }

  if (command === "uninstall") {
    await runUninstallCommand(rest);
    return;
  }

  if (command === "status") {
    await runStatusCommand(rest);
    return;
  }

  if (command === "doctor") {
    await runDoctorCommand(rest);
    return;
  }

  if (command === "launchd") {
    await runLaunchdCommand(rest);
    return;
  }

  if (command === "logs") {
    await runLogsCommand(rest);
    return;
  }

  console.error("Usage: claudepal-bridge <start|install|uninstall|pair|status|doctor|mock:event|launchd|logs> [options]");
  process.exit(1);
}

main().catch((error) => {
  console.error(error.stack ?? error.message);
  process.exit(1);
});
