# Getting Started

This guide starts the Codex Link host bridge and connects the Flutter app.

## Requirements

- Node.js 20 or newer
- pnpm 9
- Flutter SDK and Android tooling
- Codex CLI available as `codex`
- An Android device or emulator

Install dependencies from the repository root:

```bash
pnpm install
cd flutter
flutter pub get
```

## Start the Host on LAN

Use LAN mode when the phone and computer are on the same trusted network.

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --codex-command codex \
  --workdir /path/to/project \
  --sandbox workspace-write
```

The host prints a QR code and a manual pairing JSON payload. In the app, choose scan QR or paste the manual payload.

## Start the Host with a Free Cloudflared Tunnel

Use tunnel mode when the phone cannot reach the host over LAN. Tunnel mode requires a host password.

```bash
export CODEX_LINK_PASSWORD="choose-a-password"

pnpm --filter @codex-lan/host dev -- \
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

The host starts `cloudflared`, waits for a generated `trycloudflare.com` URL, converts it to `wss://`, and includes it in the pairing payload.

## Manual Tunnel URL

Any public tunnel that forwards WebSocket traffic to the local host port can work. For example:

```bash
cloudflared tunnel --url http://127.0.0.1:8787
```

Then pass the public URL to the host:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --workdir /path/to/project \
  --sandbox workspace-write \
  --password "$CODEX_LINK_PASSWORD" \
  --remote-mode tunnel \
  --public-url https://example.trycloudflare.com \
  --tunnel-provider cloudflared
```

## Run the Flutter App

```bash
cd flutter
flutter run
```

Build a debug APK:

```bash
cd flutter
flutter build apk --debug
```

The APK is written to:

```text
flutter/build/app/outputs/flutter-apk/app-debug.apk
```

## First Session

1. Pair the app with the host.
2. Select a workspace from the sidebar.
3. Create a new chat or open an existing session.
4. Send a prompt.
5. Watch tool calls, file changes, approvals, and responses stream into the chat.
