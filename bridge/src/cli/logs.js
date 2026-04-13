import { copyFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

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

function timestampFragment(date = new Date()) {
  return date.toISOString().replaceAll(":", "-");
}

function requestHeaders(authToken) {
  if (!authToken) {
    return {};
  }

  return {
    authorization: `Bearer ${authToken}`
  };
}

async function fetchJson(baseUrl, pathname, authToken) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    headers: requestHeaders(authToken)
  });
  const text = await response.text();

  if (!response.ok) {
    return {
      ok: false,
      status: response.status,
      error: text
    };
  }

  return {
    ok: true,
    status: response.status,
    body: text.length > 0 ? JSON.parse(text) : null
  };
}

function printUsageAndExit() {
  console.error("Usage: claudepal-bridge logs export [options]");
  process.exit(1);
}

export async function runLogsCommand(argv = process.argv.slice(2)) {
  const [subcommand, ...rest] = argv;
  if (subcommand !== "export") {
    printUsageAndExit();
  }

  const args = parseArguments(rest);
  const outputDirectory = args["output-dir"]
    ?? resolve(process.cwd(), `claudepal-debug-${timestampFragment()}`);
  const logPath = args["log-path"] ?? resolve(process.cwd(), "data", "claudepal.log");
  const baseUrl = args["base-url"] ?? null;
  const authToken = args["auth-token"] ?? null;

  mkdirSync(outputDirectory, { recursive: true, mode: 0o700 });

  const manifest = {
    generatedAt: new Date().toISOString(),
    logPath,
    baseUrl,
    files: []
  };

  if (existsSync(logPath)) {
    const exportedLogPath = resolve(outputDirectory, "bridge.log");
    copyFileSync(logPath, exportedLogPath);
    manifest.files.push("bridge.log");
  }

  if (baseUrl) {
    const endpoints = [
      ["health.json", "/health"],
      ["sessions.json", "/api/sessions"],
      ["events.json", "/api/events?limit=200"],
      ["pending-decisions.json", "/api/pending-decisions"]
    ];

    for (const [fileName, pathname] of endpoints) {
      const result = await fetchJson(baseUrl, pathname, authToken);
      writeFileSync(resolve(outputDirectory, fileName), JSON.stringify(result, null, 2));
      manifest.files.push(fileName);
    }
  }

  writeFileSync(resolve(outputDirectory, "manifest.json"), JSON.stringify(manifest, null, 2));

  console.log(JSON.stringify({
    status: "exported",
    outputDirectory,
    files: manifest.files
  }, null, 2));
}

