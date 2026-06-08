# Development and Release

## Repository Layout

```text
host/      TypeScript host bridge and Codex app-server adapter
flutter/   Flutter Android app
android/   Original Kotlin prototype
shared/    Protocol schema reference
docs/      Project documentation, screenshots, brand assets, release notes
```

## Host Checks

```bash
pnpm --dir host test
pnpm --dir host typecheck
pnpm --dir host build
```

The compiled host output in `host/dist/` is tracked for release convenience. Rebuild after changing TypeScript source files.

## Flutter Checks

```bash
cd flutter
flutter analyze
flutter test
flutter build apk --release
```

## Versioning

The Flutter app version is defined in `flutter/pubspec.yaml`.

The host package version is defined in `host/package.json`.

## GitHub Release Flow

1. Update version numbers and release notes.
2. Run host and Flutter verification.
3. Build the release APK.
4. Create a GitHub Release tag.
5. Upload the APK asset.

The app update checker expects a GitHub Release with a newer semantic version tag and an `.apk` asset.

## Commit Scope

Prefer small commits by area:

- `feat(host): ...`
- `fix(flutter): ...`
- `docs: ...`
- `test: ...`

Do not commit local pairing state, secrets, generated runtime files, or tunnel logs.
