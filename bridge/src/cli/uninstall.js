import { fileURLToPath } from "node:url";
import { uninstallClaudeHooks } from "../install/claude-hooks-config.js";
import { parseArguments } from "./status-support.js";

export async function runUninstallCommand(argv = process.argv.slice(2)) {
  const args = parseArguments(argv);
  const result = await uninstallClaudeHooks({
    bridgeUrl: args["bridge-url"],
    scope: args.scope,
    transport: args.transport,
    projectDir: args["project-dir"] ?? process.cwd()
  });

  console.log(
    JSON.stringify(
      {
        status: "uninstalled",
        settingsPath: result.settingsPath,
        hooks: Object.keys(result.settings.hooks ?? {})
      },
      null,
      2
    )
  );
}

if (process.argv[1] && process.argv[1] === fileURLToPath(import.meta.url)) {
  runUninstallCommand().catch((error) => {
    console.error(error.stack ?? error.message);
    process.exit(1);
  });
}

