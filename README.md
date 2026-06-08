# Codex Link

Codex Link controls a Codex app-server/agent session from a mobile app over a local connection or an explicit secure tunnel.

The project intentionally uses a **host bridge** instead of exposing Codex directly to the phone:

```text
Flutter app  ──ws:// local or wss:// tunnel──▶  Host bridge  ──local process/stdio──▶  Codex app-server
```

## Security posture

The default mode is still local/LAN. Remote access in V1 is tunnel-first: keep the host bridge bound locally or privately, then expose it through a tunnel provider such as cloudflared, ngrok, Tailscale Funnel, or a reverse proxy that gives the phone a `wss://` URL.

Do **not** expose the bridge directly on a public VPS port for V1. Tunnel mode requires a host password plus either `--public-url` or `--cloudflared-auto`. The tunnel provider should terminate TLS for the public `wss://` URL.

The mobile app never sends arbitrary shell commands. It sends structured messages (`prompt.send`, `session.create`, `workspace.switch`, `command.run`, `file.offer.request`, `file.request`, `run.cancel`, etc.) to the host bridge. The host remains the policy authority.

Yolo mode is intentionally gated. The app can only switch a session to yolo when the host is started with `--allow-yolo`; that maps future runs in that session to Codex `danger-full-access` with approvals disabled and should only be used in a trusted local workspace.

## Theme

The new Flutter UI uses a ChatGPT-mobile-inspired dark theme: pure black background, floating round menu/action controls, dark gray user bubbles, plain assistant text, bottom pill composer, smooth transitions, a command rail, Markdown rendering, and syntax-highlighted code blocks.

## Project layout

```text
host/      Node.js + TypeScript bridge with pairing, protocol v6, multi-session state, tunnel metadata, file offers, file mentions, and Codex app-server adapter
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

The easiest test mode lets the host start cloudflared and print the generated public URL automatically:

```bash
export CODEX_LINK_PASSWORD="testpass"

pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --codex-command codex \
  --workdir /path/to/allowed/project \
  --sandbox workspace-write \
  --password "$CODEX_LINK_PASSWORD" \
  --remote-mode tunnel \
  --cloudflared-auto
```

The host binds to `127.0.0.1:8787`, starts `cloudflared tunnel --url http://127.0.0.1:8787`, waits for the generated `https://...trycloudflare.com` URL, converts it to `wss://...trycloudflare.com`, then prints the QR/manual pairing payload with that URL.

Manual mode still works if you prefer to run cloudflared yourself. You can pass
the generated `https://...trycloudflare.com` URL directly; the host and app
normalize tunnel HTTP URLs to WebSocket URLs.

```bash
cloudflared tunnel --url http://127.0.0.1:8787
```

Then pass the printed URL converted from `https://` to `wss://`:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --codex-command codex \
  --workdir /path/to/allowed/project \
  --sandbox workspace-write \
  --password "$CODEX_LINK_PASSWORD" \
  --remote-mode tunnel \
  --public-url https://YOUR-CLOUDFLARED-DOMAIN.trycloudflare.com \
  --tunnel-provider cloudflared
```

In the Flutter app, scan the QR or use password login with the public URL:

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
  --session-mode app-server \
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
  --session-mode app-server \
  --codex-command codex \
  --workdir /path/to/allowed/project \
  --sandbox workspace-write \
  --password "$CODEX_LINK_PASSWORD" \
  --remote-mode tunnel \
  --public-url wss://YOUR-TUNNEL-HOST \
  --tunnel-provider other
```

## Host bridge with real Codex app-server

The default mode is `mock`, which is best for proving mobile pairing and streaming.

To run the real app-server adapter with file creation enabled inside a trusted workspace:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --codex-command codex \
  --workdir /path/to/allowed/project \
  --sandbox workspace-write
```

The bridge spawns the configured command with `shell: false`, starts `codex app-server` over stdio JSON-RPC, maps Codex notifications into `thinking`, `executing`, `response`, file-change, approval, and goal messages, and cancels active turns with `turn/interrupt`.

Follow-up prompts in the same mobile session use the stored Codex thread id through app-server `turn/start`/`turn/steer`, so the app no longer creates a fresh Codex conversation for every message.

### Sending files to the phone

Use `/send <workspace-relative-path>` in chat to ask the host to offer a real downloadable file card without asking the agent to paste file contents:

```text
/send lib/report.txt
```

The app also recognizes `send file <path>` and `send me file <path>`. Files must stay inside the active session workspace and must fit the host download size limit.

Typing `@` in the composer searches files in the active workspace. Pick a suggestion to insert `@path/to/file`; `/send @path/to/file` resolves to that workspace file and sends it to the phone.

### Workspaces

The host controls which workspaces the app can switch between. The default `--workdir` is always available. Add more allowed workspaces with repeated `--workspace` flags:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair --insecure-ws-dev --session-mode app-server \
  --workdir /home/kurisu/project-a \
  --workspace /home/kurisu/project-b \
  --workspace /home/kurisu/project-c
```

Switching a session's workspace resets that session's stored Codex thread id so Codex starts cleanly in the new directory.

### Yolo mode

Safe mode uses the host default sandbox, normally `workspace-write`. To allow the app's yolo toggle:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair --insecure-ws-dev --session-mode app-server \
  --workdir /path/to/trusted/project \
  --sandbox workspace-write \
  --allow-yolo
```

Only enable this on a trusted LAN and trusted workspace. Yolo switches that session to Codex's `danger-full-access` mode so commands can run automatically without approvals or sandboxing.

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
- Protocol v6 session list/create/delete/rename, native goal RPC, and workspace file search.
- Host info dashboard with local URL, public URL, provider, and yolo allowance.
- Persistent Codex thread id per mobile session.
- Workspace switching from the app, limited to host-configured paths.
- Safe/yolo mode toggle with host-side yolo opt-in.
- Host command catalog exposed to the app.
- Native app-server `/goal` handling through `thread/goal/set`, `thread/goal/get`, and `thread/goal/clear`.
- Send prompts and render rich agent events.
- Host-to-app file offers and downloads for generated, uploaded, and explicitly requested workspace-bound files.
- Render `thinking`, `executing`, `response`, system, and error messages.
- Copy actions for prompts, responses, file paths, and file cards.
- Markdown and syntax-highlighted code rendering.
- Cancel active runs.
- Approval request forwarding from app-server to the bridge protocol.
- Smooth ChatGPT/Codex-style Flutter UI.

## Planned hardening

- QR-pinned certificate fingerprint for self-hosted TLS.
- Device revocation UI.
- Chunked file downloads for larger files.
- Approval-specific risk display and richer permission UI.

## License

MIT. See [LICENSE](LICENSE).
