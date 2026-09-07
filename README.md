<div align="center">

<img src="https://raw.githubusercontent.com/wacht-platform/snippet-service/main/snippet-mascot/png/snip-mascot-256.png" alt="snippet mascot" width="120" height="120" />

# snippet app

**A remote Android, macOS, and Windows client for the open-source snippet coding agent.**

[![latest release](https://img.shields.io/github/v/release/wacht-platform/snippet-app?include_prereleases&label=latest%20release)](https://github.com/wacht-platform/snippet-app/releases/tag/latest)
[![built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B.svg)](https://flutter.dev)
[![license: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)

</div>

---

The snippet app is the remote window into [`snippet`](https://github.com/wacht-platform/snippet-service). Run `snippet serve` on the machine that owns your project, scan its QR code or paste its connection string, and use the app to chat with the agent, inspect work, steer tasks, and manage sessions from anywhere.

The app talks directly to your daemon over an authenticated connection. Your project, sessions, and provider keys remain on your machine.

## Download

Every successful build publishes one rolling **Latest snippet app** release containing all current platform assets:

### [Download the latest release](https://github.com/wacht-platform/snippet-app/releases/tag/latest)

| Asset | Platform |
| --- | --- |
| `snippet-android-arm64.apk` | Android arm64 phones and tablets |
| `snippet-macos.zip` | macOS desktop app |
| `snippet-windows.zip` | Windows x64 desktop app |

### Android

Open [`snippet-android-arm64.apk`](https://github.com/wacht-platform/snippet-app/releases/download/latest/snippet-android-arm64.apk) on an arm64 Android device and install it. Android may ask you to allow installation from unknown apps. The APK is currently debug-signed; if Android refuses to update an older install, uninstall that older build first.

### macOS and Windows

Download the matching ZIP from the [latest release](https://github.com/wacht-platform/snippet-app/releases/tag/latest), extract it, and launch the app. These are unsigned development builds, so the operating system may require an explicit approval the first time they open.

## Connect to a daemon

1. Install and configure the [snippet service](https://github.com/wacht-platform/snippet-service).
2. On your development machine, run:

   ```sh
   snippet serve
   ```

3. In the app, choose **Add machine**.
4. Scan the QR code or paste the URL and token from the daemon.
5. Select a session, or create a new chat from a workspace.

The daemon supports tunnelled remote access, local-only mode with `snippet serve --no-tunnel`, and service-manager setup with `snippet serve --enable`.

## Features

- Live chat with streaming replies and Markdown user and assistant messages.
- Inline tool activity, code blocks, links, approvals, steering, and selectable transcript text.
- Durable sessions across machines with rename, resume, delete, checkpoints, rewind, and history compaction.
- Automatic transcript history paging over the existing session WebSocket as you scroll upward, with conservative background prefetch and viewport-preserving scroll position.
- Delegated lanes with live status, summaries, activity, failed/completed state, and compact navigation.
- Browse, preview, edit, upload, download, create, and delete files.
- Git status, diffs, staging, commits, branches, push, and pull.
- Per-conversation model selection and reasoning settings.
- Provider and model lists that refresh when daemon configuration changes.
- Background process monitoring, logs, and termination.
- Multiple connected machines with session tabs.
- QR onboarding, session notifications, audio/image/file attachments, and video previews.

## Build locally

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install), plus the platform toolchain for the target.

```sh
flutter pub get
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
```

### Android APK

```sh
flutter build apk --release --split-per-abi
# arm64 output:
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### macOS

Run on macOS with Xcode installed:

```sh
flutter build macos --release
```

The app is at `build/macos/Build/Products/Release/snippet.app`.

### Windows

Run on Windows with the Flutter Windows toolchain:

```sh
flutter build windows --release
```

The packaged app files are under `build/windows/x64/runner/Release/`.

## Release automation

The single workflow at [`.github/workflows/release.yml`](.github/workflows/release.yml) builds Android, macOS, and Windows in parallel, then attaches all three assets to the rolling `latest` prerelease. It runs on pushes to `main` and can also be started manually from GitHub Actions.

## Architecture

```text
snippet serve ── authenticated WebSockets/HTTP ── snippet app
      │
      └── project, sessions, models, files, terminals
```

The app uses `/attach` for live session state, streaming output, terminals, and transcript history requests. The daemon's `/events` WebSocket provides device-wide status and configuration events. The app does not require a cloud backend.

## Related project

- [snippet service](https://github.com/wacht-platform/snippet-service) — Rust coding agent, TUI, daemon, model configuration, and session engine.
- [Wacht](https://wacht.dev) — the team behind the project.

## License

Copyright (C) 2026 snipextt. Licensed under the [GNU Affero General Public License v3.0 or later](LICENSE).
