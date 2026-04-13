import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createLaunchdPlist } from "../install/launchd-plist.js";
import { ensurePrivateDirectory, ensurePrivateFile } from "../fs/private-storage.js";

const PACKAGE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const DEFAULT_LABEL = "com.nikhilchowdary.claudepal.bridge";

function parseArguments(argv) {
  const argumentsMap = {};

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) {
      continue;
    }

    const key = token.slice(2);
    const nextToken = argv[index + 1];

    if (!nextToken || nextToken.startsWith("--")) {
      argumentsMap[key] = true;
      continue;
    }

    argumentsMap[key] = nextToken;
    index += 1;
  }

  return argumentsMap;
}

function launchdPaths(args) {
  const homeDirectory = process.env.HOME ?? process.cwd();
  const workingDirectory = args["working-dir"] ?? PACKAGE_ROOT;
  const dataDirectory = args["data-dir"] ?? resolve(workingDirectory, "data");
  const label = args.label ?? DEFAULT_LABEL;
  const plistDirectory = args["plist-dir"] ?? resolve(homeDirectory, "Library", "LaunchAgents");

  return {
    label,
    workingDirectory,
    dataDirectory,
    bridgeScriptPath: args["bridge-script"] ?? resolve(PACKAGE_ROOT, "src", "index.js"),
    nodePath: args["node-path"] ?? process.execPath,
    dbPath: args["db-path"] ?? resolve(dataDirectory, "claudepal.sqlite"),
    logPath: args["log-path"] ?? resolve(dataDirectory, "claudepal.log"),
    standardLogPath: args["stdio-log-path"] ?? resolve(dataDirectory, "claudepal-launchd.log"),
    host: args.host ?? "127.0.0.1",
    port: args.port ?? "19876",
    plistDirectory,
    plistPath: resolve(plistDirectory, `${label}.plist`)
  };
}

function printUsageAndExit() {
  console.error("Usage: claudepal-bridge launchd <print|install|uninstall> [options]");
  process.exit(1);
}

export async function runLaunchdCommand(argv = process.argv.slice(2)) {
  const [subcommand, ...rest] = argv;
  if (!subcommand) {
    printUsageAndExit();
  }

  const args = parseArguments(rest);
  const paths = launchdPaths(args);

  const plist = createLaunchdPlist({
    label: paths.label,
    nodePath: paths.nodePath,
    bridgeScriptPath: paths.bridgeScriptPath,
    workingDirectory: paths.workingDirectory,
    standardOutPath: paths.standardLogPath,
    standardErrorPath: paths.standardLogPath,
    environmentVariables: {
      CLAUDEPAL_DB_PATH: paths.dbPath,
      CLAUDEPAL_HOST: paths.host,
      CLAUDEPAL_LOG_PATH: paths.logPath,
      CLAUDEPAL_PORT: paths.port
    }
  });

  if (subcommand === "print") {
    process.stdout.write(plist);
    return;
  }

  if (subcommand === "install") {
    ensurePrivateDirectory(paths.plistDirectory);
    ensurePrivateDirectory(paths.dataDirectory);
    ensurePrivateFile(paths.logPath, { create: true });
    ensurePrivateFile(paths.standardLogPath, { create: true });
    writeFileSync(paths.plistPath, plist, {
      encoding: "utf8",
      mode: 0o600
    });
    ensurePrivateFile(paths.plistPath);

    console.log(JSON.stringify({
      status: "installed",
      label: paths.label,
      plistPath: paths.plistPath,
      dbPath: paths.dbPath,
      logPath: paths.logPath
    }, null, 2));
    return;
  }

  if (subcommand === "uninstall") {
    if (existsSync(paths.plistPath)) {
      rmSync(paths.plistPath, { force: true });
    }

    console.log(JSON.stringify({
      status: "removed",
      label: paths.label,
      plistPath: paths.plistPath
    }, null, 2));
    return;
  }

  printUsageAndExit();
}

