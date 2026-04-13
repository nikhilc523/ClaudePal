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

export async function runPairCommand(argv = process.argv.slice(2)) {
  const args = parseArguments(argv);
  const baseUrl = args["base-url"] ?? "http://127.0.0.1:19876";
  const bridgeUrl = args["bridge-url"] ?? baseUrl;
  const expiresInSeconds = args["expires-in-seconds"]
    ? Number.parseInt(args["expires-in-seconds"], 10)
    : 600;

  const response = await fetch(`${baseUrl}/api/pairing/sessions`, {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body: JSON.stringify({
      bridgeUrl,
      expiresInSeconds
    })
  });
  const body = await response.json();

  if (!response.ok) {
    console.error(JSON.stringify(body, null, 2));
    process.exit(1);
  }

  console.log(JSON.stringify(body, null, 2));
}
