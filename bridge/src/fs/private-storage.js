import { chmodSync, closeSync, existsSync, mkdirSync, openSync } from "node:fs";
import { dirname } from "node:path";

const PRIVATE_DIRECTORY_MODE = 0o700;
const PRIVATE_FILE_MODE = 0o600;

function ignoreMissingPath(error) {
  if (error?.code === "ENOENT") {
    return;
  }

  throw error;
}

export function ensurePrivateDirectory(directoryPath) {
  mkdirSync(directoryPath, {
    recursive: true,
    mode: PRIVATE_DIRECTORY_MODE
  });

  try {
    chmodSync(directoryPath, PRIVATE_DIRECTORY_MODE);
  } catch (error) {
    ignoreMissingPath(error);
  }
}

export function ensurePrivateFile(filePath, { create = false } = {}) {
  ensurePrivateDirectory(dirname(filePath));

  if (create && !existsSync(filePath)) {
    const fileDescriptor = openSync(filePath, "a", PRIVATE_FILE_MODE);
    closeSync(fileDescriptor);
  }

  try {
    chmodSync(filePath, PRIVATE_FILE_MODE);
  } catch (error) {
    ignoreMissingPath(error);
  }
}

export function preparePrivateFilePath(filePath) {
  ensurePrivateDirectory(dirname(filePath));
  ensurePrivateFile(filePath, { create: true });
}

