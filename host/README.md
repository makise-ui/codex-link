# Codex Link Host

Host bridge for controlling Codex app-server sessions from the Codex Link
Android app.

The phone does not talk to Codex directly. It connects to this host bridge over
LAN or a secure tunnel, and the host remains responsible for workspace access,
sandbox mode, approvals, and file transfer.

## Install

```bash
npm install -g codex-link-host
```

or:

```bash
pnpm add -g codex-link-host
```

## Update

```bash
npm update -g codex-link-host
```

or install the latest published version explicitly:

```bash
npm install -g codex-link-host@latest
```

## Start

```bash
codex-link-host \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --codex-command codex \
  --workdir /path/to/project \
  --sandbox workspace-write
```

The host prints a QR code and manual pairing payload. Pair the Android app with
that payload, then start or import a session.

## Remote Tunnel

```bash
export CODEX_LINK_PASSWORD="choose-a-password"

codex-link-host \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --codex-command codex \
  --workdir /path/to/project \
  --sandbox workspace-write \
  --password "$CODEX_LINK_PASSWORD" \
  --remote-mode tunnel \
  --cloudflared-auto
```

Do not expose the bridge directly on a public VPS port. Use a TLS-terminating
tunnel provider and a host password for remote access.

## Yolo Mode

```bash
codex-link-host \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --workdir /path/to/trusted/project \
  --sandbox workspace-write \
  --allow-yolo
```

Yolo lets paired clients switch a session to Codex `danger-full-access`. Use it
only in a trusted workspace.
