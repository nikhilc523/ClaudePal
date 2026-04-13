import { sign as signJwt, createPrivateKey } from "node:crypto";
import { readFileSync } from "node:fs";
import { connect } from "node:http2";

function encodeBase64Url(value) {
  const input = typeof value === "string" ? value : JSON.stringify(value);
  return Buffer.from(input).toString("base64url");
}

function removeNilValues(object) {
  return Object.fromEntries(
    Object.entries(object ?? {}).filter(([, value]) => value !== null && value !== undefined)
  );
}

function createHttp2Transport() {
  return {
    async request({ authority, headers, body }) {
      return await new Promise((resolve, reject) => {
        const client = connect(authority);
        let responseHeaders = {};
        const chunks = [];

        client.on("error", reject);

        const request = client.request(headers);
        request.setEncoding("utf8");
        request.on("response", (headers) => {
          responseHeaders = headers;
        });
        request.on("data", (chunk) => {
          chunks.push(chunk);
        });
        request.on("error", (error) => {
          client.destroy();
          reject(error);
        });
        request.on("end", () => {
          client.close();
          resolve({
            status: Number(responseHeaders[":status"] ?? 0),
            headers: responseHeaders,
            body: chunks.join("")
          });
        });
        request.end(body);
      });
    }
  };
}

function environmentAuthority(environment) {
  return environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
}

function apnsEnvironment(env) {
  return env.CLAUDEPAL_APNS_ENV === "production" ? "production" : "development";
}

function readPrivateKey(env) {
  if (env.CLAUDEPAL_APNS_PRIVATE_KEY) {
    return env.CLAUDEPAL_APNS_PRIVATE_KEY;
  }

  if (env.CLAUDEPAL_APNS_PRIVATE_KEY_PATH) {
    return readFileSync(env.CLAUDEPAL_APNS_PRIVATE_KEY_PATH, "utf8");
  }

  return null;
}

export class NoopPushGateway {
  async send(notification) {
    return {
      status: "skipped",
      notification
    };
  }
}

export class RecordingPushGateway {
  constructor() {
    this.sent = [];
  }

  async send(notification) {
    this.sent.push(notification);
    return {
      status: "sent",
      notification
    };
  }
}

export class APNsPushGateway {
  constructor({
    keyId,
    teamId,
    bundleId,
    privateKey,
    environment = "development",
    now = () => Date.now(),
    transport = createHttp2Transport()
  }) {
    this.keyId = keyId;
    this.teamId = teamId;
    this.bundleId = bundleId;
    this.privateKey = createPrivateKey(privateKey);
    this.environment = environment;
    this.now = now;
    this.transport = transport;
    this.cachedToken = null;
    this.cachedTokenIssuedAt = 0;
  }

  authorizationToken() {
    const issuedAt = Math.floor(this.now() / 1000);

    if (this.cachedToken && issuedAt - this.cachedTokenIssuedAt < 50 * 60) {
      return this.cachedToken;
    }

    const header = {
      alg: "ES256",
      kid: this.keyId
    };
    const claims = {
      iss: this.teamId,
      iat: issuedAt
    };
    const signingInput = `${encodeBase64Url(header)}.${encodeBase64Url(claims)}`;
    const signature = signJwt("sha256", Buffer.from(signingInput), {
      key: this.privateKey,
      dsaEncoding: "ieee-p1363"
    });

    this.cachedToken = `${signingInput}.${signature.toString("base64url")}`;
    this.cachedTokenIssuedAt = issuedAt;
    return this.cachedToken;
  }

  payloadFor(notification) {
    return JSON.stringify({
      aps: removeNilValues({
        alert: removeNilValues({
          title: notification.title,
          body: notification.body
        }),
        sound: notification.sound ?? "default",
        category: notification.category
      }),
      ...removeNilValues(notification.userInfo)
    });
  }

  async send(notification) {
    const response = await this.transport.request({
      authority: environmentAuthority(this.environment),
      headers: {
        ":method": "POST",
        ":path": `/3/device/${notification.deviceToken}`,
        authorization: `bearer ${this.authorizationToken()}`,
        "apns-topic": this.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10"
      },
      body: this.payloadFor(notification)
    });

    if (response.status >= 200 && response.status < 300) {
      return {
        status: "sent",
        notification,
        apnsId: response.headers["apns-id"] ?? null
      };
    }

    const error = new Error(`APNs request failed with status ${response.status}.`);
    error.statusCode = response.status;
    error.responseBody = response.body;
    throw error;
  }
}

export function createPushGatewayFromEnv({
  env = process.env,
  logger = null,
  now,
  transport
} = {}) {
  const keyId = env.CLAUDEPAL_APNS_KEY_ID;
  const teamId = env.CLAUDEPAL_APNS_TEAM_ID;
  const bundleId = env.CLAUDEPAL_APNS_BUNDLE_ID;
  const privateKey = readPrivateKey(env);

  if (!keyId || !teamId || !bundleId || !privateKey) {
    logger?.info?.("push.gateway_configured", {
      provider: "noop"
    });
    return new NoopPushGateway();
  }

  logger?.info?.("push.gateway_configured", {
    provider: "apns",
    environment: apnsEnvironment(env)
  });

  return new APNsPushGateway({
    keyId,
    teamId,
    bundleId,
    privateKey,
    environment: apnsEnvironment(env),
    now,
    transport
  });
}
