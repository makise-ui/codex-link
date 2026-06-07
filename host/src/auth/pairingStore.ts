import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { PROTOCOL_VERSION, type PairingPayload } from "../protocol/messages.js";

export type PairedDevice = {
  id: string;
  name: string;
  token: string;
  pairedAt: number;
  lastSeenAt?: number;
};

export type PairingStoreOptions = {
  hostId?: string;
  now?: () => number;
  pairingTtlMs?: number;
  password?: string;
};

type ActivePairing = {
  token: string;
  expiresAt: number;
  used: boolean;
};

export class PairingStore {
  private readonly now: () => number;
  private readonly pairingTtlMs: number;
  private activePairing: ActivePairing | null = null;
  private readonly devicesByToken = new Map<string, PairedDevice>();
  private readonly password?: string;
  readonly hostId: string;

  constructor(options: PairingStoreOptions = {}) {
    this.hostId = options.hostId ?? randomUUID();
    this.now = options.now ?? Date.now;
    this.pairingTtlMs = options.pairingTtlMs ?? 5 * 60 * 1000;
    this.password = options.password;
  }

  createPairingPayload(url: string, insecureDevMode: boolean): PairingPayload {
    const token = randomToken(32);
    this.activePairing = {
      token,
      expiresAt: this.now() + this.pairingTtlMs,
      used: false,
    };

    return {
      version: PROTOCOL_VERSION,
      url,
      pairingToken: token,
      hostId: this.hostId,
      insecureDevMode,
    };
  }

  claimPairing(pairingToken: string, deviceName: string): PairedDevice | null {
    const pairing = this.activePairing;
    if (!pairing || pairing.used || pairing.expiresAt <= this.now()) {
      return null;
    }

    if (!safeEqual(pairing.token, pairingToken)) {
      return null;
    }

    pairing.used = true;
    const device: PairedDevice = {
      id: randomUUID(),
      name: deviceName.trim(),
      token: randomToken(32),
      pairedAt: this.now(),
      lastSeenAt: this.now(),
    };
    this.devicesByToken.set(device.token, device);
    return device;
  }

  resume(deviceToken: string): PairedDevice | null {
    const device = this.devicesByToken.get(deviceToken);
    if (!device) {
      return null;
    }
    device.lastSeenAt = this.now();
    return device;
  }

  claimPassword(password: string, deviceName: string): PairedDevice | null {
    if (!this.password || !safeEqual(this.password, password)) {
      return null;
    }
    const device: PairedDevice = {
      id: randomUUID(),
      name: deviceName.trim(),
      token: randomToken(32),
      pairedAt: this.now(),
      lastSeenAt: this.now(),
    };
    this.devicesByToken.set(device.token, device);
    return device;
  }

  revoke(deviceToken: string): boolean {
    return this.devicesByToken.delete(deviceToken);
  }

  listDevices(): PairedDevice[] {
    return [...this.devicesByToken.values()];
  }
}

function randomToken(byteLength: number): string {
  return randomBytes(byteLength).toString("base64url");
}

function safeEqual(expected: string, actual: string): boolean {
  const expectedBytes = Buffer.from(expected);
  const actualBytes = Buffer.from(actual);
  if (expectedBytes.byteLength !== actualBytes.byteLength) {
    return false;
  }
  return timingSafeEqual(expectedBytes, actualBytes);
}
