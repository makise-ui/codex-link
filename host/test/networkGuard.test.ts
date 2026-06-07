import { describe, expect, it } from "vitest";
import { assertAllowedRemoteAddress, isPrivateOrLoopbackAddress, normalizeRemoteAddress } from "../src/safety/networkGuard.js";

describe("networkGuard", () => {
  it("normalizes IPv4-mapped IPv6 addresses", () => {
    expect(normalizeRemoteAddress("::ffff:192.168.1.42")).toBe("192.168.1.42");
    expect(normalizeRemoteAddress("::1")).toBe("127.0.0.1");
  });

  it("allows loopback and private LAN ranges", () => {
    expect(isPrivateOrLoopbackAddress("127.0.0.1")).toBe(true);
    expect(isPrivateOrLoopbackAddress("10.1.2.3")).toBe(true);
    expect(isPrivateOrLoopbackAddress("172.16.0.1")).toBe(true);
    expect(isPrivateOrLoopbackAddress("172.31.255.254")).toBe(true);
    expect(isPrivateOrLoopbackAddress("192.168.1.99")).toBe(true);
    expect(isPrivateOrLoopbackAddress("169.254.1.99")).toBe(true);
  });

  it("rejects public addresses", () => {
    expect(isPrivateOrLoopbackAddress("8.8.8.8")).toBe(false);
    expect(isPrivateOrLoopbackAddress("172.32.0.1")).toBe(false);
    expect(isPrivateOrLoopbackAddress("1.2.3.4")).toBe(false);
  });

  it("allows public remote addresses when tunnel mode is explicit", () => {
    expect(() =>
      assertAllowedRemoteAddress("203.0.113.10", { remoteMode: "tunnel" }),
    ).not.toThrow();
  });

  it("keeps rejecting public remote addresses in lan mode", () => {
    expect(() =>
      assertAllowedRemoteAddress("203.0.113.10", { remoteMode: "lan" }),
    ).toThrow(/Rejected non-LAN/);
  });
});
