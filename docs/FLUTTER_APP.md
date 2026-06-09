# Flutter App

The Flutter app is the primary Codex Link client. It is built for Android and optimized for a compact ChatGPT-style mobile workflow.

## Core Features

- QR and manual pairing.
- Password login for tunnel connections.
- Session list, new chat, rename, delete, and restore.
- Workspace selector with Playground and folder actions.
- Visible tool calls for file reads, edits, commands, approvals, and generated files.
- Markdown and syntax-highlighted code rendering.
- File download cards and inline image previews.
- `@` workspace file mentions.
- Slash commands for native host actions.
- App Server Actions screen for plugins, MCP OAuth, remote pairing, usage limits, and pending interactive requests.
- Dark and light appearance modes plus accent selection.
- GitHub release update checks.

## Connection Behavior

When the host disconnects, the app keeps the cached chat visible and schedules reconnect attempts. The composer remains editable so the user can prepare the next prompt, but sending still requires an active connection.

Foreground disconnects are shown in the app UI. Local phone notifications are reserved for background task progress and completion.

## Commands

The chat composer shows slash command suggestions inline above the input. Common commands include:

- `/goal` to set, inspect, or clear the active goal.
- `/send` to request a file from the active workspace.
- `/doctor` to inspect host/session status.
- `/status` and related app commands when exposed by the host.

Interactive app-server operations live in App Server Actions. Workspace and session browsing stay in the sidebar, while account, model, theme, connection, and env-secret controls stay in Settings.

## File Mentions

Type `@` in the composer to search files in the active workspace. Selecting a suggestion inserts a workspace-relative file mention. Mentions are useful in normal prompts and with `/send`.

## Updates

The app checks GitHub Releases for `makise-ui/codex-link`. If a newer release includes an APK asset, the app opens the release download in the system browser.

Android requires user approval to install APK updates. Codex Link does not silently replace itself.

## Build

```bash
cd flutter
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Release APK output:

```text
flutter/build/app/outputs/flutter-apk/app-release.apk
```
