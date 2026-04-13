function escapeXml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&apos;");
}

function plistKey(key) {
  return `  <key>${escapeXml(key)}</key>`;
}

function plistString(value, indent = "  ") {
  return `${indent}<string>${escapeXml(value)}</string>`;
}

function renderStringArray(key, values) {
  const items = values.map((value) => plistString(value, "    "));
  return [
    plistKey(key),
    "  <array>",
    ...items,
    "  </array>"
  ].join("\n");
}

function renderEnvironmentVariables(environmentVariables) {
  const entries = Object.entries(environmentVariables)
    .filter(([, value]) => value !== undefined && value !== null && value !== "")
    .sort(([left], [right]) => left.localeCompare(right));

  if (entries.length === 0) {
    return null;
  }

  return [
    plistKey("EnvironmentVariables"),
    "  <dict>",
    ...entries.flatMap(([key, value]) => [
      `    <key>${escapeXml(key)}</key>`,
      plistString(value, "    ")
    ]),
    "  </dict>"
  ].join("\n");
}

export function createLaunchdPlist({
  label,
  nodePath,
  bridgeScriptPath,
  workingDirectory,
  standardOutPath,
  standardErrorPath,
  environmentVariables = {}
}) {
  const environmentSection = renderEnvironmentVariables(environmentVariables);

  return [
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
    "<plist version=\"1.0\">",
    "<dict>",
    plistKey("Label"),
    plistString(label),
    renderStringArray("ProgramArguments", [
      nodePath,
      "--disable-warning=ExperimentalWarning",
      bridgeScriptPath
    ]),
    plistKey("WorkingDirectory"),
    plistString(workingDirectory),
    plistKey("RunAtLoad"),
    "  <true/>",
    plistKey("KeepAlive"),
    "  <true/>",
    plistKey("ProcessType"),
    plistString("Background"),
    plistKey("StandardOutPath"),
    plistString(standardOutPath),
    plistKey("StandardErrorPath"),
    plistString(standardErrorPath),
    ...(environmentSection ? [environmentSection] : []),
    "</dict>",
    "</plist>",
    ""
  ].join("\n");
}

