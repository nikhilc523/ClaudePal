import { collectStatusReport, parseArguments } from "./status-support.js";

export async function runStatusCommand(argv = process.argv.slice(2)) {
  const args = parseArguments(argv);
  const report = await collectStatusReport(args);
  console.log(JSON.stringify(report, null, 2));
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1])) {
  runStatusCommand().catch((error) => {
    console.error(error.stack ?? error.message);
    process.exit(1);
  });
}

