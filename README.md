# ClaudePal

A native Apple ecosystem companion for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Monitor sessions, review tool approvals, and manage your Claude Code workflow from your Mac menu bar, iPhone, and Apple Watch.

<p align="center">
  <code>>_<</code>
</p>

## Features

- **macOS Menu Bar App** — Live session monitoring, pending approval management, and a Dynamic Island-style notch panel
- **Hook Integration** — Intercepts Claude Code tool calls (PreToolUse, PostToolUse, Notification, Stop) via a local HTTP server
- **Approval Flow** — Review, approve, or deny permission-required tool calls with destructive action detection
- **iPhone App** — Dashboard with sessions, approvals, event history, and Face ID gating for sensitive actions
- **Apple Watch App** — Quick glance at session status (coming soon)
- **Widgets** — Home screen, lock screen, and Live Activity widgets for iOS
- **SQLite Storage** — Local persistence via GRDB with CloudKit sync ready (pending Apple Developer account)

## Architecture

```
Claude Code CLI
  → ~/.claudepal/hook-forward.sh (curl POST)
    → macOS HookServer (localhost:52429, Hummingbird)
      → HookProcessor (actor, AsyncStream for decisions)
        → SQLite (GRDB)
        → [CloudKit sync → iPhone / Watch]  (code written, disabled)
```

The macOS app is always the source of truth. CloudKit is a one-way projection — the iPhone can send approval commands back, but the Mac validates and resolves locally.

## Project Structure

```
ClaudePal/
├── ClaudePalMac/          macOS menu bar app (Xcode + SPM hybrid)
│   ├── Sources/           Core library (models, storage, hook server, CloudKit)
│   ├── ClaudePalMac/      App target (menu bar, notch panel, app state)
│   └── Tests/             29 tests (database, hook processor, config)
├── ios/                   iOS + watchOS apps
│   ├── ClaudePal/         iPhone app (dashboard, approvals, history, settings)
│   ├── ClaudePalKit/      Shared Swift package (models, data providers, services)
│   ├── ClaudePalWatch/    watchOS app
│   └── ClaudePalWidgetExtension/  Home/lock screen + Live Activity widgets
└── bridge/                Legacy v1 Node.js bridge (unused)
```

## Getting Started

### Prerequisites

- macOS 14+ / Xcode 16+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

### macOS App

```bash
# Build
cd ClaudePalMac
xcodebuild -project ClaudePalMac.xcodeproj -scheme ClaudePalMac -configuration Debug build

# Run
bash scripts/run-app.sh

# Verify hook server is running
curl http://127.0.0.1:52429/health

# Run tests
swift test
```

On first launch, ClaudePal installs hooks into `~/.claude/settings.json` and creates the forwarding script at `~/.claudepal/hook-forward.sh`.

### iOS App (Simulator)

```bash
cd ios
xcodegen generate
xcodebuild -project ClaudePal.xcodeproj -scheme ClaudePal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

> **Note:** The iOS app currently runs with mock data. CloudKit sync requires an Apple Developer account to enable iCloud entitlements.

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 6.29+ | SQLite persistence |
| [Hummingbird](https://github.com/hummingbird-project/hummingbird) | 2.5+ | HTTP hook server |

## Design

Dark theme with a warm copper accent (`#D4944B`). The `>_<` terminal mascot appears throughout the app as the brand identity — in the notch panel, dashboard header, app icon, and widgets.

## License

MIT
