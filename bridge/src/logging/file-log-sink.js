import { appendFileSync } from "node:fs";
import { preparePrivateFilePath } from "../fs/private-storage.js";

export function createFileLogSink({ logPath }) {
  preparePrivateFilePath(logPath);

  return (line) => {
    preparePrivateFilePath(logPath);
    appendFileSync(logPath, `${line}\n`, {
      encoding: "utf8",
      mode: 0o600
    });
  };
}

export function createCompositeSink(...sinks) {
  const activeSinks = sinks.filter(Boolean);

  return (line) => {
    for (const sink of activeSinks) {
      sink(line);
    }
  };
}
