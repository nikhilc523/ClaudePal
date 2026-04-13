import { parseArguments, collectStatusReport } from "./status-support.js";

function parseNodeMajorVersion(version) {
  return Number.parseInt(version.replace(/^v/, "").split(".")[0], 10);
}

function hasCompleteApnsConfig(env) {
  return Boolean(
    env.CLAUDEPAL_APNS_KEY_ID
    && env.CLAUDEPAL_APNS_TEAM_ID
    && env.CLAUDEPAL_APNS_BUNDLE_ID
    && (env.CLAUDEPAL_APNS_PRIVATE_KEY || env.CLAUDEPAL_APNS_PRIVATE_KEY_PATH)
  );
}

function statusFromChecks(checks) {
  if (checks.some((check) => check.status === "fail")) {
    return "fail";
  }

  if (checks.some((check) => check.status === "warn")) {
    return "warn";
  }

  return "pass";
}

export async function runDoctorCommand(argv = process.argv.slice(2), { env = process.env } = {}) {
  const args = parseArguments(argv);
  const report = await collectStatusReport(args);
  const nodeMajorVersion = parseNodeMajorVersion(process.version);
  const checks = [
    {
      name: "node",
      status: nodeMajorVersion >= 22 ? "pass" : "fail",
      message: nodeMajorVersion >= 22
        ? `Node ${process.version} satisfies the bridge runtime requirement.`
        : `Node ${process.version} is too old. Use Node 22 or newer.`
    },
    {
      name: "hook-script",
      status: report.hookScript.exists && report.hookScript.executable ? "pass" : "fail",
      message: report.hookScript.exists
        ? (
            report.hookScript.executable
              ? `${report.hookScript.path} is present and executable.`
              : `${report.hookScript.path} exists but is not executable.`
          )
        : `${report.hookScript.path} is missing.`
    },
    {
      name: "hooks-installed",
      status: report.hooks.installed ? "pass" : "fail",
      message: report.hooks.installed
        ? `ClaudePal hook groups are installed in ${report.hooks.settingsPath}.`
        : `No ClaudePal hook groups were found in ${report.hooks.settingsPath}.`
    },
    {
      name: "bridge-health",
      status: report.bridge.reachable ? "pass" : "fail",
      message: report.bridge.reachable
        ? `Bridge health endpoint responded at ${report.bridgeBaseUrl}.`
        : `Bridge health check failed for ${report.bridgeBaseUrl}.`
    },
    {
      name: "apns-config",
      status: hasCompleteApnsConfig(env) ? "pass" : "warn",
      message: hasCompleteApnsConfig(env)
        ? "APNs environment variables are present."
        : "APNs environment variables are incomplete. Push delivery cannot be validated yet."
    }
  ];

  const summary = {
    status: statusFromChecks(checks),
    checks,
    report
  };

  console.log(JSON.stringify(summary, null, 2));

  if (summary.status === "fail") {
    process.exitCode = 1;
  }
}

