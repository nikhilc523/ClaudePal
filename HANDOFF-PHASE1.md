# HANDOFF DOC — ClaudePal macOS App, Phase 1 Complete

**Date:** April 12, 2026

## Status: Phase 1 COMPLETE — E2E verified

All 5 steps of Phase 1 are done. A native macOS menu bar app receives Claude Code hooks, stores events in SQLite, and displays pending approvals in the menu bar. The full hook loop has been verified end-to-end with a real Claude Code session.

## Repo location

`/Users/nikhilchowdary/ClaudePal/ClaudePalMac/` — Swift Package, targets macOS 14+.

## What's done and verified (29 tests passing)

### Step 1 — Storage layer (13 tests)

| File | What it does |
|------|-------------|
| `Sources/ClaudePalMacCore/Models/Session.swift` | Session + SessionStatus enum |
| `Sources/ClaudePalMacCore/Models/Event.swift` | Event + EventType enum |
| `Sources/ClaudePalMacCore/Models/PendingDecision.swift` | PendingDecision + DecisionStatus enum |
| `Sources/ClaudePalMacCore/Storage/Database.swift` | AppDatabase (GRDB, DatabasePool for prod, DatabaseQueue for tests) |
| `Tests/ClaudePalMacCoreTests/DatabaseTests.swift` | 13 tests — CRUD, cascade deletes, expiry |

### Step 2 — Hook server (9 tests)

| File | What it does |
|------|-------------|
| `Sources/ClaudePalMacCore/HookServer/HookPayload.swift` | Internal HookPayload, HookType, HookEvent, JSONObject, HookDecisionResponse |
| `Sources/ClaudePalMacCore/HookServer/RawHookPayload.swift` | Wire format for raw Claude Code payloads + RawHookResponse (approve/block) |
| `Sources/ClaudePalMacCore/HookServer/HookProcessor.swift` | Actor that processes hooks, manages AsyncStream-based decision waiting |
| `Sources/ClaudePalMacCore/HookServer/HookServer.swift` | Hummingbird HTTP server with routes: `/health`, `/hook`, `/hook/{hookType}`, `/decisions/{id}/resolve` |
| `Tests/ClaudePalMacCoreTests/HookProcessorTests.swift` | 9 tests — notification, stop, postToolUse, permission approve/deny, timeout, session auto-create, destructive detection |

**Key fix applied:** Original code used `CheckedContinuation` with a `Task` dispatch to store continuations, causing a race condition where `resolve()` could fire before the continuation was stored (tests hung indefinitely). Replaced with `AsyncStream` — the continuation is stored synchronously on the actor before suspension, eliminating the race.

### Step 3 — Hook installer (7 tests)

| File | What it does |
|------|-------------|
| `Sources/ClaudePalMacCore/HookInstaller/ClaudeHookConfig.swift` | Reads/writes `~/.claude/settings.json`, creates forwarding script at `~/.claudepal/hook-forward.sh` |
| `Tests/ClaudePalMacCoreTests/ClaudeHookConfigTests.swift` | 7 tests — fresh install, idempotency, preserves existing hooks, uninstall, no-file, async flags, detection |

**Hook forwarding:** The script at `~/.claudepal/hook-forward.sh` receives Claude Code's stdin payload and `curl`s it to `http://127.0.0.1:52429/hook/{hookType}`. The server parses the raw Claude Code format (`hook_event_name`, `tool_name`, `tool_input`, `session_id`, `cwd`) via `RawHookPayload` and converts to internal `HookPayload`.

**Coexistence:** ClaudePal hooks are appended alongside existing hooks (masko-desktop, Codync). Detection uses the marker string `claudepal/hook-forward.sh`. Install is idempotent — running twice doesn't duplicate entries.

### Step 4 — macOS menu bar app

| File | What it does |
|------|-------------|
| `Sources/ClaudePalMacApp/ClaudePalMacApp.swift` | `@main` SwiftUI app with `MenuBarExtra` (.window style) |
| `Sources/ClaudePalMacApp/AppState.swift` | Central state: owns DB, HookProcessor, HookServer, ClaudeHookConfig. 1s polling for refresh. |
| `Sources/ClaudePalMacApp/MenuBarView.swift` | Dropdown UI: pending approvals with Approve/Deny, sessions list, Install/Uninstall Hooks, Launch on Login, Quit |
| `scripts/run-app.sh` | Builds and wraps in `.app` bundle with `LSUIElement=true` (menu bar only, no dock icon) |

