import { createHash, randomUUID } from "node:crypto";

const WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

function createAcceptValue(key) {
  return createHash("sha1").update(`${key}${WEBSOCKET_GUID}`).digest("base64");
}

function createFrame(opcode, payloadBuffer = Buffer.alloc(0)) {
  const payloadLength = payloadBuffer.length;
  let header;

  if (payloadLength < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x80 | opcode;
    header[1] = payloadLength;
  } else if (payloadLength < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(payloadLength, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(payloadLength), 2);
  }

  return Buffer.concat([header, payloadBuffer]);
}

function createTextFrame(message) {
  return createFrame(0x1, Buffer.from(message));
}

function createPongFrame(payloadBuffer) {
  return createFrame(0xA, payloadBuffer);
}

function createCloseFrame() {
  return createFrame(0x8);
}

function decodeIncomingFrames(buffer) {
  const frames = [];
  let offset = 0;

  while (offset + 2 <= buffer.length) {
    const firstByte = buffer[offset];
    const secondByte = buffer[offset + 1];
    const opcode = firstByte & 0x0f;
    const masked = (secondByte & 0x80) !== 0;
    let payloadLength = secondByte & 0x7f;
    offset += 2;

    if (payloadLength === 126) {
      if (offset + 2 > buffer.length) {
        break;
      }
      payloadLength = buffer.readUInt16BE(offset);
      offset += 2;
    } else if (payloadLength === 127) {
      if (offset + 8 > buffer.length) {
        break;
      }
      payloadLength = Number(buffer.readBigUInt64BE(offset));
      offset += 8;
    }

    let mask;
    if (masked) {
      if (offset + 4 > buffer.length) {
        break;
      }
      mask = buffer.subarray(offset, offset + 4);
      offset += 4;
    }

    if (offset + payloadLength > buffer.length) {
      break;
    }

    const payload = buffer.subarray(offset, offset + payloadLength);
    offset += payloadLength;

    if (masked) {
      for (let index = 0; index < payload.length; index += 1) {
        payload[index] ^= mask[index % 4];
      }
    }

    frames.push({
      opcode,
      payload
    });
  }

  return frames;
}

export class WebSocketHub {
  constructor({ logger, snapshotProvider }) {
    this.logger = logger;
    this.snapshotProvider = snapshotProvider;
    this.clients = new Map();
  }

  handleUpgrade(request, socket) {
    const key = request.headers["sec-websocket-key"];
    if (!key) {
      socket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
      socket.destroy();
      return;
    }

    const acceptValue = createAcceptValue(key);
    socket.write(
      [
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
        `Sec-WebSocket-Accept: ${acceptValue}`,
        "\r\n"
      ].join("\r\n")
    );

    const clientId = randomUUID();
    const client = { id: clientId, socket };
    this.clients.set(clientId, client);

    socket.on("close", () => {
      this.clients.delete(clientId);
    });
    socket.on("end", () => {
      this.clients.delete(clientId);
    });
    socket.on("error", () => {
      this.clients.delete(clientId);
    });
    socket.on("data", (chunk) => {
      for (const frame of decodeIncomingFrames(chunk)) {
        if (frame.opcode === 0x8) {
          socket.write(createCloseFrame());
          socket.end();
          this.clients.delete(clientId);
          return;
        }

        if (frame.opcode === 0x9) {
          socket.write(createPongFrame(frame.payload));
        }
      }
    });

    this.logger.info("websocket.connected", { clientId });
    this.send(client, {
      type: "snapshot",
      ...this.snapshotProvider()
    });
  }

  send(client, payload) {
    if (client.socket.destroyed) {
      this.clients.delete(client.id);
      return;
    }

    client.socket.write(createTextFrame(JSON.stringify(payload)));
  }

  broadcast(payload) {
    for (const client of this.clients.values()) {
      this.send(client, payload);
    }
  }

  close() {
    for (const client of this.clients.values()) {
      client.socket.end();
    }
    this.clients.clear();
  }
}
