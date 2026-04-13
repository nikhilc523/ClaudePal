import { randomBytes, randomUUID } from "node:crypto";

function createPairingCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = randomBytes(6);

  return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("");
}

function createAuthToken() {
  return randomBytes(24).toString("hex");
}

function createPairingPayload(bridgeUrl, pairingCode) {
  const url = new URL("claudepal://pair");
  url.searchParams.set("bridgeUrl", bridgeUrl);
  url.searchParams.set("pairingCode", pairingCode);
  return url.toString();
}

export class MobileCompanionService {
  constructor({ database, bridgeService, logger }) {
    this.database = database;
    this.bridgeService = bridgeService;
    this.logger = logger;
  }

  createPairingSession({ bridgeUrl, expiresInSeconds = 600 } = {}, now = new Date()) {
    const createdAt = now.toISOString();
    const pairingSession = this.database.insertPairingSession({
      id: randomUUID(),
      pairingCode: createPairingCode(),
      bridgeUrl,
      createdAt,
      expiresAt: new Date(now.getTime() + expiresInSeconds * 1000).toISOString(),
      completedAt: null
    });

    this.logger.info("pairing.session_created", {
      pairingSessionId: pairingSession.id
    });

    return {
      pairingSession,
      qrPayload: createPairingPayload(pairingSession.bridgeUrl, pairingSession.pairingCode)
    };
  }

  completePairing({ pairingCode, deviceName, platform, appVersion }, now = new Date()) {
    const pairingSession = this.database.findActivePairingSessionByCode(pairingCode, now.toISOString());

    if (!pairingSession) {
      throw new Error("Pairing session not found.");
    }

    const timestamp = now.toISOString();
    const device = this.database.insertDevice({
      id: randomUUID(),
      pairingSessionId: pairingSession.id,
      platform,
      deviceName,
      appVersion: appVersion ?? null,
      authToken: createAuthToken(),
      pushToken: null,
      notificationsEnabled: false,
      createdAt: timestamp,
      updatedAt: timestamp
    });

    this.database.markPairingSessionCompleted(pairingSession.id, timestamp);

    this.logger.info("pairing.completed", {
      pairingSessionId: pairingSession.id,
      deviceId: device.id
    });

    return {
      bridgeUrl: pairingSession.bridgeUrl,
      device
    };
  }

  authenticateDevice(authToken) {
    const device = this.database.getDeviceByAuthToken(authToken);

    if (!device) {
      throw new Error("Unauthorized device.");
    }

    return device;
  }

  registerDevice({ authToken, pushToken, notificationsEnabled, deviceName, platform, appVersion }, now = new Date()) {
    const device = this.authenticateDevice(authToken);
    const updatedDevice = this.database.updateDeviceRegistration({
      ...device,
      pushToken,
      notificationsEnabled,
      deviceName: deviceName ?? device.deviceName,
      platform: platform ?? device.platform,
      appVersion: appVersion ?? device.appVersion,
      updatedAt: now.toISOString()
    });

    this.logger.info("device.registered", {
      deviceId: updatedDevice.id,
      notificationsEnabled: updatedDevice.notificationsEnabled
    });

    return updatedDevice;
  }

  resolveDeviceDecision({ authToken, decisionId, payload }, now = new Date()) {
    const device = this.authenticateDevice(authToken);
    const result = this.bridgeService.resolvePendingDecision(decisionId, payload, now);

    return {
      device,
      ...result
    };
  }
}
