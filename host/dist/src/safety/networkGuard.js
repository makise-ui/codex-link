import net from "node:net";
export function normalizeRemoteAddress(address) {
    if (!address)
        return "";
    if (address.startsWith("::ffff:"))
        return address.slice("::ffff:".length);
    if (address === "::1")
        return "127.0.0.1";
    return address;
}
export function isPrivateOrLoopbackAddress(address) {
    const normalized = normalizeRemoteAddress(address);
    if (!normalized)
        return false;
    if (normalized === "localhost")
        return true;
    if (normalized === "127.0.0.1")
        return true;
    if (normalized.startsWith("127."))
        return true;
    if (net.isIPv4(normalized)) {
        const [a, b] = normalized.split(".").map((part) => Number(part));
        if (a === 10)
            return true;
        if (a === 172 && b >= 16 && b <= 31)
            return true;
        if (a === 192 && b === 168)
            return true;
        if (a === 169 && b === 254)
            return true;
        return false;
    }
    if (net.isIPv6(normalized)) {
        const lower = normalized.toLowerCase();
        return lower === "::1" || lower.startsWith("fe80:") || lower.startsWith("fc") || lower.startsWith("fd");
    }
    return false;
}
export function assertAllowedRemoteAddress(address) {
    if (!isPrivateOrLoopbackAddress(address)) {
        throw new Error(`Rejected non-LAN remote address: ${address ?? "unknown"}`);
    }
}
