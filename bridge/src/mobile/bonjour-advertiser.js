import { spawn } from "node:child_process";
import { hostname as systemHostname } from "node:os";

export class NoopBonjourAdvertiser {
  start() {}

  stop() {}
}

export class DnsSdBonjourAdvertiser {
  constructor({
    logger,
    serviceName,
    serviceType = "_claudepal._tcp",
    domain = "local",
    spawnCommand = spawn
  }) {
    this.logger = logger;
    this.serviceName = serviceName;
    this.serviceType = serviceType;
    this.domain = domain;
    this.spawnCommand = spawnCommand;
    this.process = null;
  }

  start({ port }) {
    if (this.process || !port) {
      return;
    }

    const child = this.spawnCommand(
      "dns-sd",
      [
        "-R",
        this.serviceName,
        this.serviceType,
        this.domain,
        String(port),
        "path=/",
        "version=0.1.0"
      ],
      {
        stdio: "ignore"
      }
    );

    child.on("error", (error) => {
      this.logger.warn("bonjour.failed", {
        message: error.message
      });
    });
    child.on("exit", (code, signal) => {
      this.logger.info("bonjour.stopped", {
        code,
        signal
      });
      if (this.process === child) {
        this.process = null;
      }
    });

    this.process = child;
    this.logger.info("bonjour.started", {
      serviceName: this.serviceName,
      serviceType: this.serviceType,
      port
    });
  }

  stop() {
    if (!this.process) {
      return;
    }

    this.process.kill("SIGTERM");
    this.process = null;
  }
}

export function createBonjourAdvertiserFromEnv({
  env = process.env,
  logger,
  platform = process.platform,
  hostname = systemHostname(),
  spawnCommand = spawn
} = {}) {
  if (env.CLAUDEPAL_BONJOUR_DISABLED === "1" || platform !== "darwin") {
    return new NoopBonjourAdvertiser();
  }

  return new DnsSdBonjourAdvertiser({
    logger,
    serviceName: env.CLAUDEPAL_BONJOUR_NAME ?? `ClaudePal Bridge on ${hostname}`,
    spawnCommand
  });
}
