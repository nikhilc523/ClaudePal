import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const ROUTES = {
  PermissionRequest: "/api/hooks/permission-request",
  Notification: "/api/hooks/notification",
  Elicitation: "/api/hooks/elicitation",
  TaskCompleted: "/api/hooks/task-completed",
  Stop: "/api/hooks/stop"
};

function parseArguments(argv) {
  const argumentsMap = {};

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) {
      continue;
    }

    argumentsMap[token.slice(2)] = argv[index + 1];
    index += 1;
  }

  return argumentsMap;
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const baseUrl = args["base-url"] ?? "http://127.0.0.1:19876";
  const fixturePath = args.fixture;

  if (!fixturePath) {
    console.error("Usage: npm run mock:event -- --fixture test/fixtures/permission-request.json");
    process.exit(1);
  }

  const absoluteFixturePath = resolve(process.cwd(), fixturePath);
  const payload = JSON.parse(await readFile(absoluteFixturePath, "utf8"));
  const route = ROUTES[payload.hook_event_name];

  if (!route) {
    console.error(`Unsupported hook_event_name: ${payload.hook_event_name}`);
    process.exit(1);
  }

  const response = await fetch(`${baseUrl}${route}`, {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  const body = await response.json();

  if (!response.ok) {
    console.error(JSON.stringify(body, null, 2));
    process.exit(1);
  }

  console.log(JSON.stringify(body, null, 2));
}

main().catch((error) => {
  console.error(error.stack ?? error.message);
  process.exit(1);
});
