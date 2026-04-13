import { constants as fsConstants } from "node:fs";
import { access, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { resolve } from "node:path";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { inspectClaudeHooksInstallation } from "../install/claude-hooks-config.js";

const DEFAULT_BRIDGE_URL = "http://127.0.0.1:19876";
const DEFAULT_LAUNCHD_LABEL = "com.nikhilchowdary.claudepal.bridge";
const PACKAGE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

export function parseArguments(argv) {
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

async function pathStatus(filePath) {
  try {
    const stats = await stat(filePath);
    return {
      exists: true,
      size: stats.size,
      modifiedAt: stats.mtime.toISOString()
    };
  } catch (error) {
    if (error.code === "ENOENT") {
      return {
        exists: false
      };
    }

    return {
      exists: false,
      error: error.message
    };
  }
}

async function executableStatus(filePath) {
  const details = await pathStatus(filePath);
  if (!details.exists) {
    return details;
  }

  try {
    await access(filePath, fsConstants.X_OK);
    return {
      ...details,
      executable: true
    };
  } catch (error) {
    return {
      ...details,
      executable: false,
      error: error.message
    };
  }
}

async function fetchJson(url, timeoutMs = 2000) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => {
    controller.abort();
  }, timeoutMs);

  try {
    const response = await fetch(url, {
      signal: controller.signal
    });
    const text = await response.text();

    return {
      ok: response.ok,
      status: response.status,
      body: text.length > 0 ? JSON.parse(text) : null
    };
  } catch (error) {
    return {
      ok: false,
      error: error.name === "AbortError" ? `Timed out after ${timeoutMs}ms.` : error.message
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

function launchdPlistPath(args) {
  return args["launchd-plist-path"]
    ?? resolve(
      process.env.HOME ?? homedir(),
      "Library",
      "LaunchAgents",
      `${args["launchd-label"] ?? DEFAULT_LAUNCHD_LABEL}.plist`
    );
}

function bridgeBaseUrl(args) {
  return args["base-url"] ?? args["bridge-url"] ?? DEFAULT_BRIDGE_URL;
}

function defaultLogPath(args) {
  return args["log-path"] ?? resolve(process.cwd(), "data", "claudepal.log");
}

function defaultDbPath(args) {
  return args["db-path"] ?? resolve(process.cwd(), "data", "claudepal.sqlite");
}

export async function collectStatusReport(args = {}) {
  const hookStatus = await inspectClaudeHooksInstallation({
    scope: args.scope,
    projectDir: args["project-dir"],
    bridgeUrl: args["bridge-url"] ?? bridgeBaseUrl(args),
    transport: args.transport
  });
  const hookScriptPath = resolve(PACKAGE_ROOT, "hooks", "forward-hook.sh");
  const baseUrl = bridgeBaseUrl(args);
  const health = args["skip-health"] ? null : await fetchJson(`${baseUrl}/health`, 2000);
  const logPath = defaultLogPath(args);
  const dbPath = defaultDbPath(args);

  return {
    packageName: "claudepal-bridge",
    bridgeBaseUrl: baseUrl,
    hookScript: {
      path: hookScriptPath,
      ...(await executableStatus(hookScriptPath))
    },
    hooks: {
      settingsPath: hookStatus.settingsPath,
      installed: hookStatus.installed,
      managedGroupCount: hookStatus.managedGroupCount,
      allowedHttpHookUrl: hookStatus.allowedHttpHookUrl,
      allowedHttpHookUrlInstalled: hookStatus.allowedHttpHookUrlInstalled,
      events: hookStatus.managedHooks
    },
    launchd: {
      plistPath: launchdPlistPath(args),
      ...(await pathStatus(launchdPlistPath(args)))
    },
    files: {
      dbPath,
      db: await pathStatus(dbPath),
      logPath,
      log: await pathStatus(logPath)
    },
    bridge: {
      reachable: Boolean(health?.ok),
      health
    }
  };
}
