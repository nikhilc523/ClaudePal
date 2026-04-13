function shouldLog(level, minimumLevel) {
  const priorities = {
    debug: 10,
    info: 20,
    warn: 30,
    error: 40
  };

  return priorities[level] >= priorities[minimumLevel];
}

export function createLogger({ level = "info", sink = console.log } = {}) {
  function log(messageLevel, message, metadata = {}) {
    if (!shouldLog(messageLevel, level)) {
      return;
    }

    sink(
      JSON.stringify({
        timestamp: new Date().toISOString(),
        level: messageLevel,
        message,
        ...metadata
      })
    );
  }

  return {
    debug(message, metadata) {
      log("debug", message, metadata);
    },
    info(message, metadata) {
      log("info", message, metadata);
    },
    warn(message, metadata) {
      log("warn", message, metadata);
    },
    error(message, metadata) {
      log("error", message, metadata);
    }
  };
}
