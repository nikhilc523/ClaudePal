import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";

const DEFAULT_BRIDGE_URL = "http://127.0.0.1:19876";
const DEFAULT_SCOPE = "local";
const DEFAULT_TRANSPORT = "hybrid";
const MANAGED_EVENT_NAMES = [
  "PermissionRequest",
  "Elicitation",
  "Notification",
  "TaskCompleted",
  "Stop"
];
const MANAGED_ROUTE_SUFFIXES = [
  "/hooks/permission-request",
  "/hooks/elicitation",
  "/hooks/notification",
  "/hooks/task-completed",
  "/hooks/stop"
];

function uniquePush(target, value) {
  if (!target.includes(value)) {
    target.push(value);
  }
}

function hookIdentity(group) {
  return JSON.stringify({
    matcher: group.matcher ?? null,
    hooks: group.hooks.map((hook) => ({
      type: hook.type,
      url: hook.url ?? null,
      command: hook.command ?? null
    }))
  });
}

function mergeHookGroups(existingGroups = [], desiredGroups = []) {
  const merged = [...existingGroups];

  for (const desiredGroup of desiredGroups) {
    const desiredIdentity = hookIdentity(desiredGroup);
    const existingIndex = merged.findIndex((group) => hookIdentity(group) === desiredIdentity);

    if (existingIndex >= 0) {
      merged[existingIndex] = desiredGroup;
      continue;
    }

    merged.push(desiredGroup);
  }

  return merged;
}

function buildAllowedHttpHookUrl(bridgeUrl) {
  const url = new URL(bridgeUrl);
  const normalizedPath = url.pathname === "/" ? "" : url.pathname.replace(/\/$/, "");
  return `${url.origin}${normalizedPath}/*`;
}

function normalizedUrlWithoutQuery(input) {
  try {
    const url = new URL(input);
    return `${url.origin}${url.pathname.replace(/\/$/, "")}`;
  } catch {
    return input;
  }
}

function buildShellHookCommand({ scriptPath, hookUrl, timeoutSeconds }) {
  return `"${scriptPath}" "${hookUrl}" "${timeoutSeconds}"`;
}

function buildHookGroups({
  bridgeUrl,
  transport,
  scope,
  packageRoot,
  permissionTimeoutSeconds,
  elicitationTimeoutSeconds,
  asyncTimeoutSeconds
}) {
  const useProjectRelativeShellPath = scope !== "user";
  const shellScriptPath = useProjectRelativeShellPath
    ? join("$CLAUDE_PROJECT_DIR", "bridge", "hooks", "forward-hook.sh")
    : join(packageRoot, "hooks", "forward-hook.sh");

  const shellCommand = (route, timeoutSeconds) =>
    buildShellHookCommand({
      scriptPath: shellScriptPath,
      hookUrl: `${bridgeUrl}${route}?timeoutSeconds=${timeoutSeconds}`,
      timeoutSeconds
    });

  const httpHook = (route, timeoutSeconds) => ({
    type: "http",
    url: `${bridgeUrl}${route}?timeoutSeconds=${timeoutSeconds}`,
    timeout: Math.max(1, Math.ceil(timeoutSeconds))
  });
  const commandHook = (route, timeoutSeconds, asyncMode = false) => ({
    type: "command",
    command: shellCommand(route, timeoutSeconds),
    timeout: Math.max(1, Math.ceil(timeoutSeconds)),
    ...(asyncMode ? { async: true } : {})
  });

  const interactiveHookFactory = transport === "command-only" ? commandHook : httpHook;
  const groups = {
    PermissionRequest: [
      {
        matcher: "",
        hooks: [interactiveHookFactory("/hooks/permission-request", permissionTimeoutSeconds)]
      }
    ],
    Elicitation: [
      {
        matcher: "",
        hooks: [interactiveHookFactory("/hooks/elicitation", elicitationTimeoutSeconds)]
      }
    ],
    Notification: [
      {
        matcher: "permission_prompt|idle_prompt|auth_success|elicitation_dialog",
        hooks: [commandHook("/hooks/notification", asyncTimeoutSeconds, true)]
      }
    ],
    TaskCompleted: [
      {
        hooks: [commandHook("/hooks/task-completed", asyncTimeoutSeconds, true)]
      }
    ],
    Stop: [
      {
        hooks: [commandHook("/hooks/stop", asyncTimeoutSeconds, true)]
      }
    ]
  };

  return groups;
}

function isManagedHook(hook) {
  if (!hook || typeof hook !== "object") {
    return false;
  }

  if (hook.type === "http" && typeof hook.url === "string") {
    const normalized = normalizedUrlWithoutQuery(hook.url);
    return MANAGED_ROUTE_SUFFIXES.some((suffix) => normalized.endsWith(suffix));
  }

  if (hook.type === "command" && typeof hook.command === "string") {
    return hook.command.includes("forward-hook.sh")
      && MANAGED_ROUTE_SUFFIXES.some((suffix) => hook.command.includes(suffix));
  }

  return false;
}

function isManagedHookGroup(group) {
  const hooks = group?.hooks;
  if (!Array.isArray(hooks) || hooks.length === 0) {
    return false;
  }

  return hooks.every(isManagedHook);
}