**Menu bar icon states:**
- `cloud.fill` — idle, server running
- `bolt.fill` — active sessions
- `bell.badge.fill` — pending approvals waiting
- `exclamationmark.circle` — server not running

### Step 5 — E2E verified

Tested with a real Claude Code session:
1. Launched ClaudePal via `./scripts/run-app.sh`
2. Server confirmed running via `curl http://127.0.0.1:52429/health`
3. Started a new Claude Code session
4. Claude triggered a tool use → PreToolUse hook fired → ClaudePal received it
5. Pending approval appeared in menu bar with tool name and command preview
6. File was created successfully after terminal approval

## Hook mode: Notification (async)

All hooks including PreToolUse are **async**. This means:
- Claude Code shows its normal terminal permission prompt
- ClaudePal receives the event in the background for monitoring
- User approves from terminal as usual

**Why async:** In Phase 1, the user is at the Mac and wants terminal + notification. Sync mode (where ClaudePal is the sole approval authority) will be activated in Phase 2 when iPhone remote approval is added — toggled via a setting.

## Dependencies

| Package | Version | Used for |
|---------|---------|----------|
| GRDB.swift | 6.29+ | SQLite persistence |
| Hummingbird | 2.5+ | HTTP server |

## Files modified outside the repo

| File | Change |
|------|--------|
| `~/.claude/settings.json` | Added ClaudePal hooks for PreToolUse, PostToolUse, Notification, Stop. Removed invalid `StopFailure` key that was causing Claude Code to skip the entire settings file. |
| `~/.claudepal/hook-forward.sh` | Forwarding script (created by installer) |
| `~/.claude/settings.json.bak.claudepal` | Backup of original settings before changes |

## Known issues / tech debt

1. **AppState uses 1-second polling timer** to refresh from the DB. Should be replaced with GRDB `ValueObservation` for reactive updates.
2. **Menu bar panel doesn't auto-dismiss** after approve/deny — `.menuBarExtraStyle(.window)` stays open until click-away.
3. **No error handling UI** — if the server fails to start, the icon shows `exclamationmark.circle` but no explanation.
4. **SMAppService** for launch-on-login won't work without proper code signing. Needs Developer ID signing for the .app bundle.
5. **RawHookResponse** returns `{"decision":"approve"}` even for async hooks where Claude Code ignores the response. Harmless but unnecessary.
6. **No Notification hook type from Claude Code** specifically for permission prompts — we rely on `PreToolUse` which fires before the permission UI appears.

## How to run

```bash
# Run tests (29 total)
cd /Users/nikhilchowdary/ClaudePal/ClaudePalMac && swift test

# Build and launch the app
./scripts/run-app.sh

# Check server health
curl http://127.0.0.1:52429/health

# Install hooks (from menu bar "Install Hooks" button, or manually)
# Hooks are already installed in current settings.json
```

## Next: Phase 1.5 or Phase 2

### Phase 1.5 — Notch Panel UI (optional polish)

Replace the `MenuBarExtra` dropdown with a Codync-style floating notch panel (Dynamic Island aesthetic). Custom `NSPanel` anchored to top-center, pill shape, expand/collapse animation. Documented in `plan.md`.

### Phase 2 — CloudKit Sync Layer

Mirror Mac-side state to CloudKit so iPhone can see it. Key deliverables:
- CloudKit container with record types (`CPSession`, `CPEvent`, `CPPendingDecision`, `CPApprovalCommand`)
- macOS app pushes state to CloudKit
- macOS app subscribes to `CPApprovalCommand` from iPhone
- Approval command processing: read → validate → resolve locally → mirror result
- **Sync mode toggle**: when enabled, PreToolUse hook switches to synchronous, ClaudePal becomes the approval authority, terminal waits silently

### Hard rules (unchanged)

- macOS is always the authority for approval resolution
- CloudKit is a projection, never the transaction finalizer
- No Node.js, no npm, no LAN pairing, no Tailscale
- Write tests after each step, verify before moving on
- Never proceed to next step without user approval
