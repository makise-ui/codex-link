import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { PROTOCOL_VERSION } from "../protocol/messages.js";
export class PairingStore {
    now;
    pairingTtlMs;
    activePairing = null;
    devicesByToken = new Map();
    password;
    hostId;
    constructor(options = {}) {
        this.hostId = options.hostId ?? randomUUID();
        this.now = options.now ?? Date.now;
        this.pairingTtlMs = options.pairingTtlMs ?? 5 * 60 * 1000;
        this.password = options.password;
    }
    createPairingPayload(input, insecureDevMode = false) {
        const payloadInput = typeof input === "string"
            ? { url: input, insecureDevMode }
            : input;
        const token = randomToken(32);
        this.activePairing = {
            token,
            expiresAt: this.now() + this.pairingTtlMs,
            used: false,
        };
        return {
            version: PROTOCOL_VERSION,
            url: payloadInput.url,
            pairingToken: token,
            hostId: this.hostId,
            insecureDevMode: payloadInput.insecureDevMode,
            ...(payloadInput.localUrl ? { localUrl: payloadInput.localUrl } : {}),
            ...(payloadInput.connectionMode ? { connectionMode: payloadInput.connectionMode } : {}),
            ...(payloadInput.tunnelProvider ? { tunnelProvider: payloadInput.tunnelProvider } : {}),
        };
    }
    claimPairing(pairingToken, deviceName) {
        const pairing = this.activePairing;
        if (!pairing || pairing.used || pairing.expiresAt <= this.now()) {
            return null;
        }
        if (!safeEqual(pairing.token, pairingToken)) {
            return null;
        }
        pairing.used = true;
        const device = {
            id: randomUUID(),
            name: deviceName.trim(),
            token: randomToken(32),
            pairedAt: this.now(),
            lastSeenAt: this.now(),
        };
        this.devicesByToken.set(device.token, device);
        return device;
    }
    resume(deviceToken) {
        const device = this.devicesByToken.get(deviceToken);
        if (!device) {
            return null;
        }
        device.lastSeenAt = this.now();
        return device;
    }
    claimPassword(password, deviceName) {
        if (!this.password || !safeEqual(this.password, password)) {
            return null;
        }
        const device = {
            id: randomUUID(),
            name: deviceName.trim(),
            token: randomToken(32),
            pairedAt: this.now(),
            lastSeenAt: this.now(),
        };
        this.devicesByToken.set(device.token, device);
        return device;
    }
    revoke(deviceToken) {
        return this.devicesByToken.delete(deviceToken);
    }
    listDevices() {
        return [...this.devicesByToken.values()];
    }
}
function randomToken(byteLength) {
    return randomBytes(byteLength).toString("base64url");
}
function safeEqual(expected, actual) {
    const expectedBytes = Buffer.from(expected);
    const actualBytes = Buffer.from(actual);
    if (expectedBytes.byteLength !== actualBytes.byteLength) {
        return false;
    }
    return timingSafeEqual(expectedBytes, actualBytes);
}
