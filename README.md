# Codex Link

Codex Link controls a Codex CLI/agent session from a mobile app over a local connection or an explicit secure tunnel.

The project intentionally uses a **host bridge** instead of exposing Codex directly to the phone:

```text
Flutter app  ──ws:// local or wss:// tunnel──▶  Host bridge  ──local process/stdio──▶  Codex CLI
```

## Security posture

The default mode is still local/LAN. Remote access in V1 is tunnel-first: keep the host bridge bound locally or privately, then expose it through a tunnel provider such as cloudflared, ngrok, Tailscale Funnel, or a reverse proxy that gives the phone a `wss://` URL.

Do **not** expose the bridge directly on a public VPS port for V1. Tunnel mode requires `--remote-mode tunnel`, `--public-url`, and a host password. The tunnel provider should terminate TLS for the public `wss://` URL.

The mobile app never sends arbitrary shell commands. It sends structured messages (`prompt.send`, `session.create`, `workspace.switch`, `command.run`, `file.request`, `run.cancel`, etc.) to the host bridge. The host remains the policy authority.

Yolo mode is intentionally gated. The app can only switch a session to yolo when the host is started with `--allow-yolo`; that maps future runs in that session to Codex `--dangerously-bypass-approvals-and-sandbox` and should only be used in a trusted local workspace.

## Theme

The new Flutter UI uses a ChatGPT-mobile-inspired dark theme: pure black background, floating round menu/action controls, dark gray user bubbles, plain assistant text, bottom pill composer, smooth transitions, a command rail, Markdown rendering, and syntax-highlighted code blocks.

## Project layout

```text
host/      Node.js + TypeScript bridge with pairing, protocol v3, multi-session state, tunnel metadata, file offers, and CLI Codex adapter
flutter/   Flutter Android client with QR/password pairing, sessions, workspace switching, commands, model settings, file cards, and rich chat UI
android/   Original Kotlin + Jetpack Compose prototype client kept as a fallback
shared/    Protocol reference schema
```

## Host bridge quick start

```bash
pnpm install
pnpm --filter @codex-lan/host test
pnpm --filter @codex-lan/host dev -- --pair --insecure-ws-dev --port 8787
```

The host prints both a pairing JSON payload and a terminal QR code. In the Flutter app, tap **Scan QR and pair** to scan it and pair automatically, or paste the JSON manually.

## Tunnel-first remote testing

### Free cloudflared quick tunnel

Start the tunnel first:

```bash
cloudflared tunnel --url http://127.0.0.1:8787
```

Cloudflared prints an `https://...trycloudflare.com` URL. Convert it to `wss://...trycloudflare.com`, then start the host with that public URL:

```bash
export CODEX_LINK_PASSWORD="testpass"

pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode cli \
  --codex-command codex \
  --workdir /path/to/allowed/project \
  --sandbox workspace-write \
  --password "$CODEX_LINK_PASSWORD" \
  --remote-mode tunnel \
  --public-url wss://YOUR-CLOUDFLARED-DOMAIN.trycloudflare.com \
  --tunnel-provider cloudflared
```

In the Flutter app, scan the QR or use password login with:

```text
wss://YOUR-CLOUDFLARED-DOMAIN.trycloudflare.com
```

Cloudflare Quick Tunnels are convenient for testing and can rotate or disappear. For regular use, configure a named tunnel or another stable provider.

### ngrok

```bash
ngrok http 8787
```

Use the printed public HTTPS host as `wss://...`:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode cli \
  --codex-command codex \
  --workdir /path/to/allowed/project \
  --sandbox workspace-write \
  --password "$CODEX_LINK_PASSWORD" \
  --remote-mode tunnel \
  --public-url wss://YOUR-NGROK-DOMAIN \
  --tunnel-provider ngrok
```

### Generic tunnel

Any provider that forwards WebSocket traffic from a public `wss://` URL to `http://127.0.0.1:8787` can work:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode cli \
  --codex-command codex \
  --workdir /path/to/allowed/project \
  --sandbox workspace-write \
  --password "$CODEX_LINK_PASSWORD" \
  --remote-mode tunnel \
  --public-url wss://YOUR-TUNNEL-HOST \
  --tunnel-provider other
```

## Host bridge with real Codex CLI

The default mode is `mock`, which is best for proving mobile pairing and streaming.

To run the real CLI adapter with file creation enabled inside a trusted workspace:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode cli \
  --codex-command codex \
  --workdir /path/to/allowed/project \
  --sandbox workspace-write
```

The bridge spawns the configured command with `shell: false`, passes each safe prompt as `codex exec --json --skip-git-repo-check --sandbox <mode> -- <prompt>` for new sessions, avoids keeping a stdin pipe open, parses Codex JSONL events into `thinking`, `executing`, and `response` messages, and cancels with `SIGINT`/`SIGTERM`.

Follow-up prompts in the same mobile session use the stored Codex thread id through `codex exec --json --skip-git-repo-check --sandbox <mode> resume <threadId> -- <prompt>`, so the app no longer creates a fresh Codex conversation for every message.

### Workspaces

The host controls which workspaces the app can switch between. The default `--workdir` is always available. Add more allowed workspaces with repeated `--workspace` flags:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair --insecure-ws-dev --session-mode cli \
  --workdir /home/kurisu/project-a \
  --workspace /home/kurisu/project-b \
  --workspace /home/kurisu/project-c
```

Switching a session's workspace resets that session's stored Codex thread id so Codex starts cleanly in the new directory.

### Yolo mode

Safe mode uses the host default sandbox, normally `workspace-write`. To allow the app's yolo toggle:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair --insecure-ws-dev --session-mode cli \
  --workdir /path/to/trusted/project \
  --sandbox workspace-write \
  --allow-yolo
```

Only enable this on a trusted LAN and trusted workspace. Yolo switches that session to Codex's dangerous bypass flag so commands can run automatically without approvals or sandboxing.

## Flutter quick start

```bash
cd /home/kurisu/codex-app/flutter
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Install the debug APK from:

```text
/home/kurisu/codex-app/flutter/build/app/outputs/flutter-apk/app-debug.apk
```

## MVP capabilities

- One-time QR/manual pairing.
- Password login and stored device token reconnect.
- Local/LAN mode and explicit tunnel mode.
- Protocol v3 session list/create/delete/rename.
- Host info dashboard with local URL, public URL, provider, and yolo allowance.
- Persistent Codex thread id per mobile session.
- Workspace switching from the app, limited to host-configured paths.
- Safe/yolo mode toggle with host-side yolo opt-in.
- Host command catalog exposed to the app.
- Send prompts and render rich agent events.
- Host-to-app file offers and downloads for workspace-bound files.
- Render `thinking`, `executing`, `response`, system, and error messages.
- Copy actions for prompts, responses, file paths, and file cards.
- Markdown and syntax-highlighted code rendering.
- Cancel active runs.
- Smooth ChatGPT/Codex-style Flutter UI.

## Planned hardening

- QR-pinned certificate fingerprint for self-hosted TLS.
- Device revocation UI.
- Real Codex app-server JSON-RPC adapter.
- Approval request forwarding.
- Chunked file downloads for larger files.
- Approval-specific risk display.
