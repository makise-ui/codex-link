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

Install the published host package:

```bash
npm install -g codex-link-host
```

Start a real Codex app-server session:

```bash
codex-link-host \
  --pair \
  --insecure-ws-dev \
  --session-mode app-server \
  --codex-command codex \
  --workdir /path/to/project \
  --sandbox workspace-write
```

Start with mock sessions for UI testing:

```bash
codex-link-host \
  --pair \
  --insecure-ws-dev \
  --session-mode mock
```

Start with extra workspaces:

```bash
codex-link-host \
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
codex-link-host \
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
pnpm pack:host
pnpm publish:host:dry-run
```

## Updating the Host

For npm-installed hosts, update the global package:

```bash
npm update -g codex-link-host
```

If npm does not move to the newest version, install the latest published tag
explicitly:

```bash
npm install -g codex-link-host@latest
```

If the host runs under a service manager, restart that service after updating:

```bash
systemctl --user restart codex-link
```

For source checkouts, the repo-local updater is still available:

```bash
scripts/update-host.sh --skip-pull
```

## Publishing the Host Package

Check the package contents without publishing:

```bash
pnpm publish:host:dry-run
```

Publish the public npm package after logging into npm:

```bash
npm login
pnpm publish:host
```
