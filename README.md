# Codex LAN Control Prototype

A local-network prototype for controlling a Codex CLI/agent session from a mobile app.

The project intentionally uses a **host bridge** instead of exposing Codex directly to the phone:

```text
Flutter/Android app  ──ws:// LAN dev prototype──▶  Host bridge  ──local process/stdio──▶  Codex CLI
```

## Security posture

This is a LAN-only prototype. The current milestone uses `ws://` with one-time pairing tokens so we can verify the app, protocol, streaming, sessions, workspace switching, and cancellation quickly.

Do **not** expose the bridge to the public internet. Do **not** port-forward it. For production hardening, switch to `wss://` with a self-signed certificate fingerprint pinned from the pairing QR payload.

The mobile app never sends arbitrary shell commands. It sends structured messages (`prompt.send`, `session.create`, `workspace.switch`, `command.run`, `run.cancel`, etc.) to the host bridge. The host remains the policy authority.

Yolo mode is intentionally gated. The app can only switch a session to yolo when the host is started with `--allow-yolo`; that maps future runs in that session to Codex `--dangerously-bypass-approvals-and-sandbox` and should only be used in a trusted local workspace.

## Theme

The new Flutter UI uses a ChatGPT-mobile-inspired dark theme: pure black background, floating round menu/action controls, dark gray user bubbles, plain assistant text, bottom pill composer, smooth transitions, a command rail, Markdown rendering, and syntax-highlighted code blocks.

## Project layout

```text
host/      Node.js + TypeScript bridge with pairing, protocol v2, multi-session state, and CLI Codex adapter
flutter/   Flutter Android client with QR pairing, sessions, workspace switching, commands, yolo toggle, and rich chat UI
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
- Stored device token reconnect.
- Protocol v2 session list/create/delete/rename.
- Persistent Codex thread id per mobile session.
- Workspace switching from the app, limited to host-configured paths.
- Safe/yolo mode toggle with host-side yolo opt-in.
- Host command catalog exposed to the app.
- Send prompts and stream rich agent events.
- Render `thinking`, `executing`, `response`, system, and error messages.
- Markdown and syntax-highlighted code rendering.
- Cancel active runs.
- Smooth ChatGPT/Codex-style Flutter UI.

## Planned hardening

- `wss://` with QR-pinned certificate fingerprint.
- Device revocation UI.
- Real Codex app-server JSON-RPC adapter.
- Approval request forwarding.
- Diff viewer and approval-specific risk display.
