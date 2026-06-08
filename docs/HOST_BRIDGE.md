# Host Bridge

The host bridge is the policy and transport layer between the Flutter app and Codex. It exposes a WebSocket protocol to the phone and uses the Codex app-server adapter locally.

## Responsibilities

- Pair trusted devices with a one-time token.
- Store session state and Codex thread ids.
- Limit sessions to configured workspaces.
- Translate Codex app-server events into mobile chat events.
- Forward approvals, goals, plans, model settings, and run cancellation.
- Offer workspace files to the phone without exposing arbitrary paths.

## Common Commands

Start a real Codex app-server session:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --codex-command codex \
  --workdir /path/to/project \
  --sandbox workspace-write
```

Start with mock sessions for UI testing:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode mock
```

Start with extra workspaces:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --workdir /home/me/project-a \
  --workspace /home/me/project-b \
  --workspace /home/me/project-c
```

## Workspace Model

The host exposes:

- The default `--workdir`.
- Any repeated `--workspace` paths.
- A Playground workspace at `~/.codex-link/playground`.

Switching a session to another workspace clears the stored Codex thread id for that session so the next prompt starts cleanly in the new directory.

## Tunnel Mode

Tunnel mode is intended for remote control through a TLS-terminating provider. Do not expose the bridge directly on a public VPS port.

Supported provider labels:

- `cloudflared`
- `ngrok`
- `tailscale`
- `other`

The public URL must be `wss://` unless it points to localhost. `https://` tunnel URLs are normalized to `wss://` by the host and app.

## Password Login

Tunnel mode requires a password:

```bash
export CODEX_LINK_PASSWORD="choose-a-password"
```

The host also accepts:

- `--password <password>`
- `CODEX_LINK_PASSWORD`
- `CODEX_LAN_PASSWORD`

## File Transfer

The app can request a workspace file with:

```text
/send path/to/file.txt
```

The host validates the path against the active workspace and sends a downloadable file offer. Image offers can be rendered as image previews in chat.

The composer also supports `@` file mentions. Pick a suggested file and use:

```text
/send @path/to/file.txt
```

## Safety Modes

Default sessions use the configured sandbox, usually `workspace-write`.

To expose the app's yolo toggle:

```bash
pnpm --filter @codex-lan/host dev -- \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --workdir /path/to/trusted/project \
  --sandbox workspace-write \
  --allow-yolo
```

Yolo maps that session to Codex `danger-full-access` with approvals disabled. Use it only in a trusted workspace.

## Useful Scripts

```bash
pnpm --dir host test
pnpm --dir host typecheck
pnpm --dir host build
```
