import os from "node:os";
import { isPrivateOrLoopbackAddress } from "../safety/networkGuard.js";

export function findLanAddress(): string | null {
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries ?? []) {
      if (entry.family !== "IPv4" || entry.internal) continue;
      if (isPrivateOrLoopbackAddress(entry.address)) {
        return entry.address;
      }
    }
  }
  return null;
}
