<div align="center">

<img src="https://raw.githubusercontent.com/wacht-platform/snippet-service/main/snippet-mascot/png/snip-mascot-256.png" alt="Mochi, the snippet mascot" width="120" height="120" />

# snippet app

**Native Android, macOS, Linux, and Windows client for snippet: inspect codebases, run parallel agent lanes, and steer coding sessions.**

[![latest release](https://img.shields.io/github/v/release/wacht-platform/snippet-app?include_prereleases&label=latest%20release)](https://github.com/wacht-platform/snippet-app/releases/tag/latest)
[![built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B.svg)](https://flutter.dev)
[![license: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![GitHub Sponsors](https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa.svg?logo=github&logoColor=white)](https://github.com/sponsors/wacht-platform)

</div>

---

The snippet app is the native multi-platform client for [`snippet`](https://github.com/wacht-platform/snippet-service). It connects directly to a running `snippet serve` daemon over authenticated HTTP and WebSockets, giving you terminal inspection, file editing, and agent steering on phone and desktop.

- **Durable daemon architecture**: Your machine runs the code, tests, and git commands. The app attaches to `snippet serve` via token-authenticated WebSockets (`/attach` and `/events`). Keys and code stay on your machine; no third-party cloud sits in the middle.
- **Git worktree isolation**: Run parallel agent lanes simultaneously. Each lane works in its own git worktree branch to prevent conflicting edits or dirtying your index.
- **Zero state loss**: Session transcripts, tool outputs, and harness checkpoints persist to local SQLite and JSONL files. Dropped connections, daemon restarts, or client switches recover from the last checkpoint without lost turns.
- **Native multi-platform builds**: Identical feature parity across Android, macOS, Linux, and Windows.

## Download

Every build on `main` publishes a rolling **Latest snippet app** release with prebuilt binaries for all supported platforms:

### [Download the latest release](https://github.com/wacht-platform/snippet-app/releases/tag/latest)

| Asset | Platform | Architecture |
| --- | --- | --- |
| `snippet-android-arm64.apk` | Android 8.0+ | arm64-v8a |
| `snippet-macos.zip` | macOS 12+ | Apple Silicon / Intel universal |
| `snippet-windows.zip` | Windows 10+ | x86_64 |
| `snippet-linux-x64.tar.gz` | Linux (GTK3 / glibc 2.31+) | x86_64 |

### Android

Download [`snippet-android-arm64.apk`](https://github.com/wacht-platform/snippet-app/releases/download/latest/snippet-android-arm64.apk) directly to your device and run the installer. The APK is currently self-signed; if an update fails over an existing install, remove the older build first.

### macOS and Windows

Download and extract the platform ZIP from the [latest release](https://github.com/wacht-platform/snippet-app/releases/tag/latest), then run `snippet.app` (macOS) or `snippet.exe` (Windows).

### Linux

Download `snippet-linux-x64.tar.gz` from the [latest release](https://github.com/wacht-platform/snippet-app/releases/tag/latest), extract it, and execute `snippet.sh`:

```sh
tar -xzf snippet-linux-x64.tar.gz
cd snippet-linux-x64
./snippet.sh
```

For packaging requirements or desktop integration, see the [Linux desktop guide](docs/linux-desktop.md).

## Connect to a daemon

1. Start `snippet serve` on the host machine containing your repository:

   ```sh
   snippet serve
   ```

2. Open the snippet app and select **Add machine**.
3. Scan the terminal QR code, or paste the URL and token printed by `snippet serve`.
4. Select an existing session or open a new session in any configured workspace.

For headless servers or remote boxes, `snippet serve` supports SSH port forwarding, custom port bindings (`--bind 127.0.0.1:4040`), and systemd user services (`snippet serve --enable`).

## Features

- **Real-time streaming and tool audit**: Live markdown responses with tool execution cards, collapsible terminal outputs, diff previews, and approvals.
- **Durable session engine**: Rename, resume, checkpoint, and rewind sessions. History compaction maintains fast context while keeping full logs searchable via `snippet history`.
- **Parallel agent lanes**: Run delegated sub-tasks in background lanes with live progress cards and independent cancel/resume controls.
- **File tree and git workspace**: Inspect working tree diffs, stage files, review branch commits, and manage working tree changes directly in the UI.
- **Provider and model routing**: Configure and switch model endpoints (Anthropic, OpenAI, Gemini, local Ollama/vLLM) per session with custom reasoning settings.
- **Process manager**: Monitor daemon child processes, stream background logs, and terminate detached processes.
- **Multi-instance switcher**: Connect multiple developer workstations, VMs, or remote build boxes with instant tab switching.

## Build locally

Requires Flutter SDK 3.24+ and the native toolchain for your host operating system.

```sh
flutter pub get
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
```

### Android APK

```sh
flutter build apk --release --split-per-abi
# Binary path: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### macOS desktop

```sh
flutter build macos --release
# Bundle path: build/macos/Build/Products/Release/snippet.app
```

### Windows desktop

```sh
flutter build windows --release
# Bundle path: build/windows/x64/runner/Release/
```

### Linux desktop

```sh
flutter build linux --release
# Bundle path: build/linux/x64/release/bundle/
```

## Release automation

The workflow at [`.github/workflows/release.yml`](.github/workflows/release.yml) compiles Android, macOS, Linux, and Windows targets on every push to `main` and updates the rolling `latest` prerelease.

## Architecture

```text
snippet serve (host daemon) ── authenticated WebSockets/HTTP ── snippet app (client)
      │
      ├── git worktrees & repositories
      ├── SQLite session index & JSONL transcripts
      ├── model providers & API credentials
      └── terminals, file operations, background processes
```

The client communicates through two primary endpoints:

- `/attach`: Bi-directional WebSocket for streaming agent events, tool inputs, approvals, terminals, and paging session transcripts.
- `/events`: Daemon-level WebSocket for workspace status, active background processes, and configuration updates.

## Related project

- [snippet service](https://github.com/wacht-platform/snippet-service) — Rust coding agent, TUI, daemon, model configuration, and session engine.
- [Wacht](https://wacht.dev) — the team behind the project.

## Sponsoring Snippet

Snippet is fully open-source (AGPL-3.0), funded by developers and companies building with autonomous agents. Sponsorships sustain continuous development, multi-platform build infrastructure, and native driver integrations.

Support development directly via [GitHub Sponsors (wacht-platform)](https://github.com/sponsors/wacht-platform) or [GitHub Sponsors (snipextt)](https://github.com/sponsors/snipextt).

### Sponsorship tiers

| Tier | Price | Benefits |
| --- | --- | --- |
| Community Backer | $15 / month | Supporter credit in repo and release notes. |
| Silver Sponsor | $250 / month | Logo on GitHub README and documentation. |
| Gold Sponsor | $500 / month | Top logo placement on GitHub README, website hero (<https://snippet.wacht.dev>), release notes, and priority feature requests. |
| Commercial & Custom Integrations | Custom | Direct contact handle ([@snipextt on X](https://x.com/snipextt)) for bespoke harness deployment, custom MCP tooling, and enterprise support. |

For bespoke harness deployment, custom MCP tooling, or enterprise support contracts, contact [@snipextt on X](https://x.com/snipextt).

## License

Copyright (C) 2026 snipextt. Licensed under the [GNU Affero General Public License v3.0 or later](LICENSE).
