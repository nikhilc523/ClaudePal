import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { installClaudeHooks } from "../install/claude-hooks-config.js";

const PACKAGE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

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

export async function runInstallCommand(argv = process.argv.slice(2)) {
  const args = parseArguments(argv);
  const result = await installClaudeHooks({
    bridgeUrl: args["bridge-url"],
    scope: args.scope,
    transport: args.transport,
    projectDir: args["project-dir"] ?? process.cwd(),
    packageRoot: PACKAGE_ROOT,
    permissionTimeoutSeconds: args["permission-timeout-seconds"]
      ? Number.parseFloat(args["permission-timeout-seconds"])
      : undefined,
    elicitationTimeoutSeconds: args["elicitation-timeout-seconds"]
      ? Number.parseFloat(args["elicitation-timeout-seconds"])
      : undefined,
    asyncTimeoutSeconds: args["async-timeout-seconds"]
      ? Number.parseFloat(args["async-timeout-seconds"])
      : undefined
  });

  console.log(
    JSON.stringify(
      {
        status: "installed",
        settingsPath: result.settingsPath,
        hooks: Object.keys(result.settings.hooks ?? {})
      },
      null,
      2
    )
  );
}

if (process.argv[1] && process.argv[1] === fileURLToPath(import.meta.url)) {
  runInstallCommand().catch((error) => {
    console.error(error.stack ?? error.message);
    process.exit(1);
  });
}
