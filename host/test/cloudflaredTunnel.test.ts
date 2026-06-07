import { describe, expect, it } from "vitest";
import { extractCloudflaredQuickTunnelUrl, toWebSocketTunnelUrl } from "../src/tunnel/cloudflaredTunnel.js";

describe("cloudflared quick tunnel helpers", () => {
  it("extracts the generated trycloudflare url from cloudflared logs", () => {
    const output = [
      "2026-06-07T16:10:00Z INF Requesting new quick Tunnel on trycloudflare.com...",
      "2026-06-07T16:10:01Z INF +--------------------------------------------------------------------------------------------+",
      "2026-06-07T16:10:01Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |",
      "2026-06-07T16:10:01Z INF |  https://administrative-preview-travelling-violations.trycloudflare.com                  |",
    ].join("\n");

    expect(extractCloudflaredQuickTunnelUrl(output)).toBe("https://administrative-preview-travelling-violations.trycloudflare.com");
    expect(toWebSocketTunnelUrl("https://administrative-preview-travelling-violations.trycloudflare.com")).toBe(
      "wss://administrative-preview-travelling-violations.trycloudflare.com",
    );
  });
});
