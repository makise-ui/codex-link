# Security Model

Codex Link is designed around a host-controlled trust boundary.

## Trust Boundary

The Flutter app is a controller. It does not execute shell commands directly and does not receive unrestricted filesystem access. It sends structured requests to the host bridge, and the host decides what is allowed.

## Recommended Deployment

- Use LAN mode only on a trusted network.
- Use tunnel mode for remote access.
- Keep the host bound to localhost or a private interface when tunneling.
- Let the tunnel provider terminate TLS and provide the public `wss://` endpoint.
- Require a strong host password for tunnel mode.

Do not expose the host bridge directly on a public VPS port.

## Workspaces

Codex sessions are constrained to host-configured workspaces. File transfer requests are resolved against the active workspace and rejected when they escape that directory.

## Yolo Mode

Yolo mode is opt-in at host startup with `--allow-yolo`. It maps the selected session to Codex `danger-full-access` with approvals disabled.

Only enable yolo mode in a workspace and network you trust.

## Secrets

Do not commit:

- `.env` files
- pairing tokens
- host passwords
- local state directories
- cloudflared or ngrok credentials

Use environment variables for host passwords:

```bash
export CODEX_LINK_PASSWORD="choose-a-password"
```