function summarizeManagedHooks(settings = {}) {
  const managedHooks = {};
  let managedGroupCount = 0;

  for (const eventName of MANAGED_EVENT_NAMES) {
    const groups = settings.hooks?.[eventName] ?? [];
    const managedGroups = groups.filter(isManagedHookGroup);
    managedHooks[eventName] = {
      totalGroups: groups.length,
      managedGroups: managedGroups.length,
      installed: managedGroups.length > 0
    };
    managedGroupCount += managedGroups.length;
  }

  return {
    managedHooks,
    managedGroupCount,
    installed: managedGroupCount > 0
  };
}

export function resolveSettingsPath({ scope = DEFAULT_SCOPE, projectDir = process.cwd() } = {}) {
  if (scope === "local") {
    return resolve(projectDir, ".claude", "settings.local.json");
  }

  if (scope === "project") {
    return resolve(projectDir, ".claude", "settings.json");
  }

  if (scope === "user") {
    return resolve(homedir(), ".claude", "settings.json");
  }

  throw new Error(`Unsupported scope: ${scope}`);
}

export async function readJsonFileOrDefault(filePath, fallbackValue) {
  try {
    const text = await readFile(filePath, "utf8");
    return JSON.parse(text);
  } catch (error) {
    if (error.code === "ENOENT") {
      return fallbackValue;
    }

    throw error;
  }
}

export async function writeJsonFile(filePath, value) {
  await mkdir(dirname(filePath), { recursive: true });
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

export function buildInstalledSettings(existingSettings = {}, options = {}) {
  const {
    bridgeUrl = DEFAULT_BRIDGE_URL,
    scope = DEFAULT_SCOPE,
    transport = DEFAULT_TRANSPORT,
    projectDir = process.cwd(),
    packageRoot = resolve(projectDir, "bridge"),
    permissionTimeoutSeconds = 295,
    elicitationTimeoutSeconds = 295,
    asyncTimeoutSeconds = 15
  } = options;

  const nextSettings = structuredClone(existingSettings);
  const nextHooks = { ...(nextSettings.hooks ?? {}) };
  const desiredGroups = buildHookGroups({
    bridgeUrl,
    transport,
    scope,
    packageRoot,
    permissionTimeoutSeconds,
    elicitationTimeoutSeconds,
    asyncTimeoutSeconds
  });

  for (const [eventName, groups] of Object.entries(desiredGroups)) {
    nextHooks[eventName] = mergeHookGroups(nextHooks[eventName], groups);
  }

  nextSettings.hooks = nextHooks;

  if (transport !== "command-only") {
    const allowedHttpHookUrls = [...(nextSettings.allowedHttpHookUrls ?? [])];
    uniquePush(allowedHttpHookUrls, buildAllowedHttpHookUrl(bridgeUrl));
    nextSettings.allowedHttpHookUrls = allowedHttpHookUrls;
  }

  return nextSettings;
}

export function buildUninstalledSettings(existingSettings = {}, options = {}) {
  const {
    bridgeUrl = DEFAULT_BRIDGE_URL,
    transport = DEFAULT_TRANSPORT
  } = options;

  const nextSettings = structuredClone(existingSettings);
  const nextHooks = { ...(nextSettings.hooks ?? {}) };

  for (const eventName of MANAGED_EVENT_NAMES) {
    const groups = nextHooks[eventName] ?? [];
    const remainingGroups = groups.filter((group) => !isManagedHookGroup(group));

    if (remainingGroups.length > 0) {
      nextHooks[eventName] = remainingGroups;
    } else {
      delete nextHooks[eventName];
    }
  }

  if (Object.keys(nextHooks).length > 0) {
    nextSettings.hooks = nextHooks;
  } else {
    delete nextSettings.hooks;
  }

  if (transport !== "command-only" && Array.isArray(nextSettings.allowedHttpHookUrls)) {
    const disallowedUrl = buildAllowedHttpHookUrl(bridgeUrl);
    const remainingAllowedUrls = nextSettings.allowedHttpHookUrls.filter((candidate) => candidate !== disallowedUrl);

    if (remainingAllowedUrls.length > 0) {
      nextSettings.allowedHttpHookUrls = remainingAllowedUrls;
    } else {
      delete nextSettings.allowedHttpHookUrls;
    }
  }

  return nextSettings;
}

export async function inspectClaudeHooksInstallation(options = {}) {
  const settingsPath = resolveSettingsPath(options);
  const settings = await readJsonFileOrDefault(settingsPath, {});
  const summary = summarizeManagedHooks(settings);
  const bridgeUrl = options.bridgeUrl ?? DEFAULT_BRIDGE_URL;

  return {
    settingsPath,
    settings,
    bridgeUrl,
    allowedHttpHookUrl: buildAllowedHttpHookUrl(bridgeUrl),
    allowedHttpHookUrlInstalled: (settings.allowedHttpHookUrls ?? []).includes(buildAllowedHttpHookUrl(bridgeUrl)),
    ...summary
  };
}

export async function installClaudeHooks(options = {}) {
  const settingsPath = resolveSettingsPath(options);
  const existingSettings = await readJsonFileOrDefault(settingsPath, {});
  const installedSettings = buildInstalledSettings(existingSettings, options);
  await writeJsonFile(settingsPath, installedSettings);

  return {
    settingsPath,
    settings: installedSettings
  };
}

export async function uninstallClaudeHooks(options = {}) {
  const settingsPath = resolveSettingsPath(options);
  const existingSettings = await readJsonFileOrDefault(settingsPath, {});
  const nextSettings = buildUninstalledSettings(existingSettings, options);
  await writeJsonFile(settingsPath, nextSettings);

  return {
    settingsPath,
    settings: nextSettings
  };
}
