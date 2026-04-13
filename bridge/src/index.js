import { resolve } from "node:path";
import { createBridgeServer } from "./server/bridge-server.js";
import { createLogger } from "./logging/logger.js";
import { createCompositeSink, createFileLogSink } from "./logging/file-log-sink.js";
import { createPushGatewayFromEnv } from "./push/push-gateway.js";
import { createBonjourAdvertiserFromEnv } from "./mobile/bonjour-advertiser.js";

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

const logPath = process.env.CLAUDEPAL_LOG_PATH
  ?? resolve(process.cwd(), "data", "claudepal.log");

const logger = createLogger({
  level: process.env.CLAUDEPAL_LOG_LEVEL ?? "info",
  sink: createCompositeSink(
    console.log,
    createFileLogSink({ logPath })
  )
});

const host = process.env.CLAUDEPAL_HOST ?? "127.0.0.1";
const port = parseInteger(process.env.CLAUDEPAL_PORT, 19876);
const dbPath = process.env.CLAUDEPAL_DB_PATH ?? resolve(process.cwd(), "data", "claudepal.sqlite");

const server = createBridgeServer({
  host,
  port,
  dbPath,
  logger,
  notificationDispatcherOptions: {
    dedupWindowMs: parseInteger(process.env.CLAUDEPAL_PUSH_DEDUP_WINDOW_MS, 30_000),
    reminderLeadMs: parseInteger(process.env.CLAUDEPAL_PUSH_REMINDER_LEAD_MS, 60_000),
    pushRetryAttempts: parseInteger(process.env.CLAUDEPAL_PUSH_RETRY_ATTEMPTS, 3),
    pushRetryDelayMs: parseInteger(process.env.CLAUDEPAL_PUSH_RETRY_DELAY_MS, 250)
  },
  pushGateway: createPushGatewayFromEnv({
    env: process.env,
    logger
  }),
  bonjourAdvertiser: createBonjourAdvertiserFromEnv({
    env: process.env,
    logger
  })
});

async function shutdown(signal) {
  logger.info("bridge.stopping", { signal });
  await server.stop();
  process.exit(0);
}

process.on("SIGINT", () => {
  shutdown("SIGINT").catch((error) => {
    logger.error("bridge.stop_failed", { message: error.message });
    process.exit(1);
  });
});

process.on("SIGTERM", () => {
  shutdown("SIGTERM").catch((error) => {
    logger.error("bridge.stop_failed", { message: error.message });
    process.exit(1);
  });
});

server.start().catch((error) => {
  logger.error("bridge.start_failed", { message: error.message });
  process.exit(1);
});
