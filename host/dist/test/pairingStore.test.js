import { describe, expect, it } from "vitest";
import { PairingStore } from "../src/auth/pairingStore.js";
describe("PairingStore", () => {
    it("claims a one-time pairing token and resumes with the device token", () => {
        let now = 1_000;
        const store = new PairingStore({ hostId: "host", now: () => now, pairingTtlMs: 1_000 });
        const payload = store.createPairingPayload("ws://192.168.1.10:8787", true);
        const device = store.claimPairing(payload.pairingToken, "Pixel");
        expect(device).not.toBeNull();
        expect(device?.name).toBe("Pixel");
        expect(store.claimPairing(payload.pairingToken, "Another phone")).toBeNull();
        expect(store.resume(device.token)?.id).toBe(device.id);
        now += 1;
        expect(store.resume("bad-token")).toBeNull();
    });
    it("rejects expired tokens", () => {
        let now = 1_000;
        const store = new PairingStore({ now: () => now, pairingTtlMs: 10 });
        const payload = store.createPairingPayload("ws://127.0.0.1:8787", true);
        now = 2_000;
        expect(store.claimPairing(payload.pairingToken, "Pixel")).toBeNull();
    });
});
