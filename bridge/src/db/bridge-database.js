import { DatabaseSync } from "node:sqlite";
import { ensurePrivateFile } from "../fs/private-storage.js";

function parseJson(text) {
  return text ? JSON.parse(text) : null;
}

function mapSession(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    cwd: row.cwd,
    displayName: row.display_name,
    status: row.status,
    lastEventType: row.last_event_type,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapEvent(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    sessionId: row.session_id,
    hookEventName: row.hook_event_name,
    type: row.type,
    title: row.title,
    message: row.message,
    payload: parseJson(row.payload_json),
    createdAt: row.created_at
  };
}

function mapPendingDecision(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    sessionId: row.session_id,
    eventId: row.event_id,
    decisionType: row.decision_type,
    status: row.status,
    payload: parseJson(row.payload_json),
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    resolvedAt: row.resolved_at,
    resolution: parseJson(row.resolution_json)
  };
}

function mapPairingSession(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    pairingCode: row.pairing_code,
    bridgeUrl: row.bridge_url,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    completedAt: row.completed_at
  };
}

function mapDevice(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    pairingSessionId: row.pairing_session_id,
    platform: row.platform,
    deviceName: row.device_name,
    appVersion: row.app_version,
    authToken: row.auth_token,
    pushToken: row.push_token,
    notificationsEnabled: row.notifications_enabled === 1,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export class BridgeDatabase {
  constructor({ dbPath }) {
    if (dbPath !== ":memory:") {
      ensurePrivateFile(dbPath, { create: true });
    }

    this.db = new DatabaseSync(dbPath);
    if (dbPath !== ":memory:") {
      ensurePrivateFile(dbPath);
    }
    this.db.exec("PRAGMA foreign_keys = ON;");
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        cwd TEXT NOT NULL,
        display_name TEXT NOT NULL,
        status TEXT NOT NULL,
        last_event_type TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        hook_event_name TEXT NOT NULL,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS pending_decisions (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
        decision_type TEXT NOT NULL,
        status TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT,
        resolved_at TEXT,
        resolution_json TEXT
      );

      CREATE TABLE IF NOT EXISTS pairing_sessions (
        id TEXT PRIMARY KEY,
        pairing_code TEXT NOT NULL UNIQUE,
        bridge_url TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        completed_at TEXT
      );

      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY,
        pairing_session_id TEXT REFERENCES pairing_sessions(id) ON DELETE SET NULL,
        platform TEXT NOT NULL,
        device_name TEXT NOT NULL,
        app_version TEXT,
        auth_token TEXT NOT NULL UNIQUE,
        push_token TEXT,
        notifications_enabled INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_events_session_created_at
        ON events(session_id, created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_pending_decisions_status
        ON pending_decisions(status);
      CREATE INDEX IF NOT EXISTS idx_pairing_sessions_code
        ON pairing_sessions(pairing_code);
      CREATE INDEX IF NOT EXISTS idx_devices_auth_token
        ON devices(auth_token);
      CREATE INDEX IF NOT EXISTS idx_devices_push_token
        ON devices(push_token);
    `);

    this.statements = {
      upsertSession: this.db.prepare(`
        INSERT INTO sessions (
          id,
          cwd,
          display_name,
          status,
          last_event_type,
          created_at,
          updated_at
        ) VALUES (
          @id,
          @cwd,
          @display_name,
          @status,
          @last_event_type,
          @created_at,
          @updated_at
        )
        ON CONFLICT(id) DO UPDATE SET
          cwd = excluded.cwd,
          display_name = excluded.display_name,
          status = excluded.status,
          last_event_type = excluded.last_event_type,
          updated_at = excluded.updated_at
      `),
      insertEvent: this.db.prepare(`
        INSERT INTO events (
          id,
          session_id,
          hook_event_name,
          type,
          title,
          message,
          payload_json,
          created_at
        ) VALUES (
          @id,
          @session_id,
          @hook_event_name,
          @type,
          @title,
          @message,
          @payload_json,
          @created_at
        )
      `),
      insertPendingDecision: this.db.prepare(`
        INSERT INTO pending_decisions (
          id,
          session_id,
          event_id,
          decision_type,
          status,
          payload_json,
          created_at,
          expires_at,
          resolved_at,
          resolution_json
        ) VALUES (
          @id,
          @session_id,
          @event_id,
          @decision_type,
          @status,
          @payload_json,
          @created_at,
          @expires_at,
          @resolved_at,
          @resolution_json
        )
      `),
      insertPairingSession: this.db.prepare(`
        INSERT INTO pairing_sessions (
          id,
          pairing_code,
          bridge_url,
          created_at,
          expires_at,
          completed_at
        ) VALUES (
          @id,
          @pairing_code,
          @bridge_url,
          @created_at,
          @expires_at,
          @completed_at
        )
      `),
      markPairingSessionCompleted: this.db.prepare(`
        UPDATE pairing_sessions
        SET completed_at = ?
        WHERE id = ?
      `),
      insertDevice: this.db.prepare(`
        INSERT INTO devices (
          id,
          pairing_session_id,
          platform,
          device_name,
          app_version,
          auth_token,
          push_token,
          notifications_enabled,
          created_at,
          updated_at
        ) VALUES (
          @id,
          @pairing_session_id,
          @platform,
          @device_name,
          @app_version,
          @auth_token,
          @push_token,
          @notifications_enabled,
          @created_at,
          @updated_at
        )
      `),
      updateDeviceRegistration: this.db.prepare(`
        UPDATE devices
        SET platform = @platform,
            device_name = @device_name,
            app_version = @app_version,
            push_token = @push_token,
            notifications_enabled = @notifications_enabled,
            updated_at = @updated_at
        WHERE id = @id
      `),
      getSession: this.db.prepare(`
        SELECT *
        FROM sessions
        WHERE id = ?
      `),
      updateSessionStatus: this.db.prepare(`
        UPDATE sessions
        SET status = ?,
            updated_at = ?
        WHERE id = ?
      `),
      getEvent: this.db.prepare(`
        SELECT *
        FROM events
        WHERE id = ?
      `),
      getPendingDecision: this.db.prepare(`
        SELECT *
        FROM pending_decisions
        WHERE id = ?
      `),
      resolvePendingDecision: this.db.prepare(`
        UPDATE pending_decisions
        SET status = @status,
            resolved_at = @resolved_at,
            resolution_json = @resolution_json
        WHERE id = @id
      `),
      getPairingSession: this.db.prepare(`
        SELECT *
        FROM pairing_sessions
        WHERE id = ?
      `),
      findActivePairingSessionByCode: this.db.prepare(`
        SELECT *
        FROM pairing_sessions
        WHERE pairing_code = ?
          AND completed_at IS NULL
          AND expires_at > ?
      `),
      getDeviceByAuthToken: this.db.prepare(`
        SELECT *
        FROM devices
        WHERE auth_token = ?
      `),
      getDeviceById: this.db.prepare(`
        SELECT *
        FROM devices
        WHERE id = ?
      `),
      listSessions: this.db.prepare(`
        SELECT *
        FROM sessions
        ORDER BY updated_at DESC
      `),
      listEvents: this.db.prepare(`
        SELECT *
        FROM events
        ORDER BY created_at DESC
        LIMIT ?
      `),
      listPendingDecisions: this.db.prepare(`
        SELECT *
        FROM pending_decisions
        ORDER BY created_at DESC
      `),
      listPushDevices: this.db.prepare(`
        SELECT *
        FROM devices
        WHERE notifications_enabled = 1
          AND push_token IS NOT NULL
          AND push_token <> ''
        ORDER BY updated_at DESC
      `),
      summary: this.db.prepare(`
        SELECT
          (SELECT COUNT(*) FROM sessions) AS sessions_count,
          (SELECT COUNT(*) FROM events) AS events_count,
          (SELECT COUNT(*) FROM pending_decisions) AS pending_decisions_count,
          (
            SELECT COUNT(*)
            FROM pending_decisions
            WHERE status = 'pending'
          ) AS unresolved_decisions_count,
          (SELECT COUNT(*) FROM devices) AS devices_count
      `)
    };
  }

  close() {
    this.db.close();
  }

  upsertSession(session) {
    this.statements.upsertSession.run({
      id: session.id,
      cwd: session.cwd,
      display_name: session.displayName,
      status: session.status,
      last_event_type: session.lastEventType,
      created_at: session.createdAt,
      updated_at: session.updatedAt
    });

    return this.getSession(session.id);
  }

  insertEvent(event) {
    this.statements.insertEvent.run({
      id: event.id,
      session_id: event.sessionId,
      hook_event_name: event.hookEventName,
      type: event.type,
      title: event.title,
      message: event.message,
      payload_json: JSON.stringify(event.payload),
      created_at: event.createdAt
    });

    return this.getEvent(event.id);
  }

  insertPendingDecision(pendingDecision) {
    this.statements.insertPendingDecision.run({
      id: pendingDecision.id,
      session_id: pendingDecision.sessionId,
      event_id: pendingDecision.eventId,
      decision_type: pendingDecision.decisionType,
      status: pendingDecision.status,
      payload_json: JSON.stringify(pendingDecision.payload),
      created_at: pendingDecision.createdAt,
      expires_at: pendingDecision.expiresAt,
      resolved_at: pendingDecision.resolvedAt,
      resolution_json: pendingDecision.resolution ? JSON.stringify(pendingDecision.resolution) : null
    });

    return this.getPendingDecision(pendingDecision.id);
  }

  insertPairingSession(pairingSession) {
    this.statements.insertPairingSession.run({
      id: pairingSession.id,
      pairing_code: pairingSession.pairingCode,
      bridge_url: pairingSession.bridgeUrl,
      created_at: pairingSession.createdAt,
      expires_at: pairingSession.expiresAt,
      completed_at: pairingSession.completedAt
    });

    return this.getPairingSession(pairingSession.id);
  }

  markPairingSessionCompleted(id, completedAt) {
    this.statements.markPairingSessionCompleted.run(completedAt, id);
    return this.getPairingSession(id);
  }

  insertDevice(device) {
    this.statements.insertDevice.run({
      id: device.id,
      pairing_session_id: device.pairingSessionId,
      platform: device.platform,
      device_name: device.deviceName,
      app_version: device.appVersion ?? null,
      auth_token: device.authToken,
      push_token: device.pushToken ?? null,
      notifications_enabled: device.notificationsEnabled ? 1 : 0,
      created_at: device.createdAt,
      updated_at: device.updatedAt
    });

    return this.getDeviceById(device.id);
  }

  updateDeviceRegistration(device) {
    this.statements.updateDeviceRegistration.run({
      id: device.id,
      platform: device.platform,
      device_name: device.deviceName,
      app_version: device.appVersion ?? null,
      push_token: device.pushToken ?? null,
      notifications_enabled: device.notificationsEnabled ? 1 : 0,
      updated_at: device.updatedAt
    });

    return this.getDeviceById(device.id);
  }

  getSession(id) {
    return mapSession(this.statements.getSession.get(id));
  }

  getEvent(id) {
    return mapEvent(this.statements.getEvent.get(id));
  }

  getPendingDecision(id) {
    return mapPendingDecision(this.statements.getPendingDecision.get(id));
  }

  getPairingSession(id) {
    return mapPairingSession(this.statements.getPairingSession.get(id));
  }

  findActivePairingSessionByCode(pairingCode, nowIso) {
    return mapPairingSession(this.statements.findActivePairingSessionByCode.get(pairingCode, nowIso));
  }

  getDeviceByAuthToken(authToken) {
    return mapDevice(this.statements.getDeviceByAuthToken.get(authToken));
  }

  getDeviceById(id) {
    return mapDevice(this.statements.getDeviceById.get(id));
  }

  updateSessionStatus(sessionId, status, updatedAt) {
    this.statements.updateSessionStatus.run(status, updatedAt, sessionId);
    return this.getSession(sessionId);
  }

  resolvePendingDecision({ id, status, resolvedAt, resolution }) {
    this.statements.resolvePendingDecision.run({
      id,
      status,
      resolved_at: resolvedAt,
      resolution_json: JSON.stringify(resolution)
    });

    return this.getPendingDecision(id);
  }

  listSessions() {
    return this.statements.listSessions.all().map(mapSession);
  }

  listEvents(limit = 50) {
    return this.statements.listEvents.all(limit).map(mapEvent);
  }

  listPendingDecisions() {
    return this.statements.listPendingDecisions.all().map(mapPendingDecision);
  }

  listPushDevices() {
    return this.statements.listPushDevices.all().map(mapDevice);
  }

  getSummary() {
    const summary = this.statements.summary.get();
    return {
      sessionsCount: summary.sessions_count,
      eventsCount: summary.events_count,
      pendingDecisionsCount: summary.pending_decisions_count,
      unresolvedDecisionsCount: summary.unresolved_decisions_count,
      devicesCount: summary.devices_count
    };
  }
}
